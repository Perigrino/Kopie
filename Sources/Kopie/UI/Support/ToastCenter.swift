import SwiftUI
import KopieCore

/// One floating toast at a time, app-wide, that survives popover close. Every
/// paste-failure surface routes through here so the wording, dedupe, and
/// lifetime live in exactly one place.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    struct Message: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var warning: Bool
        var actionTitle: String?
        var action: (() -> Void)?
        var dismissTitle: String?
        var onDismiss: (() -> Void)?

        static func == (l: Message, r: Message) -> Bool { l.id == r.id }
    }

    @Published private(set) var current: Message?
    /// One toast per session per reason — no toast spam when several pastes
    /// fail the same way (S-003 states).
    private var deliveredReasons: Set<PasteObstacle> = []
    private var hideWork: DispatchWorkItem?

    /// The three paste obstacles (S-001/S-003). All copy lives in
    /// `PasteToastCopy`; Secure Input toasts auto-fade in 6s, the others 8s.
    /// Per S-001 the Secure Input toast carries no Settings CTA — Secure Input
    /// is a user-held toggle, not a permission Kopie can request.
    func showPaste(obstacle: PasteObstacle, targetName: String?) {
        guard !deliveredReasons.contains(obstacle) else { return }
        deliveredReasons.insert(obstacle)
        let seconds: Double = obstacle == .secureInput ? 6 : 8
        show(text: PasteToastCopy.message(obstacle: obstacle, targetName: targetName),
             warning: true,
             seconds: seconds,
             reason: obstacle,
             actionTitle: obstacle == .secureInput ? nil : "Open Settings…",
             action: obstacle == .secureInput ? nil : { PasteDirectService.openAccessibilitySettings() },
             dismissTitle: "Dismiss",
             onDismiss: { [weak self] in self?.dismiss() })
    }

    /// Generic entry used by the in-popover warning toasts after Task 5's
    /// wiring; `reason` (when given) participates in the once-per-session dedupe.
    func show(text: String,
              warning: Bool,
              seconds: Double,
              reason: PasteObstacle? = nil,
              actionTitle: String? = nil,
              action: (() -> Void)? = nil,
              dismissTitle: String? = nil,
              onDismiss: (() -> Void)? = nil) {
        hideWork?.cancel()
        current = Message(text: text, warning: warning,
                          actionTitle: actionTitle, action: action,
                          dismissTitle: dismissTitle, onDismiss: onDismiss)
        ToastPanelController.shared.present(
            text: text, warning: warning,
            actionTitle: actionTitle, action: action,
            dismissTitle: dismissTitle, onDismiss: onDismiss)
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func dismiss() {
        hideWork?.cancel()
        hideWork = nil
        current = nil
        ToastPanelController.shared.hide()
    }
}

/// Borderless, non-activating panel that floats failure toasts above everything,
/// independent of the popover's lifetime (the old popover-only toast could not
/// reach a paste failure that happens after close).
@MainActor
final class ToastPanelController {
    static let shared = ToastPanelController()

    private var panel: NSPanel?
    private var keyMonitor: Any?

    func present(text: String,
                 warning: Bool,
                 actionTitle: String?,
                 action: (() -> Void)?,
                 dismissTitle: String?,
                 onDismiss: (() -> Void)?) {
        if panel == nil {
            let p = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.isMovableByWindowBackground = false
            p.hidesOnDeactivate = false
            p.becomesKeyOnlyIfNeeded = true
            panel = p
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evt in
                if evt.keyCode == 53 {          // Escape dismisses (S-003 access line)
                    MainActor.assumeIsolated {
                        self?.centerDismiss()
                    }
                    return nil
                }
                return evt
            }
        }
        let toast = CopiedToast(text: text,
                                warning: warning,
                                actionTitle: actionTitle,
                                action: action,
                                dismissTitle: dismissTitle,
                                onDismiss: onDismiss)
        let hosting = NSHostingView(rootView: toast)
        panel?.contentView = hosting
        let size = hosting.fittingSize
        if let screen = NSScreen.main {
            let x = screen.frame.midX - size.width / 2
            let y = screen.frame.maxY - 72      // just under the menu bar
            panel?.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size), display: false)
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Escape's dismissal route — kept as a method so the local key monitor
    /// never captures the panel's key lifetime into the closure.
    private func centerDismiss() {
        ToastCenter.shared.dismiss()
    }
}
