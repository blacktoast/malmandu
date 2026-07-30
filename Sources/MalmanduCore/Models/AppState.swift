import Foundation
import Observation

/// 앱 전역 상태
public enum AppStatus: String, Sendable {
    case idle
    case recording
    case transcribing
    case error
}

public enum AppError: Error, Sendable, Equatable {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case apiKeyMissing
    case apiKeyInvalid
    case networkError(String)
    case transcriptionFailed(String)
    case fileTooLarge
    case recordingFailed(String)
}

extension AppError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied: return "마이크 권한이 필요합니다"
        case .accessibilityPermissionDenied: return "손쉬운 사용 권한이 필요합니다"
        case .apiKeyMissing: return "API 키가 설정되지 않았습니다"
        case .apiKeyInvalid: return "API 키가 올바르지 않습니다"
        case .networkError(let msg): return "네트워크 오류: \(msg)"
        case .transcriptionFailed(let msg): return "변환 실패: \(msg)"
        case .fileTooLarge: return "파일이 너무 큽니다 (최대 25MB)"
        case .recordingFailed(let msg): return "녹음 실패: \(msg)"
        }
    }
}

@Observable
public final class AppState: @unchecked Sendable {
    public var status: AppStatus = .idle
    public var lastError: AppError? = nil
    public var lastAudioFileURL: URL? = nil
    public var recordingStartTime: Date? = nil
    /// 실시간 STT 부분 결과 (녹음 중 표시)
    public var partialTranscription: String? = nil
    /// 포커스 없어서 붙여넣기 못한 텍스트 (오버레이에서 복사 가능)
    public var pendingCopyText: String? = nil
    /// 녹음 시작 시 포커스되어 있던 앱 이름
    public var startingAppName: String? = nil
    /// 포커스 이탈 여부
    public var focusLost: Bool = false
    /// 원래 앱으로 돌아온 뒤 대기 문장 붙여넣기 확인이 필요한지 여부
    public var isAwaitingPendingPaste: Bool = false
    /// 오디오 레벨 히스토리 (7개 값, 미러링하여 14개 바 표시, 0.0~1.0)
    public var audioLevels: [CGFloat] = Array(repeating: 0, count: 7)

    public init() {}

    private func resetCommonState() {
        partialTranscription = nil
        startingAppName = nil
        focusLost = false
        isAwaitingPendingPaste = false
        audioLevels = Array(repeating: 0, count: 7)
    }

    public func startRecording() {
        status = .recording
        recordingStartTime = Date()
        lastError = nil
        resetCommonState()
    }

    public func stopRecording() {
        status = .transcribing
        recordingStartTime = nil
    }

    public func completeTranscription() {
        status = .idle
        lastAudioFileURL = nil
        pendingCopyText = nil
        resetCommonState()
    }

    public func fail(with error: AppError, audioURL: URL? = nil) {
        status = .error
        lastError = error
        lastAudioFileURL = audioURL
    }

    public func clearError() {
        if status == .error {
            status = .idle
            lastError = nil
        }
    }
}
