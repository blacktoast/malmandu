import Foundation

/// Accessibility 권한 서비스 프로토콜
public protocol AccessibilityServiceProtocol: Sendable {
    func isAccessibilityEnabled() -> Bool
    func requestAccessibility() -> Bool
}
