import SwiftUI

/// 변환 중 오버레이 뷰 (말풍선 + 스피너) — RT 모드 전용
public struct TranscribingOverlayView: View {
    public init() {}

    public var body: some View {
        SpinnerView(label: "변환 중...", iconSize: 14, labelSize: 13)
            .speechBubbleBackground()
    }
}
