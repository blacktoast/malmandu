import SwiftUI
import KeyboardShortcuts
import MalmanduCore

// MARK: - KeyboardShortcuts 확장

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
}

// MARK: - App

@main
struct MalmanduApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.appState)
                .environment(appDelegate.coordinator)
        } label: {
            Label {
                Text("malmandu")
            } icon: {
                Image(nsImage: Self.manduTemplateImage)
            }
        }

        // 테스트용 메인 윈도우 (디버그)
        Window("malmandu - test", id: "test") {
            TestMainView()
                .environment(appDelegate.appState)
                .environment(appDelegate.coordinator)
        }
        .defaultSize(width: 400, height: 300)

        Settings {
            SettingsView()
                .environment(appDelegate.appState)
        }
    }

    private static let manduTemplateImage: NSImage = {
        // Bundle.image(forResource:)는 @2x/@3x 파일을 자동 선택한다.
        if let img = Bundle.module.image(forResource: "mandu-template") {
            img.size = NSSize(width: 22, height: 22)
            img.isTemplate = true
            return img
        }
        return NSImage(systemSymbolName: "mic.circle", accessibilityDescription: nil) ?? NSImage()
    }()
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private(set) var coordinator: RecordingCoordinator!
    let overlayManager = OverlayManager()
    let sttFactory: STTProviderFactory = DefaultSTTProviderFactory()
    private let keychainService = KeychainService()
    private let soundService = SoundService()
    private let accessibilityService = AccessibilityService()

    // Modifier-only 단축키 감지 (Fn 등)
    private var modifierMonitorGlobal: Any?
    private var modifierMonitorLocal: Any?
    private var lastModifierFlags: NSEvent.ModifierFlags = []

    override init() {
        super.init()

        let factory = sttFactory
        let dynamicClient = DynamicSTTClient {
            let provider = STTProvider.current
            let ks = KeychainService(account: provider.keychainAccount)
            let model = UserDefaults.standard.string(forKey: provider.modelUserDefaultsKey) ?? provider.defaultModel
            return factory.makeFileClient(for: provider, model: model, apiKey: { try? ks.getAPIKey() })
        }
        let textInjector = TextInjector(accessibilityService: accessibilityService)

        coordinator = RecordingCoordinator(
            appState: appState,
            audioRecorder: AudioRecorder(),
            apiClient: dynamicClient,
            textInjector: textInjector,
            soundService: soundService,
            language: {
                let primary = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "ko"
                let secondary = UserDefaults.standard.string(forKey: "secondaryLanguage") ?? ""
                let provider = STTProvider.current
                // primary가 auto면 nil 반환 → 두 제공자 모두 자동 감지
                if primary == LanguageCode.auto { return nil }
                switch provider {
                case .groq:
                    // Groq는 보조 언어 미지원
                    return primary
                case .soniox:
                    if secondary.isEmpty || secondary == LanguageCode.auto || primary == secondary {
                        return primary
                    }
                    return "\(primary),\(secondary)"
                }
            },
            model: {
                let provider = STTProvider.current
                return UserDefaults.standard.string(forKey: provider.modelUserDefaultsKey) ?? provider.defaultModel
            },
            prompt: {
                let vocab = UserDefaults.standard.string(forKey: "customVocabulary") ?? ""
                return vocab.isEmpty ? nil : vocab
            },
            apiKeyCheck: {
                let provider = STTProvider.current
                return (try? KeychainService(account: provider.keychainAccount).getAPIKey())?.isEmpty == false
            },
            streamingClientProvider: {
                let provider = STTProvider.current
                let model = UserDefaults.standard.string(forKey: provider.modelUserDefaultsKey) ?? provider.defaultModel
                let ks = KeychainService(account: provider.keychainAccount)
                return factory.makeStreamingClient(for: provider, model: model, apiKey: { try? ks.getAPIKey() })
            },
            textPolisher: TextPolisher(apiKeyProvider: {
                try? KeychainService(account: STTProvider.groq.keychainAccount).getAPIKey()
            }),
            polishEnabled: {
                UserDefaults.standard.bool(forKey: "textPolishEnabled")
            }
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 단축키 기본값: 최초 1회 Fn 키 설정
        if !UserDefaults.standard.bool(forKey: "shortcutMigratedToV3") {
            KeyboardShortcuts.setShortcut(nil, for: .toggleRecording)
            ModifierOnlyShortcutStore.save(
                ModifierOnlyShortcut(flags: .function),
                for: .toggleRecording
            )
            UserDefaults.standard.set(true, forKey: "shortcutMigratedToV3")
        }

        // 오버레이에 AppState, coordinator 참조 연결
        overlayManager.appState = appState
        overlayManager.coordinator = coordinator

        // 테스트 중: Dock 아이콘 표시 (메뉴바+윈도우 모두 사용)
        NSApplication.shared.setActivationPolicy(.regular)

        // Accessibility 권한 체크
        if !accessibilityService.isAccessibilityEnabled() {
            _ = accessibilityService.requestAccessibility()
        }

        // 키보드 단축키 핸들러 등록
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.coordinator.toggleRecording()
                self.overlayManager.handleStatusChange(self.appState.status)
            }
        }

        // Modifier-only 단축키 감지 등록 (Fn 등)
        setupModifierOnlyMonitor()

        // RecordingCoordinator에 오버레이 콜백 연결
        coordinator.onStatusChange = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.overlayManager.handleStatusChange(status)
            }
        }

        // 에러 발생 시 토스트 표시
        coordinator.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.overlayManager.showError(error)
            }
        }

        // 포커스 이탈 시 오버레이 콜백 연결
        overlayManager.onFocusContinue = { [weak self] in
            guard let self, let bundleId = self.coordinator.startingAppBundleId else { return }
            FocusDetector().activateApp(bundleId: bundleId)
        }

        overlayManager.onFocusStop = { [weak self] in
            guard let self else { return }
            Task {
                await self.coordinator.toggleRecording()
            }
        }

        // 오버레이 취소/확인 버튼 콜백
        // X(Cancel): 오디오/소켓 폐기, 변환 없이 idle 복귀
        // ✓(Confirm): 일반 종료 — 변환 + 붙여넣기
        overlayManager.onCancel = { [weak self] in
            guard let self else { return }
            Task { await self.coordinator.cancelRecording() }
        }

        overlayManager.onConfirm = { [weak self] in
            guard let self else { return }
            Task { await self.coordinator.toggleRecording() }
        }

        overlayManager.onPastePending = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.coordinator.pastePendingTranscription()
            }
        }
    }

    // MARK: - Modifier-only 단축키 감지

    private func setupModifierOnlyMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleModifierEvent(event)
            }
        }

        modifierMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
        }
        modifierMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }

    @MainActor
    private func handleModifierEvent(_ event: NSEvent) {
        let current = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        defer { lastModifierFlags = current }

        guard let saved = ModifierOnlyShortcutStore.load(.toggleRecording), !saved.isEmpty else {
            return
        }
        let target = saved.flags.intersection(.deviceIndependentFlagsMask)

        // edge: 직전 != target, 현재 == target → 토글 1회
        guard current == target, lastModifierFlags != target else { return }

        Task {
            await coordinator.toggleRecording()
            overlayManager.handleStatusChange(appState.status)
        }
    }
}
