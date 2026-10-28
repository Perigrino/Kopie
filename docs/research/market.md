# Market

Research for Kopie. Done 2026-10-28.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Research question: what makes the best clipboard manager app on the Mac?
Decision it informs: which features and positioning go into Kopie's 2.6 redesign (robustness, UX, UI).

## Findings

- Maccy: free (PWYW), MIT, 22.1k stars; native menu-bar UI; keyboard-first (type-to-search, ⌥↩ paste, ⌥⇧↩ paste-without-formatting, ⌥P pin, ⌥⌫ delete); ignore list for `org.nspasteboard.TransientType`/`ConcealedType` + password-manager types. Actively developed; requires macOS 14+. [V](https://maccy.app, https://github.com/p0deje/Maccy)
- Paste: $2.49/mo or $29.99/yr subscription; App Store + direct; iCloud sync (Mac/iPhone/iPad); pinboards, unlimited history, Apple Intelligence suggestions, MCP integration. [V](https://pasteapp.io/pricing)
- Raycast clipboard history: bundled free in Raycast; encrypted local history; 3-month cap on free tier; ignores password-manager copies; per-entry pin/delete/filter; hotkey or keyword invocation. Core extension, very active. [V](https://www.raycast.com/core-features/clipboard-history)
- Alfred clipboard history: Powerpack (one-time license) gated; off by default for privacy; retention 24h–3mo (text/images/file links); snippet merge; ignore-apps list incl. Keychain/1Password; max clip size to protect history. [V](https://www.alfredapp.com/help/features/clipboard/)
- CopyClip 2 (FIPLAB): one-time App Store purchase (~$14.99 [K]); macOS 12+; AppKit-native; instant search, pinned clips, ⌘-number quick-paste, plain-text paste mode, Quick Look preview, editable clips, per-clip source-app label, Private Mode to pause capture, ignore-sensitive rules. [V](https://fiplab.com/apps/copyclip)
- Flycut: free, open-source, developer-oriented flat list, minimal; actively maintained [U]. [K](https://github.com/rgommezz/flycut)
- Setapp availability of Paste unverified [U].

## Comparison table

| App | Price | Platform | Headline strengths | Sync | Maintenance |
|---|---|---|---|---|---|
| Maccy | Free / PWYW | App Store + GitHub | Fast native menu-bar, keyboard-first, privacy ignore-lists | None, local-only | Very active; macOS 14+ |
| Paste | $2.49/mo or $29.99/yr | App Store + direct | Pinboards, rich cards, AI suggestions, unlimited history | iCloud multi-device | Very active |
| Raycast | Free core | Direct | Encrypted at rest, 3-mo cap, launcher glue | Encrypted multi-device [K] | Very active [K] |
| Alfred | One-time Powerpack | Direct + MAS [K] | Deep ignore lists, size cap, snippets integration | Local-only [K] | Continuously updated |
| CopyClip 2 | One-time purchase | App Store | Native AppKit, ignore rules, plain-text mode, private mode | None | Active |
| Flycut | Free, OSS | GitHub/brew | Minimal developer list | None [K] | Active [U] |

## Patterns

- Local-only (or local+encrypted) is the trust norm; the one cloud-sync player (Paste) is subscription-priced. Kopie's "fully local, no cloud" is a genuine gap, not a weakness. [V]
- Privacy ignore-lists (password managers, transient/concealed pasteboard types) + pause/erase controls are table stakes for every leader; NOT optional. [V]
- Keyboard-first beats feature breadth: hotkey-instant popup + type-to-search + paste-without-formatting + pinned quick-slots + ⌘-number paste is the common skeleton. [V]
- Retention-as-paywall (Raycast free 3-month expiry, Alfred 3-month max) is the most resented model in the category. [V](https://typefire.app/raycast-clipboard-alternative, https://www.alfredapp.com/help/features/clipboard/)

## Decisions

1. Build the privacy ignore-list, pause-capture, and retention controls as first-class, always-visible features — every verified leader treats them as baseline, and they match Kopie's privacy-first identity. [V]
2. Keep storage local, and *prove* it in the UI (no-cloud messaging, storage meter) — competitors either have no sync or charge subscriptions; trust is the differentiator. [V]
3. Invest 2.6 effort in launch latency, inline search speed, ⌥-paste, pinning, and ⌘-number paste instead of adding breadth — keyboard-first UX is what makes leaders survive. [V]
4. Never ship history-as-a-subscription; generous default retention with an unlimited option positions Kopie against Raycast/Alfred's most resented behavior. [V pattern]

## Open questions
- [U] Setapp presence of Paste — not relevant to Kopie's direct-distribution plan; skip.
- [U] Raycast multi-device sync rollout status — not a driver for Kopie (no sync). Skip.
