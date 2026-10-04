# T17 — Change the save folder from the panel header

**Milestone:** M1 · **Depends on:** T04, T06, T15 · **Estimate:** 0.5 day

## Goal

Clicking the folder name in the panel header opens a folder picker, and the folder the user picks becomes where notes are saved. The user can change the save location without leaving the panel or opening the menu bar, and the note they're typing stays as it is.

## Read first

- UX_SPEC §1 (header, destination pill), §7 (accessibility)
- ARCHITECTURE §5.1 (folder), §6 (panel)
- T06 (`FolderChooser`, `DestinationRegistry.chooseFolder`), T15 (header strip, dragging, the follow-up about the destination label)

## Scope

1. **Clickable name**: the destination name in the header becomes a borderless button (`NSButton`, or a label subclass that handles the click), when the destination shown is a folder destination, including the default `~/Documents/Otter Inbox/`.
   - Hover: a subtle rounded highlight behind the dot and name, and the tooltip shows the full `displayPath` (e.g. `~/Notes/Inbox`).
   - Click: opens the folder picker (scope 2). It acts on mouse-up, so a press that turns into a drag does nothing.
   - The rest of the header strip still drags the window. The button returns `mouseDownCanMoveWindow = false`, which also settles T15's follow-up about the label taking the mouse-down.
2. **Folder picker**: reuse T06's `FolderChooser` instead of building a second picker. The menu-bar "Choose Folder…" item and the header call the same code.
   - `NSOpenPanel`: directories only, "Create Folder" allowed, prompt "Choose", message "Choose the folder Otter saves your notes to.", starting in the current folder.
   - It opens on the capture panel's screen and above it. The capture panel floats, so give the open panel a higher `level` or it can open behind the note.
   - **Choose**: save the folder the way `chooseFolder` does now. It updates the folder destination in place, keeping its ID, so captures still waiting in the outbox for that destination go to the new folder too. Then `kick()` delivery.
   - **Cancel**: change nothing.
3. **Panel during and after the picker**:
   - The capture panel stays on screen while the picker is open. Opening the picker takes key and activates Otter, which would normally hide the panel through `windowDidResignKey`. Suppress that hide while the picker is open, the same way the Space-switch fix suppresses it.
   - When the picker closes, either way, make the capture panel key again with the editor's text, selection and caret unchanged. The header shows the new folder's name straight away.
   - The draft isn't touched. Nothing is saved or submitted by choosing a folder.
4. **Focus return**: the picker is the one place the panel flow activates Otter. Remember the app that was frontmost before the picker opened. When the panel next hides (`⌘↩`, `Esc`, click elsewhere), activate that app again so the user lands back where they were, as in T03.
5. **Keyboard and VoiceOver**: `Tab` inserts a tab in the editor, so the button can't be reached by tabbing. Add `⇧⌘O` in the panel to open the picker (UX_SPEC §2), and give the button the accessibility label "Save location: {name}" with the action description "Change folder".

## Implementation notes

- Keep `FolderChooser` in `App/MenuBar/` and pass it into `PanelController` from `AppDelegate`. Give it an optional completion so the panel learns when the picker closes and whether the folder changed.
- `chooseFolder(bookmark:displayPath:name:)` changes the *default* folder destination. The header shows the default until T10 adds per-note switching with `⌘1…⌘9`. Once it does, the header acts on the destination it shows: give `chooseFolder` a destination ID instead of always using the default.
- If the header's destination isn't a folder destination (Obsidian in T07, Apple Notes in T08), the name isn't clickable until T10 turns it into the destination menu.
- The panel reads `destinationName()` on show. After a successful choice, set the name again directly rather than waiting for the next show.
- Run the picker with `begin(completionHandler:)`, not `runModal()`, so the capture panel's fade and Space-switch logic keep running. Don't attach it as a sheet: the panel is too small for it and sheets on a non-activating panel misbehave.
- No note text in logs. Log only that the folder changed, as `FolderChooser` does now.

## Acceptance criteria

- [ ] Hovering the folder name shows the highlight and the full path as a tooltip.
- [ ] Clicking the name opens the folder picker in front of the panel, starting in the current folder.
- [ ] Choosing a folder: the header shows the new name at once, the panel is key with the text and caret unchanged, and the next `⌘↩` saves into the new folder.
- [ ] Cancel: nothing changes, and the panel is key again with the text and caret unchanged.
- [ ] Captures waiting in the outbox for a missing folder are delivered to the newly chosen folder.
- [ ] After using the picker, `⌘↩` or `Esc` returns focus to the app that was frontmost before the panel opened.
- [ ] Dragging the header strip outside the name still moves the window; pressing on the name and dragging doesn't open the picker.
- [ ] The menu-bar "Choose Folder…" still works and uses the same code.
- [ ] `⇧⌘O` opens the picker; VoiceOver reads "Save location: {name}".
- [ ] The choice persists across relaunch.

## Out of scope

Switching destinations from the header (T10's menu). Changing an Obsidian vault or Apple Notes folder from the panel. Choosing a folder for a single note only.
