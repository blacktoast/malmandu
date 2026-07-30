import Foundation
import Testing
@testable import MalmanduCore

@MainActor
@Suite("RecordingCoordinator Focus Buffer Tests")
struct RecordingCoordinatorFocusBufferTests {
    @Test("Focus-away finalized segments buffer without paste")
    func focusAwayFinalizedSegmentsBufferWithoutPaste() async {
        let (coordinator, appState, streamingClient, textInjector) = makeSUT()

        await coordinator.toggleRecording()
        coordinator.handleFocusChange(isOriginalAppActive: false)
        await streamingClient.emitFinalizedSegment("포커스 밖 문장")
        await waitFor { appState.pendingCopyText == "포커스 밖 문장" }

        #expect(appState.pendingCopyText == "포커스 밖 문장")
        #expect(textInjector.pasteTextCalled == false)
        #expect(streamingClient.pauseStreamingCallCount == 0)
        #expect(appState.status == .recording)
    }

    @Test("Returning to the original app exposes pending-paste state")
    func returningExposesPendingPasteState() async {
        let (coordinator, appState, streamingClient, _) = makeSUT()

        await coordinator.toggleRecording()
        coordinator.handleFocusChange(isOriginalAppActive: false)
        await streamingClient.emitFinalizedSegment("포커스 밖 문장")
        await waitFor { appState.pendingCopyText == "포커스 밖 문장" }
        coordinator.handleFocusChange(isOriginalAppActive: true)

        #expect(appState.focusLost == false)
        #expect(appState.isAwaitingPendingPaste == true)
        #expect(streamingClient.resumeStreamingCallCount == 0)
    }

    @Test("Pending paste inserts the buffer while recording continues")
    func pendingPasteInsertsBufferWhileRecordingContinues() async {
        let (coordinator, appState, streamingClient, textInjector) = makeSUT()

        await coordinator.toggleRecording()
        coordinator.handleFocusChange(isOriginalAppActive: false)
        await streamingClient.emitFinalizedSegment("포커스 밖 문장")
        await waitFor { appState.pendingCopyText == "포커스 밖 문장" }
        coordinator.handleFocusChange(isOriginalAppActive: true)

        await coordinator.pastePendingTranscription()

        #expect(textInjector.lastPastedText == "포커스 밖 문장")
        #expect(appState.pendingCopyText == nil)
        #expect(appState.isAwaitingPendingPaste == false)
        #expect(appState.status == .recording)
        #expect(streamingClient.finishStreamingCallCount == 0)
    }

    @Test("Speech finalized during pending paste remains buffered")
    func speechFinalizedDuringPendingPasteRemainsBuffered() async {
        let appState = AppState()
        let streamingClient = FocusBufferStreamingClient()
        let textInjector = SuspendingTextInjector()
        let coordinator = RecordingCoordinator(
            appState: appState,
            audioRecorder: MockAudioRecorder(),
            apiClient: MockGroqAPIClient(),
            textInjector: textInjector,
            soundService: MockSoundService(),
            model: { "stt-rt-v1" },
            startDelay: .zero,
            audioProcessor: MockAudioProcessor(),
            streamingClientProvider: { streamingClient }
        )

        await coordinator.toggleRecording()
        coordinator.handleFocusChange(isOriginalAppActive: false)
        await streamingClient.emitFinalizedSegment("첫 문장")
        await waitFor { appState.pendingCopyText == "첫 문장" }
        coordinator.handleFocusChange(isOriginalAppActive: true)

        let pasteTask = Task { await coordinator.pastePendingTranscription() }
        await waitFor { textInjector.pasteStarted }
        await streamingClient.emitFinalizedSegment("다음 문장")
        await waitFor { appState.pendingCopyText == "첫 문장다음 문장" }
        textInjector.finishPastes()
        await pasteTask.value

        #expect(appState.pendingCopyText == "다음 문장")
        #expect(appState.isAwaitingPendingPaste == true)
        #expect(appState.status == .recording)
    }

    @Test("Finalized segments remain buffered while the paste prompt awaits")
    func finalizedSegmentsRemainBufferedWhilePromptAwaits() async {
        let (coordinator, appState, streamingClient, textInjector) = makeSUT()

        await coordinator.toggleRecording()
        coordinator.handleFocusChange(isOriginalAppActive: false)
        await streamingClient.emitFinalizedSegment("첫 문장")
        await waitFor { appState.pendingCopyText == "첫 문장" }
        coordinator.handleFocusChange(isOriginalAppActive: true)
        await streamingClient.emitFinalizedSegment("다음 문장")
        await waitFor { appState.pendingCopyText == "첫 문장다음 문장" }

        #expect(appState.isAwaitingPendingPaste == true)
        #expect(appState.pendingCopyText == "첫 문장다음 문장")
        #expect(textInjector.pasteTextCalled == false)
    }

    @Test("Final confirmation pastes pending and final text")
    func finalConfirmationPastesPendingAndFinishResult() async {
        let (coordinator, appState, streamingClient, textInjector) = makeSUT()
        streamingClient.finishStreamingResult = "마지막 문장"

        await coordinator.toggleRecording()
        coordinator.handleFocusChange(isOriginalAppActive: false)
        await streamingClient.emitFinalizedSegment("대기 문장")
        await waitFor { appState.pendingCopyText == "대기 문장" }
        coordinator.handleFocusChange(isOriginalAppActive: true)

        await coordinator.toggleRecording()

        #expect(textInjector.lastPastedText == "대기 문장마지막 문장")
        #expect(appState.status == .idle)
    }

    @Test("Stopping while focus is away never pastes into another app")
    func stoppingWhileFocusIsAwayDoesNotPaste() async {
        let (coordinator, appState, streamingClient, textInjector) = makeSUT()
        streamingClient.finishStreamingResult = "마지막 문장"

        await coordinator.toggleRecording()
        coordinator.handleFocusChange(isOriginalAppActive: false)
        await streamingClient.emitFinalizedSegment("대기 문장")
        await waitFor { appState.pendingCopyText == "대기 문장" }

        await coordinator.toggleRecording()

        #expect(textInjector.pasteTextCalled == false)
        #expect(textInjector.lastCopiedText == "대기 문장마지막 문장")
        #expect(appState.status == .idle)
    }

    @Test("Current frontmost app is rechecked before pending paste")
    func currentAppIsRecheckedBeforePendingPaste() async {
        let focus = MutableFocusProvider()
        let (coordinator, appState, streamingClient, textInjector) = makeSUT {
            focus.bundleIdentifier
        }

        await coordinator.toggleRecording()
        coordinator.handleFocusChange(isOriginalAppActive: false)
        await streamingClient.emitFinalizedSegment("대기 문장")
        await waitFor { appState.pendingCopyText == "대기 문장" }
        coordinator.handleFocusChange(isOriginalAppActive: true)
        focus.bundleIdentifier = "other.app"

        await coordinator.pastePendingTranscription()

        #expect(textInjector.pasteTextCalled == false)
        #expect(appState.pendingCopyText == "대기 문장")
        #expect(appState.focusLost == true)
    }

    @Test("Final segment emitted by finish is delivered before completion")
    func finalSegmentEmittedByFinishIsDelivered() async {
        let (coordinator, appState, streamingClient, textInjector) = makeSUT()
        streamingClient.finalizedSegmentOnFinish = "종료 직전 문장"
        streamingClient.finishStreamingResult = "마지막 문장"

        await coordinator.toggleRecording()
        await coordinator.toggleRecording()

        #expect(textInjector.pastedTexts.joined() == "종료 직전 문장마지막 문장")
        #expect(appState.status == .idle)
    }

    @Test("Cancel discards a final segment emitted while closing the stream")
    func cancelDiscardsFinalSegmentEmittedWhileClosing() async {
        let (coordinator, appState, streamingClient, textInjector) = makeSUT()
        streamingClient.finalizedSegmentOnFinish = "버려야 할 문장"

        await coordinator.toggleRecording()
        await coordinator.cancelRecording()

        #expect(textInjector.pasteTextCalled == false)
        #expect(appState.pendingCopyText == nil)
        #expect(appState.status == .idle)
    }

    @Test("Repeated cancel clicks cannot release final-segment suppression early")
    func repeatedCancelClicksKeepFinalSegmentSuppressed() async {
        let (coordinator, appState, streamingClient, textInjector) = makeSUT()
        streamingClient.finalizedSegmentOnFinish = "버려야 할 문장"
        streamingClient.suspendFinishStreaming = true

        await coordinator.toggleRecording()
        let firstCancel = Task { await coordinator.cancelRecording() }
        await waitFor { streamingClient.finishStreamingIsSuspended }

        let secondCancel = Task { await coordinator.cancelRecording() }
        await secondCancel.value
        streamingClient.resumeFinishStreaming()
        await firstCancel.value

        #expect(streamingClient.finishStreamingCallCount == 1)
        #expect(textInjector.pasteTextCalled == false)
        #expect(appState.status == .idle)
    }

    @Test("Repeated pending-paste clicks inject only once")
    func repeatedPendingPasteClicksInjectOnlyOnce() async {
        let appState = AppState()
        let streamingClient = FocusBufferStreamingClient()
        let textInjector = SuspendingTextInjector()
        let coordinator = RecordingCoordinator(
            appState: appState,
            audioRecorder: MockAudioRecorder(),
            apiClient: MockGroqAPIClient(),
            textInjector: textInjector,
            soundService: MockSoundService(),
            model: { "stt-rt-v1" },
            startDelay: .zero,
            audioProcessor: MockAudioProcessor(),
            streamingClientProvider: { streamingClient },
            frontmostAppBundleId: { "original.app" }
        )

        await coordinator.toggleRecording()
        coordinator.handleFocusChange(isOriginalAppActive: false)
        await streamingClient.emitFinalizedSegment("한 번만")
        coordinator.handleFocusChange(isOriginalAppActive: true)

        let firstPaste = Task { await coordinator.pastePendingTranscription() }
        await waitFor { textInjector.pasteCallCount == 1 }
        let secondPaste = Task { await coordinator.pastePendingTranscription() }
        await waitFor { textInjector.pasteCallCount > 1 }
        textInjector.finishPastes()
        await firstPaste.value
        await secondPaste.value

        #expect(textInjector.pasteCallCount == 1)
    }

    private func makeSUT() -> (
        coordinator: RecordingCoordinator,
        appState: AppState,
        streamingClient: FocusBufferStreamingClient,
        textInjector: MockTextInjector
    ) {
        makeSUT(frontmostAppBundleId: { "original.app" })
    }

    private func makeSUT(
        frontmostAppBundleId: @escaping @Sendable () -> String?
    ) -> (
        coordinator: RecordingCoordinator,
        appState: AppState,
        streamingClient: FocusBufferStreamingClient,
        textInjector: MockTextInjector
    ) {
        let appState = AppState()
        let streamingClient = FocusBufferStreamingClient()
        let textInjector = MockTextInjector()
        let coordinator = RecordingCoordinator(
            appState: appState,
            audioRecorder: MockAudioRecorder(),
            apiClient: MockGroqAPIClient(),
            textInjector: textInjector,
            soundService: MockSoundService(),
            model: { "stt-rt-v1" },
            startDelay: .zero,
            audioProcessor: MockAudioProcessor(),
            streamingClientProvider: { streamingClient },
            frontmostAppBundleId: frontmostAppBundleId
        )
        return (coordinator, appState, streamingClient, textInjector)
    }

    private func waitFor(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            await Task.yield()
        }
    }
}

private final class SuspendingTextInjector: TextInjectorProtocol, @unchecked Sendable {
    private(set) var pasteCallCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var pasteStarted: Bool { pasteCallCount > 0 }

    func pasteText(_ text: String) async -> PasteResult {
        pasteCallCount += 1
        await withCheckedContinuation { continuations.append($0) }
        return .success
    }

    func copyText(_ text: String) {}

    func finishPastes() {
        let pending = continuations
        continuations = []
        pending.forEach { $0.resume() }
    }
}

private final class FocusBufferStreamingClient: StreamingSTTServiceProtocol, @unchecked Sendable {
    var finishStreamingResult = ""
    var finalizedSegmentOnFinish: String?
    var suspendFinishStreaming = false
    private(set) var finishStreamingCallCount = 0
    private(set) var finishStreamingIsSuspended = false
    private(set) var pauseStreamingCallCount = 0
    private(set) var resumeStreamingCallCount = 0

    private var onSegmentFinalized: SegmentFinalizedHandler?
    private var finishStreamingContinuation: CheckedContinuation<Void, Never>?

    func startStreaming(
        language: String?,
        model: String,
        onPartialResult: @escaping PartialResultHandler,
        onSegmentFinalized: @escaping SegmentFinalizedHandler
    ) async throws {
        self.onSegmentFinalized = onSegmentFinalized
    }

    func sendAudioChunk(_ data: Data) async throws {}

    func finishStreaming() async throws -> String {
        finishStreamingCallCount += 1
        if suspendFinishStreaming {
            await withCheckedContinuation {
                finishStreamingIsSuspended = true
                finishStreamingContinuation = $0
            }
        }
        if let finalizedSegmentOnFinish {
            await onSegmentFinalized?(finalizedSegmentOnFinish)
        }
        return finishStreamingResult
    }

    func resumeFinishStreaming() {
        finishStreamingIsSuspended = false
        finishStreamingContinuation?.resume()
        finishStreamingContinuation = nil
    }

    func pauseStreaming() async {
        pauseStreamingCallCount += 1
    }

    func resumeStreaming() async {
        resumeStreamingCallCount += 1
    }

    func emitFinalizedSegment(_ text: String) async {
        guard let onSegmentFinalized else {
            Issue.record("Expected streaming to start before emitting a finalized segment")
            return
        }
        await onSegmentFinalized(text)
    }
}

private final class MutableFocusProvider: @unchecked Sendable {
    var bundleIdentifier: String? = "original.app"
}
