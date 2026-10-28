# Design

Research for Kopie. Done 2026-10-28.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Research question: how do the best clipboard managers present their UI, and which interaction details make them feel great?
Decision it informs: UI/UX direction for Kopie's 2.6 redesign (keep / adopt / drop).

## Findings

**Presentation**
- Paste: full-width bar docked to the bottom of the active display; resizable; Compact Mode under size threshold; opens on the display you're working on. A separate lightweight "Paste Stack" window for ordered sequential pasting. Two windows with distinct jobs: quick-paste bar + fuller browsing window. [V](https://pasteapp.io/help/paste-on-mac, https://pasteapp.io/help/using-paste-stack)
- Maccy: menu-bar app with a narrow dropdown panel; one window only. [K] form, [V](https://maccy.at/about) behavior.
- Raycast: command-palette window; searchable list + right-hand detail pane with full content and metadata. [V](https://www.raycast.com/core-features/clipboard-history)

**Visual design**
- Paste: visual timeline, content preview + source app + time copied; link previews; pinboard colors. [V]
- Raycast: type icons/thumbnails; color swatches; optional rich-card images; themes setting.
- Maccy: deliberately minimal plain rows; full-text tooltip for truncated items; "no fluff" stance. [V](https://maccy.at/features)
- Day grouping headers are NOT a documented feature of any leader. [V by absence]
- Dark mode everywhere; Raycast has a themes system; Paste accent = pinboard colors.

**Interaction**
- Paste: Space = Quick Look; ⌘R rename; ⌘E inline edit; ⌘N new item; ⌘F search with inline-suggested filters; Tab moves focus search↔results; Shift-extend selection; drag items directly into other apps. [V](https://pasteapp.io/help/keyboard-shortcuts)
- Maccy: type-to-filter; ⌘1–9 quick-pick; ⌥P pin; ⌥⌫ delete; all shortcuts rebindable. [V](https://maccy.at/shortcuts)
- Raycast: ↵ paste; ⌘K action panel per item; ⌘P type filter; ⌘E rename; ⌘. pin; edit-before-paste; OCR-from-image action. [V](https://manual.raycast.com/clipboard-history)

**Paste UX**
- Paste: direct paste needs Accessibility permission; without it, graceful fallback to copy-to-clipboard. [V](https://pasteapp.io/help/paste-on-mac)
- Paste: plain-text via Shift-Return; default "always plain" setting; rebindable modifier. [V](https://pasteapp.io/help/paste-as-plain-text)
- Raycast: "Paste as…" rich/plain/RTF/HTML; multi-copy grouping; Paste Sequentially with timeout + auto line-break. [V]

**Shortcuts/settings**
- All three publish complete, documented shortcut lists; Maccy's are fully rebindable in Settings. [V]
- Short first-run setup (open method, history length, integrations) in Paste. [V]

## Decisions for Kopie's UI

1. **Keep the two-speed structure Kopie already has** (fast popover + fuller main window) — it matches Paste's validated two-window model — but make it physically fast (NSPanel instead of NSPopover; see platform.md) so the popover inherits Raycast's "instant" feel. [V pattern]
2. **Drop the floating hover-preview bubble** if the main window preview covers the same job (Raycast's detail-pane pattern covers it); reduce chrome count. Test with hover-usage telemetry in SelfTest. [U → planned test]
3. **Day headers: optional density preference, not primary structure** — no leader uses them as primary; move to a toggle, keep type-filtered sidebar as primary navigation. [V by absence]
4. **Add a ⌘K-style action panel per row** (pin/rename/edit/delete/OCR-copy/save-as-snippet) — Raycast's pattern; replaces scattered context menus. [V]
5. **Full shortcut cheat sheet in Settings + rebindable bindings** where currently hardcoded. [V]
6. **Graceful paste fallback UI**: when direct paste fails or Accessibility is missing, show copy-to-clipboard + toast; never fail silently. [V](https://pasteapp.io/help/paste-on-mac)
7. Keep the Ember theme but respect the validated leaders' typography discipline: plain, readable rows in the popover; reserve cards/thumbnails for the main window. [K]

## Open questions
- [U] Whether hover-bubble removal hurts discoverability of previews — A/B in prototype before removal.
- [U] Raycast's detail-pane layout in a narrower popover — prototype at Kopie's popover size.
