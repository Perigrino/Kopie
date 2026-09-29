import SwiftUI
import KopieCore

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    private let settings = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
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
        .background(BreathingBackground(reduceMotion: reduceMotion, cycle: state.ambientSpeed.cycle))
    }

    // MARK: - Splash mode (return visits)

    /// Shows just the LandingView for ~3 seconds, then auto-dismisses.
    private var splashView: some View {
        LandingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                splashTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    withAnimation {
                        state.finishOnboarding(retention: settings.retentionPeriod)
                        dismiss()
                    }
                }
            }
            .onDisappear { splashTask?.cancel() }
    }

    // MARK: - Full onboarding (first launch)

    private var fullOnboardingView: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: LandingView()
                case 1: stepView(1, symbol: "square.stack.3d.up",
                                 title: "Everything you copy, organized",
                                 message: "Kopie can save text and images copied on your Mac.")
                case 2: stepView(2, symbol: "hand.raised",
                                 title: "Private by design",
                                 message: "Your clipboard history stays on your Mac.")
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
            Text("Choose your retention period").font(.title2.weight(.semibold))
            Text("Kopie automatically removes items older than your chosen period. Favorites are kept unless you opt out later.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Picker("Retention", selection: $retention) {
                ForEach(RetentionPeriod.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var finalStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 52)).foregroundStyle(Color.accentColor)
            Text("You're ready").font(.title2.weight(.semibold))
            Text("Copy something to get started.")
                .font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale.combined(with: .opacity))
    }
}
