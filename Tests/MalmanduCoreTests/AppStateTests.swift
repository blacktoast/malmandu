import Testing
import Foundation
@testable import MalmanduCore

@Suite("AppState Tests")
struct AppStateTests {

    @Test("초기 상태는 idle이다")
    func initialState() {
        let state = AppState()
        #expect(state.status == .idle)
        #expect(state.lastError == nil)
        #expect(state.lastAudioFileURL == nil)
        #expect(state.recordingStartTime == nil)
    }

    @Test("startRecording: idle → recording 전환, 시간 기록")
    func startRecording() {
        let state = AppState()
        state.startRecording()
        #expect(state.status == .recording)
        #expect(state.recordingStartTime != nil)
        #expect(state.lastError == nil)
    }

    @Test("startRecording: 에러 상태에서 호출하면 에러가 클리어된다")
    func startRecordingClearsError() {
        let state = AppState()
        state.fail(with: .apiKeyMissing)
        #expect(state.status == .error)
        state.startRecording()
        #expect(state.status == .recording)
        #expect(state.lastError == nil)
    }

    @Test("stopRecording: recording → transcribing 전환, 시간 초기화")
    func stopRecording() {
        let state = AppState()
        state.startRecording()
        state.stopRecording()
        #expect(state.status == .transcribing)
        #expect(state.recordingStartTime == nil)
    }

    @Test("completeTranscription: transcribing → idle 전환, audioURL 초기화")
    func completeTranscription() {
        let state = AppState()
        state.startRecording()
        state.stopRecording()
        state.lastAudioFileURL = URL(fileURLWithPath: "/tmp/test.m4a")
        state.completeTranscription()
        #expect(state.status == .idle)
        #expect(state.lastAudioFileURL == nil)
    }

    @Test("fail: error 상태 전환, 에러 및 오디오 URL 보존")
    func failWithError() {
        let state = AppState()
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        state.fail(with: .networkError("timeout"), audioURL: url)
        #expect(state.status == .error)
        #expect(state.lastAudioFileURL == url)
        if case .networkError(let msg) = state.lastError {
            #expect(msg == "timeout")
        } else {
            Issue.record("Expected networkError")
        }
    }

    @Test("fail: audioURL 없이 호출 가능")
    func failWithoutURL() {
        let state = AppState()
        state.fail(with: .apiKeyMissing)
        #expect(state.status == .error)
        #expect(state.lastAudioFileURL == nil)
    }

    @Test("clearError: error 상태에서만 idle로 전환")
    func clearError() {
        let state = AppState()
        state.fail(with: .apiKeyMissing)
        state.clearError()
        #expect(state.status == .idle)
        #expect(state.lastError == nil)
    }

    @Test("clearError: idle 상태에서는 변화 없음")
    func clearErrorFromIdle() {
        let state = AppState()
        state.clearError()
        #expect(state.status == .idle)
    }

    @Test("clearError: recording 상태에서는 변화 없음")
    func clearErrorFromRecording() {
        let state = AppState()
        state.startRecording()
        state.clearError()
        #expect(state.status == .recording)
    }
}
