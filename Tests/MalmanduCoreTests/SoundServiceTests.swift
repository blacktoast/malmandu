import Testing
@testable import MalmanduCore

@Suite("SoundService Tests")
struct SoundServiceTests {

    // MARK: - Initial State

    @Test("soundEnabled is true by default")
    func testSoundEnabledDefaultTrue() {
        let service = SoundService()
        #expect(service.soundEnabled == true)
    }

    // MARK: - Toggle

    @Test("soundEnabled can be toggled to false")
    func testSoundEnabledToggle() {
        let service = SoundService()
        service.soundEnabled = false
        #expect(service.soundEnabled == false)
    }

    // MARK: - Sound Name Mapping

    @Test("play(.recordingStarted) maps to Tink sound name")
    func testRecordingStartedMapsToTink() {
        let service = SoundService()
        #expect(service.soundName(for: .recordingStarted) == "Tink")
    }

    @Test("play(.recordingStopped) maps to Pop sound name")
    func testRecordingStoppedMapsToPop() {
        let service = SoundService()
        #expect(service.soundName(for: .recordingStopped) == "Pop")
    }

    // MARK: - play() with soundEnabled = false

    @Test("play does nothing when soundEnabled is false")
    func testPlayDoesNothingWhenDisabled() {
        // soundEnabled=false로 초기화 시 예외 없이 조용히 반환해야 함
        let service = SoundService(soundEnabled: false)
        // NSSound를 직접 검증할 수 없으므로, 예외 없이 완료되면 통과
        service.play(.recordingStarted)
        service.play(.recordingStopped)
        #expect(service.soundEnabled == false)
    }

    // MARK: - SoundEvent Raw Values

    @Test("SoundEvent raw values are correct")
    func testSoundEventRawValues() {
        #expect(SoundEvent.recordingStarted.rawValue == "recordingStarted")
        #expect(SoundEvent.recordingStopped.rawValue == "recordingStopped")
    }
}
