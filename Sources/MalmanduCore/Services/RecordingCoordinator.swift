import AppKit
import Foundation
import Observation

/// 녹음 → STT → 붙여넣기 파이프라인 조율자
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
    public private(set) var startingAppBundleId: String?
    /// 포커스 변화 감시 태스크
    private var focusObserver: Task<Void, Never>?
    /// 비동기 모드 오디오 레벨 폴링 타이머
    private var meteringTimer: Task<Void, Never>?
    /// RT 모드: WebSocket 연결 전 수신된 오디오 청크 임시 버퍼
    private var audioChunkBuffer: [Data] = []
    private let audioChunkBufferLimit = 150  // 64ms * 150 ≈ 9.6초
    /// RT 모드 초기화 중 stop이 호출됐는지 플래그
    private var stopRequested = false
    /// 대기 문장 중복 붙여넣기 방지
    private var pendingPasteInProgress = false
    /// 취소 중 스트림 종료가 내보내는 마지막 확정 문장 폐기
    private var discardFinalizedSegments = false

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
        switch appState.status {
        case .idle, .error:
            await startRecording()
        case .recording:
            await stopAndTranscribe()
        case .transcribing:
            break // 변환 중에는 무시
        }
    }

    /// 녹음을 즉시 취소한다 — 오디오/소켓을 모두 폐기하고 변환 없이 idle로 복귀.
    /// RT/Async 모드 모두 동일하게 동작: 어떤 텍스트도 붙여넣지 않는다.
    @MainActor
    public func cancelRecording() async {
        guard appState.status == .recording, !discardFinalizedSegments else { return }
        stopRequested = true
        discardFinalizedSegments = true
        defer { discardFinalizedSegments = false }

        // 1. 마이크/녹음 중지 후 파일 즉시 삭제
        do {
            let audioURL = try await audioRecorder.stopRecording()
            try? FileManager.default.removeItem(at: audioURL)
            print("[Cancel] 오디오 파일 폐기: \(audioURL.lastPathComponent)")
        } catch {
            print("[Cancel] 녹음 중지 실패 (무시): \(error)")
        }

        // 2. RT 모드: WebSocket 종료 (반환 텍스트 무시)
        if let streamingClient = activeStreamingClient {
            activeStreamingClient = nil
            _ = try? await streamingClient.finishStreaming() as String
            print("[Cancel] RT 스트리밍 클라이언트 종료")
        }

        // 3. 보조 상태 정리
        audioChunkBuffer = []
        focusObserver?.cancel()
        focusObserver = nil
        stopMeteringTimer()

        // 4. 앱 상태 리셋: 모든 미확정/대기 텍스트 폐기
        appState.partialTranscription = nil
        appState.pendingCopyText = nil
        appState.focusLost = false
        appState.isAwaitingPendingPaste = false
        appState.stopRecording()
        appState.status = .idle
        onStatusChange?(.idle)

        soundService.play(.recordingStopped)
    }

    public func retryLastTranscription() async {
        guard let audioURL = appState.lastAudioFileURL else { return }
        startingAppBundleId = frontmostAppBundleId()
        appState.status = .transcribing
        onStatusChange?(.transcribing)
        await transcribeAndPaste(audioURL: audioURL)
    }

    /// 현재 선택된 모델이 실시간 모드인지 확인
    public var isRealtimeMode: Bool {
        STTProvider.isRealtimeModel(model())
    }

    // MARK: - 녹음 시작

    private func startRecording() async {
        // API 키 사전 체크
        if !apiKeyCheck() {
            let err = AppError.apiKeyMissing
            appState.fail(with: err)
            onStatusChange?(.error)
            onError?(err)
            return
        }

        soundService.play(.recordingStarted)
        // 효과음이 마이크에 포착되지 않도록 딜레이
        try? await Task.sleep(for: startDelay)

        let focusDetector = FocusDetector()
        startingAppBundleId = frontmostAppBundleId()
        appState.startingAppName = focusDetector.frontmostAppName()
        appState.startRecording()
        onStatusChange?(.recording)

        do {
            if isRealtimeMode, let streamingClient = streamingClientProvider() {
                // 실시간 모드: 마이크 먼저 → WebSocket 연결 → 버퍼 flush
                audioChunkBuffer = []
                stopRequested = false

                // 1. 마이크 먼저 시작 — WebSocket 연결 중에도 오디오 캡처
                try await audioRecorder.startRecordingWithStream(
                    onAudioChunk: { [weak self] chunk in
                        guard let self else { return }
                        if let client = self.activeStreamingClient {
                            Task { try? await client.sendAudioChunk(chunk) }
                        } else if self.audioChunkBuffer.count < self.audioChunkBufferLimit {
                            self.audioChunkBuffer.append(chunk)
                        }
                    },
                    onAudioLevel: { [weak self] level in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            var levels = self.appState.audioLevels
                            levels.removeFirst()
                            levels.append(CGFloat(level))
                            self.appState.audioLevels = levels
                        }
                    }
                )

                // 2. WebSocket 연결
                try await streamingClient.startStreaming(
                    language: language(),
                    model: model(),
                    onPartialResult: { [weak self] partialText in
                        Task { @MainActor [weak self] in
                            self?.appState.partialTranscription = partialText
                        }
                    },
                    onSegmentFinalized: { [weak self] (confirmedText: String) in
                        guard let self else { return }
                        await self.handleFinalizedSegment(confirmedText)
                    }
                )

                // startStreaming 대기 중 stop 호출 감지 — 즉시 정리 후 종료
                if stopRequested {
                    audioChunkBuffer = []
                    _ = try? await streamingClient.finishStreaming() as String
                    print("[RT Pipeline] 초기화 중 취소됨 → WebSocket 정리")
                    return
                }

                activeStreamingClient = streamingClient
                startFocusMonitoring()

                // 3. 버퍼된 청크 flush
                let buffered = audioChunkBuffer
                audioChunkBuffer = []
                for chunk in buffered {
                    try? await streamingClient.sendAudioChunk(chunk)
                }
                print("[RT Pipeline] 실시간 스트리밍 녹음 시작 (버퍼 \(buffered.count)개 flush)")
            } else {
                // 일반 모드: 파일 기반 녹음
                try await audioRecorder.startRecording()
                // AVAudioRecorder 미터링으로 오디오 레벨 폴링 (파형 표시용)
                startMeteringTimer()
            }
        } catch {
            audioChunkBuffer = []
            activeStreamingClient = nil
            focusObserver?.cancel()
            focusObserver = nil
            // duckSystemVolume이 이미 호출된 상태이므로 볼륨 복원 (에러 무시)
            do { _ = try await audioRecorder.stopRecording() } catch {}
            let err = AppError.recordingFailed(error.localizedDescription)
            appState.fail(with: err)
            onStatusChange?(.error)
            onError?(err)
        }
    }

    // MARK: - 녹음 중지 + 변환

    private func stopAndTranscribe() async {
        stopRequested = true
        do {
            let audioURL = try await audioRecorder.stopRecording()
            audioChunkBuffer = []
            focusObserver?.cancel()
            focusObserver = nil
            stopMeteringTimer()
            soundService.play(.recordingStopped)

            // RT 모드 초기화 중 취소: 변환 스킵, 즉시 idle 복귀
            if isRealtimeMode && activeStreamingClient == nil {
                try? FileManager.default.removeItem(at: audioURL)
                appState.stopRecording()
                appState.status = .idle
                onStatusChange?(.idle)
                print("[RT Pipeline] 초기화 중 stop — 변환 스킵")
                return
            }

            appState.stopRecording()
            onStatusChange?(.transcribing)

            if let streamingClient = activeStreamingClient {
                // 실시간 모드: 스트리밍 종료 → 최종 텍스트 수신
                activeStreamingClient = nil
                await streamingTranscribeAndPaste(streamingClient: streamingClient, fallbackAudioURL: audioURL)
            } else {
                // 일반 모드: 파일 기반 변환
                await transcribeAndPaste(audioURL: audioURL)
            }
        } catch {
            activeStreamingClient = nil
            let err = AppError.recordingFailed(error.localizedDescription)
            appState.fail(with: err)
            onStatusChange?(.error)
            onError?(err)
        }
    }

    // MARK: - 실시간 스트리밍 변환

    private func streamingTranscribeAndPaste(streamingClient: any StreamingSTTServiceProtocol, fallbackAudioURL: URL) async {
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
            appState.completeTranscription()
            onStatusChange?(.idle)
            try? FileManager.default.removeItem(at: fallbackAudioURL)
        } catch {
            print("[RT Pipeline] 실시간 변환 실패, 파일 기반 폴백 시도: \(error)")
            await transcribeAndPaste(audioURL: fallbackAudioURL)
        }
    }

    // MARK: - 포커스 모니터링

    @MainActor
    private func handleFinalizedSegment(_ confirmedText: String) async {
        guard !discardFinalizedSegments else {
            appState.partialTranscription = nil
            return
        }

        if appState.focusLost || appState.isAwaitingPendingPaste || !isOriginalAppFrontmost {
            print("[RT Pipeline] 포커스 대기 중, 오버레이 버퍼에 저장")
            appendPendingText(confirmedText)
            if !isOriginalAppFrontmost {
                handleFocusChange(isOriginalAppActive: false)
            }
        } else {
            print("[RT Pipeline] 붙여넣기: \(confirmedText.prefix(50))")
            let result = await textInjector.pasteText(confirmedText)
            if result == .needsAccessibilityPermission {
                print("[RT Pipeline] Accessibility 권한 부재 — 클립보드 복사만 수행, 토스트 안내")
                onError?(.accessibilityPermissionDenied)
                appendPendingText(confirmedText)
            }
        }
        appState.partialTranscription = nil
    }

    @MainActor
    func handleFocusChange(isOriginalAppActive: Bool) {
        guard appState.status == .recording else { return }

        if isOriginalAppActive {
            if appState.focusLost {
                print("[Focus] 원래 앱으로 포커스 복귀")
            }
            appState.focusLost = false
            appState.isAwaitingPendingPaste = appState.pendingCopyText?.isEmpty == false
        } else {
            if !appState.focusLost {
                print("[Focus] 원래 앱에서 포커스 이탈")
            }
            appState.focusLost = true
            appState.isAwaitingPendingPaste = false
        }
    }

    @MainActor
    public func pastePendingTranscription() async {
        guard appState.status == .recording,
              appState.isAwaitingPendingPaste,
              !pendingPasteInProgress,
              let pendingText = appState.pendingCopyText,
              !pendingText.isEmpty else { return }

        guard isOriginalAppFrontmost else {
            handleFocusChange(isOriginalAppActive: false)
            return
        }

        pendingPasteInProgress = true
        defer { pendingPasteInProgress = false }

        let result = await textInjector.pasteText(pendingText)
        if result == .needsAccessibilityPermission {
            onError?(.accessibilityPermissionDenied)
            return
        }

        let currentText = appState.pendingCopyText ?? ""
        if currentText.hasPrefix(pendingText) {
            let remainingText = String(currentText.dropFirst(pendingText.count))
            appState.pendingCopyText = remainingText.isEmpty ? nil : remainingText
        }
        appState.isAwaitingPendingPaste = appState.pendingCopyText?.isEmpty == false
    }

    private func startFocusMonitoring() {
        focusObserver?.cancel()
        focusObserver = Task { @MainActor [weak self] in
            let center = NSWorkspace.shared.notificationCenter
            let stream = center.notifications(named: NSWorkspace.didActivateApplicationNotification)
            for await notification in stream {
                guard let self else { break }
                guard self.appState.status == .recording else { continue }
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

    private func startMeteringTimer() {
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
                self.appState.audioLevels = levels
            }
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.cancel()
        meteringTimer = nil
    }

    private func appendPendingText(_ text: String) {
        guard !text.isEmpty else { return }
        appState.pendingCopyText = (appState.pendingCopyText ?? "") + text
    }

    private var isOriginalAppFrontmost: Bool {
        guard let startingAppBundleId else { return false }
        return frontmostAppBundleId() == startingAppBundleId
    }

    // MARK: - 파일 기반 변환 (기존 로직)

    private func transcribeAndPaste(audioURL: URL) async {
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
                    appState.pendingCopyText = text
                }
            } else {
                appState.pendingCopyText = text
            }
            appState.completeTranscription()
            onStatusChange?(.idle)
            // 성공 시 임시 파일 삭제
            try? FileManager.default.removeItem(at: audioURL)
        } catch {
            let appError: AppError
            if let e = error as? AppError {
                appError = e
            } else {
                appError = .transcriptionFailed(error.localizedDescription)
            }
            appState.fail(with: appError, audioURL: audioURL)
            onStatusChange?(.error)
            onError?(appError)
        }
    }
}
