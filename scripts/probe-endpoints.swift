// Probe claude.ai endpoints to find which (if any) rotate the sessionKey via
// Set-Cookie response headers. If any endpoint does, we can poll it periodically
// and capture the refreshed cookie — keeping the widget's session alive without
// requiring the user to re-paste.
//
// Usage:
//   swift scripts/probe-endpoints.swift "sk-ant-sid02-..."
//
// Optional second arg: org UUID. If omitted, the script calls /api/organizations
// first to discover one.

import Foundation

guard CommandLine.arguments.count >= 2 else {
    print("usage: swift scripts/probe-endpoints.swift <sessionKey-value> [org-uuid]")
    exit(1)
}

let cookie = CommandLine.arguments[1]
let providedOrgID: String? = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : nil

// Match widget's URLSession config exactly so the probe results reflect what
// the widget would observe.
let cfg = URLSessionConfiguration.default
cfg.httpCookieStorage = nil
cfg.httpCookieAcceptPolicy = .never
cfg.httpShouldSetCookies = false
let session = URLSession(configuration: cfg)

func get(_ path: String) async -> (status: Int, setCookie: [String], bodyPreview: String)? {
    guard let url = URL(string: "https://claude.ai\(path)") else { return nil }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
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
    req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
    req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
    req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
    req.timeoutInterval = 20

    do {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return nil }

        // Collect Set-Cookie headers (case-insensitive, sometimes multiple)
        var setCookies: [String] = []
        for (k, v) in http.allHeaderFields {
            guard let ks = k as? String, ks.lowercased() == "set-cookie" else { continue }
            if let vs = v as? String { setCookies.append(vs) }
        }

        let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
        return (http.statusCode, setCookies, preview)
    } catch {
        return (0, [], "error: \(error.localizedDescription)")
    }
}

func summarize(_ cookies: [String]) -> String {
    if cookies.isEmpty { return "(none)" }
    var summary: [String] = []
    for raw in cookies {
        // Just print the cookie's NAME and presence of expiry / max-age — not the value
        let name = raw.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "?"
        let hasMaxAge = raw.lowercased().contains("max-age=")
        let hasExpires = raw.lowercased().contains("expires=")
        let session = !hasMaxAge && !hasExpires
        let life = session ? "session" : (hasMaxAge ? "max-age" : "expires")
        let interesting = name.lowercased().contains("session") ? " ⭐" : ""
        summary.append("\(name) [\(life)]\(interesting)")
    }
    return summary.joined(separator: ", ")
}

func probe(_ label: String, _ path: String) async {
    guard let r = await get(path) else {
        print("  ✗ \(label): no response")
        return
    }
    let icon = r.setCookie.contains(where: { $0.lowercased().hasPrefix("sessionkey=") }) ? "🔄" : "  "
    print("\(icon) \(label.padding(toLength: 38, withPad: " ", startingAt: 0)) status=\(r.status)  Set-Cookie: \(summarize(r.setCookie))")
}

await Task {
    print("Probing claude.ai endpoints with the supplied sessionKey…\n")

    // Discover an org UUID if not provided
    var orgUUID = providedOrgID
    if orgUUID == nil {
        if let r = await get("/api/organizations") {
            // Best-effort regex extraction since we only have the first 200 bytes
            let pattern = #""uuid"\s*:\s*"([0-9a-fA-F-]{36})""#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: r.bodyPreview, range: NSRange(r.bodyPreview.startIndex..., in: r.bodyPreview)),
               let range = Range(match.range(at: 1), in: r.bodyPreview) {
                orgUUID = String(r.bodyPreview[range])
            }
        }
    }
    if let uuid = orgUUID {
        print("Using org UUID: \(uuid)\n")
    } else {
        print("Could not auto-discover an org UUID — endpoints needing one will be skipped.\n")
    }

    let endpoints: [(String, String)] = [
        ("/api/account",                                 "/api/account"),
        ("/api/auth/current_account",                    "/api/auth/current_account"),
        ("/api/organizations",                           "/api/organizations"),
        ("/api/bootstrap/me",                            "/api/bootstrap/me"),
        ("/api/me",                                      "/api/me"),
    ]

    var orgEndpoints: [(String, String)] = []
    if let uuid = orgUUID {
        orgEndpoints = [
            ("/api/organizations/{uuid}",                    "/api/organizations/\(uuid)"),
            ("/api/organizations/{uuid}/usage",              "/api/organizations/\(uuid)/usage"),
            ("/api/organizations/{uuid}/subscription",       "/api/organizations/\(uuid)/subscription"),
            ("/api/bootstrap/{uuid}",                        "/api/bootstrap/\(uuid)"),
            ("/api/bootstrap/{uuid}/statsig",                "/api/bootstrap/\(uuid)/statsig"),
        ]
    }

    print("Legend:  🔄 = response refreshes sessionKey  |  ⭐ = response cookie name contains 'session'\n")
    print("Endpoint                                  Result")
    print(String(repeating: "─", count: 100))

    for (label, path) in endpoints + orgEndpoints {
        await probe(label, path)
    }

    print("\nDone.")
}.value
