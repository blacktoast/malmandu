import Testing
import Foundation
@testable import MalmanduCore

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test Helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func makeTranscriptionJSON(_ text: String) -> Data {
    "{\"text\": \"\(text)\"}".data(using: .utf8)!
}

private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    )!
}

private func makeTemporaryAudioFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_\(UUID().uuidString).m4a")
    try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
    return url
}

/// URLProtocol에서 httpBody가 stream으로 전달될 수 있어 양쪽 모두 처리
private func readBody(from request: URLRequest) -> String {
    if let body = request.httpBody {
        return String(data: body, encoding: .utf8) ?? ""
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let n = stream.read(buffer, maxLength: 4096)
        if n > 0 { data.append(buffer, count: n) }
    }
    return String(data: data, encoding: .utf8) ?? ""
}

// Swift 6에서 @Sendable 클로저는 외부 var를 mutate할 수 없으므로
// 파일 레벨 nonisolated(unsafe) 변수로 캡처
nonisolated(unsafe) private var _capturedRequest: URLRequest? = nil
nonisolated(unsafe) private var _capturedBody: String? = nil

// MARK: - GroqAPIClientTests

// .serialized: static requestHandler + 파일 레벨 변수 공유로 인한 레이스 컨디션 방지
@Suite("GroqAPIClient Tests", .serialized)
struct GroqAPIClientTests {

    @Test("성공적인 트랜스크립션은 텍스트를 반환한다")
    func successfulTranscriptionReturnsText() async throws {
        MockURLProtocol.requestHandler = { _ in
            (makeHTTPResponse(statusCode: 200), makeTranscriptionJSON("hello world"))
        }
        let client = GroqAPIClient(apiKeyProvider: { "test-api-key" }, session: makeMockSession())
        let audioURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let result = try await client.transcribe(audioFileURL: audioURL)
        #expect(result == "hello world")
    }

    @Test("API 키가 없으면 apiKeyMissing 에러를 던진다")
    func missingAPIKeyThrowsError() async throws {
        MockURLProtocol.requestHandler = nil
        let client = GroqAPIClient(apiKeyProvider: { nil }, session: makeMockSession())
        let audioURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await #expect(throws: AppError.apiKeyMissing) {
            try await client.transcribe(audioFileURL: audioURL)
        }
    }

    @Test("HTTP 401은 apiKeyInvalid 에러를 던진다")
    func http401ThrowsApiKeyInvalid() async throws {
        MockURLProtocol.requestHandler = { _ in (makeHTTPResponse(statusCode: 401), Data()) }
        let client = GroqAPIClient(apiKeyProvider: { "invalid-key" }, session: makeMockSession())
        let audioURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await #expect(throws: AppError.apiKeyInvalid) {
            try await client.transcribe(audioFileURL: audioURL)
        }
    }

    @Test("HTTP 413은 fileTooLarge 에러를 던진다")
    func http413ThrowsFileTooLarge() async throws {
        MockURLProtocol.requestHandler = { _ in (makeHTTPResponse(statusCode: 413), Data()) }
        let client = GroqAPIClient(apiKeyProvider: { "test-api-key" }, session: makeMockSession())
        let audioURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await #expect(throws: AppError.fileTooLarge) {
            try await client.transcribe(audioFileURL: audioURL)
        }
    }

    @Test("HTTP 429는 rate limit networkError를 던진다")
    func http429ThrowsRateLimitError() async throws {
        MockURLProtocol.requestHandler = { _ in (makeHTTPResponse(statusCode: 429), Data()) }
        let client = GroqAPIClient(apiKeyProvider: { "test-api-key" }, session: makeMockSession())
        let audioURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await client.transcribe(audioFileURL: audioURL)
            Issue.record("에러가 던져져야 합니다")
        } catch AppError.networkError(let message) {
            #expect(message.lowercased().contains("rate limit"))
        } catch {
            Issue.record("예상치 못한 에러 타입: \(error)")
        }
    }

    @Test("HTTP 500은 transcriptionFailed 에러를 던진다")
    func http500ThrowsTranscriptionFailed() async throws {
        MockURLProtocol.requestHandler = { _ in
            (makeHTTPResponse(statusCode: 500), "Internal Server Error".data(using: .utf8)!)
        }
        let client = GroqAPIClient(apiKeyProvider: { "test-api-key" }, session: makeMockSession())
        let audioURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await client.transcribe(audioFileURL: audioURL)
            Issue.record("에러가 던져져야 합니다")
        } catch AppError.transcriptionFailed(let message) {
            #expect(message.contains("500"))
        } catch {
            Issue.record("예상치 못한 에러 타입: \(error)")
        }
    }

    @Test("요청은 올바른 multipart/form-data 형식을 사용한다")
    func requestUsesMultipartFormData() async throws {
        _capturedRequest = nil
        MockURLProtocol.requestHandler = { request in
            _capturedRequest = request
            return (makeHTTPResponse(statusCode: 200), makeTranscriptionJSON("test"))
        }
        let client = GroqAPIClient(apiKeyProvider: { "test-api-key" }, session: makeMockSession())
        let audioURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        _ = try await client.transcribe(audioFileURL: audioURL)

        let req = try #require(_capturedRequest)
        let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
        #expect(contentType.hasPrefix("multipart/form-data"))
        #expect(contentType.contains("boundary="))
        #expect(req.httpMethod == "POST")
        let auth = req.value(forHTTPHeaderField: "Authorization") ?? ""
        #expect(auth == "Bearer test-api-key")
    }

    @Test("language 파라미터가 제공되면 요청 바디에 포함된다")
    func languageParameterIncludedWhenProvided() async throws {
        _capturedBody = nil
        MockURLProtocol.requestHandler = { request in
            _capturedBody = readBody(from: request)
            return (makeHTTPResponse(statusCode: 200), makeTranscriptionJSON("test"))
        }
        let client = GroqAPIClient(apiKeyProvider: { "test-api-key" }, session: makeMockSession())
        let audioURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        _ = try await client.transcribe(audioFileURL: audioURL, language: "ko")

        let body = try #require(_capturedBody)
        #expect(body.contains("language"))
        #expect(body.contains("ko"))
    }

    @Test("language 파라미터가 nil이면 요청 바디에 language 필드가 없다")
    func languageParameterOmittedWhenNil() async throws {
        _capturedBody = nil
        MockURLProtocol.requestHandler = { request in
            _capturedBody = readBody(from: request)
            return (makeHTTPResponse(statusCode: 200), makeTranscriptionJSON("test"))
        }
        let client = GroqAPIClient(apiKeyProvider: { "test-api-key" }, session: makeMockSession())
        let audioURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        _ = try await client.transcribe(audioFileURL: audioURL, language: nil)

        let body = _capturedBody ?? ""
        #expect(!body.contains("name=\"language\""))
    }
}
