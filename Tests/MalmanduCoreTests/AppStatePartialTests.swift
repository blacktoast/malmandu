import Testing
import Foundation
@testable import MalmanduCore

@Suite("AppState partialTranscription Tests")
struct AppStatePartialTests {

    @Test("startRecording이 partialTranscription을 nil로 초기화한다")
    func startRecordingClearsPartial() {
        let state = AppState()
        state.partialTranscription = "이전 텍스트"
        state.startRecording()
        #expect(state.partialTranscription == nil)
    }

    @Test("completeTranscription이 partialTranscription을 nil로 초기화한다")
    func completeTranscriptionClearsPartial() {
        let state = AppState()
        state.startRecording()
        state.partialTranscription = "실시간 텍스트"
        state.stopRecording()
        state.completeTranscription()
        #expect(state.partialTranscription == nil)
    }

    @Test("stopRecording은 partialTranscription을 유지한다")
    func stopRecordingPreservesPartial() {
        let state = AppState()
        state.startRecording()
        state.partialTranscription = "실시간 텍스트"
        state.stopRecording()
        #expect(state.partialTranscription == "실시간 텍스트")
    }

    @Test("fail은 partialTranscription을 유지한다")
    func failPreservesPartial() {
        let state = AppState()
        state.partialTranscription = "부분 텍스트"
        state.fail(with: .apiKeyMissing)
        #expect(state.partialTranscription == "부분 텍스트")
    }

    @Test("clearError는 partialTranscription을 유지한다")
    func clearErrorPreservesPartial() {
        let state = AppState()
        state.fail(with: .apiKeyMissing)
        state.partialTranscription = "부분 텍스트"
        state.clearError()
        #expect(state.partialTranscription == "부분 텍스트")
    }
}
