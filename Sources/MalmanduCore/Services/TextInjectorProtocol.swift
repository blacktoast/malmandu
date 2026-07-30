import Foundation

/// 붙여넣기 결과
public enum PasteResult: Sendable, Equatable {
    /// Cmd+V 이벤트까지 성공적으로 발송됨
    case success
    /// 클립보드 복사는 됐으나 Accessibility 권한 부재로 Cmd+V 발송 불가 — 호출자가 토스트/폴백 처리
    case needsAccessibilityPermission
}

/// 텍스트 주입 서비스 프로토콜
public protocol TextInjectorProtocol: Sendable {
    func pasteText(_ text: String) async -> PasteResult
    func copyText(_ text: String)
}
