@preconcurrency import ApplicationServices
import Foundation

/// macOS Accessibility 권한 서비스
public final class AccessibilityService: AccessibilityServiceProtocol, Sendable {
    public init() {}

    public func isAccessibilityEnabled() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
