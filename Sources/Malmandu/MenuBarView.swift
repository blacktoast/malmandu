import SwiftUI
import MalmanduCore

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(RecordingCoordinator.self) private var coordinator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(appState.status == .recording ? "녹음 중지" : "녹음 시작") {
            Task { await coordinator.toggleRecording() }
        }
        .keyboardShortcut("r", modifiers: [.command])

        if appState.status == .error {
            Button("마지막 변환 재시도") {
                Task { await coordinator.retryLastTranscription() }
            }
        }

        Divider()

        Button("설정...") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
            // Settings 창을 최상위로 올리기
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for window in NSApp.windows {
                    if window.identifier?.rawValue.contains("settings") == true
                        || window.title.contains("Settings")
                        || window.title.contains("설정") {
                        window.level = .floating
                        window.orderFrontRegardless()
                    }
                }
            }
        }

        Divider()

        Button("종료") {
            NSApplication.shared.terminate(nil)
        }
    }
}
