import AppKit
import Foundation
import Observation

/// 녹음 → STT → 붙여넣기 파이프라인 조율자
@MainActor
@Observable
public final class RecordingCoordinator: @unchecked Sendable {
    public let appState: AppState
    private let audioRecorder: AudioRecorderProtocol
    private let apiClient: any STTServiceProtocol
    private let textInjector: TextInjectorProtocol
    private let soundService: SoundServiceProtocol
    private let language: () -> String?
    private let model: () -> String
    private let prompt: () -> String?
    private let startDelay: Duration
    private let apiKeyCheck: () -> Bool
    private let audioProcessor: AudioProcessorProtocol
    private let streamingClientProvider: () -> (any StreamingSTTServiceProtocol)?
    private let frontmostAppBundleId: @Sendable () -> String?
    private let textPolisher: TextPolisher?
    private let polishEnabled: () -> Bool

    /// 현재 활성화된 스트리밍 클라이언트 (RT 모드 녹음 중)
    private var activeStreamingClient: (any StreamingSTTServiceProtocol)?
    /// 녹음 시작 시 포커스되어 있던 앱의 번들 ID
    public var startingAppBundleId: String? { appState.startingAppBundleIdentifier }
    /// 포커스 변화 감시 태스크
    private var focusObserver: Task<Void, Never>?
    /// 비동기 모드 오디오 레벨 폴링 타이머
    private var meteringTimer: Task<Void, Never>?
    /// RT 모드: WebSocket 연결 전 수신된 오디오 청크 임시 버퍼
    private var audioChunkBuffer: [Data] = []
    private let audioChunkBufferLimit = 150  // 64ms * 150 ≈ 9.6초
    /// RT 모드 초기화 중 stop이 호출됐는지 플래그
    private var stopRequested = false
    /// start effect가 끝나기 전에 stop/cancel이 들어오면 해당 effect가 정리를 마무리한다.
    private var startEffectInFlight = false
    /// 대기 문장 중복 붙여넣기 방지
    private var pendingPasteInProgress = false
    /// 상태 변경 콜백 (오버레이 제어용)
    public var onStatusChange: ((AppStatus) -> Void)?
    /// 에러 발생 콜백 (토스트 표시용)
    public var onError: ((AppError) -> Void)?

    public init(
        appState: AppState,
        audioRecorder: AudioRecorderProtocol,
        apiClient: any STTServiceProtocol,
        textInjector: TextInjectorProtocol,
        soundService: SoundServiceProtocol,
        language: @escaping () -> String? = { "ko" },
        model: @escaping () -> String = { "whisper-large-v3" },
        prompt: @escaping () -> String? = { nil },
        startDelay: Duration = .milliseconds(200),
        apiKeyCheck: @escaping () -> Bool = { true },
        audioProcessor: AudioProcessorProtocol = AudioProcessor(),
        streamingClientProvider: @escaping () -> (any StreamingSTTServiceProtocol)? = { nil },
        frontmostAppBundleId: @escaping @Sendable () -> String? = { FocusDetector().frontmostAppBundleId() },
        textPolisher: TextPolisher? = nil,
        polishEnabled: @escaping () -> Bool = { false }
    ) {
        self.appState = appState
        self.audioRecorder = audioRecorder
        self.apiClient = apiClient
        self.textInjector = textInjector
        self.soundService = soundService
        self.language = language
        self.model = model
        self.prompt = prompt
        self.startDelay = startDelay
        self.apiKeyCheck = apiKeyCheck
        self.audioProcessor = audioProcessor
        self.streamingClientProvider = streamingClientProvider
        self.frontmostAppBundleId = frontmostAppBundleId
        self.textPolisher = textPolisher
        self.polishEnabled = polishEnabled
    }

    public func toggleRecording() async {
        let focusDetector = FocusDetector()
        await dispatch(.toggleRequested(
            targetBundleIdentifier: frontmostAppBundleId(),
            targetName: focusDetector.frontmostAppName()
        ))
    }

    /// 녹음을 즉시 취소한다 — 오디오/소켓을 모두 폐기하고 변환 없이 idle로 복귀.
    /// RT/Async 모드 모두 동일하게 동작: 어떤 텍스트도 붙여넣지 않는다.
    @MainActor
    public func cancelRecording() async {
        await dispatch(.cancelRequested)
    }

    public func retryLastTranscription() async {
        let focusDetector = FocusDetector()
        await dispatch(.retryRequested(
            targetBundleIdentifier: frontmostAppBundleId(),
            targetName: focusDetector.frontmostAppName()
        ))
    }

    /// 현재 선택된 모델이 실시간 모드인지 확인
    public var isRealtimeMode: Bool {
        STTProvider.isRealtimeModel(model())
    }

    private func dispatch(_ action: RecordingAction) async {
        let effects = reduce(action)
        for effect in effects {
            await perform(effect)
        }
    }

    private func reduce(_ action: RecordingAction) -> [RecordingEffect] {
        let previousStatus = appState.status
        let effects = appState.send(action)
        if appState.status != previousStatus {
            onStatusChange?(appState.status)
        }
        return effects
    }

    private func perform(_ effect: RecordingEffect) async {
        switch effect {
        case .startCapture(let sessionID):
            await startRecording(sessionID: sessionID)
        case .stopCapture(let sessionID):
            await stopAndTranscribe(sessionID: sessionID)
        case .cancelCapture(let sessionID):
            await discardRecording(sessionID: sessionID)
        case .finishTranscription(let sessionID, let audioURL),
             .retryTranscription(let sessionID, let audioURL):
            if let streamingClient = activeStreamingClient {
                activeStreamingClient = nil
                await streamingTranscribeAndPaste(
                    sessionID: sessionID,
                    streamingClient: streamingClient,
                    fallbackAudioURL: audioURL
                )
            } else {
                await transcribeAndPaste(sessionID: sessionID, audioURL: audioURL)
            }
        case .pasteSegment(let sessionID, let text):
            let result = await textInjector.pasteText(text)
            if result == .needsAccessibilityPermission {
                _ = reduce(.segmentDeliveryFailed(sessionID: sessionID, text: text))
                onError?(.accessibilityPermissionDenied)
            }
        case .pastePending(let sessionID, let text):
            guard !pendingPasteInProgress else { return }
            pendingPasteInProgress = true
            defer { pendingPasteInProgress = false }

            let result = await textInjector.pasteText(text)
            if result == .needsAccessibilityPermission {
                _ = reduce(.pendingPasteFailed(sessionID: sessionID))
                onError?(.accessibilityPermissionDenied)
            } else {
                _ = reduce(.pendingPasteSucceeded(sessionID: sessionID, text: text))
            }
        }
    }

    // MARK: - 녹음 시작

    private func startRecording(sessionID: UUID) async {
        startEffectInFlight = true
        stopRequested = false
        defer { startEffectInFlight = false }

        // API 키 사전 체크
        if !apiKeyCheck() {
            let err = AppError.apiKeyMissing
            await dispatch(.startFailed(sessionID: sessionID, err))
            onError?(err)
            return
        }

        soundService.play(.recordingStarted)
        // 효과음이 마이크에 포착되지 않도록 딜레이
        try? await Task.sleep(for: startDelay)

        guard appState.currentSessionID == sessionID,
              case .starting = appState.flowState else {
            await completeInterruptedStart(sessionID: sessionID)
            return
        }

        do {
            if isRealtimeMode, let streamingClient = streamingClientProvider() {
                // 실시간 모드: 마이크 먼저 → WebSocket 연결 → 버퍼 flush
                audioChunkBuffer = []

                // 1. 마이크 먼저 시작 — WebSocket 연결 중에도 오디오 캡처
                try await audioRecorder.startRecordingWithStream(
                    onAudioChunk: { [weak self] chunk in
                        Task { @MainActor [weak self] in
                            guard let self, self.appState.currentSessionID == sessionID else { return }
                            if let client = self.activeStreamingClient {
                                try? await client.sendAudioChunk(chunk)
                            } else if self.audioChunkBuffer.count < self.audioChunkBufferLimit {
                                self.audioChunkBuffer.append(chunk)
                            }
                        }
                    },
                    onAudioLevel: { [weak self] level in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            var levels = self.appState.audioLevels
                            levels.removeFirst()
                            levels.append(CGFloat(level))
                            _ = self.reduce(.audioLevelsUpdated(
                                sessionID: sessionID,
                                levels: levels
                            ))
                        }
                    }
                )

                if stopRequested {
                    await completeInterruptedStart(sessionID: sessionID)
                    return
                }

                // 2. WebSocket 연결
                try await streamingClient.startStreaming(
                    language: language(),
                    model: model(),
                    onPartialResult: { [weak self] partialText in
                        Task { @MainActor [weak self] in
                            _ = self?.reduce(.partialUpdated(
                                sessionID: sessionID,
                                text: partialText
                            ))
                        }
                    },
                    onSegmentFinalized: { [weak self] (confirmedText: String) in
                        guard let self else { return }
                        await self.handleFinalizedSegment(
                            confirmedText,
                            sessionID: sessionID
                        )
                    }
                )

                // startStreaming 대기 중 stop 호출 감지 — 즉시 정리 후 종료
                if stopRequested {
                    audioChunkBuffer = []
                    _ = try? await streamingClient.finishStreaming() as String
                    await completeInterruptedStart(sessionID: sessionID)
                    print("[RT Pipeline] 초기화 중 취소됨 → WebSocket 정리")
                    return
                }

                activeStreamingClient = streamingClient
                startFocusMonitoring(sessionID: sessionID)

                // 3. 버퍼된 청크 flush
                let buffered = audioChunkBuffer
                audioChunkBuffer = []
                for chunk in buffered {
                    try? await streamingClient.sendAudioChunk(chunk)
                }
                if stopRequested {
                    activeStreamingClient = nil
                    _ = try? await streamingClient.finishStreaming() as String
                    await completeInterruptedStart(sessionID: sessionID)
                    return
                }
                startEffectInFlight = false
                await dispatch(.startSucceeded(sessionID: sessionID))
                print("[RT Pipeline] 실시간 스트리밍 녹음 시작 (버퍼 \(buffered.count)개 flush)")
            } else {
                // 일반 모드: 파일 기반 녹음
                try await audioRecorder.startRecording()
                if stopRequested {
                    await completeInterruptedStart(sessionID: sessionID)
                    return
                }
                // AVAudioRecorder 미터링으로 오디오 레벨 폴링 (파형 표시용)
                startMeteringTimer(sessionID: sessionID)
                startEffectInFlight = false
                await dispatch(.startSucceeded(sessionID: sessionID))
            }
        } catch {
            audioChunkBuffer = []
            activeStreamingClient = nil
            focusObserver?.cancel()
            focusObserver = nil
            if stopRequested {
                await completeInterruptedStart(sessionID: sessionID)
                return
            }
            // duckSystemVolume이 이미 호출된 상태이므로 볼륨 복원 (에러 무시)
            do { _ = try await audioRecorder.stopRecording() } catch {}
            let err = AppError.recordingFailed(error.localizedDescription)
            await dispatch(.startFailed(sessionID: sessionID, err))
            onError?(err)
        }
    }

    // MARK: - 녹음 중지 + 변환

    private func stopAndTranscribe(sessionID: UUID) async {
        stopRequested = true
        if startEffectInFlight {
            if audioRecorder.isRecording() {
                do {
                    let audioURL = try await audioRecorder.stopRecording()
                    try? FileManager.default.removeItem(at: audioURL)
                    soundService.play(.recordingStopped)
                } catch {
                    let err = AppError.recordingFailed(error.localizedDescription)
                    await dispatch(.captureStopFailed(sessionID: sessionID, err))
                    onError?(err)
                }
            }
            return
        }

        do {
            let audioURL = try await audioRecorder.stopRecording()
            audioChunkBuffer = []
            focusObserver?.cancel()
            focusObserver = nil
            stopMeteringTimer()
            soundService.play(.recordingStopped)

            await dispatch(.captureStopped(sessionID: sessionID, audioURL))
        } catch {
            await closeActiveStreamingClient()
            clearCaptureObservers()
            let err = AppError.recordingFailed(error.localizedDescription)
            await dispatch(.captureStopFailed(sessionID: sessionID, err))
            onError?(err)
        }
    }

    private func discardRecording(sessionID: UUID) async {
        stopRequested = true

        if audioRecorder.isRecording() {
            do {
                let audioURL = try await audioRecorder.stopRecording()
                try? FileManager.default.removeItem(at: audioURL)
                print("[Cancel] 오디오 파일 폐기: \(audioURL.lastPathComponent)")
                soundService.play(.recordingStopped)
            } catch {
                print("[Cancel] 녹음 중지 실패 (무시): \(error)")
            }
        }

        if startEffectInFlight {
            return
        }

        if activeStreamingClient != nil {
            await closeActiveStreamingClient()
            print("[Cancel] RT 스트리밍 클라이언트 종료")
        }

        clearCaptureObservers()
        await dispatch(.cancelCompleted(sessionID: sessionID))
    }

    private func completeInterruptedStart(sessionID: UUID) async {
        if audioRecorder.isRecording() {
            if let audioURL = try? await audioRecorder.stopRecording() {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        audioChunkBuffer = []
        activeStreamingClient = nil
        clearCaptureObservers()

        switch appState.flowState {
        case .stopping(_, .finish):
            await dispatch(.captureUnavailable(sessionID: sessionID))
        case .stopping(_, .discard):
            await dispatch(.cancelCompleted(sessionID: sessionID))
        default:
            break
        }
    }

    private func clearCaptureObservers() {
        audioChunkBuffer = []
        focusObserver?.cancel()
        focusObserver = nil
        stopMeteringTimer()
    }

    private func closeActiveStreamingClient() async {
        guard let streamingClient = activeStreamingClient else { return }
        activeStreamingClient = nil
        _ = try? await streamingClient.finishStreaming() as String
    }

    // MARK: - 실시간 스트리밍 변환

    private func streamingTranscribeAndPaste(
        sessionID: UUID,
        streamingClient: any StreamingSTTServiceProtocol,
        fallbackAudioURL: URL
    ) async {
        do {
            // UI가 .transcribing 상태를 렌더링할 시간 확보
            // (소켓이 이미 끊긴 경우 finishStreaming이 즉시 반환되어 Thinking이 안 보이는 문제 방지)
            try? await Task.sleep(for: .milliseconds(300))
            let remainingText = try await streamingClient.finishStreaming()
            let textToPaste = (appState.pendingCopyText ?? "") + remainingText
            // 대기 중인 텍스트와 남은 텍스트를 발화 순서대로 한 번에 붙여넣기
            if !textToPaste.isEmpty {
                if appState.focusLost || !isOriginalAppFrontmost {
                    print("[RT Pipeline] 포커스 이탈 상태에서 종료 — 클립보드에 보존")
                    textInjector.copyText(textToPaste)
                } else {
                    print("[RT Pipeline] 미전달 텍스트 붙여넣기: \(textToPaste.prefix(50))...")
                    let result = await textInjector.pasteText(textToPaste)
                    if result == .needsAccessibilityPermission {
                        print("[RT Pipeline] Accessibility 권한 부재 — 클립보드 복사만 수행, 토스트 안내")
                        onError?(.accessibilityPermissionDenied)
                    }
                }
            } else {
                print("[RT Pipeline] 실시간 변환 완료 (모든 텍스트 이미 전달됨)")
            }
            await dispatch(.transcriptionSucceeded(sessionID: sessionID))
            try? FileManager.default.removeItem(at: fallbackAudioURL)
        } catch {
            print("[RT Pipeline] 실시간 변환 실패, 파일 기반 폴백 시도: \(error)")
            await transcribeAndPaste(sessionID: sessionID, audioURL: fallbackAudioURL)
        }
    }

    // MARK: - 포커스 모니터링

    @MainActor
    private func handleFinalizedSegment(_ confirmedText: String, sessionID: UUID) async {
        await dispatch(.segmentFinalized(
            sessionID: sessionID,
            text: confirmedText,
            isTargetActive: isOriginalAppFrontmost
        ))
    }

    @MainActor
    func handleFocusChange(isOriginalAppActive: Bool) {
        guard let sessionID = appState.currentSessionID else { return }
        if isOriginalAppActive {
            if appState.focusLost {
                print("[Focus] 원래 앱으로 포커스 복귀")
            }
        } else {
            if !appState.focusLost {
                print("[Focus] 원래 앱에서 포커스 이탈")
            }
        }
        _ = reduce(.focusChanged(
            sessionID: sessionID,
            isTargetActive: isOriginalAppActive
        ))
    }

    @MainActor
    public func pastePendingTranscription() async {
        await dispatch(.pastePendingRequested(isTargetActive: isOriginalAppFrontmost))
    }

    private func startFocusMonitoring(sessionID: UUID) {
        focusObserver?.cancel()
        focusObserver = Task { @MainActor [weak self] in
            let center = NSWorkspace.shared.notificationCenter
            let stream = center.notifications(named: NSWorkspace.didActivateApplicationNotification)
            for await notification in stream {
                guard let self else { break }
                guard self.appState.currentSessionID == sessionID,
                      self.appState.status == .recording else { continue }
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { continue }
                let activeBundleId = app.bundleIdentifier
                if activeBundleId == self.startingAppBundleId {
                    self.handleFocusChange(isOriginalAppActive: true)
                } else if activeBundleId != Bundle.main.bundleIdentifier {
                    self.handleFocusChange(isOriginalAppActive: false)
                }
            }
        }
    }

    // MARK: - 비동기 모드 오디오 레벨 폴링

    private func startMeteringTimer(sessionID: UUID) {
        meteringTimer?.cancel()
        guard let recorder = audioRecorder as? AudioRecorder else { return }
        meteringTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, self.appState.status == .recording else { break }
                let level = recorder.currentLevel()
                var levels = self.appState.audioLevels
                levels.removeFirst()
                levels.append(CGFloat(level))
                _ = self.reduce(.audioLevelsUpdated(
                    sessionID: sessionID,
                    levels: levels
                ))
            }
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.cancel()
        meteringTimer = nil
    }

    private var isOriginalAppFrontmost: Bool {
        guard let startingAppBundleId else { return false }
        return frontmostAppBundleId() == startingAppBundleId
    }

    // MARK: - 파일 기반 변환 (기존 로직)

    private func transcribeAndPaste(sessionID: UUID, audioURL: URL) async {
        do {
            // 원본 오디오 파일 정보
            let origSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
            print("[Async] 원본 파일: \(audioURL.lastPathComponent), 크기: \(origSize)bytes")

            // VAD로 무음 구간 제거 후 전송
            let processedURL = try await audioProcessor.trimSilence(from: audioURL)
            let procSize = (try? FileManager.default.attributesOfItem(atPath: processedURL.path)[.size] as? Int) ?? 0
            print("[Async] VAD 처리 후: \(processedURL.lastPathComponent), 크기: \(procSize)bytes, 동일파일: \(processedURL == audioURL)")

            print("[Async] API 호출: model=\(model()), language=\(language() ?? "nil")")
            var text = try await apiClient.transcribe(audioFileURL: processedURL, language: language(), model: model(), prompt: prompt())
            print("[Async] API 응답: \"\(text.prefix(100))\" (길이: \(text.count))")

            // VAD 처리된 파일 삭제 (원본과 다른 경우)
            if processedURL != audioURL {
                try? FileManager.default.removeItem(at: processedURL)
            }
            // LLM 텍스트 정리 (활성화된 경우)
            if polishEnabled(), let polisher = textPolisher {
                let before = text
                text = (try? await polisher.polish(text, language: language())) ?? text
                print("[Async] 폴리시: \"\(before.prefix(50))\" → \"\(text.prefix(50))\"")
            }
            // 포커스 확인 후 붙여넣기
            if isOriginalAppFrontmost {
                let result = await textInjector.pasteText(text)
                if result == .needsAccessibilityPermission {
                    print("[Async] Accessibility 권한 부재 — 클립보드 복사만 수행, 토스트 안내")
                    onError?(.accessibilityPermissionDenied)
                    _ = reduce(.segmentDeliveryFailed(
                        sessionID: sessionID,
                        text: text
                    ))
                }
            } else {
                textInjector.copyText(text)
            }
            await dispatch(.transcriptionSucceeded(sessionID: sessionID))
            // 성공 시 임시 파일 삭제
            try? FileManager.default.removeItem(at: audioURL)
        } catch {
            let appError: AppError
            if let e = error as? AppError {
                appError = e
            } else {
                appError = .transcriptionFailed(error.localizedDescription)
            }
            await dispatch(.transcriptionFailed(
                sessionID: sessionID,
                appError,
                audioURL: audioURL
            ))
            onError?(appError)
        }
    }
}
