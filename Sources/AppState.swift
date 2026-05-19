import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var accounts: [Account]
    @Published var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "selectedThemeId") }
    }
    @Published var isRefreshing: Bool = false
    @Published var lastError: String?

    private var refreshTimer: Timer?
    private let realProvider: UsageProvider = ClaudeAIUsageProvider()
    private let mockProvider: UsageProvider = MockUsageProvider()

    private func provider(for kind: AccountKind) -> UsageProvider {
        SessionCookieStore.has(kind) ? realProvider : mockProvider
    }

    init() {
        let savedTheme = UserDefaults.standard.string(forKey: "selectedThemeId")
            .flatMap(Theme.init(rawValue:)) ?? .liquidGlass
        self.theme = savedTheme

        self.accounts = [
            Account(kind: .personal, label: "Personal", isConfigured: true, usage: nil),
            Account(kind: .work,     label: "Work",     isConfigured: true, usage: nil),
        ]

        Task { await refreshAll() }
        startAutoRefresh()
    }

    var combinedRemainingPercent: Double? {
        let configured = accounts.filter { $0.isConfigured }
        let usages = configured.compactMap { $0.usage }
        guard !usages.isEmpty else { return nil }
        let avg = usages.map(\.remainingPercent).reduce(0, +) / Double(usages.count)
        return avg
    }

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        await withTaskGroup(of: (AccountKind, Result<AccountUsage, Error>).self) { group in
            for account in accounts where account.isConfigured {
                let kind = account.kind
                let p = provider(for: kind)
                group.addTask {
                    do {
                        let usage = try await p.fetchUsage(for: kind)
                        return (kind, .success(usage))
                    } catch {
                        return (kind, .failure(error))
                    }
                }
            }

            for await (kind, result) in group {
                guard let idx = accounts.firstIndex(where: { $0.kind == kind }) else { continue }
                switch result {
                case .success(let usage):
                    accounts[idx].usage = usage
                case .failure(let error):
                    lastError = "\(kind.displayName): \(error.localizedDescription)"
                }
            }
        }
    }

    func setAccountLabel(_ label: String, for kind: AccountKind) {
        guard let idx = accounts.firstIndex(where: { $0.kind == kind }) else { return }
        accounts[idx].label = label
    }

    func setAccountConfigured(_ configured: Bool, for kind: AccountKind) {
        guard let idx = accounts.firstIndex(where: { $0.kind == kind }) else { return }
        accounts[idx].isConfigured = configured
        if !configured { accounts[idx].usage = nil }
    }

    @discardableResult
    func saveSessionCookie(_ cookie: String, for kind: AccountKind) -> Bool {
        let ok = SessionCookieStore.save(cookie, for: kind)
        if ok { Task { await refreshAll() } }
        return ok
    }

    @discardableResult
    func clearSessionCookie(for kind: AccountKind) -> Bool {
        let ok = SessionCookieStore.delete(for: kind)
        OrgIDStore.clear(for: kind)
        if let idx = accounts.firstIndex(where: { $0.kind == kind }) {
            accounts[idx].usage = nil
        }
        return ok
    }

    func hasSessionCookie(for kind: AccountKind) -> Bool {
        SessionCookieStore.has(kind)
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }
}
