import SwiftUI

/// 말풍선 커스텀 Shape (하단 중앙 꼬리)
public struct SpeechBubbleShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerRadius: CGFloat = 16
        let tailWidth: CGFloat = 12
        let tailHeight: CGFloat = 8

        // 본체 (꼬리 위 영역)
        let bodyRect = CGRect(
            x: rect.minX, y: rect.minY,
            width: rect.width, height: rect.height - tailHeight
        )
        path.addRoundedRect(in: bodyRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        // 하단 중앙 꼬리
        let tailCenter = rect.midX
        path.move(to: CGPoint(x: tailCenter - tailWidth / 2, y: bodyRect.maxY))
        path.addLine(to: CGPoint(x: tailCenter, y: rect.maxY))
        path.addLine(to: CGPoint(x: tailCenter + tailWidth / 2, y: bodyRect.maxY))
        path.closeSubpath()

        return path
    }
}
