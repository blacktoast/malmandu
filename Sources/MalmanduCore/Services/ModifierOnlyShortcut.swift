import AppKit
import Foundation

/// Fn 등 modifier-only 단축키 정의.
/// `KeyboardShortcuts` 라이브러리가 capture하지 못하는 modifier-only 조합을 위한 별도 모델.
public struct ModifierOnlyShortcut: Codable, Equatable, Sendable {
    /// `NSEvent.ModifierFlags`의 device-independent raw value.
    public let rawFlags: UInt

    public init(flags: NSEvent.ModifierFlags) {
        self.rawFlags = flags.intersection(.deviceIndependentFlagsMask).rawValue
    }

    public var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawFlags)
    }

    public var isEmpty: Bool { rawFlags == 0 }

    /// 사람이 읽을 수 있는 표시 (예: "fn", "⇧", "⌃⌥").
    public var displayString: String {
        let f = flags
        var parts: [String] = []
        if f.contains(.function) { parts.append("fn") }
        if f.contains(.control)  { parts.append("⌃") }
        if f.contains(.option)   { parts.append("⌥") }
        if f.contains(.shift)    { parts.append("⇧") }
        if f.contains(.command)  { parts.append("⌘") }
        return parts.joined()
    }
}

/// UserDefaults 기반 저장소.
public enum ModifierOnlyShortcutStore {
    public enum Key: String {
        case toggleRecording = "modifierOnlyShortcut.toggleRecording"
    }

    public static func load(_ key: Key, defaults: UserDefaults = .standard) -> ModifierOnlyShortcut? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(ModifierOnlyShortcut.self, from: data)
    }

    public static func save(_ shortcut: ModifierOnlyShortcut?, for key: Key, defaults: UserDefaults = .standard) {
        if let shortcut, !shortcut.isEmpty {
            let data = (try? JSONEncoder().encode(shortcut)) ?? Data()
            defaults.set(data, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
