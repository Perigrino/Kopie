import Foundation

/// How long non-favorite items are kept before automatic cleanup.
public enum RetentionPeriod: Int, CaseIterable, Codable, Comparable, Sendable {
    case never = 0
    case dayOne = 1
    case dayThree = 3
    case daySeven = 7
    case dayFourteen = 14
    case dayThirty = 30
    case dayNinety = 90

    public var days: Int? { self == .never ? nil : rawValue }

    public var label: String {
        switch self {
        case .never: "Never"
        case .dayOne: "1 day"
        case .dayThree: "3 days"
        case .daySeven: "7 days"
        case .dayFourteen: "14 days"
        case .dayThirty: "30 days"
        case .dayNinety: "90 days"
        }
    }

    public static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

/// When Kopie's windows hide from screen capture. `.whenConferencing`
/// shields while a known conferencing app is frontmost (Zoom, Teams,
/// FaceTime); `.always` shields permanently. Shielded windows cannot appear
/// in ANY screenshot, recording, or share — including the user's own.
public enum ScreenShieldMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off, whenConferencing, always
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: return "Off"
        case .whenConferencing: return "During Calls"
        case .always: return "Always"
        }
    }
}

/// Snapshot of capture-time settings consumed by the pipeline.
public struct CaptureConfig: Sendable {
    public var paused: Bool
    public var saveText: Bool
    public var saveImages: Bool
    public var saveFiles: Bool
    public var ignoreDuplicates: Bool
    public var maxItems: Int
    public var excludedAppIDs: Set<String>
    public var trackSourceApp: Bool
    /// Run on-device OCR on image copies so screenshots become searchable.
    public var ocrImages: Bool
    /// What to do when content matches a secret rule (default: mask & keep).
    public var sensitivePolicy: SensitiveDataPolicy
    /// Sentinel rules that are active for this capture.
    public var sensitiveEnabledRules: Set<String>
    /// Flag OTP/magic-link-shaped captures for delete-after-next-paste.
    public var autoExpireOneTime: Bool

    public init(paused: Bool = false, saveText: Bool = true, saveImages: Bool = true,
                saveFiles: Bool = true, ignoreDuplicates: Bool = true, maxItems: Int = 1000,
                excludedAppIDs: Set<String> = [], trackSourceApp: Bool = true,
                ocrImages: Bool = true,
                sensitivePolicy: SensitiveDataPolicy = .mask,
                sensitiveEnabledRules: Set<String> = SensitiveDataDetector.allRuleIDs,
                autoExpireOneTime: Bool = true) {
        self.paused = paused
        self.saveText = saveText
        self.saveImages = saveImages
        self.saveFiles = saveFiles
        self.ignoreDuplicates = ignoreDuplicates
        self.maxItems = maxItems
        self.excludedAppIDs = excludedAppIDs
        self.trackSourceApp = trackSourceApp
        self.ocrImages = ocrImages
        self.sensitivePolicy = sensitivePolicy
        self.sensitiveEnabledRules = sensitiveEnabledRules
        self.autoExpireOneTime = autoExpireOneTime
    }
    public static let `default` = CaptureConfig()
}

public struct RetentionConfig: Sendable {
    public var period: RetentionPeriod
    public var deleteFavorites: Bool
    public init(period: RetentionPeriod = .daySeven, deleteFavorites: Bool = false) {
        self.period = period
        self.deleteFavorites = deleteFavorites
    }
}
