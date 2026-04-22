import Foundation

/// Groq Whisper API 클라이언트
public final class GroqAPIClient: STTServiceProtocol, @unchecked Sendable {
    private let apiKey: () -> String?
    private let session: URLSession
    private let baseURL: String

    public init(
        apiKeyProvider: @escaping () -> String?,
        session: URLSession = .shared,
        baseURL: String = "https://api.groq.com"
    ) {
        self.apiKey = apiKeyProvider
        self.session = session
        self.baseURL = baseURL
    }

    public func transcribe(audioFileURL: URL, language: String? = nil, model: String = "whisper-large-v3", prompt: String? = nil) async throws -> String {
        print("[GroqAPI] transcribe → language=\(language ?? "nil") model=\(model) file=\(audioFileURL.lastPathComponent) prompt=\(prompt?.prefix(40) ?? "")")
        guard let key = apiKey() else {
            throw AppError.apiKeyMissing
        }

        let url = URL(string: "\(baseURL)/openai/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioFileURL)
        var body = Data()

        // file 필드
        body.appendMultipart(boundary: boundary, name: "file",
                             filename: audioFileURL.lastPathComponent,
                             mimeType: "audio/m4a", data: audioData)
        // model 필드
        body.appendMultipart(boundary: boundary, name: "model", value: model)
        // response_format 필드
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")
        // temperature 필드 (deterministic)
        body.appendMultipart(boundary: boundary, name: "temperature", value: "0")
        // language 필드 (옵션)
        if let language {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }
        // prompt 필드 (옵션)
        if let prompt, !prompt.isEmpty {
            body.appendMultipart(boundary: boundary, name: "prompt", value: prompt)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError("Invalid response")
        }
        print("[GroqAPI] response ← status=\(httpResponse.statusCode) bytes=\(data.count) body=\(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")

        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return result.text
        case 401:
            throw AppError.apiKeyInvalid
        case 413:
            throw AppError.fileTooLarge
        case 429:
            throw AppError.networkError("Rate limit exceeded")
        default:
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AppError.transcriptionFailed("HTTP \(httpResponse.statusCode): \(errorText)")
        }
    }
}

// MARK: - Connection Ping

extension GroqAPIClient {
    /// API 키 인증 검증. `/openai/v1/models` GET으로 인증 헤더만 검증한다.
    /// 200 = 성공, 401 = apiKeyInvalid, 그 외 = networkError.
    public static func ping(apiKey: String) async throws {
        guard !apiKey.isEmpty else { throw AppError.apiKeyMissing }

        let url = URL(string: "https://api.groq.com/openai/v1/models")!
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

// MARK: - Data multipart helper
extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
