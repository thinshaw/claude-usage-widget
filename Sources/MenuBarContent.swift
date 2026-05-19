import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ForEach(state.accounts.filter { $0.isConfigured }) { account in
                AccountCard(account: account, theme: state.theme)
            }

            if state.accounts.filter({ $0.isConfigured }).isEmpty {
                Text("No accounts configured.\nOpen Settings to add one.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }

            if let err = state.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.33))
                    .lineLimit(2)
            }

            footer
        }
        .padding(16)
        .frame(width: 320)
        .background(menuBackground)
    }

    @ViewBuilder
    private var menuBackground: some View {
        switch state.theme {
        case .liquidGlass:
            Color.clear
        case .sciFi:
            Color(red: 0.02, green: 0.04, blue: 0.06)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.95, blue: 0.85).opacity(0.06),
                            .clear
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(state.theme.accent)
                Text("Claude Usage")
                    .font(state.theme.titleFont)
            }
            Spacer()
            RefreshButton(isRefreshing: state.isRefreshing) {
                Task { await state.refreshAll() }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { openSettings() }
                .buttonStyle(.borderless)
                .font(.system(size: 12))

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var angle: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(angle))
        }
        .buttonStyle(.borderless)
        .help("Refresh now")
        .onChange(of: isRefreshing) { _, refreshing in
            if refreshing {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { angle = 0 }
            }
        }
    }
}

struct AccountCard: View {
    let account: Account
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: account.kind.icon)
                    .foregroundStyle(theme.accent)
                Text(account.label)
                    .font(theme.titleFont)
                Spacer()
                if let planLabel = account.usage?.planLabel {
                    Text(planLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(theme.accent.opacity(0.15))
                        )
                }
            }

            if let usage = account.usage {
                if usage.windows.isEmpty {
                    Text("No active limits right now.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(usage.windows, id: \.label) { window in
                            UsageWindowRow(window: window, theme: theme)
                        }
                    }
                }

                if let extra = usage.extra, extra.isEnabled {
                    ExtraUsageRow(extra: extra, theme: theme)
                        .padding(.top, 2)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .themedPanel(theme)
    }
}

struct UsageWindowRow: View {
    let window: UsageWindow
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.label)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(round(window.utilization * 100)))%")
                    .font(theme.monoFont)
                if let reset = window.resetsAt {
                    Text("· resets \(reset, style: .relative)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            UsageBar(utilization: window.utilization, theme: theme)
        }
    }
}

struct ExtraUsageRow: View {
    let extra: ExtraUsage
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Extra usage")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(format(money: extra.usedCredits) + " / " + format(money: extra.monthlyLimit))
                    .font(theme.monoFont)
            }
            UsageBar(utilization: extra.utilization, theme: theme)
        }
    }

    private func format(money: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = extra.currency
        f.maximumFractionDigits = money >= 100 ? 0 : 2
        return f.string(from: NSNumber(value: money)) ?? "$\(money)"
    }
}

struct UsageBar: View {
    let utilization: Double  // 0…1
    let theme: Theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.accent.opacity(0.12))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [theme.accent, theme.secondaryAccent],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, utilization))))
                    .animation(.easeOut(duration: 0.6), value: utilization)
            }
        }
        .frame(height: 6)
    }
}
