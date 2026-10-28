# Reviews

Research for Kopie. Done 2026-10-28.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Research question: what do users love and hate about the leading Mac clipboard managers?
Decision it informs: which UX/UI improvements and robustness fixes go into Kopie's 2.6 redesign.

## Findings

- Paste is praised for polished card UI and unlimited retention; hated for its subscription ("a lot of people hate Paste because they are a subscription") and occasional hangs/freezes. [V](https://pasteapp.io/, https://blog.apps.deals/paste-vs-maccy-raycast-alfred-clipboard-managers-mac, https://www.reddit.com/r/macapps/comments/13xg34c/best_clipboard_managers_for_macos_working_on)
- Maccy is loved for speed, minimality, keyboard-first flow, open-source trust; hated for paste ops failing (silently or after updates), and large-history problems (>5 GB memory reported at 10k+ items). [V](https://github.com/p0deje/Maccy/issues/1372, https://github.com/p0deje/Maccy/issues/1080, https://github.com/p0deje/Maccy/issues/843)
- Raycast is loved for integrated fast history with type filters, pins, plain-text paste, encrypted storage; hated for quiet 3-month expiry punishing free users and a hidden 32,768-char clip limit. [V](https://manual.raycast.com/clipboard-history, https://typefire.app/raycast-clipboard-alternative, https://manual.raycast.com/v1/core)
- CopyClip (v1 and v2) is loved for being free and set-and-forget; hated for missing copies in rapid succession and mangling Word rich-table paste. [V](https://apps.apple.com/us/app/copyclip-2-clipboard-manager/id1020812363?mt=12, https://apps.apple.com/us/app/copyclip-clipboard-history/id595191960?mt=12)
- Alfred is loved for workflow/snippet integration; hated for 3-month max retention, Accessibility permission trip-wires, pastes failing in Java apps/VMs, and non-scoped apps (Eudic) polluting history. [V](https://www.alfredapp.com/help/features/clipboard/, https://www.alfredapp.com/help/troubleshooting/clipboard-history/, https://www.alfredforum.com/topic/20401-alfred-clipboard-copies-when-it-shouldnt)

## Likes and dislikes

| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| Paste | Polished card-based UI with visual previews; unlimited retention; iCloud sync; Stack sequential paste | Subscription pricing; hangs/freezes; slow feature pace | pasteapp.io, blog.apps.deals, r/macapps threads |
| Maccy | Blazing fast; minimal; keyboard-first; free/OSS trust; respects password managers | Paste ops fail (silent/regression); slow popup with big history; memory leaks; 200-item default cap [K] | maccy.app, GitHub issues 843/1080/1372 |
| Raycast | Launcher-integrated speed; type filters; pins; plain-text paste; encrypted storage | Quiet 3-month expiry; hidden clip limit; extra step to reach via launcher | manual.raycast.com, typefire.app, HN |
| CopyClip | Free; simple; set-and-forget | Misses rapid successive copies; breaks rich-table paste; v2 text-only | osxdaily, App Store reviews |
| Alfred | Workflow/snippet integration; clipboard merging | 3-month max retention; permission trip-wires; VM/Java paste failures; history pollution from apps like Eudic | alfredapp.com docs/forum |

Recurring robustness complaint patterns (the chance for Kopie to do better):
1. **Silent paste failure** — the #1 cross-app complaint (modifier conflicts, accessibility revocation, secure input, VMs). No leader solved it publicly.
2. **Dropped captures** — fast successive copies get skipped; unrelated apps pollute history.
3. **Large-history collapse** — slow popups, memory bloat, hidden limits.

## Feature matrix
See features.md.

## Decisions

1. Make paste reliability the product: automatic retry on failure (re-copy then re-send ⌘V), graceful fallback to copy-to-clipboard with a visible toast, detection of Secure Input. Test against Electron apps, terminal emulators, VM targets. [U → planned test: automated paste matrix in acceptance script]
2. Every copy must land: tighten the changeCount polling loop; if an item is skipped, surface it in the UI. Test with rapid successive-copy harness. [U → planned test]
3. Stress-test at 50k items and MB-sized clips; lazy-load previews and virtualize the list; cap preview bytes, not data. [U → planned test]
4. Graceful degradation everywhere permissions are missing (Accessibility, screen capture); never fail silently.

## Open questions
- [U] Whether synthetic ⌘V behavior differs across macOS 13/14/15/26 in target apps — build a per-OS paste test matrix.
