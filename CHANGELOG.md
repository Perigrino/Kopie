# Changelog

## 2.5.0 — October 22, 2026 · "Ember" redesign

Full visual redesign of every Kopie surface, built from `docs/redesign/prototype.html` and applied 1:1 to the app.

### New look
- **Ember palette** — Kopie's own peach→rose accent, derived from the app icon, colors the whole app: nav pills, selection tiles, toggles, primary buttons, focus rings and the "Rich" tag.
- **Canvas glows** — every window, popover, settings and onboarding view sits on a soft ember/rose glow background.
- **True light & dark** — the app follows the macOS appearance everywhere, with no half-themed surfaces.
- **Card-based rows** — history rows are cards with content tiles that fill with the Ember gradient when selected.
- **Redesigned sidebar** — same nav order as before (All · Text · Images · Files · Today · Favorites · Pinned · Sensitive), now with gradient active pills and live count badges.
- **New page header** — "History" title with a description, a search field with ⌘F hint and a "Today" filter chip.

### Menu-bar popover
- Ember background with day-group labels and the fixed footer (Open Kopie / Settings · Select / Clear).
- Restored the copied-from source app on rows; rows now highlight with both arrow keys and mouse hover.

### Details panel
- Type eyebrow, Plain Text / Formatted chips, content box, meta card, and a gradient Copy button with star / pin / trash actions.

### Settings & onboarding
- Settings uses a nav rail with gradient active tabs and ember toggles across all six tabs.
- Welcome splash and the 5-step onboarding rebuilt on the canvas with gradient tiles and the shipped app icon.

### Fix & feel
- Toasts, buttons, empty states, confirm dialogs and skeleton loaders all restyled to the spec.
- Main window opens at a fixed 1518×1102 (clamped to the screen), scrollbar gap fixed, "Rich" tag readable in both modes, color-swatch rows restored.

The app icon and the left-aligned navigation are unchanged, as always.
