import Foundation

protocol UsageProvider {
    func fetchUsage(for kind: AccountKind) async throws -> AccountUsage
}

/// Mock provider so we can develop the UI before wiring the real data source.
/// Replace with `AdminAPIUsageProvider`, `DesktopAppUsageProvider`, or whatever
/// data source we settle on.
struct MockUsageProvider: UsageProvider {
    func fetchUsage(for kind: AccountKind) async throws -> AccountUsage {
        try? await Task.sleep(nanoseconds: 250_000_000)
        switch kind {
        case .personal:
            return AccountUsage(
                windows: [
                    UsageWindow(label: "5-hour", utilization: 0.21,
                                resetsAt: Date().addingTimeInterval(60 * 60 * 3 + 60 * 12)),
                    UsageWindow(label: "7-day",  utilization: 0.48,
                                resetsAt: Date().addingTimeInterval(60 * 60 * 24 * 4)),
                ],
                extra: nil,
                planLabel: "Claude Pro",
                lastUpdated: Date()
            )
        case .work:
            return AccountUsage(
                windows: [
                    UsageWindow(label: "5-hour", utilization: 0.62,
                                resetsAt: Date().addingTimeInterval(60 * 60 + 60 * 47)),
                    UsageWindow(label: "Opus 7-day", utilization: 0.81,
                                resetsAt: Date().addingTimeInterval(60 * 60 * 24 * 3)),
                ],
                extra: ExtraUsage(isEnabled: true, monthlyLimit: 275.0,
                                  usedCredits: 221.49, utilization: 0.805,
                                  currency: "USD"),
                planLabel: "Claude Max",
                lastUpdated: Date()
            )
        }
    }
}
