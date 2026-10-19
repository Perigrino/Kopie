import SwiftUI

/// Motion vocabulary adapted from Airpisode: critically damped, no overshoot.
enum Motion {
    static let smooth = Animation.timingCurve(0.22, 0.68, 0.24, 1, duration: dSmooth)
    static let quick = Animation.timingCurve(0.20, 0.70, 0.25, 1, duration: dQuick)
    static let gentle = Animation.timingCurve(0.22, 0.55, 0.24, 1, duration: dGentle)

    static let dSmooth: Double = 0.45
    static let dQuick: Double = 0.28
    static let dGentle: Double = 0.38

    static var smoothAnim: Animation { .spring(response: 0.55, dampingFraction: 0.88).speed(1.0) }
    static var quickAnim: Animation { .easeInOut(duration: dQuick) }
    static var gentleAnim: Animation { .easeInOut(duration: dGentle) }
}

/// Applies an appear animation (opacity + y-offset fade-in).
struct AppearModifier: ViewModifier {
    var delay: Double = 0
    @State private var isVisible = false
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 8)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Motion.smoothAnim) { isVisible = true }
                }
            }
    }
}
extension View { func appear(delay: Double = 0) -> some View { modifier(AppearModifier(delay: delay)) } }

/// Hover lift: slightly scales and raises a card/button on hover (macOS only).
struct HoverLiftModifier: ViewModifier {
    var amount: CGFloat = 1.02
    var lift: CGFloat = 2
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? amount : 1, anchor: .center)
            .offset(y: hovering ? -lift : 0)
            .onHover { hovering = $0 }
            .animation(Motion.quickAnim, value: hovering)
    }
}
extension View { func hoverLift() -> some View { modifier(HoverLiftModifier()) } }
