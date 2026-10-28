# Glossary

Every thing in Kopie has exactly one name. Source of truth for UI copy and stories.

| Term | Means | Not |
| --- | --- | --- |
| Clip | One captured clipboard item (text, image, files, color, code, rich text) | item, entry, record, snippet (unless saved as a Snippet) |
| History | The full stored list of clips, searchable | list, archive |
| Popover | The small menu-bar panel for quick search + quick paste | menu, dropdown, overlay |
| Main window | The browsing window with sidebar + detail pane | browser, viewer |
| Detail pane | The right-hand area of the main window that shows the selected clip | preview (reserved for hover preview), inspector |
| Hover preview | The floating bubble showing a clip when hovering it (kept in 2.6) | bubble, tooltip |
| Direct paste | Worth inserting the selected clip into the active app with a synthetic ⌘V (⌥↩) | auto paste, smart paste |
| Paste as plain | Paste the clip stripped to plain text | unformatted paste, plain mode |
| Retry | One automatic re-copy + re-send ⌘V when direct paste fails | anti-retry, resync |
| Fallback | Give up on direct paste, copy to the clipboard, and tell the user | degrade, backup |
| Capture | Recording a copy the user makes anywhere | addition, import |
| Missed-copy badge | Small popover row shown when a capture tick was skipped | warning, alert |
| Masked item | A clip whose content looks like a secret; hidden until revealed | sensitive flag, redacted |
| Ignore list | Apps whose copies Kopie never captures | blacklist, exclusion |
| Secure field | Any field with Secure Input active (passwords, logins); direct paste is skipped there | protected field |
| Toast | The transient inline message at the popover edge for feedback and fallback | notification, popup |
| Favorite/Pin | Saved clips that retention must never expire | star, saved |
| Retention | The rule for how long clips are kept | cleanup policy |
| Cheat sheet | The Settings page listing every shortcut, generated from live bindings | keybindings list |
| Spotlight/Launcher | (Out of scope) system-wide search surfaces | |

Button verbs: **Paste**, **Copy**, **Delete** (irreversible; "Move to Trash" reserved if it can come back), **Reveal**, **Save Snippet**, **Export…**, **Open Settings…**, **Dismiss**.
