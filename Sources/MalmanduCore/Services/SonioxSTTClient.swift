import Foundation

/// Soniox 비동기 STT 클라이언트
/// 4단계 흐름: 파일 업로드 → 트랜스크립션 생성 → 상태 폴링 → 텍스트 취득
public final class SonioxSTTClient: STTServiceProtocol, @unchecked Sendable {
    private let apiKey: () -> String?
    private let session: URLSession
    private let baseURL: String
    private let pollingTimeout: Duration
    private let pollingInterval: Duration

    public init(
        apiKeyProvider: @escaping () -> String?,
        session: URLSession = .shared,
        baseURL: String = "https://api.soniox.com",
        pollingTimeout: Duration = .seconds(60),
        pollingInterval: Duration = .seconds(2)
    ) {
        self.apiKey = apiKeyProvider
        self.session = session
        self.baseURL = baseURL
        self.pollingTimeout = pollingTimeout
        self.pollingInterval = pollingInterval
    }

    public func transcribe(audioFileURL: URL, language: String? = nil, model: String = "stt-async-v4", prompt: String? = nil) async throws -> String {
        guard let key = apiKey() else {
            print("[Soniox] API 키 없음")
            throw AppError.apiKeyMissing
        }

        print("[Soniox] 변환 시작: model=\(model), language=\(language ?? "auto")")

        // Step 1: 파일 업로드
        let fileId: String
        do {
            fileId = try await uploadFile(audioFileURL: audioFileURL, apiKey: key)
            print("[Soniox] 파일 업로드 완료: fileId=\(fileId)")
        } catch {
            print("[Soniox] 파일 업로드 실패: \(error)")
            throw error
        }

        // Step 2: 트랜스크립션 생성
        let transcriptionId: String
        do {
            transcriptionId = try await createTranscription(fileId: fileId, model: model, language: language, prompt: prompt, apiKey: key)
            print("[Soniox] 트랜스크립션 생성: id=\(transcriptionId)")
        } catch {
            print("[Soniox] 트랜스크립션 생성 실패: \(error)")
            throw error
        }

        // Step 3: 완료까지 폴링
        do {
            try await pollUntilComplete(transcriptionId: transcriptionId, apiKey: key)
            print("[Soniox] 폴링 완료")
        } catch {
            print("[Soniox] 폴링 실패: \(error)")
            throw error
        }

        // Step 4: 텍스트 취득
        let text: String
        do {
            text = try await fetchTranscript(transcriptionId: transcriptionId, apiKey: key)
            print("[Soniox] 변환 결과: \(text.prefix(100))...")
        } catch {
            print("[Soniox] 텍스트 취득 실패: \(error)")
            throw error
        }
        return text
    }

    // MARK: - Step 1: 파일 업로드

    private func uploadFile(audioFileURL: URL, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/files")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioFileURL)
        var body = Data()
        body.appendMultipart(boundary: boundary, name: "file",
                             filename: audioFileURL.lastPathComponent,
                             mimeType: "audio/mp4", data: audioData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try checkHTTPResponse(response, data: data)

        let result = try JSONDecoder().decode(FileUploadResponse.self, from: data)
        return result.id
    }

    // MARK: - Step 2: 트랜스크립션 생성

    private func createTranscription(fileId: String, model: String, language: String?, prompt: String?, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "file_id": fileId,
        ]

        if let language, !language.isEmpty {
            let hints = language.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            body["language_hints"] = hints
        }

        if let prompt, !prompt.isEmpty {
            body["context"] = prompt
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try checkHTTPResponse(response, data: data)

        let result = try JSONDecoder().decode(TranscriptionCreateResponse.self, from: data)
        return result.id
    }

    // MARK: - Step 3: 폴링

    private func pollUntilComplete(transcriptionId: String, apiKey: String) async throws {
        let clock = ContinuousClock()
        let start = clock.now

        while true {
            try Task.checkCancellation()

            let url = URL(string: "\(baseURL)/v1/transcriptions/\(transcriptionId)")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            try checkHTTPResponse(response, data: data)

            let status = try JSONDecoder().decode(TranscriptionStatusResponse.self, from: data)

            switch status.status {
            case "completed":
                return
            case "error":
                let message = status.error_message ?? "알 수 없는 오류"
                throw AppError.transcriptionFailed("Soniox: \(message)")
            case "queued", "processing":
                let elapsed = clock.now - start
                if elapsed > pollingTimeout {
                    throw AppError.transcriptionFailed("Soniox: 변환 시간 초과 (\(Int(pollingTimeout.components.seconds))초)")
                }
                try await Task.sleep(for: pollingInterval)
            default:
                throw AppError.transcriptionFailed("Soniox: 예상치 못한 상태 - \(status.status)")
            }
        }
    }

    // MARK: - Step 4: 텍스트 취득

    private func fetchTranscript(transcriptionId: String, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/transcriptions/\(transcriptionId)/transcript")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try checkHTTPResponse(response, data: data)

        // JSON 응답 시도, 실패하면 raw text로 처리
        if let result = try? JSONDecoder().decode(TranscriptResponse.self, from: data) {
            return result.text
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        throw AppError.transcriptionFailed("Soniox: 빈 응답")
    }

    // MARK: - HTTP 응답 검사

    private func checkHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200, 201:
            return
        case 401:
            throw AppError.apiKeyInvalid
        case 400:
            let errorText = String(data: data, encoding: .utf8) ?? "Bad request"
            throw AppError.transcriptionFailed("Soniox: \(errorText)")
        default:
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AppError.transcriptionFailed("Soniox HTTP \(httpResponse.statusCode): \(errorText)")
        }
    }
}

// MARK: - Connection Ping

extension SonioxSTTClient {
    /// API 키 인증 검증. `/v1/models` GET으로 인증 헤더만 검증한다.
    public static func ping(apiKey: String) async throws {
        guard !apiKey.isEmpty else { throw AppError.apiKeyMissing }

        let url = URL(string: "https://api.soniox.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("Invalid response")
        }
        switch http.statusCode {
        case 200:
            return
        case 401:
            throw AppError.apiKeyInvalid
        default:
            throw AppError.networkError("HTTP \(http.statusCode)")
        }
    }
}

// MARK: - Soniox 응답 모델

private struct FileUploadResponse: Codable {
    let id: String
}

private struct TranscriptionCreateResponse: Codable {
    let id: String
    let status: String?
}

private struct TranscriptionStatusResponse: Codable {
    let status: String
    let error_message: String?
}

private struct TranscriptResponse: Codable {
    let text: String
}
