# T01 — Project scaffold

**Milestone:** M0 · **Depends on:** — · **Estimate:** 0.5 day

## Goal

An empty but correctly configured menu-bar app with a testable core package and CI, so every later task is pure feature work.

## Read first

- ARCHITECTURE §1 (two modules), §2 (layout), §12 (dependencies)
- DECISIONS ADR-001, ADR-004, ADR-008

## Scope

1. Xcode project `Otter`, macOS app, Swift 6 language mode, deployment target **14.0**.
2. SwiftUI `@main` app with `@NSApplicationDelegateAdaptor(AppDelegate.self)`. No windows open at launch.
3. `Info.plist`:
   - `LSUIElement = YES` (no Dock icon, no app menu)
   - `NSAppleEventsUsageDescription = "Otter adds your quick notes to Apple Notes."`
   - Placeholder bundle ID `com.yourname.otter`
4. Signing & capabilities: **Hardened Runtime on**, **App Sandbox off**. Automatic signing with a personal team for local dev.
5. Local Swift package `Packages/OtterCore` (Foundation only) linked into the app; a `OtterCoreTests` test target with one passing test.
6. Folder layout per ARCHITECTURE §2 (empty files/folders are fine).
7. A placeholder `NSStatusItem` (SF Symbol `square.and.pencil`, template) with a menu containing only "Quit Otter ⌘Q".
8. Logging helper: `extension Logger { static let panel = Logger(subsystem: "com.yourname.otter", category: "panel") … }` for the categories in ARCHITECTURE §10.
9. Add `KeyboardShortcuts` via SPM (used in T02).
10. GitHub Actions workflow: on push/PR, `macos-latest`, run `swift test` in `Packages/OtterCore` and `xcodebuild -scheme Otter build` (no signing: `CODE_SIGNING_ALLOWED=NO`).
11. `.gitignore` for Xcode, `README.md` already exists — link docs from it.

## Implementation notes

- Prefer `NSStatusItem` from AppKit over SwiftUI `MenuBarExtra`: we need a badge state and dynamic menu later (T12), which is awkward in `MenuBarExtra`.
- Keep `AppDelegate.applicationDidFinishLaunching` minimal; later tasks register services here. Anything slow must be deferred (ARCHITECTURE §9).
- OtterCore must not import AppKit or SwiftUI. Add a CI check: `! grep -rE "import (AppKit|SwiftUI|Cocoa)" Packages/OtterCore/Sources`.

## Acceptance criteria

- [ ] Launching shows a menu bar icon and **no** Dock icon; Quit works.
- [ ] `swift test` passes in `Packages/OtterCore`.
- [ ] CI is green on a PR.
- [ ] Hardened runtime enabled, sandbox disabled (verify with `codesign -d --entitlements - Otter.app`).
- [ ] Idle CPU 0% and memory < 25 MB in Activity Monitor.

## Out of scope

Hotkeys, panel, any real menu items, Sparkle.
