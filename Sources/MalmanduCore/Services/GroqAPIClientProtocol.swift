import Foundation

/// Groq API 응답 모델
public struct TranscriptionResponse: Codable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// 하위 호환성을 위한 타입 별칭
public typealias GroqAPIClientProtocol = STTServiceProtocol
