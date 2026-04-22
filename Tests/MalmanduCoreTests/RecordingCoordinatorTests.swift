import Testing
import Foundation
@testable import MalmanduCore

@Suite("RecordingCoordinator Tests")
struct RecordingCoordinatorTests {

    // MARK: - Helpers

    func makeSUT(
        startRecordingError: Error? = nil,
        stopRecordingError: Error? = nil,
        stopRecordingURL: URL = URL(fileURLWithPath: "/tmp/test.m4a"),
        transcribeError: Error? = nil,
        transcribeResult: String = "hello world",
        streamingClient: MockStreamingSTTClient? = nil
    ) -> (
        coordinator: RecordingCoordinator,
        appState: AppState,
        recorder: MockAudioRecorder,
        apiClient: MockGroqAPIClient,
        textInjector: MockTextInjector,
        soundService: MockSoundService
    ) {
        let appState = AppState()
        let recorder = MockAudioRecorder()
        recorder.startRecordingError = startRecordingError
        recorder.stopRecordingError = stopRecordingError
        recorder.stopRecordingResult = stopRecordingURL
        let apiClient = MockGroqAPIClient()
        apiClient.transcribeError = transcribeError
        apiClient.transcribeResult = transcribeResult
        let textInjector = MockTextInjector()
        let soundService = MockSoundService()

        let coordinator = RecordingCoordinator(
            appState: appState,
            audioRecorder: recorder,
            apiClient: apiClient,
            textInjector: textInjector,
            soundService: soundService,
            model: { streamingClient != nil ? "stt-rt-v1" : "whisper-large-v3" },
            startDelay: .zero,
            audioProcessor: MockAudioProcessor(),
            streamingClientProvider: { streamingClient }
        )

        return (coordinator, appState, recorder, apiClient, textInjector, soundService)
    }

    // MARK: - Test 1: idle → recording

    @Test("toggleRecording: idle 상태에서 호출하면 recording 상태가 된다")
    func toggleRecordingFromIdleStartsRecording() async {
        let (coordinator, appState, recorder, _, _, _) = makeSUT()

        // toggleRecording은 startRecording을 호출한 뒤 audioRecorder.startRecording을 await하므로
        // startRecording이 완료될 때까지 status가 recording으로 유지됨
        await coordinator.toggleRecording()

        // startRecording이 호출됐고 에러 없으면 status는 recording
        #expect(recorder.startRecordingCalled == true)
        // startRecording 완료 후 에러 없으면 recording 상태 유지
        #expect(appState.status == .recording)
    }

    @Test("toggleRecording: error 상태에서 호출하면 recording을 시작한다")
    func toggleRecordingFromErrorStartsRecording() async {
        let (coordinator, appState, recorder, _, _, _) = makeSUT()
        appState.fail(with: .apiKeyMissing)
        #expect(appState.status == .error)

        await coordinator.toggleRecording()

        #expect(recorder.startRecordingCalled == true)
        #expect(appState.status == .recording)
    }

    // MARK: - Test 2: recording → transcribing → idle

    @Test("toggleRecording: recording 상태에서 호출하면 transcribing을 거쳐 idle이 된다")
    func toggleRecordingFromRecordingTranscribesAndGoesIdle() async {
        let (coordinator, appState, _, _, textInjector, _) = makeSUT(transcribeResult: "안녕하세요")

        // 먼저 recording 시작
        await coordinator.toggleRecording()
        #expect(appState.status == .recording)

        // 두 번째 toggle: stop → transcribe → idle
        await coordinator.toggleRecording()

        #expect(appState.status == .idle)
        #expect(textInjector.pasteTextCalled == true)
        #expect(textInjector.lastPastedText == "안녕하세요")
    }

    // MARK: - Test 3: transcribing 상태에서는 무시

    @Test("toggleRecording: transcribing 상태에서 호출하면 아무것도 하지 않는다")
    func toggleRecordingFromTranscribingDoesNothing() async {
        let (coordinator, appState, recorder, apiClient, _, _) = makeSUT()

        // 수동으로 transcribing 상태로 설정
        appState.stopRecording() // idle → transcribing (via startRecording → stopRecording)
        // 실제로는 startRecording 없이 직접 transcribing으로
        appState.status = .transcribing

        let recorderCalledBefore = recorder.startRecordingCalled
        let apiCalledBefore = apiClient.transcribeCalled

        await coordinator.toggleRecording()

        // 아무것도 호출되지 않아야 함
        #expect(recorder.startRecordingCalled == recorderCalledBefore)
        #expect(apiClient.transcribeCalled == apiCalledBefore)
        #expect(appState.status == .transcribing)
    }

    // MARK: - Test 4: 성공적인 파이프라인

    @Test("성공 파이프라인: stop → transcribe → paste → idle")
    func successfulTranscriptionPipeline() async {
        let audioURL = URL(fileURLWithPath: "/tmp/pipeline_test.m4a")
        let (coordinator, appState, recorder, apiClient, textInjector, soundService) = makeSUT(
            stopRecordingURL: audioURL,
            transcribeResult: "transcribed text"
        )

        // start recording
        await coordinator.toggleRecording()
        #expect(appState.status == .recording)

        // stop and transcribe
        await coordinator.toggleRecording()

        #expect(recorder.stopRecordingCalled == true)
        #expect(apiClient.transcribeCalled == true)
        #expect(apiClient.lastAudioFileURL == audioURL)
        #expect(textInjector.pasteTextCalled == true)
        #expect(textInjector.lastPastedText == "transcribed text")
        #expect(appState.status == .idle)
        #expect(appState.lastAudioFileURL == nil) // 성공 시 URL 클리어
        // 효과음: recordingStarted, recordingStopped
        #expect(soundService.playedEvents.contains(.recordingStarted))
        #expect(soundService.playedEvents.contains(.recordingStopped))
    }

    // MARK: - Test 5: 전사 실패 시 에러 상태 및 audioURL 보존

    @Test("전사 실패: error 상태로 전환되고 audioURL이 보존된다")
    func failedTranscriptionPreservesAudioURL() async {
        let audioURL = URL(fileURLWithPath: "/tmp/fail_test.m4a")
        let transcribeError = AppError.transcriptionFailed("API timeout")
        let (coordinator, appState, _, _, textInjector, _) = makeSUT(
            stopRecordingURL: audioURL,
            transcribeError: transcribeError
        )

        await coordinator.toggleRecording() // start
        await coordinator.toggleRecording() // stop → fail

        #expect(appState.status == .error)
        #expect(appState.lastAudioFileURL == audioURL)
        #expect(textInjector.pasteTextCalled == false)
        if case .transcriptionFailed(let msg) = appState.lastError {
            #expect(msg == "API timeout")
        } else {
            Issue.record("Expected transcriptionFailed error")
        }
    }

    @Test("전사 실패: 일반 Error도 transcriptionFailed로 래핑된다")
    func failedTranscriptionWrapsGenericError() async {
        struct GenericError: Error { let message: String }
        let audioURL = URL(fileURLWithPath: "/tmp/generic_fail.m4a")
        let (coordinator, appState, _, _, _, _) = makeSUT(
            stopRecordingURL: audioURL,
            transcribeError: GenericError(message: "network down")
        )

        await coordinator.toggleRecording() // start
        await coordinator.toggleRecording() // stop → fail

        #expect(appState.status == .error)
        #expect(appState.lastAudioFileURL == audioURL)
        if case .transcriptionFailed = appState.lastError {
            // 래핑됨 - OK
        } else {
            Issue.record("Expected transcriptionFailed wrapping generic error")
        }
    }

    // MARK: - Test 6: retryLastTranscription

    @Test("retryLastTranscription: lastAudioFileURL을 사용해 재전사한다")
    func retryLastTranscriptionUsesLastAudioFileURL() async {
        let audioURL = URL(fileURLWithPath: "/tmp/retry_test.m4a")
        let (coordinator, appState, _, apiClient, textInjector, _) = makeSUT(
            transcribeResult: "retry result"
        )

        // 에러 상태에서 audioURL 보존
        appState.fail(with: .transcriptionFailed("first attempt"), audioURL: audioURL)

        await coordinator.retryLastTranscription()

        #expect(apiClient.transcribeCalled == true)
        #expect(apiClient.lastAudioFileURL == audioURL)
        #expect(textInjector.pasteTextCalled == true)
        #expect(textInjector.lastPastedText == "retry result")
        #expect(appState.status == .idle)
    }

    @Test("retryLastTranscription: lastAudioFileURL이 없으면 아무것도 하지 않는다")
    func retryLastTranscriptionWithNoURLDoesNothing() async {
        let (coordinator, appState, _, apiClient, _, _) = makeSUT()
        #expect(appState.lastAudioFileURL == nil)

        await coordinator.retryLastTranscription()

        #expect(apiClient.transcribeCalled == false)
        #expect(appState.status == .idle)
    }

    // MARK: - Test 7: 효과음

    @Test("효과음: 녹음 시작 시 recordingStarted 재생")
    func soundPlayedOnRecordingStart() async {
        let (coordinator, _, _, _, _, soundService) = makeSUT()

        await coordinator.toggleRecording()

        #expect(soundService.playedEvents.first == .recordingStarted)
    }

    @Test("효과음: 녹음 중지 시 recordingStopped 재생")
    func soundPlayedOnRecordingStop() async {
        let (coordinator, _, _, _, _, soundService) = makeSUT()

        await coordinator.toggleRecording() // start
        await coordinator.toggleRecording() // stop

        #expect(soundService.playedEvents.contains(.recordingStopped))
    }

    @Test("효과음: 전체 파이프라인에서 순서대로 재생된다")
    func soundPlayedInOrder() async {
        let (coordinator, _, _, _, _, soundService) = makeSUT()

        await coordinator.toggleRecording() // start → recordingStarted
        await coordinator.toggleRecording() // stop → recordingStopped

        #expect(soundService.playedEvents.count == 2)
        #expect(soundService.playedEvents[0] == .recordingStarted)
        #expect(soundService.playedEvents[1] == .recordingStopped)
    }

    // MARK: - Test 8: startRecording 에러

    @Test("startRecording 에러: error 상태로 전환된다")
    func startRecordingErrorSetsErrorState() async {
        struct RecordingError: Error, LocalizedError {
            var errorDescription: String? { "microphone unavailable" }
        }
        let (coordinator, appState, _, _, _, _) = makeSUT(
            startRecordingError: RecordingError()
        )

        await coordinator.toggleRecording()

        #expect(appState.status == .error)
        if case .recordingFailed(let msg) = appState.lastError {
            #expect(msg == "microphone unavailable")
        } else {
            Issue.record("Expected recordingFailed error")
        }
    }

    @Test("stopRecording 에러: error 상태로 전환된다")
    func stopRecordingErrorSetsErrorState() async {
        struct StopError: Error, LocalizedError {
            var errorDescription: String? { "stop failed" }
        }
        let (coordinator, appState, _, _, _, _) = makeSUT(
            stopRecordingError: StopError()
        )

        await coordinator.toggleRecording() // start
        await coordinator.toggleRecording() // stop → error

        #expect(appState.status == .error)
        if case .recordingFailed(let msg) = appState.lastError {
            #expect(msg == "stop failed")
        } else {
            Issue.record("Expected recordingFailed error")
        }
    }

    // MARK: - RT 모드 테스트

    @Test("RT 모드: 녹음 시작 시 startStreaming이 호출된다")
    func rtModeStartStreamingCalled() async {
        let streamingClient = MockStreamingSTTClient()
        let (coordinator, appState, recorder, _, _, _) = makeSUT(streamingClient: streamingClient)

        await coordinator.toggleRecording()

        #expect(streamingClient.startStreamingCalled == true)
        #expect(recorder.startRecordingCalled == true)
        #expect(appState.status == .recording)
    }

    @Test("RT 모드: 종료 시 남은 텍스트를 붙여넣는다")
    func rtModeFinishStreamingPastesRemainingText() async {
        let streamingClient = MockStreamingSTTClient()
        streamingClient.finishStreamingResult = "남은 텍스트"
        let (coordinator, appState, _, _, textInjector, _) = makeSUT(streamingClient: streamingClient)

        await coordinator.toggleRecording() // start (RT)
        await coordinator.toggleRecording() // stop → finishStreaming

        #expect(streamingClient.finishStreamingCalled == true)
        #expect(textInjector.pasteTextCalled == true)
        #expect(textInjector.lastPastedText == "남은 텍스트")
        #expect(appState.status == .idle)
    }

    @Test("RT 모드: 빈 텍스트면 붙여넣기 없이 idle로 복귀한다")
    func rtModeFinishStreamingEmptyTextGoesIdle() async {
        let streamingClient = MockStreamingSTTClient()
        streamingClient.finishStreamingResult = ""
        let (coordinator, appState, _, _, textInjector, _) = makeSUT(streamingClient: streamingClient)

        await coordinator.toggleRecording() // start (RT)
        await coordinator.toggleRecording() // stop → finishStreaming (empty)

        #expect(streamingClient.finishStreamingCalled == true)
        #expect(textInjector.pasteTextCalled == false)
        #expect(appState.status == .idle)
    }

    @Test("RT 모드: finishStreaming 에러 시 파일 기반 폴백으로 전환한다")
    func rtModeFinishStreamingErrorFallsBackToFile() async {
        let streamingClient = MockStreamingSTTClient()
        streamingClient.finishStreamingError = NSError(domain: "test", code: 1)
        let audioURL = URL(fileURLWithPath: "/tmp/rt_fallback.m4a")
        let (coordinator, appState, _, apiClient, textInjector, _) = makeSUT(
            stopRecordingURL: audioURL,
            transcribeResult: "폴백 결과",
            streamingClient: streamingClient
        )

        await coordinator.toggleRecording() // start (RT)
        await coordinator.toggleRecording() // stop → finishStreaming 에러 → 파일 폴백

        #expect(streamingClient.finishStreamingCalled == true)
        #expect(apiClient.transcribeCalled == true) // 파일 기반 폴백
        #expect(textInjector.lastPastedText == "폴백 결과")
        #expect(appState.status == .idle)
    }

    // MARK: - Cancel Recording Tests

    @Test("cancelRecording: 비동기 모드에서 호출하면 변환/붙여넣기 없이 idle로 복귀한다")
    func cancelRecordingAsyncModeDiscardsAudio() async {
        let (coordinator, appState, _, apiClient, textInjector, _) = makeSUT()

        await coordinator.toggleRecording()
        #expect(appState.status == .recording)

        await coordinator.cancelRecording()

        #expect(appState.status == .idle)
        #expect(apiClient.transcribeCalled == false, "취소 시 STT 호출 금지")
        #expect(textInjector.pasteTextCalled == false, "취소 시 붙여넣기 금지")
    }

    @Test("cancelRecording: RT 모드에서 호출하면 finishStreaming만 호출 후 idle로 복귀한다")
    func cancelRecordingRTModeClosesSocketAndDiscards() async {
        let streamingClient = MockStreamingSTTClient()
        streamingClient.finishStreamingResult = "남은 텍스트가 있어도"
        let (coordinator, appState, _, apiClient, textInjector, _) = makeSUT(streamingClient: streamingClient)

        await coordinator.toggleRecording()
        #expect(appState.status == .recording)

        await coordinator.cancelRecording()

        #expect(appState.status == .idle)
        #expect(streamingClient.finishStreamingCalled == true, "RT 모드는 소켓을 정리해야 함")
        #expect(apiClient.transcribeCalled == false, "취소 시 파일 기반 변환도 호출 금지")
        #expect(textInjector.pasteTextCalled == false, "취소 시 붙여넣기 금지 (남은 텍스트도 무시)")
    }

    @Test("cancelRecording: idle 상태에서 호출하면 아무것도 하지 않는다")
    func cancelRecordingFromIdleIsNoOp() async {
        let (coordinator, appState, recorder, _, _, _) = makeSUT()

        await coordinator.cancelRecording()

        #expect(appState.status == .idle)
        #expect(recorder.stopRecordingCalled == false)
    }

    @Test("cancelRecording: pendingCopyText와 partialTranscription을 모두 비운다")
    func cancelRecordingClearsPendingTexts() async {
        let streamingClient = MockStreamingSTTClient()
        let (coordinator, appState, _, _, _, _) = makeSUT(streamingClient: streamingClient)

        await coordinator.toggleRecording()
        appState.pendingCopyText = "이전 부분 텍스트"
        appState.partialTranscription = "스트리밍 중인 텍스트"

        await coordinator.cancelRecording()

        #expect(appState.pendingCopyText == nil)
        #expect(appState.partialTranscription == nil)
        #expect(appState.status == .idle)
    }
}
