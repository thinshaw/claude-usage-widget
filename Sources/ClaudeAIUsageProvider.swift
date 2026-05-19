import Foundation

/// Hits the same internal claude.ai endpoints that the Claude desktop app uses
/// to render its Settings → Usage screen, authenticated with the user-supplied
/// `sessionKey` cookie stored per account in Keychain.
///
/// Endpoint shape captured from Safari Web Inspector on 2026-05-19:
///   GET https://claude.ai/api/organizations/{org_uuid}/usage
///   Cookie: sessionKey=sk-ant-sid02-...
///
/// Each cookie maps to one or more orgs. We discover the org UUID once per
/// account via `GET /api/organizations` and cache it in UserDefaults.
struct ClaudeAIUsageProvider: UsageProvider {
    private static let base = "https://claude.ai"

    /// Dedicated URLSession that does NOT share the global cookie storage and
    /// will not auto-send or auto-store cookies. We must enforce this because
    /// every request carries an explicit `Cookie: sessionKey=…` header for a
    /// specific account, and we'd get cross-account contamination if URLSession
    /// silently merged in cookies it had cached from a previous account's reply.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = nil
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        return URLSession(configuration: cfg)
    }()

    enum ProviderError: LocalizedError {
        case noSessionCookie
        case noOrganizations
        case http(Int, String)
        case decoding(String)
        case sessionExpired

        var errorDescription: String? {
            switch self {
            case .noSessionCookie:       return "No session cookie saved for this account."
            case .noOrganizations:       return "Session has no accessible organizations."
            case .http(let code, let body): return "claude.ai returned \(code): \(body.prefix(120))"
            case .decoding(let detail):  return "Could not parse usage response: \(detail)"
            case .sessionExpired:        return "Session expired — re-paste your sessionKey cookie."
            }
        }
    }

    func fetchUsage(for kind: AccountKind) async throws -> AccountUsage {
        guard let cookie = SessionCookieStore.load(for: kind), !cookie.isEmpty else {
            throw ProviderError.noSessionCookie
        }

        // If the user (or a prior auto-pick) chose an org for this slot, use it
        // directly. Don't auto-fall-back to a different one — that would hide
        // configuration mistakes and produce the wrong account's data.
        if let cached = OrgIDStore.load(for: kind) {
            let url = URL(string: "\(Self.base)/api/organizations/\(cached)/usage")!
            let data = try await Self.get(url: url, cookie: cookie)
            return try Self.parseUsage(data)
        }

        // No selection yet: auto-pick the first org whose /usage endpoint
        // responds, and cache it. The user can override via Settings.
        let orgs = try await fetchOrganizations(cookie: cookie)
        guard !orgs.isEmpty else { throw ProviderError.noOrganizations }

        var lastError: Error?
        for org in orgs {
            do {
                let url = URL(string: "\(Self.base)/api/organizations/\(org.uuid)/usage")!
                let data = try await Self.get(url: url, cookie: cookie)
                let usage = try Self.parseUsage(data)
                OrgIDStore.save(org.uuid, for: kind)
                return usage
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? ProviderError.noOrganizations
    }

    /// Public org-listing used by Settings so the user can pick which org each
    /// account slot tracks.
    func fetchOrganizations(for kind: AccountKind) async throws -> [Organization] {
        guard let cookie = SessionCookieStore.load(for: kind), !cookie.isEmpty else {
            throw ProviderError.noSessionCookie
        }
        return try await fetchOrganizations(cookie: cookie)
    }

    // MARK: - Org discovery

    private func fetchOrganizations(cookie: String) async throws -> [Organization] {
        let url = URL(string: "\(Self.base)/api/organizations")!
        let data = try await Self.get(url: url, cookie: cookie)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ProviderError.decoding("/api/organizations was not a JSON array")
        }
        return arr.compactMap { dict in
            guard let uuid = dict["uuid"] as? String, !uuid.isEmpty else { return nil }
            let name = (dict["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Org \(uuid.prefix(8))"
            return Organization(uuid: uuid, name: name)
        }
    }

    // MARK: - HTTP

    private static func get(url: URL, cookie: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        // Belt-and-suspenders: also disable cookie handling at the request level
        // so an explicit Cookie header is never augmented by URLSession.
        req.httpShouldHandleCookies = false
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("sessionKey=\(cookie)", forHTTPHeaderField: "Cookie")
        req.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        req.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        // Sec-Fetch-* headers normally added by the browser. Cloudflare's bot
        // detection flags their absence; matching the browser request fingerprint
        // dramatically reduces transient 401/403s.
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.timeoutInterval = 20

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.decoding("no HTTP response")
        }
        switch http.statusCode {
        case 401, 403:
            throw ProviderError.sessionExpired
        case 200..<300:
            return data
        default:
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw ProviderError.http(http.statusCode, body)
        }
    }

    // MARK: - Parsing
    //
    // Real claude.ai usage response shape (captured 2026-05-19):
    //   {
    //     "five_hour":           null | {"utilization": 0..100, "resets_at": "ISO8601"},
    //     "seven_day":           null | {...},
    //     "seven_day_opus":      null | {...},
    //     "seven_day_sonnet":    null | {...},
    //     "seven_day_oauth_apps":null | {...},
    //     ...other named buckets...
    //     "extra_usage": {
    //       "is_enabled": bool,
    //       "monthly_limit": Double,
    //       "used_credits": Double,
    //       "utilization": Double,   // 0..100
    //       "currency": "USD",
    //       "disabled_reason": null | string
    //     }
    //   }
    //
    // `utilization` arrives as 0..100 (percent); we normalize to 0..1.
    private static let windowSpec: [(key: String, label: String)] = [
        ("five_hour",        "5-hour"),
        ("seven_day",        "7-day"),
        ("seven_day_opus",   "Opus 7-day"),
        ("seven_day_sonnet", "Sonnet 7-day"),
    ]

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseUsage(_ data: Data) throws -> AccountUsage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decoding("response is not a JSON object")
        }

        var windows: [UsageWindow] = []
        for (key, label) in windowSpec {
            guard let dict = json[key] as? [String: Any] else { continue }
            let util = (dict["utilization"] as? Double) ?? 0
            var resetsAt: Date?
            if let iso = dict["resets_at"] as? String {
                resetsAt = isoFormatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
            }
            windows.append(UsageWindow(label: label, utilization: util / 100.0, resetsAt: resetsAt))
        }

        var extra: ExtraUsage?
        if let e = json["extra_usage"] as? [String: Any] {
            // claude.ai sends monthly_limit and used_credits in *cents*
            // (e.g. 27500 = $275.00). Normalize to dollars so the model is
            // a real currency amount.
            let limitCents = (e["monthly_limit"] as? Double) ?? 0
            let usedCents  = (e["used_credits"]  as? Double) ?? 0
            extra = ExtraUsage(
                isEnabled:    (e["is_enabled"] as? Bool) ?? false,
                monthlyLimit: limitCents / 100.0,
                usedCredits:  usedCents / 100.0,
                utilization:  ((e["utilization"] as? Double) ?? 0) / 100.0,
                currency:     (e["currency"] as? String) ?? "USD"
            )
        }

        let plan = inferPlanLabel(windows: windows, extra: extra)

        return AccountUsage(
            windows: windows,
            extra: extra,
            planLabel: plan,
            lastUpdated: Date()
        )
    }

    private static func inferPlanLabel(windows: [UsageWindow], extra: ExtraUsage?) -> String {
        // Heuristic until we capture the subscription endpoint too.
        if windows.contains(where: { $0.label.starts(with: "Opus") }) { return "Claude Max" }
        if extra?.isEnabled == true { return "Claude (with extra usage)" }
        return "Claude Pro"
    }
}
