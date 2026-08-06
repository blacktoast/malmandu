import Foundation
import Testing
@testable import MalmanduCore

@MainActor
@Suite("AppState session text reducer tests")
struct AppStatePartialTests {
    @Test("focus presentation is derived from the recording session")
    func focusPresentation() {
        let (state, sessionID) = recordingState()

        _ = state.send(.focusChanged(sessionID: sessionID, isTargetActive: false))
        #expect(state.focusLost)
        #expect(state.overlayPresentation == .focusLost)

        _ = state.send(.segmentFinalized(
            sessionID: sessionID,
            text: "대기 문장",
            isTargetActive: false
        ))
        _ = state.send(.focusChanged(sessionID: sessionID, isTargetActive: true))
        #expect(state.isAwaitingPendingPaste)
        #expect(state.overlayPresentation == .pendingPaste)
    }

    @Test("pending paste removes only the delivered prefix")
    func pendingPasteKeepsNewerText() {
        let (state, sessionID) = recordingState()
        _ = state.send(.focusChanged(sessionID: sessionID, isTargetActive: false))
        _ = state.send(.segmentFinalized(
            sessionID: sessionID,
            text: "첫 문장",
            isTargetActive: false
        ))
        _ = state.send(.focusChanged(sessionID: sessionID, isTargetActive: true))

        #expect(
            state.send(.pastePendingRequested(isTargetActive: true))
                == [.pastePending(sessionID: sessionID, text: "첫 문장")]
        )

        _ = state.send(.segmentFinalized(
            sessionID: sessionID,
            text: "다음 문장",
            isTargetActive: true
        ))
        _ = state.send(.pendingPasteSucceeded(sessionID: sessionID, text: "첫 문장"))

        #expect(state.pendingCopyText == "다음 문장")
        #expect(state.isAwaitingPendingPaste)
    }

    @Test("late final segments are accepted for finish and discarded for cancel")
    func lateFinalSegmentsRespectStopMode() {
        let (finishState, finishSessionID) = recordingState()
        _ = finishState.send(.stopRequested)
        #expect(
            finishState.send(.segmentFinalized(
                sessionID: finishSessionID,
                text: "마지막",
                isTargetActive: false
            )).isEmpty
        )
        #expect(finishState.pendingCopyText == "마지막")

        let (discardState, discardSessionID) = recordingState()
        _ = discardState.send(.cancelRequested)
        #expect(
            discardState.send(.segmentFinalized(
                sessionID: discardSessionID,
                text: "버림",
                isTargetActive: false
            )).isEmpty
        )
        #expect(discardState.pendingCopyText == nil)
    }

    @Test("partial text survives finish transition and clears on completion")
    func partialTextLifecycle() {
        let (state, sessionID) = recordingState()
        _ = state.send(.partialUpdated(sessionID: sessionID, text: "실시간 텍스트"))
        _ = state.send(.stopRequested)

        #expect(state.partialTranscription == "실시간 텍스트")

        _ = state.send(.captureUnavailable(sessionID: sessionID))

        #expect(state.partialTranscription == nil)
    }

    private func recordingState() -> (AppState, UUID) {
        let state = AppState()
        let effects = state.send(.toggleRequested(
            targetBundleIdentifier: "original.app",
            targetName: "Editor"
        ))
        guard case .startCapture(let sessionID)? = effects.first else {
            preconditionFailure("Expected startCapture effect")
        }
        _ = state.send(.startSucceeded(sessionID: sessionID))
        return (state, sessionID)
    }
}
