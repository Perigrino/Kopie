import AppKit

/// A process-local `NSEvent` monitor that is gated to one window.
///
/// `NSEvent.addLocalMonitorForEvents` sees events for the *whole process*.
/// Any monitor that acts without first checking which window an event
/// targets steals input from every other window in the app — the bug class
/// where the menu-bar popover's list consumed the main window's arrow keys
/// (and clicks) while the main view appeared dead. This helper makes the
/// window gate mandatory: `accepts` decides which events belong to the
/// owning surface; everything else passes through untouched and `handle`
/// is never called.
///
/// Threading: AppKit delivers local-monitor calls on the main thread, so
/// the closures run inside `MainActor.assumeIsolated`; only the Sendable
/// Bool decision crosses back out — the `NSEvent` itself is returned in
/// the nonisolated tail (NSEvent is not Sendable).
///
/// Lifecycle: the monitor lives as long as the instance. Replacing the
/// instance (e.g. SwiftUI re-running `onAppear`) unregisters the previous
/// monitor in `deinit`, so monitors can never stack. `remove()` is the
/// explicit teardown for `onDisappear`-style paths.
///
/// Note: PreviewPanel's close-on-outside-click monitors deliberately do
/// NOT use this helper — they implement the inverse policy (act on events
/// that land *outside* the owned windows), which a per-window gate cannot
/// express.
@MainActor
final class GatedEventMonitor {
    // nonisolated(unsafe): touched from deinit (nonisolated), same pattern
    // as AppState.retentionTimer. The token is only ever set/cleared on the
    // main actor; deinit runs after the last main-actor access.
    nonisolated(unsafe) private var token: Any?

    /// - Parameters:
    ///   - mask: Event types to observe (e.g. `.keyDown`, `.flagsChanged`).
    ///   - accepts: The window gate. Return true *only* for events the
    ///     owning surface should see (typically `event.window === myWindow`,
    ///     or a policy like `GlobalActions.isPopoverKeyEvent`). Foreign
    ///     events pass through and `handle` is never called.
    ///   - handle: Runs on the main actor for accepted events. Return true
    ///     to consume (swallow) the event, false to let it continue.
    init(for mask: NSEvent.EventTypeMask,
         accepts: @escaping @MainActor (NSEvent) -> Bool,
         handle: @escaping @MainActor (NSEvent) -> Bool) {
        token = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            let handled = MainActor.assumeIsolated {
                accepts(event) && handle(event)
            }
            return handled ? nil : event
        }
    }

    /// Unregisters the monitor (idempotent).
    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    deinit {
        // Safety net for owners that drop the instance without remove().
        // Owner teardown should still call remove() on the main actor.
        if let token { NSEvent.removeMonitor(token) }
    }
}
