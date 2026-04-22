import SwiftUI

/// 취소 / 확인 액션 버튼 pill (Pencil 디자인 gO03N: 100×30, 버튼 36×24)
/// ManduIconGroupView 외부 분리 컴포넌트 — 오버레이 다크 배경 밖에 별도 배치
public struct ActionButtonsPillView: View {
    public var onCancel: (() -> Void)?
    public var onConfirm: (() -> Void)?

    @State private var isCancelHovering = false
    @State private var isConfirmHovering = false

    public init(onCancel: (() -> Void)? = nil, onConfirm: (() -> Void)? = nil) {
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        ZStack {
            // 외곽 pill: 100×30 캡슐
            Capsule()
                .fill(Color.buttonDarkHover.opacity(0.85))

            HStack(spacing: 8) {
                // Cancel 버튼: 36×24 알약, dark
                Button(action: {
                    print("[ActionPill] Cancel tapped")
                    onCancel?()
                }) {
                    ZStack {
                        Capsule()
                            .fill(isCancelHovering ? Color.buttonDarkHover : Color.buttonDark)
                            .frame(width: 36, height: 24)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.buttonIcon)
                            .frame(width: 12, height: 12)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressablePillButtonStyle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isCancelHovering = hovering
                    }
                }

                // Confirm 버튼: 36×24 알약, purple
                Button(action: {
                    print("[ActionPill] Confirm tapped")
                    onConfirm?()
                }) {
                    ZStack {
                        Capsule()
                            .fill(isConfirmHovering ? Color.manduPurpleHover : Color.manduPurple)
                            .frame(width: 36, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 12, height: 12)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressablePillButtonStyle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        isConfirmHovering = hovering
                    }
                }
            }
        }
        .frame(width: 100, height: 30)
    }
}

/// Pill 버튼 press scale 효과 — gesture 충돌 없이 ButtonStyle로 처리
private struct PressablePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.easeOut(duration: configuration.isPressed ? 0.1 : 0.15), value: configuration.isPressed)
    }
}
