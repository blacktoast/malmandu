import AppKit
import SwiftUI

/// nonactivating NSPanel 안에서도 SwiftUI 컨트롤의 첫 클릭을 받는 NSHostingView.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {

    required init(rootView: Content) {
        super.init(rootView: rootView)
        // NSHostingView가 패널 크기에 간섭하지 않도록 (macOS 13+)
        sizingOptions = []
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// nonactivatingPanel 안에서 첫 클릭이 무시되지 않도록 강제 수락.
    /// 이 값이 false면 SwiftUI Button.action이 호출되지 않는다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
