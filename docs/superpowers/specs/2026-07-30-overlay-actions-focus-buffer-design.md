# Overlay Actions and Focus Buffer Design

## Goal

Make the recording overlay actions reliable and preserve real-time transcription while the original target application is not focused.

## Required behavior

- X discards the active recording, streaming result, partial text, and pending text, then closes the overlay.
- ✓ pastes every not-yet-delivered phrase in speaking order, finalizes the stream, and closes the overlay.
- Losing the original application's focus must not pause audio capture or streaming transcription.
- Finalized phrases produced while focus is away are appended to a pending buffer and must never be pasted into another application.
- Returning to the original application shows a “붙여넣을까요?” prompt.
- Pressing “붙여넣기” inserts the pending buffer, clears the prompt, and keeps recording.
- Additional finalized phrases produced before the pending buffer is pasted remain buffered in order.

## Design

### Button event delivery

`ClickThroughHostingView` currently turns an `NSHostingView` hit into `nil`. SwiftUI controls are hosted by that same view, so the override also drops button clicks. Keep the non-activating panel, but let the hosting view return AppKit's normal hit-test result. The panel remains a small fixed overlay and does not activate Malmandu.

### Focus and pending text

Keep `focusLost` for the away screen and add one explicit `isAwaitingPendingPaste` flag for the returned-but-not-yet-pasted state. This is smaller than replacing the existing state model with a new enum and avoids changing unrelated overlay states.

The coordinator owns all transitions:

1. Original app loses focus: set `focusLost`, clear the prompt flag, and keep streaming.
2. A segment finalizes while focus is away or a prompt is pending: append it to `pendingCopyText`.
3. Original app returns: clear `focusLost`; if pending text exists, set the prompt flag.
4. User presses “붙여넣기”: paste `pendingCopyText`, clear it and the prompt flag on success, and leave recording active.
5. User presses ✓: finish streaming, concatenate pending text and the final stream result, paste once, then complete the recording.
6. User presses X: cancel through the existing discard path.

### UI

`RecordingOverlayView` gains a pending-paste branch between the focus-lost and normal recording branches. It displays the buffered text, a “붙여넣기” button, and the existing X/✓ action pill. No new window or toast system is introduced.

### Error handling

If accessibility permission prevents insertion, keep the pending text available and use the existing error callback. Final confirmation preserves the current clipboard fallback behavior supplied by `TextInjector`.

## Verification

- AppKit hosting hit testing returns an interactive view for the button region.
- Focus loss does not call streaming pause and finalized segments are buffered.
- Focus return exposes the pending-paste prompt.
- Pending paste inserts only the buffer and recording remains active.
- Segments arriving before paste remain ordered in the buffer.
- Confirmation pastes pending plus final text and returns to idle.
- Cancellation discards all pending and partial text.
