import SwiftUI
import KopieCore

struct OnboardingView: View {
    /// Initial step (render/testing harness); real users always start at 0.
    var initialStep: Int = 0
    @EnvironmentObject var state: AppState
    private let settings = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    init(initialStep: Int = 0) {
        self.initialStep = initialStep
        _step = State(initialValue: initialStep)
    }
    @State private var retention = RetentionPeriod.daySeven
    @State private var splashTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if state.isReturnLaunch {
                splashView
            } else {
                fullOnboardingView
            }
        }
        .frame(width: 520, height: 420)
        .background {
            // Spec canvas: near-black (or warm paper) with the two glows.
            Theme.canvas(for: scheme)
            // Esc skips the splash (and only the splash — not an onboarding step).
            if state.isReturnLaunch {
                Button("") { endSplash() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
    }

    // MARK: - Splash mode (return visits)

    /// Shows just the LandingView for ~5 seconds, then auto-dismisses. A
    /// click anywhere (or Esc) skips the wait — nobody should sit through an
    /// animation they have seen before.
    private var splashView: some View {
        LandingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { endSplash() }
            .onAppear {
                splashTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    endSplash()
                }
            }
            .onDisappear { splashTask?.cancel() }
            .overlay(alignment: .bottom) {
                Text("Click anywhere to continue")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
                    .padding(.bottom, 10)
                    .opacity(hintShown ? 1 : 0)
                    .animation(.easeIn(duration: 0.4).delay(0.8), value: hintShown)
            }
    }

    @State private var hintShown = false

    private func endSplash() {
        splashTask?.cancel()
        withAnimation {
            state.finishOnboarding(retention: settings.retentionPeriod)
            dismiss()
        }
    }

    // MARK: - Full onboarding (first launch)

    private var fullOnboardingView: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: LandingView()
                case 1: stepView(1, gradientTile: true,
                                 symbol: "square.stack.3d.up",
                                 title: "Everything you copy, organized",
                                 message: "Text, images, links, and files — everything you copy is saved and searchable. Paste anything back in one click or a keystroke.")
                case 2: stepView(2, gradientTile: false,
                                 symbol: "hand.raised",
                                 title: "Private by design",
                                 message: "Your history stays on your Mac — encrypted at rest, never uploaded. Copy a password or API key and Kopie masks it automatically; one-time codes vanish after you paste them.")
                case 3: retentionStep
                default: finalStep
                }
            }
            .id(step) // treat each step as a distinct identity so the transition runs
            .transition(reduceMotion ? .opacity
                        : .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                                      removal: .opacity.combined(with: .offset(x: -24))))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.22), value: step)

            Divider()
            HStack {
                EmberGhostButton(title: "Back", muted: step == 0) {
                    withAnimation { step = max(0, step - 1) }
                }
                .disabled(step == 0) // spec: Back reads 45% on the first step
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(i == step ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.chipColor(for: scheme)))
                            .frame(width: i == step ? 9 : 7, height: i == step ? 9 : 7)
                            .animation(Motion.quick, value: step)
                    }
                }
                Spacer()
                EmberPrimaryButton(title: step == 4 ? "Start copying" : "Continue") {
                    withAnimation {
                        if step == 4 {
                            state.finishOnboarding(retention: retention)
                            dismiss()
                        } else { step += 1 }
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Step bodies (spec: centered gap 12, icon tiles, 18/700 headline)

    private func stepView(_ tag: Int, gradientTile: Bool, symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            stepTile(gradient: gradientTile, symbol: symbol)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary(for: scheme))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary(for: scheme))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tag(tag)
    }

    /// The spec's icon tile: 64×64 rounded square over the canvas — a
    /// gradient-filled tile with a white glyph, or a plain chip with an
    /// accent glyph.
    private func stepTile(gradient: Bool, symbol: String, size: CGFloat = 64) -> some View {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            .fill(gradient ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.chipColor(for: scheme)))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(gradient ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.accentInk(for: scheme)))
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 10, y: 4)
    }

    private var retentionStep: some View {
        let columns = Array(repeating: GridItem(.fixed(60), spacing: 5), count: 3)
        return VStack(spacing: 12) {
            stepTile(gradient: true, symbol: "clock.arrow.circlepath", size: 56)
            Text("How long should history stick around?")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary(for: scheme))
            Text("Items older than this are removed automatically — favorites and pins are always kept. You can change this anytime in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary(for: scheme))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            // Spec: a 3-column chip grid; the live choice wears the gradient.
            LazyVGrid(columns: columns, alignment: .center, spacing: 5) {
                ForEach(RetentionPeriod.allCases, id: \.rawValue) { p in
                    let on = retention == p
                    Button {
                        withAnimation(Motion.quick) { retention = p }
                    } label: {
                        Text(p.label)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(on ? Color.white : Theme.textSecondary(for: scheme))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.chipColor(for: scheme))))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The single most important fact for a menu-bar app — how to get back —
    /// gets its own visual: a rendered keycap so the combo reads at a glance.
    private var hotkeyRow: some View {
        HStack(spacing: 8) {
            keycap("⌘"); keycap("⇧"); keycap("V")
            Text("or click the Kopie icon in your menu bar")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary(for: scheme))
        }
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textPrimary(for: scheme))
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.chipColor(for: scheme))
                    .shadow(color: .black.opacity(0.18), radius: 0.5, y: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.hairline(for: scheme), lineWidth: 1)
            )
    }

    private var finalStep: some View {
        VStack(spacing: 12) {
            // Spec: the shipped app icon, exactly as shipped, no redraw.
            Image(nsImage: AppIcon.image(pointSize: 76))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.22), radius: 15, y: 6)
            Text("You're ready")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary(for: scheme))
            VStack(spacing: 10) {
                Text("Copy anything — it lands here instantly.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary(for: scheme))
                hotkeyRow
            }
            Text("Try it: copy this sentence, then press the keys above.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary(for: scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale.combined(with: .opacity))
    }
}
