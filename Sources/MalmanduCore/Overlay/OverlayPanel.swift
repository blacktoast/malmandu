import AppKit
import SwiftUI

/// 항상 최상위에 뜨는 플로팅 NSPanel (마우스 투과, 포커스 탈취 방지)
public final class OverlayPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 모든 일반 윈도우 위 + 메뉴바 위. 단 screenSaver 레벨은 클릭이 막히므로 사용 금지.
        level = .statusBar

        // 모든 Space + fullscreen 앱 위에서도 표시
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // 포커스 탈취 방지 — nonactivatingPanel이라 앱 활성화는 막혀 있지만,
        // 패널 자체는 key가 될 수 있어야 SwiftUI Button.action이 발동된다.
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false

        // hover 감지를 위해 마우스 이벤트 수신 (nonactivatingPanel로 포커스 탈취 없음)
        ignoresMouseEvents = false

        // 투명 배경
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseUp {
            print("[OverlayPanel] sendEvent type=\(event.type.rawValue) loc=\(event.locationInWindow) isKey=\(isKeyWindow) ignoresMouse=\(ignoresMouseEvents)")
        }
        super.sendEvent(event)
    }
}
