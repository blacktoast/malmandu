import SwiftUI

/// 회전 스피너 + 라벨 (Thinking, 변환 중 등)
struct SpinnerView: View {
    let label: String
    let iconSize: CGFloat
    let labelSize: CGFloat

    @State private var rotation: Double = 0

    init(label: String, iconSize: CGFloat = 14, labelSize: CGFloat = 13) {
        self.label = label
        self.iconSize = iconSize
        self.labelSize = labelSize
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(.white)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            Text(label)
                .font(.system(size: labelSize, weight: .medium))
                .foregroundColor(.white)
        }
    }
}
