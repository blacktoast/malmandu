import AppKit
import SwiftUI
import Testing
@testable import MalmanduCore

@Suite("RecordingOverlayView layout tests", .serialized)
struct RecordingOverlayViewLayoutTests {
    @Test("real-time text can grow past three lines without re-entering AppKit constraints")
    @MainActor
    func multilineRealtimeText() async throws {
        _ = NSApplication.shared

        let state = AppState()
        let streamingClient = MockStreamingSTTClient()
        let coordinator = RecordingCoordinator(
            appState: state,
            audioRecorder: MockAudioRecorder(),
            apiClient: MockGroqAPIClient(),
            textInjector: MockTextInjector(),
            soundService: MockSoundService(),
            model: { "stt-rt-v1" },
            startDelay: .zero,
            audioProcessor: MockAudioProcessor(),
            streamingClientProvider: { streamingClient }
        )
        await coordinator.toggleRecording()

        nonisolated(unsafe) var sawAnimatedTranscriptUpdate = false
        let rootView = OverlayRootView(appState: state, coordinator: coordinator)
            .transaction { transaction in
                if state.partialTranscription != nil, transaction.animation != nil {
                    sawAnimatedTranscriptUpdate = true
                }
            }
        let hostingView = ClickThroughHostingView(rootView: rootView)
        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 200))
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        defer { panel.close() }

        try await Task.sleep(for: .milliseconds(400))
        streamingClient.emitPartialResult(
            String(repeating: "실시간 받아쓰기 문장이 계속 길어집니다. ", count: 20)
        )
        try await Task.sleep(for: .milliseconds(100))
        hostingView.updateConstraintsForSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        #expect(sawAnimatedTranscriptUpdate == false)
        #expect(panel.contentLayoutRect.size == NSSize(width: 280, height: 200))
    }

    @Test("pending paste prompt keeps the overlay panel fixed")
    @MainActor
    func pendingPastePromptLayout() async throws {
        _ = NSApplication.shared

        let state = AppState()
        state.status = .recording
        state.pendingCopyText = "포커스를 잃은 동안 말한 문장"
        state.isAwaitingPendingPaste = true

        let rootView = RecordingOverlayView(
            appState: state,
            isRealtimeMode: true,
            onPastePending: {}
        )
        let hostingView = ClickThroughHostingView(rootView: rootView)
        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 200))
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        defer { panel.close() }

        try await Task.sleep(for: .milliseconds(100))
        hostingView.updateConstraintsForSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        #expect(panel.contentLayoutRect.size == NSSize(width: 280, height: 200))
    }
}
