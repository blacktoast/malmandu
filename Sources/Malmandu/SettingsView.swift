import SwiftUI
import KeyboardShortcuts
import MalmanduCore

// MARK: - 디자인 토큰 (Pencil 변수 1:1 매핑)

private enum SettingsTheme {
    static let accentPrimary      = Color(hex: 0x7C3AED)
    static let accentPrimaryLight = Color(hex: 0xEDE9FE)
    static let borderLight        = Color(hex: 0xE5E7EB)
    static let borderMuted        = Color(hex: 0xF0F1F3)
    static let danger             = Color(hex: 0xEF4444)
    static let success            = Color(hex: 0x22C55E)
    static let fgInverse          = Color(hex: 0xFFFFFF)
    static let fgMuted            = Color(hex: 0x888888)
    static let fgPrimary          = Color(hex: 0x1A1A1A)
    static let fgSecondary        = Color(hex: 0x666666)
    static let surfacePrimary     = Color(hex: 0xFFFFFF)
    static let surfaceSecondary   = Color(hex: 0xF7F8FA)
    static let surfaceHover       = Color(hex: 0xEDF0F4)
    static let toggleOff          = Color(hex: 0xD1D5DB)
    static let toggleOn           = Color(hex: 0x7C3AED)
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

// MARK: - 사이드바 항목

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case apiModel
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "일반"
        case .apiModel: return "API 및 모델"
        case .preferences: return "설정"
        }
    }

    /// SF Symbols — Pencil 디자인의 lucide 아이콘과 동일한 의미
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .apiModel: return "key"
        case .preferences: return "slider.horizontal.3"
        }
    }
}

// MARK: - 메인

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: SettingsSection = .general
    /// API 페이지에서 변경된 provider를 다른 페이지가 observe할 수 있게 하는 트리거
    @State private var providerRevision: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
                .frame(width: 176)

            Group {
                switch selection {
                case .general:
                    GeneralPane()
                case .apiModel:
                    APIModelPane(providerRevision: $providerRevision)
                case .preferences:
                    PreferencesPane(providerRevision: providerRevision)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsTheme.surfacePrimary)
        }
        .frame(width: 580, height: 580)
        .background(SettingsTheme.surfacePrimary)
    }
}

// MARK: - 사이드바

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 앱 로고 영역
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SettingsTheme.accentPrimary)
                        .frame(width: 30, height: 30)
                    Text("M")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(SettingsTheme.fgInverse)
                }
                Text("malmandu")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SettingsTheme.fgPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            // 네비게이션
            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    SidebarNavItem(
                        icon: section.icon,
                        title: section.title,
                        isSelected: selection == section,
                        action: { selection = section }
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SettingsTheme.surfaceSecondary)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SettingsTheme.borderLight)
                .frame(width: 1)
        }
    }
}

private struct SidebarNavItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? SettingsTheme.accentPrimary : SettingsTheme.fgSecondary)
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? SettingsTheme.accentPrimary : SettingsTheme.fgSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? SettingsTheme.accentPrimaryLight
                          : (isHovered ? SettingsTheme.surfaceHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - 컨텐츠 스캐폴드

private struct ContentScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(SettingsTheme.fgPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(SettingsTheme.fgSecondary)
                }
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 카드 + 섹션

/// "섹션 라벨이 카드 밖에" 패턴 (Tjedv / Fb6C5 스타일)
private struct SectionBlock<Content: View>: View {
    let title: String
    var titleMuted: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(titleMuted ? SettingsTheme.fgMuted : SettingsTheme.fgPrimary)
            content
        }
    }
}

private struct SettingsCard<Content: View>: View {
    var background: Color = SettingsTheme.surfaceSecondary
    var borderColor: Color = SettingsTheme.borderMuted
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - 커스텀 토글 (Pencil 디자인 매칭)

private struct PillToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? SettingsTheme.toggleOn : SettingsTheme.toggleOff)
                .frame(width: 40, height: 22)
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 0.5)
                .padding(2)
        }
        .animation(.easeInOut(duration: 0.15), value: isOn)
        .contentShape(Capsule())
        .onTapGesture { isOn.toggle() }
    }
}

private struct ToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SettingsTheme.fgPrimary)
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(SettingsTheme.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            PillToggle(isOn: $isOn)
        }
    }
}

// MARK: - 커스텀 드롭다운

private struct DropdownPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    private var currentLabel: String {
        options.first(where: { $0.0 == selection })?.1 ?? ""
    }

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(option.1) { selection = option.0 }
            }
        } label: {
            HStack {
                Text(currentLabel)
                    .font(.system(size: 12))
                    .foregroundColor(SettingsTheme.fgPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SettingsTheme.fgMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(SettingsTheme.surfacePrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(SettingsTheme.borderLight, lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 커스텀 버튼

private struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(SettingsTheme.fgInverse)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(disabled ? SettingsTheme.accentPrimary.opacity(0.5) : SettingsTheme.accentPrimary)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - 제공자 카드 (side-by-side)

private struct ProviderCard: View {
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? SettingsTheme.accentPrimary : SettingsTheme.fgPrimary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(SettingsTheme.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(SettingsTheme.accentPrimary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(isSelected ? SettingsTheme.accentPrimaryLight : SettingsTheme.surfacePrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? SettingsTheme.accentPrimary : SettingsTheme.borderLight,
                            lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 일반 패널

private struct GeneralPane: View {
    @State private var soundEnabled: Bool = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    @State private var textPolishEnabled: Bool = UserDefaults.standard.bool(forKey: "textPolishEnabled")
    @State private var customVocabulary: String = UserDefaults.standard.string(forKey: "customVocabulary") ?? ""
    @State private var newTerm: String = ""
    @State private var isAddingTerm: Bool = false

    var body: some View {
        ContentScaffold(title: "일반", subtitle: "앱의 일반 설정을 관리합니다") {
            SectionBlock(title: "커스텀 단어 / 용어") {
                SettingsCard {
                    Text("자주 사용하는 고유명사나 전문 용어를 등록하면 음성 인식 정확도가 향상됩니다")
                        .font(.system(size: 11))
                        .foregroundColor(SettingsTheme.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VocabularyInputField(
                        vocabulary: $customVocabulary,
                        newTerm: $newTerm,
                        isAdding: $isAddingTerm
                    )

                    VocabularyTagsRow(vocabulary: $customVocabulary)

                    Text("쉼표로 구분하여 여러 단어를 한번에 추가할 수 있습니다")
                        .font(.system(size: 10))
                        .foregroundColor(SettingsTheme.fgMuted)
                }
            }

            SectionBlock(title: "소리") {
                SettingsCard {
                    ToggleRow(
                        title: "효과음",
                        description: "녹음 시작/종료 시 효과음을 재생합니다",
                        isOn: $soundEnabled
                    )
                    .onChange(of: soundEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "soundEnabled")
                    }
                }
            }

            SectionBlock(title: "텍스트 다듬기") {
                SettingsCard {
                    ToggleRow(
                        title: "AI 텍스트 다듬기",
                        description: "Groq LLM(llama-3.3-70b)으로 군말 제거 및 조사를 교정합니다. 비동기 모드에서만 적용됩니다.",
                        isOn: $textPolishEnabled
                    )
                    .onChange(of: textPolishEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "textPolishEnabled")
                    }
                }
            }
        }
    }
}

// MARK: - API 및 모델 패널

private struct APIModelPane: View {
    @Binding var providerRevision: Int

    private let sttFactory: STTProviderFactory = DefaultSTTProviderFactory()
    @State private var selectedProvider: STTProvider = STTProvider.current
    @State private var apiKey: String = ""
    @State private var selectedModel: String = ""
    @State private var silenceAutoDisconnect: Bool = UserDefaults.standard.object(forKey: "silenceAutoDisconnect") as? Bool ?? false
    @State private var testResult: String?
    @State private var isTesting: Bool = false
    @State private var apiKeyMasked: Bool = true

    private var providerHintURL: String {
        switch selectedProvider {
        case .groq:  return "api.groq.com"
        case .soniox: return "soniox.com"
        }
    }

    private var providerDescription: (String, String) {
        // (Groq 설명, Soniox 설명)
        ("Whisper 기반 비동기 변환", "실시간 스트리밍 지원")
    }

    private var supportsRealtime: Bool {
        // Soniox의 stt-rt-v4 등 RT 모델이 있을 때만
        selectedProvider == .soniox
    }

    var body: some View {
        ContentScaffold(title: "API 및 모델", subtitle: "STT 제공자 및 모델을 설정합니다") {
            SectionBlock(title: "STT 제공자") {
                HStack(spacing: 10) {
                    ProviderCard(
                        title: "Groq",
                        description: providerDescription.0,
                        isSelected: selectedProvider == .groq,
                        action: { selectProvider(.groq) }
                    )
                    ProviderCard(
                        title: "Soniox",
                        description: providerDescription.1,
                        isSelected: selectedProvider == .soniox,
                        action: { selectProvider(.soniox) }
                    )
                }
            }

            SectionBlock(title: "API 키") {
                SettingsCard {
                    Text("\(selectedProvider.displayName) API Key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SettingsTheme.fgSecondary)

                    HStack(spacing: 8) {
                        APIKeyField(apiKey: $apiKey, masked: $apiKeyMasked, onSubmit: saveAPIKey)

                        PrimaryButton(
                            title: isTesting ? "검증 중..." : "검증",
                            icon: "checkmark.shield",
                            disabled: apiKey.isEmpty || isTesting,
                            action: {
                                saveAPIKey()
                                testAPIConnection()
                            }
                        )
                    }

                    HStack(spacing: 6) {
                        if let result = testResult {
                            Circle()
                                .fill(testResultIsSuccess ? SettingsTheme.success : SettingsTheme.danger)
                                .frame(width: 6, height: 6)
                            Text(result)
                                .font(.system(size: 11))
                                .foregroundColor(testResultIsSuccess ? SettingsTheme.success : SettingsTheme.danger)
                        } else {
                            Text("\(providerHintURL)에서 API 키를 발급받을 수 있습니다")
                                .font(.system(size: 10))
                                .foregroundColor(SettingsTheme.fgMuted)
                        }
                    }
                }
            }

            SectionBlock(title: "모델 선택") {
                SettingsCard {
                    DropdownPicker(
                        selection: $selectedModel,
                        options: selectedProvider.models.map { ($0.id, $0.displayName) }
                    )
                    .onChange(of: selectedModel) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: selectedProvider.modelUserDefaultsKey)
                    }
                }
            }

            SectionBlock(title: "실시간 모드", titleMuted: !supportsRealtime) {
                if supportsRealtime {
                    SettingsCard {
                        ToggleRow(
                            title: "침묵 시 자동 소켓 해제",
                            description: "5초 침묵 시 WebSocket을 자동 해제하여 API 비용을 절감합니다. 음성이 다시 감지되면 자동 재연결됩니다.",
                            isOn: $silenceAutoDisconnect
                        )
                        .onChange(of: silenceAutoDisconnect) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "silenceAutoDisconnect")
                        }
                    }
                } else {
                    SettingsCard(background: SettingsTheme.surfaceSecondary,
                                 borderColor: SettingsTheme.borderLight) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "bolt.slash")
                                .font(.system(size: 15))
                                .foregroundColor(SettingsTheme.fgMuted)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("실시간 스트리밍 사용 불가")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(SettingsTheme.fgMuted)
                                Text("실시간 모드는 Soniox 제공자에서만 사용 가능합니다")
                                    .font(.system(size: 11))
                                    .foregroundColor(SettingsTheme.fgMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                    }
                    .opacity(0.7)
                }
            }
        }
        .onAppear { reloadForProvider(selectedProvider) }
    }

    private var testResultIsSuccess: Bool {
        guard let r = testResult else { return false }
        return r.contains("성공") || r.contains("유효")
    }

    private func selectProvider(_ provider: STTProvider) {
        guard provider != selectedProvider else { return }
        selectedProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "selectedSTTProvider")
        reloadForProvider(provider)
        providerRevision &+= 1
    }

    private func reloadForProvider(_ provider: STTProvider) {
        let ks = KeychainService(account: provider.keychainAccount)
        apiKey = (try? ks.getAPIKey()) ?? ""
        selectedModel = UserDefaults.standard.string(forKey: provider.modelUserDefaultsKey) ?? provider.defaultModel
        testResult = nil
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }
        let ks = KeychainService(account: selectedProvider.keychainAccount)
        try? ks.save(apiKey: apiKey)
    }

    private func testAPIConnection() {
        isTesting = true
        testResult = nil
        let provider = selectedProvider
        let key = apiKey
        let factory = sttFactory
        Task {
            do {
                try await factory.testConnection(provider: provider, apiKey: key)
                testResult = "인증 성공! (API 키 유효)"
            } catch AppError.apiKeyInvalid {
                testResult = "API 키가 유효하지 않습니다"
            } catch AppError.apiKeyMissing {
                testResult = "API 키를 입력해주세요"
            } catch let AppError.networkError(msg) {
                testResult = "네트워크 오류: \(msg)"
            } catch {
                testResult = "오류: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

// MARK: - API 키 입력 필드

private struct APIKeyField: View {
    @Binding var apiKey: String
    @Binding var masked: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if masked {
                    SecureField("API 키를 입력하세요", text: $apiKey)
                } else {
                    TextField("API 키를 입력하세요", text: $apiKey)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(SettingsTheme.fgPrimary)
            .onSubmit(onSubmit)

            Button(action: { masked.toggle() }) {
                Image(systemName: masked ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundColor(SettingsTheme.fgMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(SettingsTheme.surfacePrimary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SettingsTheme.borderLight, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - 설정 (단축키 + 언어) 패널

private struct PreferencesPane: View {
    let providerRevision: Int

    @State private var provider: STTProvider = STTProvider.current
    @State private var selectedLanguage: String = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "ko"
    @State private var secondaryLanguage: String = UserDefaults.standard.string(forKey: "secondaryLanguage") ?? ""

    private let languages: [(String, String)] = [
        (LanguageCode.auto, "자동 감지"),
        ("ko", "한국어"),
        ("en", "English"),
        ("ja", "日本語"),
        ("zh", "中文"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch"),
    ]

    private var primaryOptions: [(String, String)] { languages }

    private var secondaryOptions: [(String, String)] {
        [("", "없음")] + languages.filter { $0.0 != LanguageCode.auto }
    }

    private var showSecondary: Bool {
        provider.supportsSecondaryLanguage && selectedLanguage != LanguageCode.auto
    }

    private var languageHint: String {
        switch provider {
        case .groq:
            return "Groq Whisper는 단일 언어만 지원합니다. 자동 감지를 선택하면 모델이 언어를 추론합니다."
        case .soniox:
            return "Soniox는 여러 언어를 동시에 인식할 수 있습니다. 기본 언어를 자동 감지로 두면 보조 언어 설정은 사용되지 않습니다."
        }
    }

    var body: some View {
        ContentScaffold(title: "설정", subtitle: "단축키 및 언어를 설정합니다") {
            SectionBlock(title: "단축키") {
                SettingsCard {
                    UnifiedShortcutRecorderField(
                        label: "녹음 토글",
                        keyboardName: .toggleRecording,
                        modifierKey: .toggleRecording
                    )
                    .foregroundColor(SettingsTheme.fgPrimary)

                    Text("일반 키 조합 또는 Fn 등 modifier-only 키를 등록할 수 있습니다. 시스템 단축키와 충돌 시 동작하지 않을 수 있습니다.")
                        .font(.system(size: 11))
                        .foregroundColor(SettingsTheme.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SectionBlock(title: "언어") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("기본 언어")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(SettingsTheme.fgSecondary)
                            DropdownPicker(selection: $selectedLanguage, options: primaryOptions)
                                .onChange(of: selectedLanguage) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "selectedLanguage")
                                }
                        }

                        if showSecondary {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("보조 언어")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(SettingsTheme.fgSecondary)
                                DropdownPicker(selection: $secondaryLanguage, options: secondaryOptions)
                                    .onChange(of: secondaryLanguage) { _, newValue in
                                        UserDefaults.standard.set(newValue, forKey: "secondaryLanguage")
                                    }
                            }
                        }

                        Text(languageHint)
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.fgMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear { refreshProvider() }
        .onChange(of: providerRevision) { _, _ in refreshProvider() }
    }

    private func refreshProvider() {
        provider = STTProvider.current
    }
}

// MARK: - 고유명사 입력 + 태그

private struct VocabularyInputField: View {
    @Binding var vocabulary: String
    @Binding var newTerm: String
    @Binding var isAdding: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("단어를 입력하고 Enter를 누르세요", text: $newTerm)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(SettingsTheme.fgPrimary)
                .onSubmit { commit() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(SettingsTheme.surfacePrimary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SettingsTheme.borderLight, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private func commit() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // 쉼표로 여러 개 한번에 추가 지원
        let incoming = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var existing = vocabulary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for term in incoming where !existing.contains(term) {
            existing.append(term)
        }
        vocabulary = existing.joined(separator: ", ")
        UserDefaults.standard.set(vocabulary, forKey: "customVocabulary")
        newTerm = ""
    }
}

private struct VocabularyTagsRow: View {
    @Binding var vocabulary: String

    private var terms: [String] {
        vocabulary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        if terms.isEmpty {
            EmptyView()
        } else {
            FlowLayout(spacing: 6) {
                ForEach(terms, id: \.self) { term in
                    HStack(spacing: 6) {
                        Text(term)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(SettingsTheme.accentPrimary)
                        Button(action: { remove(term) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(SettingsTheme.accentPrimary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(SettingsTheme.accentPrimaryLight)
                    )
                }
            }
        }
    }

    private func remove(_ term: String) {
        let updated = terms.filter { $0 != term }.joined(separator: ", ")
        vocabulary = updated
        UserDefaults.standard.set(vocabulary, forKey: "customVocabulary")
    }
}

// MARK: - FlowLayout (태그 줄바꿈)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
