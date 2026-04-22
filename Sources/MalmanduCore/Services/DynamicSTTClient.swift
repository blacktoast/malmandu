import Foundation

/// 런타임 STT 제공자 전환을 위한 프록시 클라이언트.
/// 매 transcribe() 호출 시 현재 선택된 제공자의 클라이언트를 생성하여 위임.
/// 요구사항: 모든 STT 클라이언트는 상태 비저장(stateless)이어야 합니다.
public final class DynamicSTTClient: STTServiceProtocol, @unchecked Sendable {
    private let clientProvider: @Sendable () -> any STTServiceProtocol

    public init(_ clientProvider: @escaping @Sendable () -> any STTServiceProtocol) {
        self.clientProvider = clientProvider
    }

    public func transcribe(audioFileURL: URL, language: String?, model: String, prompt: String?) async throws -> String {
        try await clientProvider().transcribe(audioFileURL: audioFileURL, language: language, model: model, prompt: prompt)
    }
}
