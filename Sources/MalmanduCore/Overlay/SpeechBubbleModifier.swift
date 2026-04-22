import SwiftUI

struct SpeechBubbleBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                SpeechBubbleShape()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
    }
}

extension View {
    func speechBubbleBackground() -> some View {
        modifier(SpeechBubbleBackground())
    }
}
