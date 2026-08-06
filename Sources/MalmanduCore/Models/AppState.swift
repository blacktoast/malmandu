import Foundation
import Observation

/// 앱 전역 상태
public enum AppStatus: String, Sendable, Equatable {
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

enum RecordingStopMode: Sendable, Equatable {
    case finish
    case discard
}

enum RecordingFocus: Sendable, Equatable {
    case target
    case away
    case awaitingPaste
}

struct RecordingSession: Sendable, Equatable {
    let id: UUID
    let targetBundleIdentifier: String?
    let targetName: String?
    let startedAt: Date
    var focus: RecordingFocus = .target
    var partialTranscription: String?
    var pendingCopyText: String?
    var audioLevels: [CGFloat] = AppState.emptyAudioLevels
}

struct RecordingFailure: Sendable, Equatable {
    let error: AppError
    let audioURL: URL?
}

enum RecordingFlowState: Sendable, Equatable {
    case idle
    case starting(RecordingSession)
    case recording(RecordingSession)
    case stopping(RecordingSession, RecordingStopMode)
    case transcribing(RecordingSession)
    case failed(RecordingFailure)
}

public enum RecordingOverlayPresentation: Sendable, Equatable {
    case hidden
    case starting
    case recording
    case focusLost
    case pendingPaste
    case transcribing
}

enum RecordingAction: Sendable, Equatable {
    case toggleRequested(targetBundleIdentifier: String?, targetName: String?)
    case stopRequested
    case cancelRequested
    case retryRequested(targetBundleIdentifier: String?, targetName: String?)
    case startSucceeded(sessionID: UUID)
    case startFailed(sessionID: UUID, AppError)
    case captureStopped(sessionID: UUID, URL)
    case captureUnavailable(sessionID: UUID)
    case captureStopFailed(sessionID: UUID, AppError)
    case cancelCompleted(sessionID: UUID)
    case focusChanged(sessionID: UUID, isTargetActive: Bool)
    case partialUpdated(sessionID: UUID, text: String?)
    case audioLevelsUpdated(sessionID: UUID, levels: [CGFloat])
    case segmentFinalized(sessionID: UUID, text: String, isTargetActive: Bool)
    case segmentDeliveryFailed(sessionID: UUID, text: String)
    case pastePendingRequested(isTargetActive: Bool)
    case pendingPasteSucceeded(sessionID: UUID, text: String)
    case pendingPasteFailed(sessionID: UUID)
    case transcriptionSucceeded(sessionID: UUID)
    case transcriptionFailed(sessionID: UUID, AppError, audioURL: URL?)
}

enum RecordingEffect: Sendable, Equatable {
    case startCapture(sessionID: UUID)
    case stopCapture(sessionID: UUID)
    case cancelCapture(sessionID: UUID)
    case finishTranscription(sessionID: UUID, URL)
    case retryTranscription(sessionID: UUID, URL)
    case pasteSegment(sessionID: UUID, text: String)
    case pastePending(sessionID: UUID, text: String)
}

@MainActor
@Observable
public final class AppState: @unchecked Sendable {
    nonisolated static let emptyAudioLevels: [CGFloat] = Array(repeating: 0, count: 7)

    private(set) var flowState: RecordingFlowState = .idle

    public var status: AppStatus {
        switch flowState {
        case .idle: .idle
        case .starting, .recording: .recording
        case .stopping, .transcribing: .transcribing
        case .failed: .error
        }
    }

    public var overlayPresentation: RecordingOverlayPresentation {
        switch flowState {
        case .idle, .failed:
            .hidden
        case .starting:
            .starting
        case .recording(let session):
            switch session.focus {
            case .target: .recording
            case .away: .focusLost
            case .awaitingPaste: .pendingPaste
            }
        case .stopping, .transcribing:
            .transcribing
        }
    }

    public var lastError: AppError? {
        guard case .failed(let failure) = flowState else { return nil }
        return failure.error
    }

    public var lastAudioFileURL: URL? {
        guard case .failed(let failure) = flowState else { return nil }
        return failure.audioURL
    }

    public var recordingStartTime: Date? {
        switch flowState {
        case .starting(let session), .recording(let session):
            session.startedAt
        default:
            nil
        }
    }

    public var partialTranscription: String? { session?.partialTranscription }
    public var pendingCopyText: String? { session?.pendingCopyText }
    public var startingAppName: String? { session?.targetName }
    public var startingAppBundleIdentifier: String? { session?.targetBundleIdentifier }
    var currentSessionID: UUID? { session?.id }
    public var focusLost: Bool { session?.focus == .away }
    public var isAwaitingPendingPaste: Bool { session?.focus == .awaitingPaste }
    public var audioLevels: [CGFloat] { session?.audioLevels ?? Self.emptyAudioLevels }

    public init() {}

    @discardableResult
    func send(_ action: RecordingAction) -> [RecordingEffect] {
        switch action {
        case .toggleRequested(let bundleIdentifier, let targetName):
            switch flowState {
            case .idle, .failed:
                let session = RecordingSession(
                    id: UUID(),
                    targetBundleIdentifier: bundleIdentifier,
                    targetName: targetName,
                    startedAt: Date()
                )
                flowState = .starting(session)
                return [.startCapture(sessionID: session.id)]
            case .starting(let session), .recording(let session):
                flowState = .stopping(session, .finish)
                return [.stopCapture(sessionID: session.id)]
            case .stopping, .transcribing:
                return []
            }

        case .stopRequested:
            switch flowState {
            case .starting(let session), .recording(let session):
                flowState = .stopping(session, .finish)
                return [.stopCapture(sessionID: session.id)]
            default:
                return []
            }

        case .cancelRequested:
            switch flowState {
            case .starting(let session), .recording(let session):
                flowState = .stopping(session, .discard)
                return [.cancelCapture(sessionID: session.id)]
            default:
                return []
            }

        case .retryRequested(let bundleIdentifier, let targetName):
            guard case .failed(let failure) = flowState, let audioURL = failure.audioURL else {
                return []
            }
            let session = RecordingSession(
                id: UUID(),
                targetBundleIdentifier: bundleIdentifier,
                targetName: targetName,
                startedAt: Date()
            )
            flowState = .transcribing(session)
            return [.retryTranscription(sessionID: session.id, audioURL)]

        case .startSucceeded(let sessionID):
            guard case .starting(let session) = flowState, session.id == sessionID else { return [] }
            flowState = .recording(session)
            return []

        case .startFailed(let sessionID, let error):
            guard case .starting(let session) = flowState, session.id == sessionID else { return [] }
            flowState = .failed(RecordingFailure(error: error, audioURL: nil))
            return []

        case .captureStopped(let sessionID, let audioURL):
            guard case .stopping(let session, .finish) = flowState, session.id == sessionID else { return [] }
            flowState = .transcribing(session)
            return [.finishTranscription(sessionID: session.id, audioURL)]

        case .captureUnavailable(let sessionID):
            guard case .stopping(let session, _) = flowState, session.id == sessionID else { return [] }
            flowState = .idle
            return []

        case .captureStopFailed(let sessionID, let error):
            guard case .stopping(let session, .finish) = flowState, session.id == sessionID else { return [] }
            flowState = .failed(RecordingFailure(error: error, audioURL: nil))
            return []

        case .cancelCompleted(let sessionID):
            guard case .stopping(let session, .discard) = flowState, session.id == sessionID else { return [] }
            flowState = .idle
            return []

        case .focusChanged(let sessionID, let isTargetActive):
            guard case .recording(var session) = flowState, session.id == sessionID else { return [] }
            session.focus = isTargetActive
                ? (session.pendingCopyText?.isEmpty == false ? .awaitingPaste : .target)
                : .away
            flowState = .recording(session)
            return []

        case .partialUpdated(let sessionID, let text):
            return updateSession(sessionID: sessionID) { session in
                session.partialTranscription = text
                return []
            }

        case .audioLevelsUpdated(let sessionID, let levels):
            switch flowState {
            case .starting(var session) where session.id == sessionID:
                session.audioLevels = levels
                flowState = .starting(session)
            case .recording(var session) where session.id == sessionID:
                session.audioLevels = levels
                flowState = .recording(session)
            default:
                break
            }
            return []

        case .segmentFinalized(let sessionID, let text, let isTargetActive):
            guard !text.isEmpty else { return [] }
            return updateSession(sessionID: sessionID) { session in
                session.partialTranscription = nil
                if session.focus == .target, isTargetActive {
                    return [.pasteSegment(sessionID: session.id, text: text)]
                }
                session.pendingCopyText = (session.pendingCopyText ?? "") + text
                if !isTargetActive {
                    session.focus = .away
                }
                return []
            }

        case .segmentDeliveryFailed(let sessionID, let text):
            return updateSession(sessionID: sessionID) { session in
                session.pendingCopyText = (session.pendingCopyText ?? "") + text
                session.focus = .awaitingPaste
                return []
            }

        case .pastePendingRequested(let isTargetActive):
            guard case .recording(var session) = flowState,
                  session.focus == .awaitingPaste,
                  let pendingText = session.pendingCopyText,
                  !pendingText.isEmpty else { return [] }
            guard isTargetActive else {
                session.focus = .away
                flowState = .recording(session)
                return []
            }
            return [.pastePending(sessionID: session.id, text: pendingText)]

        case .pendingPasteSucceeded(let sessionID, let pastedText):
            return updateSession(sessionID: sessionID) { session in
                let currentText = session.pendingCopyText ?? ""
                if currentText.hasPrefix(pastedText) {
                    let remaining = String(currentText.dropFirst(pastedText.count))
                    session.pendingCopyText = remaining.isEmpty ? nil : remaining
                }
                session.focus = session.pendingCopyText?.isEmpty == false ? .awaitingPaste : .target
                return []
            }

        case .pendingPasteFailed(let sessionID):
            guard currentSessionID == sessionID else { return [] }
            return []

        case .transcriptionSucceeded(let sessionID):
            guard case .transcribing(let session) = flowState, session.id == sessionID else { return [] }
            flowState = .idle
            return []

        case .transcriptionFailed(let sessionID, let error, let audioURL):
            guard case .transcribing(let session) = flowState, session.id == sessionID else { return [] }
            flowState = .failed(RecordingFailure(error: error, audioURL: audioURL))
            return []
        }
    }

    private var session: RecordingSession? {
        switch flowState {
        case .starting(let session),
             .recording(let session),
             .stopping(let session, _),
             .transcribing(let session):
            session
        case .idle, .failed:
            nil
        }
    }

    private func updateSession(
        sessionID: UUID,
        _ update: (inout RecordingSession) -> [RecordingEffect]
    ) -> [RecordingEffect] {
        switch flowState {
        case .starting(var session) where session.id == sessionID:
            let effects = update(&session)
            flowState = .starting(session)
            return effects
        case .recording(var session) where session.id == sessionID:
            let effects = update(&session)
            flowState = .recording(session)
            return effects
        case .stopping(var session, let mode) where session.id == sessionID && mode == .finish:
            let effects = update(&session)
            flowState = .stopping(session, mode)
            return effects
        case .transcribing(var session) where session.id == sessionID:
            let effects = update(&session)
            flowState = .transcribing(session)
            return effects
        default:
            return []
        }
    }
}
