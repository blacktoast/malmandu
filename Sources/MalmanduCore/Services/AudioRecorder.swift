@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class SystemVolumeDucker: @unchecked Sendable {
    typealias ReadVolume = () -> (deviceID: AudioDeviceID, volume: Float)?
    typealias WriteVolume = (AudioDeviceID, Float) -> Bool

    private let readVolume: ReadVolume
    private let writeVolume: WriteVolume
    private let lock = NSLock()
    private var saved: (deviceID: AudioDeviceID, volume: Float)?

    init(readVolume: @escaping ReadVolume, writeVolume: @escaping WriteVolume) {
        self.readVolume = readVolume
        self.writeVolume = writeVolume
    }

    func duck() {
        lock.lock()
        defer { lock.unlock() }
        guard saved == nil, let current = readVolume(),
              writeVolume(current.deviceID, current.volume * 0.15) else { return }
        saved = current
    }

    @discardableResult
    func restore() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let saved else { return true }
        // ponytail: bounded sync retries; add a device listener only if detached outputs still strand volume.
        for _ in 0..<3 {
            if writeVolume(saved.deviceID, saved.volume) {
                self.saved = nil
                return true
            }
        }
        return false
    }
}

/// AVAudioRecorder/AVAudioEngine 기반 녹음 서비스
public final class AudioRecorder: NSObject, AudioRecorderProtocol, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine?
    private var recordingURL: URL?
    private var isStreamingMode = false
    private let maxDuration: TimeInterval
    private let systemVolumeDucker: SystemVolumeDucker

    public init(maxDuration: TimeInterval = 300) { // 5분 기본
        self.maxDuration = maxDuration
        self.systemVolumeDucker = SystemVolumeDucker(
            readVolume: Self.getSystemVolume,
            writeVolume: Self.setSystemVolume
        )
        super.init()
    }

    // MARK: - 일반 녹음 (파일 기반)

    public func startRecording() async throws {
        isStreamingMode = false
        duckSystemVolume()
        let url = makeRecordingURL()

        recorder = try AVAudioRecorder(url: url, settings: AudioConstants.m4aSettings)
        recorder?.isMeteringEnabled = true
        recorder?.record(forDuration: maxDuration)
        recordingURL = url
    }

    /// AVAudioRecorder의 현재 오디오 레벨 (0.0~1.0, RT 모드와 감도 매칭)
    public func currentLevel() -> Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0) // dB (-160 ~ 0)
        // dB → 선형 변환 (RT 모드의 RMS*8.0과 유사한 스케일)
        let linear = pow(10.0, power / 20.0) // dB → 선형 진폭
        return min(pow(linear * 8.0, 0.4), 1.0) // 감마 보정: 작은 소리 감도 향상
    }

    // MARK: - 스트리밍 녹음 (PCM 청크 + 파일 동시 저장)

    public func startRecordingWithStream(onAudioChunk: @escaping AudioChunkHandler) async throws {
        try await startRecordingWithStream(onAudioChunk: onAudioChunk, onAudioLevel: { _ in })
    }

    public func startRecordingWithStream(onAudioChunk: @escaping AudioChunkHandler, onAudioLevel: @escaping AudioLevelHandler) async throws {
        isStreamingMode = true
        duckSystemVolume()

        var tapInstalled = false
        var startSucceeded = false
        defer {
            if !startSucceeded {
                if tapInstalled { audioEngine?.inputNode.removeTap(onBus: 0) }
                audioEngine?.stop()
                audioEngine = nil
                recordingURL = nil
                isStreamingMode = false
                restoreSystemVolume()
            }
        }

        let url = makeRecordingURL()
        recordingURL = url

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // PCM s16le 16kHz mono 포맷 (Soniox RT 요구사항)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw AppError.recordingFailed("오디오 포맷 생성 실패")
        }

        // 파일 동시 저장 (M4A — 재시도/비동기 폴백용)
        let audioFile = try AVAudioFile(forWriting: url, settings: AudioConstants.m4aSettings)

        // 입력 → 16kHz mono PCM 변환기
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AppError.recordingFailed("오디오 변환기 생성 실패")
        }

        // 탭 설치: 입력 오디오를 PCM으로 변환하여 콜백 + 파일 저장
        let bufferSize: AVAudioFrameCount = 1024 // 64ms @ 16kHz (실시간 저지연)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard self != nil else { return }

            // 파일 저장 (M4A)
            try? audioFile.write(from: buffer)

            // PCM s16le로 변환하여 콜백
            let frameCount = AVAudioFrameCount(targetFormat.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate)
            guard frameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData, let channelData = convertedBuffer.int16ChannelData {
                let byteCount = Int(convertedBuffer.frameLength) * 2 // 16-bit = 2 bytes per sample
                let data = Data(bytes: channelData[0], count: byteCount)
                onAudioChunk(data)

                // RMS 계산 (Int16 → Float 변환 후)
                let int16Ptr = data.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
                let sampleCount = data.count / 2
                var sumOfSquares: Float = 0
                for i in 0..<sampleCount {
                    let sample = Float(int16Ptr[i]) / 32768.0
                    sumOfSquares += sample * sample
                }
                let rms = sqrt(sumOfSquares / Float(max(sampleCount, 1)))
                onAudioLevel(min(pow(rms * 8.0, 0.4), 1.0))
            }
        }
        tapInstalled = true

        // start() 실패해도 cleanup이 engine을 정리할 수 있도록 미리 할당
        audioEngine = engine
        engine.prepare()
        try engine.start()
        startSucceeded = true
    }

    // MARK: - 공통

    public func stopRecording() async throws -> URL {
        if isStreamingMode {
            return try stopStreamingRecording()
        } else {
            return try stopFileRecording()
        }
    }

    public func isRecording() -> Bool {
        if isStreamingMode {
            return audioEngine?.isRunning ?? false
        }
        return recorder?.isRecording ?? false
    }

    public static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Private

    private func duckSystemVolume() {
        systemVolumeDucker.duck()
    }

    private func restoreSystemVolume() {
        if !systemVolumeDucker.restore() {
            print("[AudioRecorder] 시스템 볼륨 복원 실패")
        }
    }

    private func makeRecordingURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "malmandu_\(UUID().uuidString).m4a"
        return tempDir.appendingPathComponent(fileName)
    }

    private func stopFileRecording() throws -> URL {
        defer { restoreSystemVolume() }
        guard let recorder = recorder, let url = recordingURL else {
            throw AppError.recordingFailed("No active recording")
        }
        recorder.stop()
        self.recorder = nil

        // 25MB 제한 체크
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        if fileSize > 25 * 1024 * 1024 {
            throw AppError.fileTooLarge
        }

        return url
    }

    private func stopStreamingRecording() throws -> URL {
        defer { restoreSystemVolume() }
        guard let engine = audioEngine, let url = recordingURL else {
            throw AppError.recordingFailed("No active streaming recording")
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil

        return url
    }

    // MARK: - CoreAudio 볼륨 제어

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return err == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private static func getSystemVolume() -> (deviceID: AudioDeviceID, volume: Float)? {
        guard let deviceID = defaultOutputDevice() else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let err = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        return err == noErr ? (deviceID, Float(volume)) : nil
    }

    private static func setSystemVolume(_ deviceID: AudioDeviceID, _ newVolume: Float) -> Bool {
        var value = min(max(0, Float32(newVolume)), 1)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }
}
