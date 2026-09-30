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
            BreathingBackground(reduceMotion: reduceMotion, cycle: state.ambientSpeed.cycle)
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
                case 1: stepView(1, symbol: "square.stack.3d.up",
                                 title: "Everything you copy, organized",
                                 message: "Text, images, links, and files — everything you copy is saved and searchable. Paste anything back in one click or a keystroke.")
                case 2: stepView(2, symbol: "hand.raised",
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
                Button("Back") { withAnimation { step = max(0, step - 1) } }
                    .disabled(step == 0)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                Button(step == 4 ? "Get Started" : "Continue") {
                    withAnimation {
                        if step == 4 {
                            state.finishOnboarding(retention: retention)
                            dismiss()
                        } else { step += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    private func stepView(_ tag: Int, symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 52)).foregroundStyle(Color.accentColor)
            Text(title).font(.title2.weight(.semibold))
            Text(message).font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tag(tag)
    }

    private var retentionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 52)).foregroundStyle(Color.accentColor)
            Text("How long should history stick around?").font(.title2.weight(.semibold))
            Text("Items older than this are removed automatically — favorites and pins are always kept. You can change this anytime in Settings.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Picker("Retention", selection: $retention) {
                ForEach(RetentionPeriod.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden() // the heading above names the choice; without
            // this, macOS renders the "Retention" label beside the control —
            // squeezed into a one-character-wide column (vertical text).
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The single most important fact for a menu-bar app — how to get back —
    /// gets its own visual: a rendered keycap so the combo reads at a glance.
    private var hotkeyRow: some View {
        HStack(spacing: 8) {
            keycap("⌘"); keycap("⇧"); keycap("V")
            Text("or click the Kopie icon in your menu bar")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 0.5, y: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 0.5)
            )
    }

    private var finalStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 52)).foregroundStyle(Color.accentColor)
            Text("You're ready").font(.title2.weight(.semibold))
            VStack(spacing: 10) {
                Text("Copy anything — it lands here instantly.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                hotkeyRow
            }
            Text("Try it: copy this sentence, then press the keys above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale.combined(with: .opacity))
    }
}
