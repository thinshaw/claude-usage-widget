namespace ClaudeWidget.Models;

public enum AccountKind { Personal, Work }

public static class AccountKindExtensions
{
    public static string DisplayName(this AccountKind kind) => kind switch
    {
        AccountKind.Personal => "Personal",
        AccountKind.Work => "Work",
        _ => "Unknown"
    };

    /// <summary>Segoe Fluent Icons glyph code (for use with FontFamily="Segoe Fluent Icons").</summary>
    public static string Glyph(this AccountKind kind) => kind switch
    {
        AccountKind.Personal => "", // Contact
        AccountKind.Work     => "", // Work
        _ => ""
    };

    /// <summary>Stable string for storage keys.</summary>
    public static string Key(this AccountKind kind) => kind switch
    {
        AccountKind.Personal => "personal",
        AccountKind.Work     => "work",
        _ => "unknown"
    };
}

/// <summary>One usage window (5-hour, 7-day, etc.) as claude.ai reports it.</summary>
public sealed record UsageWindow(string Label, double Utilization, DateTimeOffset? ResetsAt);

/// <summary>Credits-based extra usage (the paid add-on visible in claude.ai → Settings → Usage when enabled).</summary>
public sealed record ExtraUsage(
    bool IsEnabled,
    double MonthlyLimit,   // dollars (already normalized from cents)
    double UsedCredits,    // dollars (already normalized from cents)
    double Utilization,    // 0..1
    string Currency);

public sealed record AccountUsage(
    IReadOnlyList<UsageWindow> Windows,
    ExtraUsage? Extra,
    string PlanLabel,
    DateTimeOffset LastUpdated)
{
    /// <summary>Most-utilized active window — the one the user most likely cares about.</summary>
    public UsageWindow? PrimaryWindow =>
        Windows.Count == 0 ? null : Windows.OrderByDescending(w => w.Utilization).First();

    /// <summary>
    /// Highest utilization 0..1 across all active limits on this account
    /// (windows + extra_usage). Drives the menu-bar percentage badge.
    /// </summary>
    public double PeakUtilization
    {
        get
        {
            double peak = 0;
            foreach (var w in Windows) peak = Math.Max(peak, w.Utilization);
            if (Extra is { IsEnabled: true }) peak = Math.Max(peak, Extra.Utilization);
            return Math.Min(1, peak);
        }
    }
}

public sealed record Organization(string Uuid, string Name);

public sealed class Account
{
    public required AccountKind Kind { get; init; }
    public string Label { get; set; } = "";
    public bool IsConfigured { get; set; } = true;
    public AccountUsage? Usage { get; set; }
    public List<Organization> AvailableOrgs { get; set; } = new();
    public string? SelectedOrgUuid { get; set; }
}
