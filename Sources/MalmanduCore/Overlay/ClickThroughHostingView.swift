import AppKit
import SwiftUI

/// 투명 영역 클릭을 아래 앱으로 투과시키는 NSHostingView 서브클래스.
/// NSPanel(ignoresMouseEvents=false) 안에서 사용하여,
/// SwiftUI 뷰가 있는 영역만 마우스 이벤트를 수신하고 나머지는 투과한다.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {

    required init(rootView: Content) {
        super.init(rootView: rootView)
        // NSHostingView가 패널 크기에 간섭하지 않도록 (macOS 13+)
        sizingOptions = []
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        // self가 직접 반환되면 = SwiftUI 자식 뷰가 없는 투명 영역 → 클릭 투과
        let final: NSView? = (result === self) ? nil : result
        print("[ClickThroughHV] hitTest pt=\(point) → \(final.map { "\(type(of: $0))" } ?? "nil")")
        return final
    }

    /// nonactivatingPanel 안에서 첫 클릭이 무시되지 않도록 강제 수락.
    /// 이 값이 false면 SwiftUI Button.action이 호출되지 않는다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        print("[ClickThroughHV] mouseDown @ \(event.locationInWindow)")
        super.mouseDown(with: event)
    }
}
