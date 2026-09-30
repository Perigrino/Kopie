import Foundation
import KopieCore

/// Cross-cutting actions the popover can trigger (opening windows/settings).
/// Owned by AppDelegate, which installs the closures when it finishes loading.
@MainActor
enum GlobalActions {
    static var openMain: (() -> Void)?
    static var openSettings: (@MainActor () -> Void)?
    static var openOnboarding: (() -> Void)?
    static var closePopover: (() -> Void)?
    /// Show (or switch) the floating preview bubble for an item. `rowY` is the
    /// row's center in popover-root coordinates (top-down).
    static var showPreview: ((ClipboardItem, CGFloat?) -> Void)?
    /// Update the anchor of an already-visible bubble (list scrolled, row
    /// moved). Ignored unless that item's bubble is up.
    static var movePreview: ((ClipboardItem, CGFloat?) -> Void)?
    /// Schedule the bubble to hide after `seconds` unless the cursor is on it.
    static var clearPreview: ((Double) -> Void)?
}


