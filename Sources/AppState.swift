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
    @Published var selectedMenuBarAccount: AccountKind {
        didSet { UserDefaults.standard.set(selectedMenuBarAccount.rawValue, forKey: "selectedMenuBarAccount") }
    }

    private var refreshTimer: Timer?
    private let realProvider = ClaudeAIUsageProvider()
    private let mockProvider: UsageProvider = MockUsageProvider()

    private func provider(for kind: AccountKind) -> UsageProvider {
        SessionCookieStore.has(kind) ? realProvider : mockProvider
    }

    init() {
        let savedTheme = UserDefaults.standard.string(forKey: "selectedThemeId")
            .flatMap(Theme.init(rawValue:)) ?? .liquidGlass
        self.theme = savedTheme
        let savedMenuBarAccount = UserDefaults.standard.string(forKey: "selectedMenuBarAccount")
            .flatMap(AccountKind.init(rawValue:)) ?? .personal
        self.selectedMenuBarAccount = savedMenuBarAccount

        self.accounts = [
            Account(kind: .personal, label: "Personal", isConfigured: true, usage: nil,
                    selectedOrgUUID: OrgIDStore.load(for: .personal)),
            Account(kind: .work,     label: "Work",     isConfigured: true, usage: nil,
                    selectedOrgUUID: OrgIDStore.load(for: .work)),
        ]

        Task {
            for account in accounts where SessionCookieStore.has(account.kind) {
                await loadOrganizations(for: account.kind)
            }
            await refreshAll()
        }
        startAutoRefresh()
    }

    /// Utilization for whichever account the user selected for the menu-bar
    /// badge.
    var selectedMenuBarUtilization: Double? {
        guard let account = accounts.first(where: { $0.kind == selectedMenuBarAccount && $0.isConfigured }) else {
            return nil
        }
        return account.usage?.peakUtilization
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
                    // Only surface the error if we have no data to show; an
                    // intermittent 401 / 5xx while the last-good numbers are
                    // still on screen would mislead the user into thinking the
                    // session is dead when it isn't.
                    if accounts[idx].usage == nil {
                        lastError = "\(kind.displayName): \(error.localizedDescription)"
                    }
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
        if !configured {
            accounts[idx].usage = nil
            if selectedMenuBarAccount == kind,
               let fallback = accounts.first(where: { $0.isConfigured && $0.kind != kind })?.kind {
                selectedMenuBarAccount = fallback
            }
        }
    }

    @discardableResult
    func saveSessionCookie(_ cookie: String, for kind: AccountKind) -> Bool {
        let ok = SessionCookieStore.save(cookie, for: kind)
        guard ok else { return false }
        // Loading a new cookie may unlock a different set of orgs — clear any
        // prior selection and force re-discovery.
        OrgIDStore.clear(for: kind)
        if let idx = accounts.firstIndex(where: { $0.kind == kind }) {
            accounts[idx].selectedOrgUUID = nil
            accounts[idx].availableOrgs = []
            accounts[idx].usage = nil
        }
        Task {
            await loadOrganizations(for: kind)
            await refreshAll()
        }
        return true
    }

    @discardableResult
    func clearSessionCookie(for kind: AccountKind) -> Bool {
        let ok = SessionCookieStore.delete(for: kind)
        OrgIDStore.clear(for: kind)
        if let idx = accounts.firstIndex(where: { $0.kind == kind }) {
            accounts[idx].usage = nil
            accounts[idx].availableOrgs = []
            accounts[idx].selectedOrgUUID = nil
        }
        return ok
    }

    func hasSessionCookie(for kind: AccountKind) -> Bool {
        SessionCookieStore.has(kind)
    }

    func loadOrganizations(for kind: AccountKind) async {
        guard SessionCookieStore.has(kind) else { return }
        do {
            let orgs = try await realProvider.fetchOrganizations(for: kind)
            guard let idx = accounts.firstIndex(where: { $0.kind == kind }) else { return }
            accounts[idx].availableOrgs = orgs
            if let cached = OrgIDStore.load(for: kind),
               orgs.contains(where: { $0.uuid == cached }) {
                accounts[idx].selectedOrgUUID = cached
            }
        } catch {
            // Non-fatal: the picker just won't populate. fetchUsage uses the
            // cached UUID and works independently of this lookup.
        }
    }

    func setSelectedOrg(_ uuid: String, for kind: AccountKind) {
        OrgIDStore.save(uuid, for: kind)
        guard let idx = accounts.firstIndex(where: { $0.kind == kind }) else { return }
        accounts[idx].selectedOrgUUID = uuid
        accounts[idx].usage = nil
        Task { await refreshAll() }
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
