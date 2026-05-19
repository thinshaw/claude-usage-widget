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

        let orgID = try await resolveOrgID(for: kind, cookie: cookie)
        let url = URL(string: "\(Self.base)/api/organizations/\(orgID)/usage")!

        let data = try await Self.get(url: url, cookie: cookie)
        return try Self.parseUsage(data)
    }

    // MARK: - Org discovery

    private func resolveOrgID(for kind: AccountKind, cookie: String) async throws -> String {
        if let cached = OrgIDStore.load(for: kind) { return cached }
        let url = URL(string: "\(Self.base)/api/organizations")!
        let data = try await Self.get(url: url, cookie: cookie)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ProviderError.decoding("/api/organizations was not a JSON array")
        }
        guard let uuid = arr.first?["uuid"] as? String, !uuid.isEmpty else {
            throw ProviderError.noOrganizations
        }
        OrgIDStore.save(uuid, for: kind)
        return uuid
    }

    // MARK: - HTTP

    private static func get(url: URL, cookie: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("sessionKey=\(cookie)", forHTTPHeaderField: "Cookie")
        req.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        req.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
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
            extra = ExtraUsage(
                isEnabled:    (e["is_enabled"] as? Bool) ?? false,
                monthlyLimit: (e["monthly_limit"] as? Double) ?? 0,
                usedCredits:  (e["used_credits"] as? Double) ?? 0,
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
