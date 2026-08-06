import Foundation
import Testing
@testable import MalmanduCore

@MainActor
@Suite("AppState reducer tests")
struct AppStateTests {
    @Test("initial state is idle and hidden")
    func initialState() {
        let state = AppState()

        #expect(state.flowState == .idle)
        #expect(state.status == .idle)
        #expect(state.overlayPresentation == .hidden)
    }

    @Test("toggle starts one recording session")
    func toggleStartsRecordingSession() {
        let state = AppState()

        let effects = state.send(.toggleRequested(
            targetBundleIdentifier: "com.example.editor",
            targetName: "Editor"
        ))
        let sessionID = startSessionID(from: effects)

        #expect(effects == [.startCapture(sessionID: sessionID)])
        #expect(state.status == .recording)
        #expect(state.startingAppBundleIdentifier == "com.example.editor")
        #expect(state.startingAppName == "Editor")
        #expect(state.recordingStartTime != nil)
        #expect(state.overlayPresentation == .starting)

        _ = state.send(.startSucceeded(sessionID: sessionID))

        #expect(state.overlayPresentation == .recording)
    }

    @Test("stop during starting enters non-interactive stopping state")
    func stopDuringStarting() {
        let state = AppState()
        let sessionID = startSession(state)

        let effects = state.send(.toggleRequested(targetBundleIdentifier: nil, targetName: nil))

        #expect(effects == [.stopCapture(sessionID: sessionID)])
        #expect(state.status == .transcribing)
        #expect(state.overlayPresentation == .transcribing)
        guard case .stopping(_, .finish) = state.flowState else {
            Issue.record("Expected finish stopping state")
            return
        }
    }

    @Test("normal finish follows stopping and transcription phases")
    func normalFinishTransitions() {
        let state = AppState()
        let audioURL = URL(fileURLWithPath: "/tmp/test.m4a")
        let sessionID = startSession(state)
        _ = state.send(.startSucceeded(sessionID: sessionID))

        #expect(state.send(.stopRequested) == [.stopCapture(sessionID: sessionID)])
        #expect(
            state.send(.captureStopped(sessionID: sessionID, audioURL))
                == [.finishTranscription(sessionID: sessionID, audioURL)]
        )
        #expect(state.overlayPresentation == .transcribing)

        #expect(state.send(.transcriptionSucceeded(sessionID: sessionID)).isEmpty)
        #expect(state.flowState == .idle)
        #expect(state.overlayPresentation == .hidden)
    }

    @Test("repeated stop and cancel requests are ignored once stopping")
    func repeatedTerminalRequestsAreIgnored() {
        let state = AppState()
        let sessionID = startSession(state)
        _ = state.send(.startSucceeded(sessionID: sessionID))

        #expect(state.send(.cancelRequested) == [.cancelCapture(sessionID: sessionID)])
        #expect(state.send(.cancelRequested).isEmpty)
        #expect(state.send(.stopRequested).isEmpty)
        #expect(state.send(.toggleRequested(targetBundleIdentifier: nil, targetName: nil)).isEmpty)
        guard case .stopping(_, .discard) = state.flowState else {
            Issue.record("Expected discard stopping state")
            return
        }
    }

    @Test("failed transcription retains its audio URL for retry")
    func failureAndRetry() {
        let state = AppState()
        let audioURL = URL(fileURLWithPath: "/tmp/retry.m4a")
        let sessionID = startSession(state)
        _ = state.send(.startSucceeded(sessionID: sessionID))
        _ = state.send(.stopRequested)
        _ = state.send(.captureStopped(sessionID: sessionID, audioURL))
        _ = state.send(.transcriptionFailed(
            sessionID: sessionID,
            .networkError("timeout"),
            audioURL: audioURL
        ))

        #expect(state.status == .error)
        #expect(state.lastAudioFileURL == audioURL)

        let effects = state.send(.retryRequested(
            targetBundleIdentifier: "com.example.editor",
            targetName: "Editor"
        ))
        let retrySessionID = retrySessionID(from: effects)

        #expect(effects == [.retryTranscription(sessionID: retrySessionID, audioURL)])
        #expect(state.status == .transcribing)
        #expect(state.startingAppBundleIdentifier == "com.example.editor")
    }

    @Test("late results from a completed session cannot mutate a restarted session")
    func staleResultsAreIgnoredAfterRestart() {
        let state = AppState()
        let firstEffects = state.send(.toggleRequested(
            targetBundleIdentifier: "first.app",
            targetName: "First"
        ))
        guard case .startCapture(let firstSessionID)? = firstEffects.first else {
            Issue.record("Expected session-scoped start effect")
            return
        }

        _ = state.send(.startSucceeded(sessionID: firstSessionID))
        _ = state.send(.stopRequested)
        _ = state.send(.captureUnavailable(sessionID: firstSessionID))

        let secondEffects = state.send(.toggleRequested(
            targetBundleIdentifier: "second.app",
            targetName: "Second"
        ))
        guard case .startCapture(let secondSessionID)? = secondEffects.first else {
            Issue.record("Expected second session-scoped start effect")
            return
        }

        _ = state.send(.partialUpdated(
            sessionID: firstSessionID,
            text: "이전 세션 콜백"
        ))
        _ = state.send(.startSucceeded(sessionID: firstSessionID))

        #expect(firstSessionID != secondSessionID)
        #expect(state.partialTranscription == nil)
        #expect(state.overlayPresentation == .starting)
    }

    private func startSession(_ state: AppState) -> UUID {
        startSessionID(from: state.send(.toggleRequested(
            targetBundleIdentifier: nil,
            targetName: nil
        )))
    }

    private func startSessionID(from effects: [RecordingEffect]) -> UUID {
        guard case .startCapture(let sessionID)? = effects.first else {
            preconditionFailure("Expected startCapture effect")
        }
        return sessionID
    }

    private func retrySessionID(from effects: [RecordingEffect]) -> UUID {
        guard case .retryTranscription(let sessionID, _)? = effects.first else {
            preconditionFailure("Expected retryTranscription effect")
        }
        return sessionID
    }
}
