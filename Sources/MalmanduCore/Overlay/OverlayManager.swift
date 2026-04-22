import AppKit
import SwiftUI

/// 오버레이 패널 생명주기 관리
@MainActor
public final class OverlayManager {
    private var panel: OverlayPanel?
    private var hostingView: ClickThroughHostingView<OverlayRootView>?
    private var pendingDismissTask: Task<Void, Never>?
    private var toastPanel: OverlayPanel?
    private var toastDismissTask: Task<Void, Never>?
    public weak var appState: AppState?
    public weak var coordinator: RecordingCoordinator?
    public var onFocusContinue: (() -> Void)?
    public var onFocusStop: (() -> Void)?
    public var onCancel: (() -> Void)?
    public var onConfirm: (() -> Void)?

    public init() {}

    /// 오버레이 표시 (AppState 상태에 따라 내부 SwiftUI 뷰가 자동 전환)
    public func show(status: AppStatus) {
        // 진행 중인 dismiss 취소 (빠른 재진입 시 패널 재사용)
        pendingDismissTask?.cancel()
        pendingDismissTask = nil

        if panel == nil {
            createPanel(status: status)
        }
        // rootView 교체 불필요 — @Observable AppState가 SwiftUI 뷰를 자동 업데이트
    }

    /// 오버레이 숨김 (SwiftUI removal transition이 먼저 재생되도록 350ms 지연 후 패널 파괴)
    public func dismiss() {
        guard let panelToRemove = panel else { return }
        pendingDismissTask?.cancel()
        pendingDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            // 그동안 새 패널이 생성되거나 dismiss가 취소된 경우 패널 보존
            guard self?.panel === panelToRemove else { return }
            panelToRemove.orderOut(nil)
            self?.panel = nil
            self?.hostingView = nil
            self?.pendingDismissTask = nil
        }
    }

    /// AppState 상태 변화에 따라 자동 제어
    public func handleStatusChange(_ status: AppStatus) {
        switch status {
        case .recording, .transcribing:
            show(status: status)
        case .idle, .error:
            dismiss()
        }
    }

    /// 토스트 메시지 표시 (자동으로 3초 후 사라짐)
    public func showToast(icon: String = "exclamationmark.triangle.fill", message: String, submessage: String? = nil, duration: TimeInterval = 3.0) {
        // 기존 토스트 정리
        dismissToast()

        let view = ToastOverlayView(icon: icon, message: message, submessage: submessage)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame.size = hostingView.fittingSize

        let panelSize = hostingView.fittingSize
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.minY + 80
        )

        let panel = OverlayPanel(contentRect: NSRect(origin: origin, size: panelSize))
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        toastPanel = panel

        // 자동 dismiss
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            dismissToast()
        }
    }

    /// 토스트 숨김
    public func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toastPanel?.orderOut(nil)
        toastPanel = nil
    }

    /// 에러에 따른 토스트 표시
    public func showError(_ error: AppError) {
        switch error {
        case .apiKeyMissing:
            showToast(
                icon: "key.fill",
                message: "API Key 설정 필요",
                submessage: "메뉴바 → 설정에서 Groq API 키를 입력하세요"
            )
        case .apiKeyInvalid:
            showToast(
                icon: "key.slash.fill",
                message: "API Key가 유효하지 않습니다",
                submessage: "설정에서 API 키를 확인해주세요"
            )
        case .microphonePermissionDenied:
            showToast(
                icon: "mic.slash.fill",
                message: "마이크 권한이 필요합니다",
                submessage: "시스템 설정 → 개인 정보 보호 → 마이크"
            )
        case .accessibilityPermissionDenied:
            showToast(
                icon: "hand.raised.fill",
                message: "손쉬운 사용 권한이 필요합니다",
                submessage: "시스템 설정 → 개인 정보 보호 → 손쉬운 사용"
            )
        case .networkError(let msg):
            showToast(icon: "wifi.slash", message: "네트워크 오류", submessage: msg)
        case .transcriptionFailed(let msg):
            showToast(icon: "waveform.slash", message: "변환 실패", submessage: msg)
        case .fileTooLarge:
            showToast(icon: "exclamationmark.triangle.fill", message: "녹음 파일이 너무 큽니다", submessage: "25MB 이하로 녹음해주세요")
        case .recordingFailed(let msg):
            showToast(icon: "mic.slash.fill", message: "녹음 실패", submessage: msg)
        }
    }

    // MARK: - Private

    private func createPanel(status: AppStatus) {
        // visible 콘텐츠에 거의 딱 맞게 패널을 잡는다.
        // 다크 캡슐(약 220×80) + 6 gap + 액션 pill(100×30) + 여백 = 약 240×130
        let size = NSSize(width: 280, height: 200)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - 12  // 메뉴바로부터 12px 아래
        )

        let panel = OverlayPanel(contentRect: NSRect(origin: origin, size: size))
        self.panel = panel

        // rootView 1회만 설정 — AppState가 @Observable이므로 자동 업데이트
        guard let appState else { return }
        let rootView = OverlayRootView(
            appState: appState,
            coordinator: coordinator,
            onFocusContinue: onFocusContinue,
            onFocusStop: onFocusStop,
            onCancel: onCancel,
            onConfirm: onConfirm
        )
        let hv = ClickThroughHostingView(rootView: rootView)
        panel.contentView = hv
        hostingView = hv
        panel.orderFrontRegardless()
    }
}
