# T07 — Obsidian vault awareness

**Milestone:** M1 · **Depends on:** T06 · **Estimate:** 0.5 day

## Goal

An Obsidian vault is just a folder, so there's no separate Obsidian destination. A folder destination that sits anywhere inside a vault picks up the vault's conventions: attachments go where Obsidian would put them, links use the vault's style, and notes open in Obsidian. Each capture is still its own note in the folder the user chose.

No daily notes. Tasks often span several days, so filing captures by date isn't useful. Anyone who wants one running file can use T06's append mode.

## Read first

- ARCHITECTURE §5.1, §5.2
- DECISIONS ADR-002
- T09 §4 (who uses the attachment helpers), T12 §2 (who uses "Open in Obsidian")

## Scope

1. `ObsidianVault` (pure, in `Destinations/Obsidian/`):
   - `containing(_ url: URL) -> ObsidianVault?`: walk up from `url` (the folder itself included) to the first ancestor with a `.obsidian/` directory. If vaults are nested, the nearest one wins. A `.obsidian` *file* doesn't count.
   - `root: URL`, `name: String` (the root's `lastPathComponent`, which is what `obsidian://` takes), `relativePath(of:) -> String?`.
2. `ObsidianVaultSettings`: read `<vault>/.obsidian/app.json` → `attachmentFolderPath`, `useMarkdownLinks`, `newLinkFormat`. If the file is missing, malformed or holds an unexpected type, use Obsidian's defaults: `/`, `false` and `shortest`. Read it at each delivery so changes in Obsidian apply without a relaunch (it's a tiny file).
3. `ObsidianAttachmentPlacement` (pure; T09 wires it in). Input: the vault, the settings, the note's vault-relative path and the attachment's file name. Output: the directory to copy into and the embed text.
   - Directory from `attachmentFolderPath`: `/` = vault root; `./` = the note's folder; `./sub` = `sub` under the note's folder; anything else is vault-relative. Reject `..` and absolute paths, falling back to the vault root.
   - Embed: wikilinks → `![[name.png]]` (vault-relative path when `newLinkFormat` is `absolute`). Markdown links → `![](path/relative/to/note.png)` with spaces and other reserved characters percent-encoded. Use `[name](…)` without the `!` for non-image files.
   - Inside a vault, these override `FolderOptions.attachmentsFolder`.
4. `ObsidianLink.openURL(vault:relativePath:) -> URL`: `obsidian://open?vault=<name>&file=<vault-relative path without .md>`. Percent-encode both values with an unreserved-only set (`A–Z a–z 0–9 - . _ ~`), so `/`, `&`, `=`, `#` and spaces are all encoded.
5. `ObsidianLink.open(_ fileURL: URL)` (app side; T12's recents call it): if the file is in a vault and something handles `obsidian://` (`NSWorkspace.urlForApplication(toOpen:)`), open it there; otherwise reveal it in Finder.
6. Receipts: remove `DeliveryReceipt.Location.obsidian(vault:path:)`. Folder deliveries keep returning `.file(URL)`, and "is this in a vault" is worked out when the note is opened, so a folder that moves into or out of a vault later still does the right thing.
7. `VaultDiscovery` (for T10's Add menu and onboarding): read `~/Library/Application Support/obsidian/obsidian.json` (`vaults: {id: {path, ts}}`, `ts` in ms). Return `[DiscoveredVault(id, name, path, lastOpened)]`, newest first, skipping paths that don't exist or have no `.obsidian/`. A missing or malformed file returns `[]`.
8. Temporary menu item "Use Obsidian Vault ▸" listing the discovered vaults. Choosing one makes the default folder destination point at the vault root, through the same `DestinationRegistry.chooseFolder` path as "Choose Folder…" (T17). The user can then pick a subfolder from the panel header, and it's still recognised as the vault. T10 replaces the menu.
9. Docs: update ARCHITECTURE §2 (file tree), §3 (receipt), §5.2 (drop the daily-note row and `MomentFormat`, describe vault detection), and add an ADR recording that daily notes were dropped and why (ADR-002's consequences no longer mention `daily-notes.json`).

## Implementation notes

- Never write inside `.obsidian/`. Only read `app.json` and `obsidian.json`.
- Don't cache the vault lookup across deliveries. It's a few `stat` calls, and caching would miss a folder that was moved.
- T06's file-naming rules already strip the characters that break Obsidian links (`# ^ [ ] |`), and its `created`/`source` frontmatter shows up as Obsidian properties. Neither needs changing.
- The panel header needs no Obsidian case: a vault folder is a folder destination, so T17's "Change folder" already works for it.
- Fixtures in `Tests/Fixtures/`:
  - a vault with an empty `.obsidian/`
  - `app.json` with `attachmentFolderPath` set to each of `/`, `./`, `./assets` and `Assets/Images`
  - `useMarkdownLinks: true`
  - `newLinkFormat: "absolute"`
  - malformed `app.json`
  - a nested subfolder
  - a vault inside a vault
  - an `obsidian.json` with one path that no longer exists

## Acceptance criteria

- [x] Unit tests: `containing` finds the vault from the root, from a deep subfolder and for a nested vault, and returns `nil` outside any vault and for a `.obsidian` file.
- [x] Unit tests: settings parsing for every fixture, including the defaults when parsing fails.
- [x] Unit tests: attachment directory and embed text for each `attachmentFolderPath` form × both link styles, with names containing spaces and `#`.
- [x] Unit tests: `openURL` encoding (spaces, `/`, `&`, emoji, `.md` stripped).
- [x] Unit tests: `VaultDiscovery` sorts newest first and skips missing paths. A missing or malformed `obsidian.json` returns `[]`.
- [ ] Manual: "Use Obsidian Vault ▸" lists your vaults with the one opened most recently first. Choosing one and saving a note puts a new file in the vault root, and it appears in Obsidian within a second.
- [ ] Manual: change the folder from the header to a subfolder of the vault. The next note lands there.
- [ ] Manual: `ObsidianLink.open` on a delivered note (via a debug menu item or a test hook) opens that exact note in Obsidian. With Obsidian closed, it launches Obsidian on that note.

## Out of scope

Daily notes, Periodic Notes and note templates. Appending under a heading. Writing through `obsidian://` URIs or plugins. Writing into `.obsidian/`. Templater syntax and Canvas files. Updating the other specs that still mention daily notes (OVERVIEW, UX_SPEC, T09, T11, T12, T16, tasks README) is tracked separately.
