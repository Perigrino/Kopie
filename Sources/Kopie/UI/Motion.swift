import SwiftUI

/// Motion vocabulary adapted from Airpisode: critically damped, no overshoot.
enum Motion {
    static let quick = Animation.timingCurve(0.20, 0.70, 0.25, 1, duration: dQuick)

    static let dQuick: Double = 0.28
}
