# T11 — Save-clipboard hotkey and HUD

**Milestone:** M1 · **Depends on:** T02, T05 (T09 for images) · **Estimate:** 0.5 day

## Goal

The fastest possible "save this for later": copy something, press a second hotkey, see a brief confirmation, keep working. No panel, no typing.

## Read first

- UX_SPEC §2 (keyboard map), §3 (HUD)

## Scope

1. Handle `KeyboardShortcuts.Name.saveClipboard` (no default; suggest `⌥⇧Space` in Settings/onboarding).
2. Read the general pasteboard with the same precedence as T09 (files → image → string). Create a `Capture` with `source: .clipboard` to the **default** destination and enqueue it.
3. `HUDController`: a borderless, non-activating, click-through panel (`ignoresMouseEvents = true`, level `.statusBar`, `.canJoinAllSpaces + .fullScreenAuxiliary`) near the bottom center of the screen with the pointer. Fades in, stays 1.2 s, fades out. Messages:
   - "✓ Saved to {destination name}" — shown on enqueue success (delivery is async, like the panel)
   - "✕ Clipboard is empty"
   - "✕ Skipped — copied from a password manager"
4. Menu bar "Save Clipboard" item calls the same path.

## Implementation notes

- **Respect concealed/transient data.** If the pasteboard contains `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType` (used by 1Password, Bitwarden and others), do not save it. Same check applies to T09 paste.
- Deduplicate: if the same clipboard `changeCount` was already saved in the last 10 s, show "Already saved" instead of creating a duplicate.
- A plain URL on the clipboard is saved as-is (no title fetching — ADR-009). Template can wrap it: single-line template already handles it.

## Acceptance criteria

- [ ] Copy text in Safari → hotkey → HUD → text in today's daily note; Safari stays focused, no keystrokes lost.
- [ ] Copy a screenshot → hotkey → image attached (if default destination supports it).
- [ ] Copy a password from a password manager → hotkey → "Skipped" HUD, nothing saved.
- [ ] HUD never takes focus or intercepts clicks.

## Out of scope

Capturing the current *selection* without copying (needs Accessibility — post-v1).
