// Tests/KopieCoreTests/PastePlanTests.swift
import Testing
@testable import KopieCore

struct PastePlanTests {

    // S-001: Secure Input gates the paste before any event is posted.
    @Test func secureInputFallsBackBeforeFirstPost() {
        let decision = PastePlan.decide(PasteInput(axGranted: true, secureInputActive: true, attemptsMade: 0))
        #expect(decision == .fallback(.secureInput))
    }

    // S-003: missing Accessibility falls back, never posts.
    @Test func axMissingFallsBack() {
        let decision = PastePlan.decide(PasteInput(axGranted: false, secureInputActive: false, attemptsMade: 0))
        #expect(decision == .fallback(.axMissing))
    }

    // S-002: exactly one retry per paste op.
    @Test func firstAttemptPostsThenOneRetryThenFallback() {
        #expect(PastePlan.decide(PasteInput(axGranted: true, secureInputActive: false, attemptsMade: 0)) == .post)
        #expect(PastePlan.decide(PasteInput(axGranted: true, secureInputActive: false, attemptsMade: 1)) == .retry)
        #expect(PastePlan.decide(PasteInput(axGranted: true, secureInputActive: false, attemptsMade: 2)) == .fallback(.targetRefused))
        #expect(PastePlan.decide(PasteInput(axGranted: true, secureInputActive: false, attemptsMade: 7)) == .fallback(.targetRefused))
    }

    // Retry counts only posts, not other inputs.
    @Test func midOpSignalsWinOverRetry() {
        // Secure Input turning on between posts escalates straight to fallback.
        #expect(PastePlan.decide(PasteInput(axGranted: true, secureInputActive: true, attemptsMade: 1)) == .fallback(.secureInput))
    }

    // S-003: each obstacle maps to a distinct toast copy.
    @Test func obstacleDetectionOrder() {
        #expect(PasteObstacle.detect(axGranted: true, secureInputActive: true, targetStillFront: true) == .secureInput)
        #expect(PasteObstacle.detect(axGranted: false, secureInputActive: false, targetStillFront: true) == .axMissing)
        #expect(PasteObstacle.detect(axGranted: true, secureInputActive: false, targetStillFront: false) == .targetRefused)
        #expect(PasteObstacle.detect(axGranted: true, secureInputActive: false, targetStillFront: true) == nil)
    }

    @Test func toastCopyIsDistinctPerObstacle() {
        let secure = PasteToastCopy.message(obstacle: .secureInput, targetName: "Safari")
        let ax = PasteToastCopy.message(obstacle: .axMissing, targetName: "Safari")
        let refused = PasteToastCopy.message(obstacle: .targetRefused, targetName: "Safari")
        #expect(Set([secure, ax, refused]).count == 3)
        #expect(refused == "Unable to paste into Safari. The clip is on your clipboard.")
        #expect(secure == "Kopie can't paste while a password field is active. The clip is on your clipboard.")
        // nil target never renders "Unable to paste into the app."  as a broken sentence piece.
        #expect(PasteToastCopy.message(obstacle: .targetRefused, targetName: nil).contains("clip is on your clipboard"))
    }
}
