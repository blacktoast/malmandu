import SwiftUI
import AppKit

/// 만두 캐릭터 + 말풍선 그룹 (Pencil 디자인 스펙 N1HrC: 173×54)
/// 버튼은 ActionButtonsPillView로 분리됨
public struct ManduIconGroupView: View {
    public let audioLevels: [CGFloat]
    public var isTranscribing: Bool

    @State private var showThinking: Bool = false

    public init(audioLevels: [CGFloat], isTranscribing: Bool = false) {
        self.audioLevels = audioLevels
        self.isTranscribing = isTranscribing
    }

    private var manduImage: NSImage? {
        if let url = Bundle.module.url(forResource: "mandu", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return Bundle.main.image(forResource: "mandu")
    }

    public var body: some View {
        ZStack {
            // 1. Speech Bubble: 113×38, Pencil pos(50, 8) → frame center(86.5, 27) 기준 offset(20, 0)
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.manduPurple)
                .frame(width: 113, height: 38)
                .overlay(
                    ZStack {
                        // 파형 — 항상 렌더링, opacity/blur로만 제어
                        WaveformBarsView(levels: audioLevels)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .opacity(showThinking ? 0 : 1)
                            .blur(radius: showThinking ? 4 : 0)

                        if showThinking {
                            SpinnerView(label: "Thinking", iconSize: 10, labelSize: 11)
                                .transition(.blurReplace(.downUp))
                        }
                    }
                    .onChange(of: isTranscribing) { _, newValue in
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showThinking = newValue
                        }
                    }
                )
                .offset(x: 20, y: 0)

            // 2. Mandu character: 36×36, Pencil pos(10, 9) → offset(-58.5, 0)
            if let img = manduImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                    .offset(x: -58.5, y: 0)
            } else {
                Color.clear
                    .frame(width: 36, height: 36)
                    .offset(x: -58.5, y: 0)
            }

            // 3. Bubble Tail (small, 6×6)
            Ellipse()
                .fill(Color.manduPurple)
                .frame(width: 6, height: 6)
                .rotationEffect(.radians(-0.054))
                .offset(x: -52.6, y: 7.7)

            // 4. Bubble Tail (medium, 10×10)
            Ellipse()
                .fill(Color.manduPurple)
                .frame(width: 10, height: 10)
                .rotationEffect(.radians(-0.077))
                .offset(x: -45.6, y: 5.7)

            // 5. Bubble Tail (large, 14×14)
            Ellipse()
                .fill(Color.manduPurple)
                .frame(width: 14, height: 14)
                .offset(x: -36.6, y: 0.8)
        }
        .frame(width: 173, height: 54)
    }
}
