import Foundation

/// Cross-cutting actions the popover can trigger (opening windows/settings).
/// Owned by AppDelegate, which installs the closures when it finishes loading.
@MainActor
enum GlobalActions {
    static var openMain: (() -> Void)?
    static var openSettings: (@MainActor () -> Void)?
    static var openOnboarding: (() -> Void)?
    static var closePopover: (() -> Void)?
}


