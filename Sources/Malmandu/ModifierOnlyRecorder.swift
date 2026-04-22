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
    var onCaptureKeyed: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCaptureModifierOnly: ((NSEvent.ModifierFlags) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    private var pendingFlags: NSEvent.ModifierFlags = []
    private var keyDownHappened: Bool = false
    private var eventMonitor: Any?
    private var isActive: Bool = false

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
        keyDownHappened = false
        onFocusChange?(true)

        // 로컬 이벤트 모니터로 키 입력을 가로챔 — AppKit 라우팅(Cmd 조합 등)을 우회
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isActive else { return event }
            switch event.type {
            case .keyDown:
                if event.keyCode == 53 {  // Escape — 취소
                    self.deactivate()
                    return nil
                }
                self.keyDownHappened = true
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                self.onCaptureKeyed?(event.keyCode, mods)
                self.deactivate()
                return nil
            case .flagsChanged:
                self.handleFlags(event)
                return nil
            default:
                return event
            }
        }
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        pendingFlags = []
        keyDownHappened = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        onFocusChange?(false)
    }

    private func handleFlags(_ event: NSEvent) {
        let current = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if current.rawValue != 0 {
            if current.rawValue.nonzeroBitCount >= pendingFlags.rawValue.nonzeroBitCount {
                pendingFlags = current
            }
        } else {
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
