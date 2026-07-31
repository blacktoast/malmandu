import AppKit
import Testing
@testable import Malmandu

@Suite("UnifiedRecorderNSView Tests")
@MainActor
struct UnifiedRecorderNSViewTests {
    @Test("로컬 Ctrl+Space keyDown을 조합키로 캡처한다")
    func capturesLocalControlSpace() throws {
        _ = NSApplication.shared
        let view = UnifiedRecorderNSView(isKeyPressed: { _ in false })
        var captured: (keyCode: UInt16, modifiers: NSEvent.ModifierFlags)?
        view.onCaptureKeyed = { captured = ($0, $1) }

        view.mouseDown(with: try #require(mouseDownEvent()))
        NSApp.sendEvent(try #require(controlSpaceKeyDownEvent()))

        #expect(captured?.keyCode == 49)
        #expect(captured?.modifiers.intersection([.command, .option, .control, .shift]) == .control)
    }

    @Test("시스템이 가로챈 글로벌 Ctrl+Space를 조합키로 캡처한다")
    func capturesGlobalControlSpace() throws {
        _ = NSApplication.shared
        var pressedKeys: Set<CGKeyCode> = []
        let view = UnifiedRecorderNSView(
            isKeyPressed: { pressedKeys.contains($0) }
        )
        var captured: (keyCode: UInt16, modifiers: NSEvent.ModifierFlags)?
        view.onCaptureKeyed = { captured = ($0, $1) }

        view.mouseDown(with: try #require(mouseDownEvent()))
        NSApp.sendEvent(try #require(controlFlagsChangedEvent()))
        pressedKeys.insert(49)
        pollFourTimes(view)

        #expect(captured?.keyCode == 49)
        #expect(captured?.modifiers.intersection([.command, .option, .control, .shift]) == .control)
    }

    @Test("키를 누르기 전에 뗀 modifier는 조합에 남지 않는다")
    func excludesReleasedModifierFromPolledShortcut() throws {
        _ = NSApplication.shared
        var pressedKeys: Set<CGKeyCode> = []
        let view = UnifiedRecorderNSView(
            isKeyPressed: { pressedKeys.contains($0) }
        )
        var capturedModifiers: NSEvent.ModifierFlags?
        view.onCaptureKeyed = { _, modifiers in capturedModifiers = modifiers }

        view.mouseDown(with: try #require(mouseDownEvent()))
        NSApp.sendEvent(try #require(flagsChangedEvent([.control, .shift], keyCode: 56)))
        NSApp.sendEvent(try #require(flagsChangedEvent(.control, keyCode: 56)))
        pressedKeys.insert(49)
        pollFourTimes(view)

        #expect(capturedModifiers?.intersection([.command, .option, .control, .shift]) == .control)
    }

    @Test("폴링 후보보다 로컬 keyDown을 우선한다")
    func prefersLocalKeyDownOverPolledCandidate() throws {
        _ = NSApplication.shared
        var pressedKeys: Set<CGKeyCode> = []
        let view = UnifiedRecorderNSView(
            isKeyPressed: { pressedKeys.contains($0) }
        )
        var captures = 0
        view.onCaptureKeyed = { _, _ in captures += 1 }

        view.mouseDown(with: try #require(mouseDownEvent()))
        pressedKeys.insert(49)
        view.pollPressedKeys()

        #expect(captures == 0)

        NSApp.sendEvent(try #require(controlSpaceKeyDownEvent()))
        #expect(captures == 1)
    }

    @Test("modifier-only 단축키 캡처를 유지한다")
    func capturesModifierOnlyShortcut() throws {
        _ = NSApplication.shared
        let view = UnifiedRecorderNSView(isKeyPressed: { _ in false })
        var captured: NSEvent.ModifierFlags?
        view.onCaptureModifierOnly = { captured = $0 }

        view.mouseDown(with: try #require(mouseDownEvent()))
        NSApp.sendEvent(try #require(controlFlagsChangedEvent()))
        NSApp.sendEvent(try #require(flagsChangedEvent([], keyCode: 59)))

        #expect(captured == .control)
    }

    @Test("폴링 후보 중 modifier를 먼저 떼어도 조합키로 캡처한다")
    func keepsCandidateModifiersAfterRelease() throws {
        _ = NSApplication.shared
        var pressedKeys: Set<CGKeyCode> = []
        let view = UnifiedRecorderNSView(
            isKeyPressed: { pressedKeys.contains($0) }
        )
        var keyedCapture: (UInt16, NSEvent.ModifierFlags)?
        var modifierOnlyCapture: NSEvent.ModifierFlags?
        view.onCaptureKeyed = { keyedCapture = ($0, $1) }
        view.onCaptureModifierOnly = { modifierOnlyCapture = $0 }

        view.mouseDown(with: try #require(mouseDownEvent()))
        NSApp.sendEvent(try #require(controlFlagsChangedEvent()))
        pressedKeys.insert(49)
        view.pollPressedKeys()
        NSApp.sendEvent(try #require(flagsChangedEvent([], keyCode: 59)))
        for _ in 0..<3 {
            view.pollPressedKeys()
        }

        #expect(keyedCapture?.0 == 49)
        #expect(keyedCapture?.1.intersection([.command, .option, .control, .shift]) == .control)
        #expect(modifierOnlyCapture == nil)
    }

    @Test("설정 창이 키 윈도우가 아니면 폴링을 중지한다")
    func stopsPollingOutsideKeyWindow() throws {
        _ = NSApplication.shared
        var pressedKeys: Set<CGKeyCode> = []
        let window = NSWindow()
        let view = UnifiedRecorderNSView(
            isKeyPressed: { pressedKeys.contains($0) }
        )
        window.contentView = view
        var captured = false
        var isRecording = false
        view.onCaptureKeyed = { _, _ in captured = true }
        view.onFocusChange = { isRecording = $0 }

        view.mouseDown(with: try #require(mouseDownEvent()))
        pressedKeys.insert(49)
        view.pollPressedKeys()

        #expect(!captured)
        #expect(!isRecording)
    }

    private func pollFourTimes(_ view: UnifiedRecorderNSView) {
        for _ in 0..<4 {
            view.pollPressedKeys()
        }
    }

    private func mouseDownEvent() -> NSEvent? {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }

    private func controlSpaceKeyDownEvent() -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        )
    }

    private func controlFlagsChangedEvent() -> NSEvent? {
        flagsChangedEvent(.control, keyCode: 59)
    }

    private func flagsChangedEvent(
        _ modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

@Suite("Space shortcut polling")
struct SpaceShortcutPollStateTests {
    @Test("modifier를 먼저 떼어도 Space key-up에서 한 번 실행한다")
    func triggersOnceWhenModifierIsReleasedBeforeSpace() {
        var state = SpaceShortcutPollState()

        let pressed = state.update(
            isSpacePressed: true,
            modifiers: .control,
            targetModifiers: .control
        )
        let heldAfterModifierRelease = state.update(
            isSpacePressed: true,
            modifiers: [],
            targetModifiers: .control
        )
        let released = state.update(
            isSpacePressed: false,
            modifiers: [],
            targetModifiers: .control
        )
        let remainsReleased = state.update(
            isSpacePressed: false,
            modifiers: [],
            targetModifiers: .control
        )
        let wrongModifiersPressed = state.update(
            isSpacePressed: true,
            modifiers: .shift,
            targetModifiers: .control
        )
        let wrongModifiersReleased = state.update(
            isSpacePressed: false,
            modifiers: [],
            targetModifiers: .control
        )
        state.reset(isSpacePressed: true)
        let releasedAfterReset = state.update(
            isSpacePressed: false,
            modifiers: [],
            targetModifiers: .control
        )

        #expect(!pressed)
        #expect(!heldAfterModifierRelease)
        #expect(released)
        #expect(!remainsReleased)
        #expect(!wrongModifiersPressed)
        #expect(!wrongModifiersReleased)
        #expect(!releasedAfterReset)
    }
}
