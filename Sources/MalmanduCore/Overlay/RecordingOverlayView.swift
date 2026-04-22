import SwiftUI

/// 녹음 중 오버레이 뷰 (만두 캐릭터 + 파형 + 실시간 텍스트)
public struct RecordingOverlayView: View {
    let appState: AppState
    var isRealtimeMode: Bool = false
    var onContinue: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    @State private var rtTextHeight: CGFloat = 0
    private let rtTextMaxHeight: CGFloat = 80

    public init(
        appState: AppState,
        isRealtimeMode: Bool = false,
        onContinue: (() -> Void)? = nil,
        onStop: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onConfirm: (() -> Void)? = nil
    ) {
        self.appState = appState
        self.isRealtimeMode = isRealtimeMode
        self.onContinue = onContinue
        self.onStop = onStop
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        if appState.focusLost {
            focusLostView
        } else if isRealtimeMode {
            rtModeView
        } else {
            asyncModeView
        }
    }

    private var asyncModeView: some View {
        VStack(spacing: 6) {
            // 만두 + 파형 영역 — 다크 배경 안
            ManduIconGroupView(
                audioLevels: appState.audioLevels,
                isTranscribing: appState.status == .transcribing
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.overlayBackground.opacity(0.94)))

            // 버튼 pill — 다크 배경 밖, 별도 캡슐 배경
            ActionButtonsPillView(onCancel: onCancel, onConfirm: onConfirm)
        }
    }

    private var rtModeView: some View {
        VStack(spacing: 6) {
            // 라벨 + 만두/파형 + 텍스트 — 다크 배경 안
            // VStack은 center 정렬(기본) — 텍스트(200) 등장 시 만두/라벨 위치 고정
            VStack(spacing: 2) {
                // Real Time 라벨: 만두 폭(183)과 동일한 컨테이너에서 leading 정렬
                // 컨테이너 자체는 center 정렬되므로 텍스트 등장 시 위치 변하지 않음
                HStack(spacing: 0) {
                    Text("Real Time")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(Color.manduPurple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.manduPurple.opacity(0.125)))
                        .padding(.leading, 10)  // 만두 leading edge(x=10)에 align
                    Spacer(minLength: 0)
                }
                .frame(width: 173)  // 만두/버블 영역과 동일 폭으로 고정

                ManduIconGroupView(
                    audioLevels: appState.audioLevels,
                    isTranscribing: appState.status == .transcribing
                )
                // 녹음 중 파형 지터 방지 (변환 중일 때는 스피너 애니메이션을 허용해야 함)
                .transaction { $0.animation = appState.status == .recording ? nil : $0.animation }

                rtTextBox
            }
            .frame(width: 200)  // 폭 고정 — 텍스트 등장 시 만두 출렁임 방지 (높이 spring은 유지)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.overlayBackground.opacity(0.94)))

            // 버튼 pill — 다크 배경 밖
            ActionButtonsPillView(onCancel: onCancel, onConfirm: onConfirm)
        }
    }

    private var rtTextBody: some View {
        // 빈 상태에서도 1줄 높이를 유지하기 위해 공백 fallback
        Text(displayText?.isEmpty == false ? displayText! : " ")
            .font(.system(size: 13))
            .foregroundColor(Color.overlayText)
            .lineSpacing(13 * 0.5)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: RTTextHeightKey.self, value: geo.size.height)
                }
            )
    }

    @ViewBuilder
    private var rtTextBox: some View {
        let needsScroll = rtTextHeight > rtTextMaxHeight
        Group {
            if needsScroll {
                ScrollView {
                    rtTextBody
                }
                .scrollIndicators(.hidden)
                .frame(height: rtTextMaxHeight)
            } else {
                rtTextBody
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 200)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.textAreaBackground))
        .onPreferenceChange(RTTextHeightKey.self) { rtTextHeight = $0 }
    }

    private var displayText: String? {
        let parts = [appState.pendingCopyText, appState.partialTranscription]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined()
    }

    private var focusLostView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 16))

                Text("\(appState.startingAppName ?? "앱")에서 포커싱이 해제되었습니다")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            Text("돌아가서 계속하거나 녹음을 종료하세요")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))

            if let pendingText = appState.pendingCopyText, !pendingText.isEmpty {
                ScrollView {
                    Text(pendingText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 350, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 80)
            }

            HStack(spacing: 16) {
                Button(action: { onContinue?() }) {
                    Text("계속")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: {
                    if let pendingText = appState.pendingCopyText, !pendingText.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pendingText, forType: .string)
                    }
                    onStop?()
                }) {
                    Text("종료")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .speechBubbleBackground()
    }
}

private struct RTTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
