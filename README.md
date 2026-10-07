# otter

 otter is a FOS macOS menu-bar utility for capturing notes. what quick notes should've been. press a hotkey from anywhere, a small floating panel appears, type, hit `⌘↩`, and the note is filed into the notes system of your choice

 connects to obsidian and Apple native folders. 

No account. No backend. Your data stays on your Mac by default.


![otter display](images/example.png)
![otter display on top of full screen app](images/overlay-ex.png)

## install

Needs macOS 14 Sonoma or later.

- **Download:** get `Otter-<version>.dmg` from the [latest release](https://github.com/elizabeth-ling/otter/releases/latest), open it, drag Otter to Applications, and open it from there. Otter is signed and notarized by Apple, so it opens without a Gatekeeper warning.
- **Homebrew:** `brew install --cask elizabeth-ling/tap/otter`

Otter updates itself. Once a day it checks for a new version and, when there is one, shows "Update Available…" in its menu bar menu. You can also pick "Check for Updates…" yourself.

## permissions

- **No Accessibility permission.** The global shortcuts don't need it.
- **Files & Folders.** macOS asks the first time Otter saves to a protected location such as Documents, Desktop or iCloud Drive, which is where the Otter Inbox and most Obsidian vaults live. Otter writes only to the folders you choose. It also reads Obsidian's list of vaults and each vault's `.obsidian/app.json`, so notes and attachments follow the vault's settings. It never changes them.
- **Notifications.** macOS asks the first time a note can't be delivered, so Otter can tell you. If you say no, the menu bar icon still shows an amber dot.
- **Apple Notes** (not in v1): saving to Notes will need Automation permission for Notes.

## privacy

- No account, no telemetry, no analytics, no crash reporting.
- **The update check is Otter's only network access.** Once a day it fetches `appcast.xml` from this repo's GitHub releases. The request carries Otter's version number and nothing about you or your notes. Turn it off in Settings › Advanced › "Automatically check for updates" and Otter makes no network requests at all.
- Your notes go only to the folders you pick. Until a note is delivered, it waits in `~/Library/Application Support/Otter/`. Logs never contain note text.

## docs

| Doc | What's in it |
|---|---|
| [context/docs/OVERVIEW.md](context/docs/OVERVIEW.md) | Problem, principles, scope, non-goals, success criteria, milestones, open questions |
| [context/docs/UX_SPEC.md](context/docs/UX_SPEC.md) | Panel anatomy, states, keyboard map, menu bar, settings, first run |
| [context/docs/ARCHITECTURE.md](context/docs/ARCHITECTURE.md) | Components, data flow, capture pipeline, destinations, permissions, storage, performance budget |
| [context/docs/DECISIONS.md](context/docs/DECISIONS.md) | Architecture decision records (why Swift, why files, why not the App Store, etc.) |
| [context/tasks/README.md](context/tasks/README.md) | Build plan: milestones, dependency graph, task conventions |

## build tasks

| # | Task | Milestone |
|---|---|---|
| T01 | [Project scaffold](context/tasks/T01-project-scaffold.md) | M0 |
| T02 | [Global hotkey](context/tasks/T02-global-hotkey.md) | M0 |
| T03 | [Floating capture panel](context/tasks/T03-floating-panel.md) | M0 |
| T04 | [Editor, keyboard map, draft autosave](context/tasks/T04-editor-and-drafts.md) | M0 |
| T05 | [Capture pipeline and outbox](context/tasks/T05-capture-pipeline-outbox.md) | M0 |
| T06 | [Folder destination](context/tasks/T06-folder-destination.md) | M0 |
| T07 | [Obsidian vault awareness](context/tasks/T07-obsidian-destination.md) | M1 |
| T08 | [Apple Notes destination](context/tasks/T08-apple-notes-destination.md) | M3 (after v1) |
| T09 | [Paste handling and attachments](context/tasks/T09-paste-and-attachments.md) | M1 |
| T10 | [Settings and first-run onboarding](context/tasks/T10-settings-and-onboarding.md) | M2 |
| T11 | [Save-clipboard hotkey and HUD](context/tasks/T11-clipboard-capture-hud.md) | M1 |
| T12 | [Menu bar item, recents, launch at login](context/tasks/T12-menubar-and-lifecycle.md) | M2 |
| T13 | [Packaging, notarization, updates](context/tasks/T13-packaging-and-distribution.md) | M2 |
| T14 | [Performance and reliability hardening](context/tasks/T14-performance-and-reliability.md) | M2 |
| T15 | [Sticky-note panel: shape, dragging, remembered position](context/tasks/T15-sticky-note-panel.md) | M0 |
| T16 | [`⌘S`: save as a named note and start a new one](context/tasks/T16-save-as-named-note.md) | M1 |
| T17 | [Change the save folder from the panel header](context/tasks/T17-change-folder-from-panel.md) | M1 |
| T18 | [Bulleted lists and checkboxes in the editor](context/tasks/T18-md-lists-and-checkboxes.md) | M1 |

## releasing

Pushing a `v*` tag builds, signs, notarizes and publishes a release with no manual steps (ADR-019): [`release.yml`](.github/workflows/release.yml) runs [`scripts/release.sh`](scripts/release.sh), publishes the GitHub release with the DMG and `appcast.xml`, and updates the Homebrew tap.

For each release:

1. Add a `## [x.y.z]` section to [`CHANGELOG.md`](CHANGELOG.md). It becomes both the GitHub release notes and the notes in the update window.
2. Commit it to `main`, then tag and push: `git tag vx.y.z && git push origin vx.y.z`.

### one-time setup

1. **Sparkle keys.** Resolve packages (`xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath build/SourcePackages`), then run `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`. Put the public key it prints into `SPARKLE_PUBLIC_ED_KEY` in the Otter target's build settings. Export the private key with `generate_keys -x sparkle-private-key.txt`, store it as a secret, and delete the file. Losing this key means existing installs can't update, so back it up somewhere safe.
2. **Developer ID Application certificate.** Export it from Keychain Access as a `.p12`, then `base64 -i certificate.p12 | pbcopy`.
3. **App Store Connect API key** (Users and Access › Integrations › App Store Connect API, Developer role), for `notarytool`.
4. **Homebrew tap.** Create the public repo `elizabeth-ling/homebrew-tap`, and a fine-grained token with *Contents: read and write* on it only.

Repository secrets (Settings › Secrets and variables › Actions):

| Secret | What |
|---|---|
| `DEVELOPMENT_TEAM` | the Team ID of the Developer ID certificate |
| `DEVELOPER_ID_CERTIFICATE_P12` | the base64 `.p12` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | its export password |
| `ASC_KEY_P8` | the contents of `AuthKey_XXXX.p8` |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | from the App Store Connect API page |
| `SPARKLE_PRIVATE_KEY` | the exported Sparkle private key |
| `HOMEBREW_TAP_TOKEN` | the tap token |

Never commit `.p12`, `.p8` or Sparkle key files.

### building a release locally

```sh
xcrun notarytool store-credentials otter-notary   # once
DEVELOPMENT_TEAM=XXXXXXXXXX NOTARY_KEYCHAIN_PROFILE=otter-notary scripts/release.sh 0.1.1
```

`scripts/release.sh --local 0.1.1` skips Developer ID signing and notarization (ad-hoc signed), to try the script on a Mac without the certificate.

### testing an update before a public release

1. Build two versions, with the second's build number higher, and point the appcast at a local server. Each version needs a `CHANGELOG.md` section. Use the real Sparkle key, or a throwaway pair passed as `SPARKLE_PUBLIC_ED_KEY` and `SPARKLE_PRIVATE_KEY`.
   ```sh
   scripts/release.sh 0.1.0
   DOWNLOAD_URL_PREFIX=http://localhost:8000/ BUILD_NUMBER=100000 scripts/release.sh 0.1.1
   ```
2. Install 0.1.0 from its DMG and use it: change a setting, leave a draft in the panel, and queue a note for an unplugged folder.
3. Serve 0.1.1 and point the installed app at it:
   ```sh
   python3 -m http.server 8000 -d build/release/0.1.1
   defaults write io.github.elizabeth-ling.otter SUFeedURL http://localhost:8000/appcast.xml
   ```
4. In Otter's menu, choose Check for Updates… and install. Then check that it's 0.1.1 and that the setting, the draft and the waiting note survived.
5. `defaults delete io.github.elizabeth-ling.otter SUFeedURL`

## license

[MIT](LICENSE)
