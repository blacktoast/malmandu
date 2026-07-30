import AppKit
import Foundation

/// 클립보드 + CGEvent Cmd+V 자동 붙여넣기 서비스
public final class TextInjector: TextInjectorProtocol, @unchecked Sendable {
    private let accessibilityService: AccessibilityServiceProtocol

    public init(accessibilityService: AccessibilityServiceProtocol) {
        self.accessibilityService = accessibilityService
    }

    public func pasteText(_ text: String) async -> PasteResult {
        // 1. 현재 클립보드 백업
        let pasteboard = NSPasteboard.general
        let backup = pasteboard.string(forType: .string)

        // 2. 텍스트를 클립보드에 복사 (권한과 무관하게 항상 선행)
        copyText(text)

        // 3. Accessibility 권한 확인 — 없으면 최초 1회 시스템 프롬프트 유도 후 결과 반환
        guard accessibilityService.isAccessibilityEnabled() else {
            _ = accessibilityService.requestAccessibility()
            return .needsAccessibilityPermission
        }

        // 4. Cmd+V 발송
        sendPasteKeyEvent()

        // 5. 딜레이 후 클립보드 복원
        try? await Task.sleep(for: .milliseconds(200))
        if let backup {
            copyText(backup)
        }

        return .success
    }

    public func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func sendPasteKeyEvent() {
        let source = CGEventSource(stateID: .hidSystemState)
        // V key = 0x09
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
