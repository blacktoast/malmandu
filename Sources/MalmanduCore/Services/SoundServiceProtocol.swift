import Foundation

/// 효과음 이벤트
public enum SoundEvent: String, Sendable {
    case recordingStarted
    case recordingStopped
}

/// 효과음 서비스 프로토콜
public protocol SoundServiceProtocol: Sendable {
    func play(_ event: SoundEvent)
    var soundEnabled: Bool { get set }
}
