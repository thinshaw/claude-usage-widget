using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using ClaudeWidget.Models;

namespace ClaudeWidget.Services;

/// <summary>
/// Hits the same internal claude.ai endpoints that the Claude desktop app uses
/// to render Settings → Usage, authenticated with a user-supplied sessionKey
/// cookie stored per account in Windows Credential Manager.
///
/// Endpoint shape (captured from Safari Web Inspector on 2026-05-19):
///   GET https://claude.ai/api/organizations/{org_uuid}/usage
///   Cookie: sessionKey=sk-ant-sid02-...
///
/// CRITICAL: each request explicitly sets its own Cookie header. HttpClient must
/// have cookie handling disabled (HttpClientHandler.UseCookies = false) or the
/// shared cookie container will silently merge cookies across accounts and both
/// account slots will end up tracking the same org. Same bug we hit on macOS.
/// </summary>
public sealed class ClaudeAIUsageProvider
{
    private const string BaseUrl = "https://claude.ai";

    private static readonly HttpClient HttpClient = CreateClient();

    private static HttpClient CreateClient()
    {
        var handler = new HttpClientHandler
        {
            UseCookies = false,             // ← the load-bearing line
            UseDefaultCredentials = false,
            AllowAutoRedirect = true,
            AutomaticDecompression = DecompressionMethods.All,
        };
        var client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(20)
        };
        return client;
    }

    public sealed class ProviderException : Exception
    {
        public enum Kind { NoSessionCookie, NoOrganizations, SessionExpired, Http, Decoding }
        public Kind Code { get; }
        public int HttpStatus { get; }
        public ProviderException(Kind code, string message, int httpStatus = 0)
            : base(message) { Code = code; HttpStatus = httpStatus; }
    }

    /// <summary>Fetch usage for the given account. Uses cached org UUID if present.</summary>
    public async Task<AccountUsage> FetchUsageAsync(AccountKind kind, CancellationToken ct = default)
    {
        var cookie = SessionCookieStore.Load(kind)
            ?? throw new ProviderException(ProviderException.Kind.NoSessionCookie,
                "No session cookie saved for this account.");

        // Fast path: cached org UUID. If it 404s, fall through to auto-pick.
        var cached = OrgIdStore.Load(kind);
        if (!string.IsNullOrEmpty(cached))
        {
            try
            {
                var data = await GetAsync($"/api/organizations/{cached}/usage", cookie, ct);
                return ParseUsage(data);
            }
            catch (ProviderException ex) when (ex.Code == ProviderException.Kind.Http && ex.HttpStatus == 404)
            {
                OrgIdStore.Clear(kind);
            }
        }

        // Auto-pick: iterate orgs until /usage responds successfully, cache it.
        var orgs = await FetchOrganizationsAsync(cookie, ct);
        if (orgs.Count == 0)
            throw new ProviderException(ProviderException.Kind.NoOrganizations,
                "Session has no accessible organizations.");

        Exception? last = null;
        foreach (var org in orgs)
        {
            try
            {
                var data = await GetAsync($"/api/organizations/{org.Uuid}/usage", cookie, ct);
                var usage = ParseUsage(data);
                OrgIdStore.Save(kind, org.Uuid);
                return usage;
            }
            catch (Exception ex)
            {
                last = ex;
            }
        }
        throw last ?? new ProviderException(ProviderException.Kind.NoOrganizations,
            "No org returned a usable response.");
    }

    /// <summary>
    /// Public org-listing for Settings → Accounts (so the user can pick which
    /// org each slot tracks). Returns [] on failure rather than throwing —
    /// the picker just won't populate, but fetchUsage continues to work.
    /// </summary>
    public async Task<List<Organization>> FetchOrganizationsForAsync(AccountKind kind, CancellationToken ct = default)
    {
        var cookie = SessionCookieStore.Load(kind);
        if (string.IsNullOrEmpty(cookie)) return new List<Organization>();
        try { return await FetchOrganizationsAsync(cookie, ct); }
        catch { return new List<Organization>(); }
    }

    private async Task<List<Organization>> FetchOrganizationsAsync(string cookie, CancellationToken ct)
    {
        var data = await GetAsync("/api/organizations", cookie, ct);
        using var doc = JsonDocument.Parse(data);
        if (doc.RootElement.ValueKind != JsonValueKind.Array)
            throw new ProviderException(ProviderException.Kind.Decoding,
                "/api/organizations was not a JSON array");

        var result = new List<Organization>();
        foreach (var item in doc.RootElement.EnumerateArray())
        {
            var uuid = item.TryGetProperty("uuid", out var u) ? u.GetString() : null;
            if (string.IsNullOrEmpty(uuid)) continue;
            var name = item.TryGetProperty("name", out var n) ? n.GetString() : null;
            if (string.IsNullOrEmpty(name)) name = $"Org {uuid[..8]}";
            result.Add(new Organization(uuid!, name!));
        }
        return result;
    }

    private static async Task<string> GetAsync(string path, string cookie, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, BaseUrl + path);
        // Headers matching what Safari sends on claude.ai. The Sec-Fetch-* set
        // reduces transient Cloudflare 401/403s significantly.
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("*/*"));
        req.Headers.TryAddWithoutValidation("Cookie", $"sessionKey={cookie}");
        req.Headers.TryAddWithoutValidation("anthropic-client-platform", "web_claude_ai");
        req.Headers.UserAgent.ParseAdd(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/130.0.0.0 Safari/537.36");
        req.Headers.TryAddWithoutValidation("Origin", "https://claude.ai");
        req.Headers.TryAddWithoutValidation("Referer", "https://claude.ai/settings/usage");
        req.Headers.TryAddWithoutValidation("Sec-Fetch-Dest", "empty");
        req.Headers.TryAddWithoutValidation("Sec-Fetch-Mode", "cors");
        req.Headers.TryAddWithoutValidation("Sec-Fetch-Site", "same-origin");

        using var resp = await HttpClient.SendAsync(req, ct);
        var body = await resp.Content.ReadAsStringAsync(ct);
        switch ((int)resp.StatusCode)
        {
            case 401:
            case 403:
                throw new ProviderException(ProviderException.Kind.SessionExpired,
                    "Session expired — re-paste your sessionKey cookie.", (int)resp.StatusCode);
            case >= 200 and < 300:
                return body;
            default:
                var snippet = body.Length > 120 ? body[..120] : body;
                throw new ProviderException(ProviderException.Kind.Http,
                    $"claude.ai returned {(int)resp.StatusCode}: {snippet}",
                    (int)resp.StatusCode);
        }
    }

    // MARK: - Parsing
    //
    // Real claude.ai usage response shape:
    //   {
    //     "five_hour":        null | { "utilization": 0..100, "resets_at": "ISO8601" },
    //     "seven_day":        null | {...},
    //     "seven_day_opus":   null | {...},
    //     "seven_day_sonnet": null | {...},
    //     ...
    //     "extra_usage": {
    //       "is_enabled": bool,
    //       "monthly_limit": Double,   // CENTS — divide by 100 for dollars
    //       "used_credits": Double,    // CENTS
    //       "utilization": Double,     // 0..100 (percent)
    //       "currency": "USD",
    //       "disabled_reason": null | string
    //     }
    //   }
    //
    // CRITICAL: monthly_limit and used_credits are in CENTS. 27500 = $275.00.
    // Don't display the raw number to the user.

    private static readonly (string Key, string Label)[] WindowSpec = new[]
    {
        ("five_hour",        "5-hour"),
        ("seven_day",        "7-day"),
        ("seven_day_opus",   "Opus 7-day"),
        ("seven_day_sonnet", "Sonnet 7-day"),
    };

    private static AccountUsage ParseUsage(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new ProviderException(ProviderException.Kind.Decoding,
                "response is not a JSON object");

        var windows = new List<UsageWindow>();
        foreach (var (key, label) in WindowSpec)
        {
            if (!root.TryGetProperty(key, out var w) || w.ValueKind != JsonValueKind.Object) continue;
            var util = w.TryGetProperty("utilization", out var u) && u.ValueKind == JsonValueKind.Number
                ? u.GetDouble() / 100.0 : 0;
            DateTimeOffset? resetsAt = null;
            if (w.TryGetProperty("resets_at", out var r) && r.ValueKind == JsonValueKind.String &&
                DateTimeOffset.TryParse(r.GetString(), out var parsed))
            {
                resetsAt = parsed;
            }
            windows.Add(new UsageWindow(label, util, resetsAt));
        }

        ExtraUsage? extra = null;
        if (root.TryGetProperty("extra_usage", out var e) && e.ValueKind == JsonValueKind.Object)
        {
            var isEnabled = e.TryGetProperty("is_enabled", out var en) && en.ValueKind == JsonValueKind.True;
            double limitCents = e.TryGetProperty("monthly_limit", out var ml) && ml.ValueKind == JsonValueKind.Number
                ? ml.GetDouble() : 0;
            double usedCents = e.TryGetProperty("used_credits", out var uc) && uc.ValueKind == JsonValueKind.Number
                ? uc.GetDouble() : 0;
            double utilPct = e.TryGetProperty("utilization", out var eu) && eu.ValueKind == JsonValueKind.Number
                ? eu.GetDouble() : 0;
            string currency = e.TryGetProperty("currency", out var cu) && cu.ValueKind == JsonValueKind.String
                ? (cu.GetString() ?? "USD") : "USD";

            extra = new ExtraUsage(
                IsEnabled:    isEnabled,
                MonthlyLimit: limitCents / 100.0,   // cents → dollars
                UsedCredits:  usedCents  / 100.0,   // cents → dollars
                Utilization:  utilPct    / 100.0,   // 0..100 → 0..1
                Currency:     currency);
        }

        var plan = InferPlanLabel(windows, extra);
        return new AccountUsage(windows, extra, plan, DateTimeOffset.UtcNow);
    }

    private static string InferPlanLabel(IReadOnlyList<UsageWindow> windows, ExtraUsage? extra)
    {
        if (windows.Any(w => w.Label.StartsWith("Opus"))) return "Claude Max";
        if (extra is { IsEnabled: true } && windows.Count == 0) return "Claude (with extra usage)";
        if (extra is { IsEnabled: true }) return "Claude (with extra usage)";
        return "Claude Pro";
    }
}
