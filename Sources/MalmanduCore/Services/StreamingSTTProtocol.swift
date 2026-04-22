import Foundation

/// 실시간 부분 결과 콜백 (오버레이 표시용)
public typealias PartialResultHandler = @Sendable (String) -> Void

/// 세그먼트 확정 콜백 (즉시 텍스트 붙여넣기용)
public typealias SegmentFinalizedHandler = @Sendable (String) -> Void

/// 실시간 스트리밍 STT 프로토콜
public protocol StreamingSTTServiceProtocol: Sendable {
    /// WebSocket 연결을 열고 스트리밍 세션 시작
    /// - onPartialResult: 부분 인식 결과가 올 때마다 호출 (오버레이 표시용)
    /// - onSegmentFinalized: 발화 구간이 확정될 때 호출 (즉시 붙여넣기용)
    func startStreaming(
        language: String?,
        model: String,
        onPartialResult: @escaping PartialResultHandler,
        onSegmentFinalized: @escaping SegmentFinalizedHandler
    ) async throws

    /// 오디오 청크(PCM s16le) 전송
    func sendAudioChunk(_ data: Data) async throws

    /// 스트리밍 종료 신호 → 남은 텍스트 반환
    func finishStreaming() async throws -> String

    /// 오디오 스트리밍 일시정지 (포커스 이탈 시)
    func pauseStreaming() async

    /// 오디오 스트리밍 재개 (포커스 복귀 시)
    func resumeStreaming() async
}

public extension StreamingSTTServiceProtocol {
    func pauseStreaming() async {}
    func resumeStreaming() async {}
}
