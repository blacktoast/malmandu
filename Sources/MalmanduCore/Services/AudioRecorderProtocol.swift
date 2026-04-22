import Foundation

/// 오디오 청크 핸들러 (PCM s16le 데이터)
public typealias AudioChunkHandler = @Sendable (Data) -> Void

/// 오디오 레벨 핸들러 (0.0~1.0 RMS 값)
public typealias AudioLevelHandler = @Sendable (Float) -> Void

/// 오디오 녹음 서비스 프로토콜
public protocol AudioRecorderProtocol: Sendable {
    func startRecording() async throws
    /// 실시간 스트리밍용: 녹음하면서 PCM 청크를 콜백으로 전달
    func startRecordingWithStream(onAudioChunk: @escaping AudioChunkHandler) async throws
    /// 실시간 스트리밍용: PCM 청크 + 오디오 레벨(RMS) 콜백
    func startRecordingWithStream(onAudioChunk: @escaping AudioChunkHandler, onAudioLevel: @escaping AudioLevelHandler) async throws
    func stopRecording() async throws -> URL
    func isRecording() -> Bool
    static func requestMicrophonePermission() async -> Bool
}
