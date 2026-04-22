import SwiftUI

/// NSHostingView의 rootView — AppState를 직접 관찰하여 자동 업데이트
/// rootView 교체 없이 @Observable AppState 변화에 반응
struct OverlayRootView: View {
    let appState: AppState
    // weak 참조를 위해 class wrapper 없이 optional로 유지
    // RecordingCoordinator는 AppDelegate가 소유하므로 수명 보장됨
    var coordinator: RecordingCoordinator?
    var onFocusContinue: (() -> Void)?
    var onFocusStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    /// 노치 transition 발동 단일 진실 — 모든 변화는 withAnimation으로 명시 제어
    @State private var isVisible = false

    private var shouldShow: Bool {
        appState.status == .recording || appState.status == .transcribing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                overlayContent
                Spacer()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // 최초 등장: 다음 runloop으로 미루어 false→true 변화로 insertion transition trigger
            if shouldShow {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVisible = true
                    }
                }
            }
        }
        .onChange(of: appState.status) { _, _ in
            let target = shouldShow
            if target != isVisible {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVisible = target
                }
            }
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        // isVisible이 단일 진실 — 모든 변화는 withAnimation으로 제어되어
        // .blurReplace insertion/removal transition이 안정적으로 발동
        if isVisible {
            RecordingOverlayView(
                appState: appState,
                isRealtimeMode: coordinator?.isRealtimeMode ?? false,
                onContinue: onFocusContinue,
                onStop: onFocusStop,
                onCancel: onCancel,
                onConfirm: onConfirm
            )
            .transition(.blurReplace(.downUp))
        }
    }
}
