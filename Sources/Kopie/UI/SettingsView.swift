import SwiftUI
import KopieCore

/// Settings, restyled per the prototype's section: a 196pt nav rail (gradient
/// active tab, hairline divider) and one content pane with a tab header
/// (icon 26 + 20/700 title + 12pt subtitle) above the existing tab body.
/// The tab bodies keep their Forms — all functionality is unchanged; the
/// window chrome and controls are re-themed, nothing more.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme

    enum Tab: String, CaseIterable, Identifiable {
        case general, clipboard, cleanup, privacy, security, storage
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: "General"
            case .clipboard: "Clipboard"
            case .cleanup: "Cleanup"
            case .privacy: "Privacy"
            case .security: "Security"
            case .storage: "Storage"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .clipboard: "doc.on.clipboard"
            case .cleanup: "trash"
            case .privacy: "hand.raised"
            case .security: "lock.shield"
            case .storage: "externaldrive"
            }
        }
        var subtitle: String {
            switch self {
            case .general: "Launch behaviour, appearance, and the global shortcut."
            case .clipboard: "Capture behaviour and what lands in history."
            case .cleanup: "How old items are removed automatically."
            case .privacy: "Sensitive items, masking, and screen capture."
            case .security: "Encryption of history at rest."
            case .storage: "Where history lives and how much it uses."
            }
        }
    }

    @State private var selection: Tab = .general

    /// Lets the smoke-test harness open the window on a specific tab.
    init(initialSelection: Tab = .general) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle()
                .fill(Theme.hairline(for: scheme))
                .frame(width: 1)
            content
        }
        .frame(width: 660, height: 520)
        .background(Theme.winBackground(for: scheme))
        // Every settings toggle renders as the spec's 38×22 gradient capsule.
        .toggleStyle(EmberToggleStyle())
    }

    // MARK: - Nav rail (spec: 196pt, pad 14/12, gap 3, `.on` = gradient)

    private var rail: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Tab.allCases) { tab in
                railItem(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .background(alignment: .trailing) {
            Rectangle().fill(Theme.hairline(for: scheme)).frame(width: 1)
        }
    }

    private func railItem(_ tab: Tab) -> some View {
        let isActive = selection == tab
        return Button {
            withAnimation(Motion.quick) { selection = tab }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)
                Text(tab.label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.clear))
            )
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.textPrimary(for: scheme)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content pane (spec: pad 20/24, gap 14, header icon 26)

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: selection.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.accentInk(for: scheme))
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.label)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary(for: scheme))
                    Text(selection.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary(for: scheme))
                }
            }
            Group {
                switch selection {
                case .general: SettingsGeneralTab()
                case .clipboard: SettingsClipboardTab()
                case .cleanup: SettingsCleanupTab()
                case .privacy: SettingsPrivacyTab()
                case .security: SettingsSecurityTab()
                case .storage: SettingsStorageTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
