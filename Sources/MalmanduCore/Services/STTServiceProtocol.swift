import Foundation

/// STT 모델 정보
public struct STTModelInfo: Sendable, Identifiable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// STT 서비스 프로토콜 — 모든 STT 제공자가 구현
public protocol STTServiceProtocol: Sendable {
    func transcribe(audioFileURL: URL, language: String?, model: String, prompt: String?) async throws -> String
}

/// STT 제공자 열거형
public enum STTProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case groq
    case soniox

    public var id: String { rawValue }

    /// UserDefaults에서 현재 선택된 제공자 읽기
    public static var current: STTProvider {
        STTProvider(rawValue: UserDefaults.standard.string(forKey: "selectedSTTProvider") ?? "groq") ?? .groq
    }

    /// 모델 ID가 실시간 모델인지 확인
    public static func isRealtimeModel(_ modelId: String) -> Bool {
        modelId.hasPrefix("stt-rt-")
    }

    public var displayName: String {
        switch self {
        case .groq: return "Groq"
        case .soniox: return "Soniox"
        }
    }

    public var models: [STTModelInfo] {
        switch self {
        case .groq: return [
            STTModelInfo(id: "whisper-large-v3", displayName: "Whisper Large v3 (정확도 우선)"),
            STTModelInfo(id: "whisper-large-v3-turbo", displayName: "Whisper Large v3 Turbo (속도 우선)"),
        ]
        case .soniox: return [
            STTModelInfo(id: "stt-rt-v4", displayName: "STT Real-time v4 (실시간)"),
            STTModelInfo(id: "stt-async-v4", displayName: "STT Async v4 (비동기)"),
            STTModelInfo(id: "stt-async-v3", displayName: "STT Async v3 (레거시)"),
        ]
        }
    }

    public var defaultModel: String {
        switch self {
        case .groq: return "whisper-large-v3"
        case .soniox: return "stt-rt-v4"
        }
    }

    public var keychainAccount: String {
        switch self {
        case .groq: return "groq-api-key"
        case .soniox: return "soniox-api-key"
        }
    }

    public var modelUserDefaultsKey: String {
        switch self {
        case .groq: return "selectedModel"
        case .soniox: return "selectedSonioxModel"
        }
    }

    // MARK: - Capabilities

    /// 보조(2차) 언어 지정 지원 여부
    /// - Groq Whisper: 단일 언어만 지원 → false
    /// - Soniox: language_hints 다중 언어 지원 → true
    public var supportsSecondaryLanguage: Bool {
        switch self {
        case .groq: return false
        case .soniox: return true
        }
    }

    /// "자동 감지" 옵션 지원 여부 (모든 제공자 공통: language=nil 전달)
    public var supportsAutoLanguageDetect: Bool { true }
}

/// 언어 설정 sentinel — UserDefaults에 저장될 때 사용
public enum LanguageCode {
    /// 자동 감지를 의미하는 sentinel 값
    public static let auto = "auto"
}
