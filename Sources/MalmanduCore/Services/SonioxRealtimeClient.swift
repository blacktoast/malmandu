import FluidAudio
import Foundation

/// Soniox 실시간 WebSocket STT 클라이언트
/// 스트리밍 모드: startStreaming → sendAudioChunk (반복) → finishStreaming
/// 파일 모드: transcribe(audioFileURL:) — 파일을 청크로 나눠 WebSocket 전송
public final class SonioxRealtimeClient: STTServiceProtocol, StreamingSTTServiceProtocol, @unchecked Sendable {
    private let apiKey: () -> String?
    private let wsURL: String
    private let timeout: Duration
    private let session: URLSession

    // 스트리밍 세션 상태
    private var wsTask: URLSessionWebSocketTask?
    private var remainingText: String = ""
    private var pendingPaste: String = ""
    private var segmentsDelivered: Bool = false
    private var receiveTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?
    private var onPartialResult: PartialResultHandler?
    private var onSegmentFinalized: SegmentFinalizedHandler?

    // 침묵 감지 (Silero VAD) + 자동 재연결
    private var isSocketConnected: Bool = false
    private var silenceDisconnectTask: Task<Void, Never>?
    private var disconnectedBuffer: [Data] = []
    private var preBuffer: [Data] = []
    private let preBufferMaxChunks = 4
    private let silenceTimeout: Duration = .seconds(3)
    private var isReconnecting: Bool = false
    private var streamingLanguage: String?
    private var streamingModel: String = "stt-rt-v4"
    private var vadManager: VadManager?
    private var vadState: VadStreamState = .initial()
    private var isSpeaking: Bool = false
    private var isPaused: Bool = false

    public init(
        apiKeyProvider: @escaping () -> String?,
        wsURL: String = "wss://stt-rt.soniox.com/transcribe-websocket",
        timeout: Duration = .seconds(60),
        session: URLSession = .shared
    ) {
        self.apiKey = apiKeyProvider
        self.wsURL = wsURL
        self.timeout = timeout
        self.session = session
    }

    // MARK: - StreamingSTTServiceProtocol (실시간 스트리밍)

    public func startStreaming(language: String?, model: String, onPartialResult: @escaping PartialResultHandler, onSegmentFinalized: @escaping SegmentFinalizedHandler) async throws {
        guard let key = apiKey() else {
            throw AppError.apiKeyMissing
        }

        guard let url = URL(string: wsURL) else {
            throw AppError.networkError("Invalid WebSocket URL")
        }

        print("[Soniox RT] 스트리밍 시작: model=\(model), language=\(language ?? "auto")")

        let task = session.webSocketTask(with: url)
        task.resume()
        wsTask = task
        isSocketConnected = true
        remainingText = ""
        pendingPaste = ""
        segmentsDelivered = false
        preBuffer = []
        disconnectedBuffer = []
        isSpeaking = false
        // Silero VAD 초기화
        if vadManager == nil {
            vadManager = try await VadManager(config: VadConfig(defaultThreshold: 0.5))
        }
        if let vad = vadManager {
            vadState = await vad.makeStreamState()
        } else {
            vadState = .initial()
        }
        streamingLanguage = language
        streamingModel = model
        self.onPartialResult = onPartialResult
        self.onSegmentFinalized = onSegmentFinalized

        // 설정 JSON 전송 (api_key 포함)
        try await sendConfig(to: task, apiKey: key, model: model, audioFormat: "pcm_s16le", language: language)

        // 백그라운드 수신 루프 시작
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    public func pauseStreaming() async {
        isPaused = true
        silenceDisconnectTask?.cancel()
        silenceDisconnectTask = nil
        print("[Soniox RT] ⏸ 포커스 이탈 → 오디오 일시정지")
    }

    public func resumeStreaming() async {
        isPaused = false
        print("[Soniox RT] ▶️ 포커스 복귀 → 오디오 재개")
    }

    public func sendAudioChunk(_ data: Data) async throws {
        guard !isPaused else { return }
        // 프리버퍼에 항상 저장
        preBuffer.append(data)
        if preBuffer.count > preBufferMaxChunks {
            preBuffer.removeFirst()
        }

        // Silero VAD로 음성/침묵 감지 (PCM s16le → Float32 변환)
        let silenceAutoDisconnect = UserDefaults.standard.object(forKey: "silenceAutoDisconnect") as? Bool ?? false
        if silenceAutoDisconnect, let vad = vadManager {
            let floatSamples = pcmS16leToFloat32(data)
            if !floatSamples.isEmpty {
                let result = try? await vad.processStreamingChunk(floatSamples, state: vadState)
                if let result {
                    vadState = result.state

                    if let event = result.event {
                        if event.isStart {
                            // 음성 시작 감지
                            isSpeaking = true
                            silenceDisconnectTask?.cancel()
                            silenceDisconnectTask = nil

                            if !isSocketConnected {
                                print("[Soniox RT] 🎤 음성 감지 (VAD) → 소켓 재연결")
                                await reconnectSocket()
                                return
                            }
                        } else if event.isEnd {
                            // 음성 종료 감지 → 타이머 시작
                            isSpeaking = false
                            if isSocketConnected && silenceDisconnectTask == nil {
                                print("[Soniox RT] 🔇 침묵 감지 (VAD) → \(Int(silenceTimeout.components.seconds))초 타이머 시작")
                                silenceDisconnectTask = Task { [weak self] in
                                    try? await Task.sleep(for: self?.silenceTimeout ?? .seconds(3))
                                    guard !Task.isCancelled else { return }
                                    await self?.disconnectForSilence()
                                }
                            }
                        }
                    }
                }
            }
        }

        // 소켓 연결 + 재연결 중 아닌 경우에만 직접 전송
        if isSocketConnected && !isReconnecting, let task = wsTask {
            try? await task.send(.data(data))
        } else {
            if disconnectedBuffer.count < 160 {
                disconnectedBuffer.append(data)
            }
            if disconnectedBuffer.count % 20 == 0 {
                print("[Soniox RT] 📦 버퍼 \(disconnectedBuffer.count)청크 (소켓:\(isSocketConnected), 재연결:\(isReconnecting), 말중:\(isSpeaking))")
            }
        }
    }

    // MARK: - 침묵 감지 + 자동 재연결

    /// PCM s16le → Float32 변환 (Silero VAD 입력 형식)
    private func pcmS16leToFloat32(_ data: Data) -> [Float] {
        data.withUnsafeBytes { ptr -> [Float] in
            guard let base = ptr.bindMemory(to: Int16.self).baseAddress else { return [] }
            let count = data.count / 2
            return (0..<count).map { Float(base[$0]) / 32768.0 }
        }
    }

    /// 침묵 2초 → WebSocket 해제 (비용 절감)
    private func disconnectForSilence() async {
        guard isSocketConnected, let task = wsTask else { return }

        print("[Soniox RT] 침묵 감지 → 소켓 해제 (비용 절감)")
        // 침묵 중 쌓인 버퍼 비우기 (무음 데이터를 서버에 보낼 필요 없음)
        disconnectedBuffer = []
        await finalizeAndClose(task: task, timeoutMs: 300)
    }

    /// finalize 전송 → <fin> 대기 → 플러시 → 소켓 닫기 (공통)
    private func finalizeAndClose(task: URLSessionWebSocketTask, timeoutMs: Int) async {
        try? await task.send(.data(Data()))
        try? await Task.sleep(for: .milliseconds(50))
        try? await task.send(.string(#"{"type":"finalize"}"#))

        if let recv = receiveTask {
            _ = await withTaskGroup(of: Void.self) { group in
                group.addTask { await recv.value }
                group.addTask { try? await Task.sleep(for: .milliseconds(timeoutMs)) }
                await group.next()
                group.cancelAll()
            }
        }

        flushPendingPaste()
        receiveTask?.cancel()
        task.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        receiveTask = nil
        isSocketConnected = false
    }

    /// 음성 재감지 → WebSocket 재연결
    private func reconnectSocket() async {
        guard !isReconnecting, let key = apiKey(), let url = URL(string: wsURL) else { return }
        isReconnecting = true

        print("[Soniox RT] 음성 감지 → 소켓 재연결")

        let task = session.webSocketTask(with: url)
        task.resume()
        wsTask = task
        isSocketConnected = true

        // config 재전송
        try? await sendConfig(to: task, apiKey: key, model: streamingModel, audioFormat: "pcm_s16le", language: streamingLanguage)

        // 수신 루프 재시작
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        // 끊긴 동안 쌓인 오디오 + 프리버퍼 전송 (첫 단어 안 잘림)
        let bufferedChunks = preBuffer + disconnectedBuffer
        print("[Soniox RT] 버퍼 전송: 프리버퍼 \(preBuffer.count)청크 + 끊긴동안 \(disconnectedBuffer.count)청크")
        preBuffer = []
        disconnectedBuffer = []
        for chunk in bufferedChunks {
            try? await task.send(.data(chunk))
        }

        // 버퍼 전송 완료 후에야 직접 전송 허용
        isReconnecting = false
    }

    public func finishStreaming() async throws -> String {
        // 침묵으로 이미 소켓이 끊긴 경우 — 추가 작업 불필요
        silenceDisconnectTask?.cancel()
        guard let task = wsTask, isSocketConnected else {
            flushPendingPaste()
            let remaining = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
            let delivered = segmentsDelivered
            cleanup()
            if remaining.isEmpty && !delivered {
                print("[Soniox RT] 빈 응답 (음성 없음)")
            }
            return remaining
        }

        print("[Soniox RT] finalize 전송")
        await finalizeAndClose(task: task, timeoutMs: 400)
        print("[Soniox RT] 종료 완료")

        let remaining = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let delivered = segmentsDelivered
        cleanup()

        if remaining.isEmpty && !delivered {
            print("[Soniox RT] 빈 응답 (음성 없음)")
        }

        return remaining
    }

    // MARK: - STTServiceProtocol (파일 기반 폴백)

    public func transcribe(audioFileURL: URL, language: String? = nil, model: String = "stt-rt-v4", prompt: String? = nil) async throws -> String {
        guard let key = apiKey() else {
            throw AppError.apiKeyMissing
        }

        print("[Soniox RT File] 파일 기반 변환: model=\(model)")

        let audioData = try Data(contentsOf: audioFileURL)

        guard let url = URL(string: wsURL) else {
            throw AppError.networkError("Invalid WebSocket URL")
        }

        let task = session.webSocketTask(with: url)
        task.resume()

        defer { task.cancel(with: .normalClosure, reason: nil) }

        // 설정 전송
        try await sendConfig(to: task, apiKey: key, model: model, audioFormat: "auto", language: language)

        // 오디오 전송 (청크)
        let chunkSize = 32_768
        var offset = 0
        while offset < audioData.count {
            try Task.checkCancellation()
            let end = min(offset + chunkSize, audioData.count)
            try await task.send(.data(Data(audioData[offset..<end])))
            offset = end
        }

        // 종료 신호
        try await task.send(.data(Data()))

        // 결과 수신
        return try await receiveAllResults(wsTask: task)
    }

    // MARK: - 수신 루프 (스트리밍 모드 — is_final 기반)

    private func receiveLoop() async {
        guard let task = wsTask else { return }

        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                print("[Soniox RT] 수신 종료: \(error.localizedDescription)")
                break
            }

            if let jsonString = extractString(from: message) {
                guard let data = jsonString.data(using: .utf8),
                      let response = try? JSONDecoder().decode(RTTranscriptionResponse.self, from: data) else {
                    continue
                }

                let isTimeout = response.error_code == 408
                let isFinished = response.finished ?? false || isTimeout

                // <fin> 감지 → 수신 루프 즉시 종료 (manual finalization 완료 신호)
                let hasFin = response.tokens.contains { $0.text.contains("<fin>") }

                // 특수 토큰 필터링
                let tokens = response.tokens.filter { !$0.text.contains("<end>") && !$0.text.contains("<START>") && !$0.text.contains("<fin>") }
                if !tokens.isEmpty {
                    // 처음부터 연속으로 is_final == true인 토큰 찾기
                    var finalEndIndex = 0
                    for token in tokens {
                        if token.is_final == true {
                            finalEndIndex += 1
                        } else {
                            break
                        }
                    }

                    if finalEndIndex > 0 {
                        // 확정된 연속 토큰 → 버퍼에 누적 (디바운스 붙여넣기)
                        let confirmedText = tokens[0..<finalEndIndex]
                            .map { $0.text }
                            .joined()

                        // Soniox 엔드포인트 자동 구두점 정리
                        var cleaned = confirmedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        // 순수 구두점만 있는 세그먼트는 무시
                        let isPunctuationOnly = !cleaned.isEmpty && cleaned.allSatisfy { ".,!?;:…".contains($0) }
                        if isPunctuationOnly { cleaned = "" }
                        // 끝에 붙은 자동 마침표 제거 (침묵 시 Soniox가 자동 추가)
                        if cleaned.hasSuffix(".") && !cleaned.hasSuffix("...") {
                            cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespaces)
                        }
                        if !cleaned.isEmpty {
                            pendingPaste += cleaned + " "
                            print("[Soniox RT] 확정(\(finalEndIndex)토큰): \(cleaned.prefix(80))")
                            schedulePaste()
                        }

                        // 나머지 미확정 토큰 → 오버레이에 표시
                        let pendingText = tokens[finalEndIndex...]
                            .map { $0.text }
                            .joined()
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        remainingText = pendingText
                        onPartialResult?(pendingText)
                    } else {
                        // 아직 확정 없음 → 전체를 오버레이에 표시
                        let allText = tokens.map { $0.text }.joined()
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        remainingText = allText
                        onPartialResult?(allText)
                    }
                }

                if isFinished || hasFin {
                    print("[Soniox RT] 세션 종료 (\(hasFin ? "<fin>" : "finished"))")
                    break
                }
            }
        }
        receiveTask = nil
    }

    // MARK: - 결과 수신 (파일 모드)

    private func receiveAllResults(wsTask: URLSessionWebSocketTask) async throws -> String {
        var latestResult = ""
        let clock = ContinuousClock()
        let start = clock.now

        while true {
            try Task.checkCancellation()

            if clock.now - start > timeout {
                throw AppError.transcriptionFailed("Soniox RT: 변환 시간 초과")
            }

            let message: URLSessionWebSocketTask.Message
            do {
                message = try await wsTask.receive()
            } catch {
                break
            }

            if let jsonString = extractString(from: message),
               let data = jsonString.data(using: .utf8),
               let response = try? JSONDecoder().decode(RTTranscriptionResponse.self, from: data) {
                let text = response.tokens.map { $0.text }.joined()
                if !text.isEmpty { latestResult = text }
                let done = response.finished ?? false || response.error_code == 408
                if done { break }
            }
        }

        if latestResult.isEmpty {
            throw AppError.transcriptionFailed("Soniox RT: 빈 응답")
        }
        return latestResult.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 응답 파싱

    private func sendConfig(to task: URLSessionWebSocketTask, apiKey: String, model: String, audioFormat: String, language: String?) async throws {
        var config: [String: Any] = [
            "api_key": apiKey,
            "model": model,
            "audio_format": audioFormat,
            "enable_endpoint_detection": true,
            "max_endpoint_delay_ms": 300,
        ]
        if audioFormat != "auto" {
            config["sample_rate"] = 16000
            config["num_channels"] = 1
        }
        if let language, !language.isEmpty {
            let hints = language.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            config["language_hints"] = hints
        }
        // 앱 기반 컨텍스트 추가
        let focusDetector = FocusDetector()
        if let appContext = focusDetector.appContext() {
            var contextObj: [String: Any] = ["general": appContext.toSonioxGeneral()]
            // 고유명사(terms)도 추가
            let vocab = UserDefaults.standard.string(forKey: "customVocabulary") ?? ""
            if !vocab.isEmpty {
                let terms = vocab.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
                contextObj["terms"] = terms
            }
            config["context"] = contextObj
            let terms = (contextObj["terms"] as? [String]) ?? []
            print("[Soniox RT] 컨텍스트: domain=\(appContext.domain), topic=\(appContext.topic), terms=\(terms.prefix(5))")
        } else {
            // 컨텍스트 없이 고유명사만
            let vocab = UserDefaults.standard.string(forKey: "customVocabulary") ?? ""
            if !vocab.isEmpty {
                let terms = vocab.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
                config["context"] = ["terms": terms]
            }
        }
        let data = try JSONSerialization.data(withJSONObject: config)
        try await task.send(.string(String(data: data, encoding: .utf8)!))
    }

    private func extractString(from message: URLSessionWebSocketTask.Message) -> String? {
        switch message {
        case .string(let text): return text
        case .data(let data): return String(data: data, encoding: .utf8)
        @unknown default: return nil
        }
    }


    /// 300ms 디바운스 — 빠른 연속 확정을 하나로 묶어서 붙여넣기
    private func schedulePaste() {
        pasteTask?.cancel()
        pasteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, !self.pendingPaste.isEmpty else { return }
            // 앞쪽 공백만 제거, 뒤쪽 공백은 유지 (다음 세그먼트와 띄어쓰기)
            let text = self.pendingPaste.drop(while: { $0.isWhitespace || $0.isNewline })
            self.pendingPaste = ""
            if !text.isEmpty {
                self.segmentsDelivered = true
                self.onSegmentFinalized?(String(text))
            }
        }
    }

    /// 버퍼에 남은 텍스트를 즉시 플러시
    private func flushPendingPaste() {
        pasteTask?.cancel()
        let text = pendingPaste.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingPaste = ""
        if !text.isEmpty {
            segmentsDelivered = true
            onSegmentFinalized?(text)
        }
    }

    private func cleanup() {
        wsTask = nil
        receiveTask = nil
        pasteTask?.cancel()
        pasteTask = nil
        silenceDisconnectTask?.cancel()
        silenceDisconnectTask = nil
        isSocketConnected = false
        isReconnecting = false
        isSpeaking = false
        isPaused = false
        preBuffer = []
        disconnectedBuffer = []
        vadState = .initial()
        onPartialResult = nil
        onSegmentFinalized = nil
    }
}

// MARK: - 응답 모델

private struct RTTranscriptionResponse: Codable {
    let tokens: [RTToken]
    let finished: Bool?
    let error_code: Int?
}

private struct RTToken: Codable {
    let text: String
    let is_final: Bool?
}
