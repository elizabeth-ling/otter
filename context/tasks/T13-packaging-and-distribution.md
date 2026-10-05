# T13 — Packaging, notarization, updates

**Milestone:** M2 · **Depends on:** T10, T12 · **Estimate:** 1 day

## Goal

A stranger can download a DMG (or `brew install --cask`), open it without Gatekeeper warnings, and get updates automatically.

## Read first

- DECISIONS ADR-004 (outside the App Store), ADR-009 (network)
- OVERVIEW §10 open questions 1–3 (name, developer account, license)

## Prerequisites (decide first)

- Final app name and bundle ID.
- Apple Developer Program membership ($99/yr) for a **Developer ID Application** certificate and notarization. Without it, users must right-click → Open and approve in System Settings — acceptable for a private beta, poor for a public release.
- License (recommendation: MIT, public repo).

## Scope

1. Signing: Developer ID Application, hardened runtime, secure timestamp. Entitlements: none beyond hardened runtime defaults. v1 sends no Apple Events (ADR-015); T08 checks later whether Notes needs the `apple-events` entitlement.
2. Release script `scripts/release.sh` (and a GitHub Actions workflow triggered by a `v*` tag):
   1. `xcodebuild archive` → `-exportArchive` with `method = developer-id`
   2. `ditto -c -k --keepParent` → `xcrun notarytool submit --wait` (App Store Connect API key in CI secrets)
   3. `xcrun stapler staple Otter.app`
   4. Build DMG (`create-dmg` or `hdiutil`) with Applications symlink; sign, notarize and staple the DMG too
   5. `spctl -a -vv -t install Otter.dmg` must say *accepted, source=Notarized Developer ID*
3. **Sparkle 2**: add via SPM; `SUFeedURL` pointing at an `appcast.xml` on GitHub Pages/Releases; EdDSA keys (`generate_keys`), public key in Info.plist, private key in CI secrets; `generate_appcast` in the release workflow. "Check for Updates…" menu item; "Automatically check for updates" toggle in Settings › Advanced (default on; this is Otter's only network access — say so).
4. GitHub Release with DMG + release notes from `CHANGELOG.md`.
5. Homebrew: start with your own tap (`homebrew-tap/Casks/otter.rb`); submit to `homebrew/cask` once there are a few releases and some users.
6. README: install instructions, permissions explained (why folder access; T08 adds Notes automation later), privacy statement (no telemetry, no network except update checks).

## Implementation notes

- Versioning: `CFBundleShortVersionString` = SemVer, `CFBundleVersion` = monotonically increasing build number (Sparkle compares this).
- Test updates end-to-end with two locally built versions before the first public release.
- Keep signing secrets only in CI; never commit `.p12`/`.p8` files.

## Acceptance criteria

- [ ] On a clean Mac (or fresh user account), download DMG → drag to Applications → open: no Gatekeeper warning.
- [ ] `spctl` and `codesign --verify --deep --strict` pass on app and DMG.
- [ ] v0.1.0 → v0.1.1 auto-update via Sparkle works and keeps settings, outbox and drafts.
- [ ] `brew install --cask yourname/tap/otter` works.
- [ ] Tagging `v*` produces a complete release with no manual steps.

## Out of scope

Mac App Store build. Crash reporting services.
