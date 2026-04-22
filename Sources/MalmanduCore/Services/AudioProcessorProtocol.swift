import Foundation

/// 오디오 전처리 서비스 프로토콜 (VAD 기반 무음 제거)
public protocol AudioProcessorProtocol: Sendable {
    func trimSilence(from audioURL: URL) async throws -> URL
}
