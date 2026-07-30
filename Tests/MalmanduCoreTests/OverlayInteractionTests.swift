import AppKit
import SwiftUI
import Testing
@testable import MalmanduCore

@Suite("Overlay interaction tests", .serialized)
struct OverlayInteractionTests {
    @Test("SwiftUI button center remains hit-testable")
    @MainActor
    func buttonCenterHitTest() {
        _ = NSApplication.shared

        let hostingView = ClickThroughHostingView(rootView: Button("Confirm") {})
        hostingView.frame = NSRect(x: 0, y: 0, width: 120, height: 44)
        hostingView.layoutSubtreeIfNeeded()

        let center = NSPoint(x: hostingView.bounds.midX, y: hostingView.bounds.midY)
        #expect(hostingView.hitTest(center) != nil)
    }
}
