import Foundation

/// STT 프로바이더 인스턴스 생성 + 연결 테스트의 단일 진입점.
///
/// UI 레이어(`SettingsView`, `AppDelegate`)는 이 팩토리만 알면 되며,
/// 구체 클라이언트 클래스(`GroqAPIClient`, `SonioxSTTClient`, `SonioxRealtimeClient`)를
/// 직접 import / 생성해서는 안 된다.
///
/// 새 프로바이더 추가 절차는 `docs/adding-stt-provider.md` 참고.
public protocol STTProviderFactory: Sendable {
    /// 파일 기반 STT 클라이언트 생성. 모델이 RT 모델이면 RT 클라이언트(파일 폴백 포함)를 반환할 수 있다.
    func makeFileClient(
        for provider: STTProvider,
        model: String,
        apiKey: @escaping @Sendable () -> String?
    ) -> any STTServiceProtocol

    /// 실시간 스트리밍 클라이언트 생성. RT 미지원 프로바이더는 nil 반환.
    func makeStreamingClient(
        for provider: STTProvider,
        model: String,
        apiKey: @escaping @Sendable () -> String?
    ) -> (any StreamingSTTServiceProtocol)?

    /// API 키 인증 검증 (ping). 실제 transcribe는 하지 않음.
    /// 성공 시 throw 없음. 인증 실패 / 네트워크 오류 시 throw.
    func testConnection(provider: STTProvider, apiKey: String) async throws
}

/// 기본 구현. 새 프로바이더 추가 시 아래 switch 문에 한 줄씩 추가하면 된다.
public final class DefaultSTTProviderFactory: STTProviderFactory {
    public init() {}

    public func makeFileClient(
        for provider: STTProvider,
        model: String,
        apiKey: @escaping @Sendable () -> String?
    ) -> any STTServiceProtocol {
        switch provider {
        case .groq:
            return GroqAPIClient(apiKeyProvider: apiKey)
        case .soniox:
            // RT 모델이 선택되어 있으면 RealtimeClient를 파일 폴백으로 사용 (기존 동작 유지)
            if STTProvider.isRealtimeModel(model) {
                return SonioxRealtimeClient(apiKeyProvider: apiKey)
            } else {
                return SonioxSTTClient(apiKeyProvider: apiKey)
            }
        }
    }

    public func makeStreamingClient(
        for provider: STTProvider,
        model: String,
        apiKey: @escaping @Sendable () -> String?
    ) -> (any StreamingSTTServiceProtocol)? {
        switch provider {
        case .groq:
            return nil // RT 미지원
        case .soniox:
            guard STTProvider.isRealtimeModel(model) else { return nil }
            return SonioxRealtimeClient(apiKeyProvider: apiKey)
        }
    }

    public func testConnection(provider: STTProvider, apiKey: String) async throws {
        switch provider {
        case .groq:
            try await GroqAPIClient.ping(apiKey: apiKey)
        case .soniox:
            try await SonioxSTTClient.ping(apiKey: apiKey)
        }
    }
}
