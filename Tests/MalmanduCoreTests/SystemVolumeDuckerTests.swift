import CoreAudio
import Foundation
import Testing
@testable import MalmanduCore

@Suite("SystemVolumeDucker Tests")
struct SystemVolumeDuckerTests {
    @Test("기본 출력이 바뀌어도 낮췄던 장치의 볼륨을 복원한다")
    func restoresTheOriginalOutputDevice() {
        var output: (deviceID: AudioDeviceID, volume: Float)? = (7, 0.8)
        var writes: [(deviceID: AudioDeviceID, volume: Float)] = []
        let ducker = SystemVolumeDucker(
            readVolume: { output },
            writeVolume: {
                writes.append(($0, $1))
                return true
            }
        )

        ducker.duck()
        output = (9, 0.4)
        #expect(ducker.restore())

        #expect(writes.map(\.deviceID) == [7, 7])
        #expect(abs(writes[0].volume - 0.12) < 0.0001)
        #expect(writes[1].volume == 0.8)
    }

    @Test("첫 복원 쓰기가 실패하면 다시 시도한다")
    func retriesAFailedRestore() {
        var restoreAttempts = 0
        let ducker = SystemVolumeDucker(
            readVolume: { (7, 0.8) },
            writeVolume: { _, volume in
                guard volume == 0.8 else { return true }
                restoreAttempts += 1
                return restoreAttempts > 1
            }
        )

        ducker.duck()

        #expect(ducker.restore())
        #expect(restoreAttempts == 2)
    }

    @Test("동시 duck 호출은 볼륨을 한 번만 낮춘다")
    func serializesConcurrentDucking() {
        let stateLock = NSLock()
        let firstReadStarted = DispatchSemaphore(value: 0)
        let secondReadStarted = DispatchSemaphore(value: 0)
        var readCount = 0
        var writeCount = 0
        let ducker = SystemVolumeDucker(
            readVolume: {
                stateLock.lock()
                readCount += 1
                let count = readCount
                stateLock.unlock()

                if count == 1 {
                    firstReadStarted.signal()
                    _ = secondReadStarted.wait(timeout: .now() + .milliseconds(250))
                } else {
                    secondReadStarted.signal()
                }
                return (7, 0.8)
            },
            writeVolume: { _, _ in
                stateLock.lock()
                writeCount += 1
                stateLock.unlock()
                return true
            }
        )

        let queue = DispatchQueue(label: "SystemVolumeDuckerTests", attributes: .concurrent)
        let group = DispatchGroup()
        group.enter()
        queue.async {
            ducker.duck()
            group.leave()
        }
        firstReadStarted.wait()
        group.enter()
        queue.async {
            ducker.duck()
            group.leave()
        }
        group.wait()

        #expect(readCount == 1)
        #expect(writeCount == 1)
    }
}
