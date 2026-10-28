# Features

Research for Kopie. Done 2026-10-28.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Research question: what is the complete feature set of the category leaders?
Decision it informs: the feature matrix and gap analysis for Kopie's 2.6 redesign.

## Findings

**Paste** (pasteapp.io — [V] throughout)
- Capture: text, links, images, files, colors; unlimited history ("kept for as long as you choose").
- Search: instant search + filters (type, source app, device, date); OCR search inside images with highlighted matches.
- Pinboards: named/color-coded boards, separate from history; shareable/collaborative.
- Paste: PlainText Mode; configurable QuickPaste modifier; drag-and-drop images as files; sequential paste stack ("copy one snippet, then the next").
- Preview/edit: inline previews + Quick Look (Space); in-place edit (⌘E); rename; rotate; extract text from images; new items (⌘N).
- Sync: iCloud Mac/iPhone/iPad, private iCloud only; iOS keyboard extension.
- Security: ignores password-manager/concealed content; Ignore Applications list; sensitive-data rules.
- AI: Apple Intelligence next-paste suggestions; history as context for external AI tools (MCP).

**Maccy** (github.com/p0deje/Maccy — [V])
- Capture: text-focused; image slideout preview (⌃Space); HEX color swatch; files as paths [K/U]; OCR search inside images (v2.4) + copy-OCR-text button (v2.7).
- Search: type-to-filter, deliberately minimal.
- Pins: ⌥P, editable in Settings.
- Paste: Enter = copy, ⌥Enter = paste, ⌥⇧Enter = paste without formatting; numbered quick-pick rows.
- Retention: cap ~999 (raise via `defaults historySize`); clear-all options.
- Security: ignores Transient/Concealed types + 1Password/Bitwarden/Keeweb flags; per-app ignore; pause-capture (⌥-click); ignore-next-copy; per-type ignore incl. Universal Clipboard (`com.apple.is-remote-clipboard`).

**Raycast** (manual.raycast.com/clipboard-history — [V])
- Capture: text, images, files, links, emails, colors; **multi-copies group into one entry**; saves every original format.
- Paste: Paste As (rich/plain/RTF/HTML/any); prefer-plain-text setting; Paste as PNG; copy back; share.
- Smart actions: OCR (Fast/Accurate), QR decode, edit content, rename, pin (⌘.), save as Snippet, send to AI.
- Retention: 1d/1w/1m/3m free; 6m/1y/unlimited Pro-gated; bulk delete by time window.
- Security: encrypted at rest locally; password managers/transient ignored.

## Feature matrix

| Feature | Paste | Maccy | Raycast | Kopie (current) | Version one (2.6)? |
|---|---|---|---|---|---|
| Rich formats captured | ✅ | ⚠️ text-focus | ✅ | ✅ | keep |
| Images/files/colors | ✅ | ⚠️ | ✅ | ✅ | keep |
| OCR + image-search | ✅ | ✅ | ✅ (+QR) | ⚠️ OCR browse, not search | **yes — close gap** |
| Fuzzy / instant search | ✅ | ✅ | ✅ | ✅ | keep |
| Pins / boards | ✅ shared boards | ✅ pins | ✅ pins | ✅ favorites+pins | keep |
| Inline edit | ✅ | ✅ (pins) | ✅ | ✅ (⌘E) | keep |
| Paste-as-plain | ✅ | ✅ | ✅ | ✅ (⌃ modifier) | keep |
| Paste queue / stack | ✅ stack | ❌ | ✅ sequential | ✅ paste queue [K] | keep |
| iCloud sync | ✅ | ❌ | ❌ | ❌ (by design) | no — trust-first |
| Ignore apps/types | ✅ | ✅ strong | ✅ | ✅ | strengthen |
| Pause capture | ✅ | ✅ (⌥-click) | ✅ | ✅ pause state | surface in UI |
| At-rest encryption | ✅ | ⚠️ [U] | ✅ | ✅ HistoryCrypto | keep + surface |
| Sensitive masking | ✅ rules | ✅ ignore | ✅ | ✅ sentinel | keep |
| Multi-copy grouping | ❌ | ❌ | ✅ | ❌ | **yes — differentiator** |
| Paste-As (rich/plain/RTF/HTML) | ⚠️ | ✅ | ✅ | ✅ tabs | keep |
| AI integration | ✅ | ❌ | ✅ | ❌ | no for 2.6 (accepted gap) |
| iOS companion | ✅ | ❌ | ❌ | ❌ | no (accepted gap) |
| Drag to other apps | ✅ | ❌ | ❌ | ✅ [K] | keep |

## Decisions

1. Make captured image text **searchable** (OCR text indexed into search), not just browsable — all three leaders do this; Kopie's OCR is browse-only today. Test: search a screenshot's text term lands the item. [U → planned test]
2. Adopt multi-copy rapid-succession grouping (Raycast-style) — no other leader gaps it; it also neutralizes the CopyClip-style "missed copies" complaint. Test: capture 5 fast copies, verify one grouped entry. [U → planned test]
3. Retention rules always exempt pinned/favorites; offer unlimited tier (Kopie is local-only — no reason to gate history). [V pattern]
4. Surface encryption + sensitive masking + no-cloud in the UI (security badge row) — mid-tier security depth is Kopie's differentiator. [V]
5. Accepted gaps for 2.6: no AI integration, no iOS companion, no cloud sync — recorded as deliberate, aligned with privacy-first positioning. [K]

## Open questions
- [U] Maccy at-rest encryption status — not a driver for Kopie's plan; skip.
- [U] Whether grouped multi-copies should expand as a unit or as individual rows on search — prototype both, pick by usability test.
