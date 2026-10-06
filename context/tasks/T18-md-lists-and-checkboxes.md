# T18 — Bulleted lists and checkboxes in the editor

**Milestone:** M1 · **Depends on:** T04, the shipped inline styling (ADR-016) · **Estimate:** 1.5 days

## Goal

Typing `- ` at the start of a line shows a bullet, and `- [ ] ` shows a checkbox. Wrapped lines hang under the item's text. As in Obsidian, the line with the caret shows its marker as dimmed raw text (`- `, `- [ ] `), and every other line shows the rendered `•` or checkbox. `↩` continues a list, `↩` on an empty item ends it, `Tab` / `⇧Tab` nest items, and a click or `⌘L` ticks a task. The note stays plain Markdown: the draft, the outbox and the saved file contain exactly `- ` and `- [x] `, so Obsidian renders the same list.

## Read first

- UX_SPEC §1 "Inline Markdown styling" (the rules this extends) and "Lists and tasks"; §2 keyboard map
- DECISIONS ADR-016, ADR-017
- ARCHITECTURE §2 (file layout), §9 (restyle budget), §11 (testing)
- The shipped code and its tests: `MarkdownStyling`, `HiddenMarkerEditing`, `MarkdownFormatting` (OtterCore `Editor/`), `MarkdownStyler`, `EditorTextView` (App `Panel/`)

## Scope

1. **Which lines are list items** (pure OtterCore). Outside a fenced code block, a line is an item when it has optional indentation (spaces and tabs), then `-`, then one space or tab:
   - `- ` is a bullet. `- [ ] ` is an unchecked task, and `- [x] ` / `- [X] ` is a checked one. As in GFM, a task marker needs the space after `]`, so `- [ ]` on its own and `- [x](url)` are bullets whose text starts with `[`.
   - The item's **prefix** is its indentation plus `- `, plus `[ ] ` for a task. Any extra spaces after the prefix are part of the item's text.
   - These aren't items: a lone `-`, `-x`, the rules `---` and `- - -`, `*` / `+` / numbered lists, `> - quoted`, and lines inside a fence.
   - **Level**: consecutive item lines form a list, and any other line, blank ones included, ends it. An item's level is one more than the level of the nearest item above it in the same list with less indentation, or 0 if there isn't one. A tab counts as 4 columns. With this rule, lists indented with 2 spaces, 4 spaces or tabs all nest, and a jump of several tabs still nests only one level.
2. **How items look**:
   - An item is indented by its level × one step, plus a gutter. Wrapped lines line up under the start of the item's text (hanging indent). The indentation characters are always hidden, because the level indent stands in for them.
   - **On other lines**, the marker (`- `, `[ ] `) is hidden like an inline marker (ADR-016). In its place, in the gutter, the editor draws `•` for a bullet, an empty box for `[ ]` and a ticked box for `[x]`.
   - **Revealed lines** are the line with the caret, and every line a selection touches. On these, the marker shows as raw text in `tertiaryLabelColor`: `- `, `- [ ] ` or `- [x] `. It hangs left into the gutter, so the item's text doesn't move. The gutter is as wide as `- [x] ` in the editor font, so it fits either marker. Nothing is drawn on a revealed line.
   - The swap happens live as the caret or selection moves between lines. Like link reveal (ADR-016), it changes attributes only: it isn't an undo step and doesn't touch the text. Since the item's text start and hanging indent don't change, the line doesn't re-wrap.
   - So after `↩` continues a list, the new line shows a dimmed `- ` (or `- [ ] `) with the caret after it. The line above becomes a rendered bullet.
   - A checked task's text is dimmed (`secondaryLabelColor`) and struck through, on revealed lines too. Inline styles still apply to it.
   - Inline styling inside an item's text works the same as anywhere else. Inline markers stay hidden on revealed lines too (ADR-016); only list markers reveal.
3. **Caret and selection** (`HiddenMarkerEditing`):
   - **Arriving on an item line from another line** (click, `↑` / `↓`, `→` across the line break, `⌘←`): a position anywhere in the hidden prefix, or at either end of it, snaps to the start of the item's text. A click on a rendered bullet lands there too. The snap uses the line as it looked before the move, while its marker was still hidden. Typing straight after arriving therefore goes into the item, as in Obsidian.
   - **On a revealed line**, the marker is ordinary visible text. `←` steps into it one character at a time, and the caret can stop before the `-` or inside `[ ]`; you edit the raw Markdown, as in Obsidian. The hidden indentation is never a caret stop: a position in it moves to just before the `-`, and `←` from there goes to the end of the line above in one press. `⌘←` on an item line goes to the start of the item's text.
   - A selection's ends never fall inside hidden indentation. A selection that includes a marker's `-` also includes the indentation before it, so `⌘A` then `⌫` empties the note, and triple-click takes the whole line.
4. **Keys**:
   - `↩` in an item with text splits the line at the caret, splitting inline spans as it does now. The new line gets the same indentation and `- `, or `- [ ] ` for a task. A new task is always unchecked. At the start of the item's text, the split leaves an empty item above and the text moves down with the caret. With the caret before or inside the revealed marker, `↩` does the same as at the start of the text, so it never splits the marker or leaves indentation behind.
   - `↩` in an empty item (no text, or only whitespace) adds no line break. A nested item outdents one level, as `⇧Tab` does. A top-level item loses its prefix and becomes an empty line, with the caret on it.
   - `⌫` at the start of an item's text removes the marker in one step: `- `, or all of `- [ ] `. The indentation stays, and the line becomes plain text. The next `⌫` deletes as usual.
   - `⌦` at the end of an item whose next line is also an item joins the next item's text onto this line. The next item's prefix is deleted along with the line break.
   - `Tab`, with the caret in an item or a selection that touches items, indents each of those items by one tab character. This only works if the first of them has an item above it at the same level or deeper, which becomes its parent. Otherwise Otter beeps and nothing changes. Outside items, `Tab` inserts a tab as it does now.
   - `⇧Tab` in items outdents each one: its indentation is cut back to its parent's (`\t\t- x` under `\t- p` becomes `\t- x`). On a top-level item it beeps. Outside items it does nothing, as now.
   - `⌘L` toggles a task, as Obsidian's default shortcut does. A plain line or a bullet becomes `- [ ] `, an unchecked task becomes checked, and a checked task becomes unchecked. With a selection across lines (blank lines skipped, indentation kept): if any line isn't a task, those lines become unchecked tasks; otherwise, if any task is unchecked, every task is checked; otherwise every task is unchecked.
   - `⇧⌘8` toggles a bullet. If every non-blank selected line is already an item, their markers are removed, task markers included. Otherwise each plain line gets `- ` after its indentation.
   - Each of these is one `⌘Z` step, and the caret stays where it was in the text.
5. **Checkbox click**: on a line that isn't revealed, clicking the drawn box toggles `[ ]` ↔ `[x]` as one undo step ("Check" / "Uncheck"). Checking writes `[x]` and unchecking writes `[ ]`, including for `[X]`. The caret and selection don't move, so the clicked line stays rendered. The toggle happens on mouse-up inside the box, whose hit area is at least 20 × 20 pt; a press that turns into a drag selects text as usual. The pointer is an arrow over a box. Clicks on a box are ignored while an input method is composing.
   - On a revealed line there's no drawn box, only raw `[ ]` text. A click there places the caret like a click on any text, and doesn't toggle. You can type the `x` yourself, or press `⌘L`. That way a click on the line you're editing never changes the note when you meant to move the caret.
6. **Paste, copy, undo, IME, VoiceOver**:
   - Paste and drop insert text the same way as now. Pasted lines don't get markers added, and a pasted Markdown list is styled because it's just text.
   - Copy includes any markers inside the copied range. Copying part of one item's text copies only that text.
   - Styling is never an undo step. `⌘Z` after a `↩` that continued a list removes the line break and the new marker together.
   - While an input method is composing, `↩` and `Tab` go to the input method and nothing restyles (ADR-016).
   - VoiceOver reads the Markdown, markers included. `⌘L` is the keyboard way to tick a box.

## Implementation notes

- **New `Editor/MarkdownLists.swift`** (Foundation only):
  - `MarkdownListItem`: `lineRange`, `prefixRange`, `contentRange` (from the start of the text to the end of the line, without the line break), `indentColumns`, `level`, `kind` (`.bullet` / `.task(checked:)`) and `checkboxRange?`. Ranges are UTF-16, as in `MarkdownSpan`.
  - `MarkdownLists.items(in:) -> [MarkdownListItem]`. Share fence detection with `MarkdownStyling` (move it into a helper both use) rather than copying it.
  - `MarkdownLists.apply(_ command: ListCommand, to:selection:) -> MarkdownEdit?` covers `.toggleTask` (`⌘L`), `.toggleBullet` (`⇧⌘8`), `.indent` and `.outdent`, and returns `nil` where the editor should beep. `MarkdownLists.toggleCheckbox(_:in:) -> MarkdownEdit` handles clicks.
  - Keep these commands out of `MarkdownStyle`. That enum is the inline styles, and `MarkdownStyler` switches over it.
- **Revealing, like `⌘K`'s link reveal.** Pass the items and the selection to `HiddenMarkerEditing` (`init(text:spans:items:revealing:)`). Items on the lines the selection touches keep only their indentation as a hidden run; every other item's whole prefix is a hidden run. `MarkdownStyler` gets a reveal path like `reveal(_:)` for links. When the caret moves to another line, it re-attributes the line it left and the line it lands on, and nothing else.
- **Prefix runs are never merged with inline runs.** Today `MarkdownStyling.hiddenRuns` merges adjacent markers, which would make `- **` in `- **b**` one run.
  - A hidden prefix run snaps to its end. It is only met on arrival, when `setSelectedRanges` checks the proposed selection against the rules built for the old selection. After that the new line is revealed.
  - Hidden indentation on a revealed line snaps to its end (just before the `-`), and `previousCaretStop` skips it.
  - Inline runs keep ADR-016's rule. On a revealed `- **b**`, the stops are before `-`, before the space, and at 2 (before the hidden `**`). A position at 4 snaps back to 2, and typing there is plain. Arriving anywhere in 0…4 lands at 2.
- **Selections, deletion, copy and paste**: `trimmedSelection` grows a selection covering a `-` back over that line's indentation. Apart from that, a revealed marker is ordinary text to `deletion`, `replacement` and `copiedMarkdown`. `⌫` at the start of the text, `⌦` at the end and `↩` keep their list rules.
- **`↩`** builds on the existing span split. `lineBreakEdit` already returns the line break and the reopened openers; put the new prefix right after the line break, before the openers. `↩` inside a fence or outside items is unchanged.
- **Styler**: add each item line's paragraph style, checked dimming and revealed state to `LineStyle`. The existing per-line diff then re-attributes any line whose level or reveal changed, such as children when their parent is outdented.
  - Text start: `headIndent` is level × step + gutter on every line, so wrapping never depends on the reveal.
  - Hidden line: `firstLineHeadIndent` = `headIndent`, and the prefix uses the existing hidden attributes.
  - Revealed line: `firstLineHeadIndent` = `headIndent` − the width of the raw marker in the editor font. Measure it, and cache it per marker and font. The marker is drawn in `tertiaryLabelColor`. The ARCHITECTURE §9 budget still applies: a restyle under 1 ms for a 10 KB note, checked with a 200-item list.
- **Hidden tabs still advance. The reveal doesn't reduce this risk.** Indentation stays hidden on every line, revealed ones included. A tab in the near-zero hidden font still jumps to the next tab stop, so hidden indentation would push the text right, and on a revealed line it would also push the marker out of the gutter. Before building on it, spike a fix: for example, item paragraphs with no tab stops and a zero default interval, or zero-advance control characters. The spike also checks that the negative-offset marker on a revealed line lines up at every level. The editor is on TextKit 2 today because nothing touches `layoutManager`. Touching it falls the whole view back to TextKit 1, so only do that on purpose, and say so in the PR.
- **Drawing**: `EditorTextView` draws the bullets and boxes of the visible items that aren't revealed, for example in `drawBackground(in:)`, using the styler's items and the line fragment at each item's text start. Each glyph sits on the first line's baseline. The bullet is `•` in `secondaryLabelColor`; the boxes are the SF Symbols `square` and `checkmark.square.fill` in the accent colour. Size them from the editor font so the Font setting (UX_SPEC §5) carries over. Gutter and step are each about 1.5 em.
- **Keys**: override `insertTab(_:)` and `insertBacktab(_:)`. Add `⌘L` and `⇧⌘8` next to `formattingShortcuts` in `performKeyEquivalent`. Match `⇧⌘8` by key code, because `charactersIgnoringModifiers` gives `*` on some layouts. Every edit goes through `apply(_:actionName:)`, so it's one undo step and the draft is saved.
- **Clicks**: hit-test the drawn boxes (only on lines that aren't revealed) in `mouseDown(with:)` before calling `super`, track the press to mouse-up, and set the arrow cursor over the boxes in `resetCursorRects`.
- `MarkdownFormatting.blockPrefix` already keeps `- [ ] ` outside inline markers. It can switch to the item parser if that's simpler, but its behaviour mustn't change (`listQuoteAndHeadingMarkersStayOutside`).
- How Obsidian renders a plain line directly under an item (a lazy continuation) is up to Markdown. The editor shows lines as they're typed.
- No note text in logs.

## Acceptance criteria

**Unit tests (OtterCore, `swift test`)**

- [x] `MarkdownListsTests`, parsing:
  - `- `, `- [ ] `, `- [x] ` and `- [X] ` are items with the right prefix, text and checked state.
  - `-`, `-x`, `---`, `- - -`, `* a`, `+ a`, `1. a`, `> - a`, `- [ ]` with no trailing space, `- [x](u)` and lines inside a fence aren't items, or aren't tasks.
  - Levels are right for 2-space, 4-space, tab and mixed indentation, including a jump of several levels and a non-item line ending the list.
  - Ranges are right in UTF-16 with emoji in the text.
- [x] `MarkdownListsTests`, commands:
  - The `⌘L` cycle works on a plain line, a bullet, an unchecked task, a checked task and across mixed lines (blank lines skipped, indentation kept).
  - `⇧⌘8` adds and removes bullets.
  - Indent works where allowed and returns `nil` for a list's first item. Outdent cuts indentation back to the parent's.
  - The checkbox toggle writes `[x]` and `[ ]`.
  - The caret stays where it was in the text.
- [x] `HiddenMarkerEditingTests`, caret and selection:
  - With the selection on another line, positions in an item's hidden prefix, or at either end of it, snap to the start of the item's text.
  - With the selection on the item's line, only the indentation is a hidden run: the caret can stop before the `-` and inside `[ ]`.
  - Positions in the hidden indentation of a revealed line snap to just before the `-`.
  - On a revealed line, `←` steps through the marker and then to the end of the line above. `→` from the line above arrives at the start of the text.
  - In `- **b**`, a prefix run and an inline run are never merged. Revealed, the stops are before `-`, before the space, and 2, with 4 snapping to 2. Arriving anywhere in 0…4 lands at 2.
  - A selection covering a `-` grows over that line's indentation.
- [x] `HiddenMarkerEditingTests`, `↩`:
  - It continues bullets and tasks with the same indentation, and a checked task continues as an unchecked one.
  - It splits inline spans in an item: `- **ab‸c**` becomes `- **ab**⏎- **c**`.
  - At the start of an item's text it leaves an empty item above, and so does a caret before or inside the marker.
  - On an empty nested item it outdents; on an empty top-level item it clears the line.
  - Inside a fence it's a plain line break.
- [x] `HiddenMarkerEditingTests`, deleting and copying:
  - `⌫` at the start of an item's text removes the whole marker and keeps the indentation.
  - `⌦` at the end of an item joins the next item.
  - Deleting a selection across items removes the prefixes inside it.
  - `copiedMarkdown` keeps markers for a selection across lines. Within one item, it includes the marker only if the selection does.
- [x] `MarkdownStylingTests`: a prefix's hidden run isn't merged with an inline marker next to it, and a revealed item contributes only its indentation. All existing tests still pass.

**Manual (running app)**

- [ ] Typing `- ` shows a dimmed `- ` while the caret is on the line, and a bullet once the caret leaves. `- [ ] ` behaves the same with a box. `- [x] ` shows a ticked box with dimmed, struck-through text. The saved file holds exactly the Markdown typed, and Obsidian renders the same list.
- [ ] Moving the caret up and down a list swaps raw markers and rendered bullets live, line by line. The item's text never shifts sideways or re-wraps, at any level.
- [ ] After `↩` continues a list, the new line shows a dimmed `- ` or `- [ ] `, and the line above shows its bullet or box.
- [ ] Clicking the raw `[ ]` on the caret line places the caret and doesn't toggle.
- [ ] At every level, long items wrap under their text, not under the bullet. Checked with the System and Monospaced fonts at several sizes.
- [ ] `↩`, `↩` twice, `⌫`, `⌦`, `Tab`, `⇧Tab`, `⌘L` and `⇧⌘8` behave as UX_SPEC §1 "Lists and tasks" describes, and each is one `⌘Z` step.
- [ ] Clicking a box ticks and unticks it without moving the caret. Dragging from a box selects text, and the pointer is an arrow over a box.
- [ ] Bold, links and code inside items look and edit the same as elsewhere.
- [ ] With the Japanese IME composing in an item, `↩` commits the composition and doesn't continue the list.
- [ ] A restored draft, a Markdown list pasted from another app, and undo / redo after each list action all show the right bullets and boxes.
- [ ] Typing in a 200-item note stays instant, and the `restyle` signpost stays under budget.

## Out of scope

`*` and `+` bullets. Numbered lists. Other task states (`[-]`, `[/]`, Obsidian's custom statuses). Lists inside block quotes. Continuation lines and `⇧↩` soft breaks inside an item (`⇧↩` behaves like `↩`). Smart paste, meaning adding markers to pasted lines or re-indenting a pasted list. A setting to indent with spaces. Moving items by drag or with `⌥⌘↑` / `⌥⌘↓`. Headings and other block styling. A VoiceOver checkbox control.

## Decisions (reviewed)

The user approved the spec with one change, to decision 1. The other decisions stand as written.

1. **Resolved by the user: Obsidian-style reveal.** On the line with the caret, and on any line a selection touches, the marker shows as dimmed raw text. Every other line shows the rendered bullet or box. This replaces "markers always hidden and drawn over". It brings these follow-on choices, made in this revision:
   - Indentation stays hidden on every line. The marker hangs into a gutter wide enough for `- [x] `, so the text never moves when a line is revealed. (Obsidian shifts the text instead.)
   - The caret snaps past the marker only when it arrives from another line. Once the marker is revealed, it's ordinary text.
   - On a revealed line, a click on the raw `[ ]` places the caret and doesn't toggle; use `⌘L` or type the `x`.
   - `↩` with the caret before or inside the marker acts as at the start of the text.
2. **Approved.** Only `- ` makes a bullet. `*` and `+` bullets and numbered lists show as typed.
3. **Approved.** A checked item is dimmed and struck through, on revealed lines too.
4. **Approved.** `↩` on an empty nested item outdents it one level. An empty top-level item ends the list.
5. **Approved.** `⌫` at the start of a task's text removes the whole `- [ ] ` in one step and keeps the indentation.
6. **Approved.** `⌘L` toggles a task and `⇧⌘8` toggles a bullet.
7. **Approved.** `Tab` indents with a tab character. It's refused on the first item of a list.
8. **Approved.** A task needs the space after `]`.
9. **Superseded by 1.** A selection that includes a `-` now takes the indentation with it, so `⌘A` then `⌫` empties the note in one press.
10. **Approved.** M1.
