import AppKit
import SwiftUI
import KeyboardShortcuts
import MalmanduCore

/// 통합 단축키 Recorder.
/// 일반 키 조합(keyCode + modifiers)과 modifier-only(Fn 등)를
/// 한 UI로 캡처하고, 내부적으로 KeyboardShortcuts 또는 ModifierOnlyShortcutStore에 저장한다.
struct UnifiedShortcutRecorderField: View {
    let label: String
    let keyboardName: KeyboardShortcuts.Name
    let modifierKey: ModifierOnlyShortcutStore.Key

    @State private var isRecording: Bool = false
    @State private var refreshTick: Int = 0

    private var displayLabel: String {
        _ = refreshTick
        if let s = KeyboardShortcuts.getShortcut(for: keyboardName) {
            return s.description
        }
        if let m = ModifierOnlyShortcutStore.load(modifierKey), !m.isEmpty {
            return m.displayString
        }
        return ""
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                UnifiedRecorderRepresentable(
                    isRecording: $isRecording,
                    onCaptureKeyed: { keyCode, mods in
                        setKeyed(keyCode: keyCode, modifiers: mods)
                    },
                    onCaptureModifierOnly: { shortcut in
                        setModifierOnly(shortcut)
                    }
                )
                .frame(width: 160, height: 22)
                .overlay(
                    Text(isRecording ? "키를 누르세요…" : (displayLabel.isEmpty ? "기록되지 않음" : displayLabel))
                        .font(.system(size: 12))
                        .foregroundColor(isRecording ? .secondary : .primary)
                        .allowsHitTesting(false)
                )
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.textBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )

                if !displayLabel.isEmpty {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("단축키 제거")
                }
            }
        }
        .onAppear { refreshTick &+= 1 }
    }

    private func setKeyed(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let key = KeyboardShortcuts.Key(rawValue: Int(keyCode))
        let cleanMods = modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.function)
        let shortcut = KeyboardShortcuts.Shortcut(key, modifiers: cleanMods)
        KeyboardShortcuts.setShortcut(shortcut, for: keyboardName)
        ModifierOnlyShortcutStore.save(nil, for: modifierKey)
        refreshTick &+= 1
    }

    private func setModifierOnly(_ shortcut: ModifierOnlyShortcut) {
        KeyboardShortcuts.setShortcut(nil, for: keyboardName)
        ModifierOnlyShortcutStore.save(shortcut, for: modifierKey)
        refreshTick &+= 1
    }

    private func clear() {
        KeyboardShortcuts.setShortcut(nil, for: keyboardName)
        ModifierOnlyShortcutStore.save(nil, for: modifierKey)
        refreshTick &+= 1
    }
}

// MARK: - NSView 래퍼

private struct UnifiedRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCaptureKeyed: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCaptureModifierOnly: (ModifierOnlyShortcut) -> Void

    func makeNSView(context: Context) -> UnifiedRecorderNSView {
        let view = UnifiedRecorderNSView()
        view.onCaptureKeyed = onCaptureKeyed
        view.onCaptureModifierOnly = { flags in
            let s = ModifierOnlyShortcut(flags: flags)
            guard !s.isEmpty else { return }
            onCaptureModifierOnly(s)
        }
        view.onFocusChange = { focused in
            if isRecording != focused { isRecording = focused }
        }
        return view
    }

    func updateNSView(_ nsView: UnifiedRecorderNSView, context: Context) {}
}

final class UnifiedRecorderNSView: NSView {
    typealias KeyStateProvider = (CGKeyCode) -> Bool

    var onCaptureKeyed: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCaptureModifierOnly: ((NSEvent.ModifierFlags) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    private static let modifierKeyCodes: Set<CGKeyCode> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private let isKeyPressed: KeyStateProvider
    private var pendingFlags: NSEvent.ModifierFlags = []
    private var currentFlags: NSEvent.ModifierFlags = []
    private var pressedKeyCodes: Set<CGKeyCode> = []
    private var polledCandidate: CGKeyCode?
    private var polledCandidateModifiers: NSEvent.ModifierFlags = []
    private var polledCandidateTicks: Int = 0
    private var keyDownHappened: Bool = false
    private var eventMonitor: Any?
    private var keyStateTimer: Timer?
    private var isActive: Bool = false

    init(
        isKeyPressed: @escaping KeyStateProvider = {
            CGEventSource.keyState(.combinedSessionState, key: $0)
        }
    ) {
        self.isKeyPressed = isKeyPressed
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 클릭 전엔 first responder가 되지 않도록 거부 — 자동 포커스 방지
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard !isActive else { return }
        activate()
    }

    private func activate() {
        guard !isActive else { return }
        isActive = true
        pendingFlags = []
        currentFlags = []
        polledCandidate = nil
        polledCandidateModifiers = []
        polledCandidateTicks = 0
        keyDownHappened = false
        onFocusChange?(true)

        // 로컬 이벤트 모니터로 키 입력을 가로챔 — AppKit 라우팅(Cmd 조합 등)을 우회
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isActive else { return event }
            switch event.type {
            case .keyDown:
                self.handleKeyDown(event)
                return nil
            case .flagsChanged:
                self.handleFlags(event)
                return nil
            default:
                return event
            }
        }
        pressedKeyCodes = currentPressedKeyCodes()
        // ponytail: 4틱(약 25ms) 확인으로 새 권한과 로컬 keyDown 경합을 피한다. 더 짧은 입력이 필요할 때만 이벤트 탭 권한을 추가한다.
        let timer = Timer(
            timeInterval: 1.0 / 120.0,
            target: self,
            selector: #selector(pollPressedKeysFromTimer),
            userInfo: nil,
            repeats: true
        )
        keyStateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        pendingFlags = []
        currentFlags = []
        pressedKeyCodes = []
        polledCandidate = nil
        polledCandidateModifiers = []
        polledCandidateTicks = 0
        keyDownHappened = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        keyStateTimer?.invalidate()
        keyStateTimer = nil
        onFocusChange?(false)
    }

    func pollPressedKeys() {
        guard isActive else { return }
        if let window, !NSApp.isActive || !window.isKeyWindow {
            deactivate()
            return
        }
        let current = currentPressedKeyCodes()
        let newlyPressed = current.subtracting(pressedKeyCodes)
        pressedKeyCodes = current

        if let polledCandidate {
            guard current.contains(polledCandidate) else {
                self.polledCandidate = nil
                polledCandidateModifiers = []
                polledCandidateTicks = 0
                if currentFlags.isEmpty {
                    deactivate()
                }
                return
            }
            polledCandidateTicks += 1
            guard polledCandidateTicks >= 4 else { return }
            handleKeyDown(
                keyCode: polledCandidate,
                modifiers: polledCandidateModifiers
            )
            return
        }

        guard let keyCode = newlyPressed.min() else { return }
        polledCandidate = keyCode
        polledCandidateModifiers = currentFlags.union(NSEvent.modifierFlags)
        polledCandidateTicks = 1
        keyDownHappened = true
    }

    @objc private func pollPressedKeysFromTimer() {
        pollPressedKeys()
    }

    private func currentPressedKeyCodes() -> Set<CGKeyCode> {
        Set((0...127).compactMap { rawValue in
            let keyCode = CGKeyCode(rawValue)
            guard !Self.modifierKeyCodes.contains(keyCode), isKeyPressed(keyCode) else {
                return nil
            }
            return keyCode
        })
    }

    private func handleKeyDown(_ event: NSEvent) {
        handleKeyDown(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    private func handleKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard isActive else { return }
        if keyCode == 53 {  // Escape — 취소
            deactivate()
            return
        }
        keyDownHappened = true
        let mods = modifiers.intersection(.deviceIndependentFlagsMask)
        onCaptureKeyed?(keyCode, mods)
        deactivate()
    }

    private func handleFlags(_ event: NSEvent) {
        let current = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        currentFlags = current
        if current.rawValue != 0 {
            if current.rawValue.nonzeroBitCount >= pendingFlags.rawValue.nonzeroBitCount {
                pendingFlags = current
            }
        } else {
            if polledCandidate != nil {
                return
            }
            if !keyDownHappened, !pendingFlags.isEmpty {
                let captured = pendingFlags
                onCaptureModifierOnly?(captured)
            }
            deactivate()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { deactivate() }
        super.viewWillMove(toWindow: newWindow)
    }
}
