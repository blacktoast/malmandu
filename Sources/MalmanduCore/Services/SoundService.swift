import AppKit
import Foundation

/// NSSound 기반 효과음 서비스
public final class SoundService: SoundServiceProtocol, @unchecked Sendable {
    public var soundEnabled: Bool

    public init(soundEnabled: Bool = true) {
        self.soundEnabled = soundEnabled
    }

    public func soundName(for event: SoundEvent) -> String {
        switch event {
        case .recordingStarted: return "Tink"
        case .recordingStopped: return "Pop"
        }
    }

    public func play(_ event: SoundEvent) {
        guard soundEnabled else { return }
        NSSound(named: soundName(for: event))?.play()
    }
}
