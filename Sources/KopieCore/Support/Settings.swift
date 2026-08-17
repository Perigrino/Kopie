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

    // Convenient aliases
    public static var day7: RetentionPeriod { .daySeven }
    public static var ninetyDays: RetentionPeriod { .dayNinety }
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

    public init(paused: Bool = false, saveText: Bool = true, saveImages: Bool = true,
                saveFiles: Bool = true, ignoreDuplicates: Bool = true, maxItems: Int = 1000,
                excludedAppIDs: Set<String> = []) {
        self.paused = paused
        self.saveText = saveText
        self.saveImages = saveImages
        self.saveFiles = saveFiles
        self.ignoreDuplicates = ignoreDuplicates
        self.maxItems = maxItems
        self.excludedAppIDs = excludedAppIDs
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
