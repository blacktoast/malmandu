import SwiftUI
import MalmanduCore

/// 테스트용 메인 윈도우 (디버그)
struct TestMainView: View {
    @Environment(AppState.self) private var appState
    @Environment(RecordingCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(statusColor)

            Text("malmandu")
                .font(.largeTitle.bold())

            Text("상태: \(appState.status.rawValue)")
                .font(.title2)
                .foregroundColor(statusColor)

            HStack(spacing: 16) {
                Button(action: {
                    Task { await coordinator.toggleRecording() }
                }) {
                    Label(
                        appState.status == .recording ? "녹음 중지" : "녹음 시작",
                        systemImage: appState.status == .recording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .font(.title3)
                    .frame(width: 140, height: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.status == .recording ? .red : .blue)
                .disabled(appState.status == .transcribing)

                if appState.status == .error {
                    Button("재시도") {
                        Task { await coordinator.retryLastTranscription() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = appState.lastError {
                Text("오류: \(String(describing: error))")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Divider()

            Text("단축키: ⌘+Shift+Space")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("메뉴바 상단의 마이크 아이콘도 확인해보세요")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 300)
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle: return .primary
        case .recording: return .red
        case .transcribing: return .orange
        case .error: return .red
        }
    }
}
