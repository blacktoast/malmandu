import SwiftUI

/// 오디오 레벨 기반 파형 바 시각화 (중앙에서 양쪽으로 퍼지는 효과)
/// 7개 audioLevels를 미러링하여 14개 바로 표시. 최신 값이 중앙, 오래된 값이 양쪽 끝.
public struct WaveformBarsView: View {
    public let levels: [CGFloat]

    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 30
    private let barCornerRadius: CGFloat = 2

    // 바마다 고유 변동 (비대칭, 자연스러운 불규칙성) — 14개
    private let barSeeds: [CGFloat] = [0.7, 1.05, 0.8, 1.2, 0.65, 1.1, 0.9, 0.95, 0.75, 1.15, 0.85, 1.0, 0.7, 0.9]
    // 벨 커브 가중치 — 14포인트, exp(-0.5*((i-6.5)/2.8)^2) 정규화, 대칭
    private let bellWeights: [CGFloat] = [0.08, 0.15, 0.27, 0.42, 0.62, 0.84, 1.0, 1.0, 0.84, 0.62, 0.42, 0.27, 0.15, 0.08]

    public init(levels: [CGFloat]) {
        self.levels = levels
    }

    /// 7개 levels → 14개 미러링 배열
    private var mirroredLevels: [CGFloat] {
        let padded = levels.count >= 7
            ? Array(levels.suffix(7))
            : Array(repeating: CGFloat(0), count: 7 - levels.count) + levels
        return padded + padded.reversed()
    }

    public var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<14, id: \.self) { index in
                let level = mirroredLevels[index]
                let seed = barSeeds[index]
                let bell = bellWeights[index]
                let variedLevel = level * seed * bell
                let height = minHeight + (maxHeight - minHeight) * min(variedLevel, 1.0)

                RoundedRectangle(cornerRadius: barCornerRadius)
                    .fill(Color.white)
                    .frame(width: barWidth, height: height)
                    .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: height)
            }
        }
    }
}
