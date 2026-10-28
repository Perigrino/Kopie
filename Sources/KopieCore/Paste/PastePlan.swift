// Sources/KopieCore/Paste/PastePlan.swift
import Foundation
import os

/// Why a direct paste did not happen. The clip is ALWAYS already staged on the
/// system pasteboard before a paste op starts, so every failure path leaves the
/// user holding the copy — the toast only has to explain what happened.
public enum PasteObstacle: String, Equatable, Sendable {
    case secureInput
    case axMissing
    case targetRefused

    /// Mid-op failure signals ordered most-user-hostile first.
    public static func detect(axGranted: Bool, secureInputActive: Bool, targetStillFront: Bool) -> PasteObstacle? {
        secureInputActive ? .secureInput : (!axGranted ? .axMissing : (!targetStillFront ? .targetRefused : nil))
    }
}

/// What to do with a direct-paste attempt right now.
public enum PasteOutcome: Equatable, Sendable {
    case post                         // stage is on the pasteboard; post ⌘V now
    case retry                        // exactly one retry left: refocus target, re-post
    case fallback(PasteObstacle)      // do NOT post; surface toast
}

/// Inputs the plan needs; pure value so it can cross actor boundaries.
public struct PasteInput: Equatable, Sendable {
    public var axGranted: Bool
    public var secureInputActive: Bool
    public var attemptsMade: Int   // synthetic ⌘V posts already sent for this op (0-based)

    public init(axGranted: Bool, secureInputActive: Bool, attemptsMade: Int) {
        self.axGranted = axGranted
        self.secureInputActive = secureInputActive
        self.attemptsMade = attemptsMade
    }
}

public enum PastePlan {
    /// Decision table (S-001/S-002/S-003 of docs/STORIES.md):
    /// 1. Secure Input active → never post, fallback (S-001).
    /// 2. Missing Accessibility → fallback + "Open Settings…" toast (S-003).
    /// 3. attempt 0 → post; attempt 1 → retry; anything ≥ 2 → target refused (S-002).
    public static func decide(_ input: PasteInput) -> PasteOutcome {
        if input.secureInputActive { return .fallback(.secureInput) }
        if !input.axGranted { return .fallback(.axMissing) }
        switch input.attemptsMade {
        case 0: return .post
        case 1: return .retry
        default: return .fallback(.targetRefused)
        }
    }
}

public enum PasteToastCopy {
    /// Each obstacle gets its own sentence; `targetName` renders the target app's
    /// name so the user can connect the failure to the app it tried to reach.
    public static func message(obstacle: PasteObstacle, targetName: String?) -> String {
        switch obstacle {
        case .secureInput:
            return "Kopie can't paste while a password field is active. The clip is on your clipboard."
        case .axMissing:
            return "Kopie needs Accessibility access to paste into \(targetName ?? "this app"). The clip is on your clipboard."
        case .targetRefused:
            return "Unable to paste into \(targetName ?? "the app"). The clip is on your clipboard."
        }
    }
}

public enum PasteLog {
    /// One log line per paste decision, so a user report ("paste didn't happen")
    /// can be answered without attaching a debugger ("logs captured").
    public static let logger = Logger(subsystem: "com.kopie.app", category: "paste")
}
