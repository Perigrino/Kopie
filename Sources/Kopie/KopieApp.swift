import AppKit
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

    /// The app's one popover, bound at creation. The popover object is
    /// created exactly once in applicationDidFinishLaunching; its content
    /// window, however, is created lazily on first show — so the gate below
    /// checks `isShown` + the live window rather than a captured window
    /// reference that would go stale or not-yet-exist.
    nonisolated(unsafe) private static weak var boundPopover: NSPopover?

    static func bindPopover(_ popover: NSPopover?) {
        boundPopover = popover
    }

    /// True when `event` belongs to the popover's own (shown) window.
    ///
    /// `addLocalMonitorForEvents` sees keyDown/flagsChanged for the entire
    /// process. The popover's keyboard handlers must therefore filter by
    /// window before acting — otherwise arrows/return/escape pressed in the
    /// main window were consumed by the popover's list, so main-view
    /// navigation and clicks appeared dead while the menu-bar list moved.
    /// Text (and other) events in other windows pass through untouched.
    static func isPopoverKeyEvent(_ event: NSEvent) -> Bool {
        guard let popover = boundPopover, popover.isShown else { return false }
        guard let popWindow = popover.contentViewController?.view.window else { return false }
        // `event.window` is nil for app-directed events with no target window;
        // treat those as not ours (a popover never is).
        return event.window === popWindow
    }
}


