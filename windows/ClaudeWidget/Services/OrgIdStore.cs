using Windows.Storage;
using ClaudeWidget.Models;

namespace ClaudeWidget.Services;

/// <summary>
/// Caches the claude.ai org UUID per account in LocalSettings so we don't hit
/// /api/organizations on every usage refresh. Cleared whenever the user clears
/// the session cookie.
/// </summary>
public static class OrgIdStore
{
    private const string Prefix = "orgID.";

    private static ApplicationDataContainer Settings =>
        ApplicationData.Current.LocalSettings;

    public static string? Load(AccountKind kind)
    {
        var v = Settings.Values[Prefix + kind.Key()] as string;
        return string.IsNullOrEmpty(v) ? null : v;
    }

    public static void Save(AccountKind kind, string uuid)
    {
        Settings.Values[Prefix + kind.Key()] = uuid;
    }

    public static void Clear(AccountKind kind)
    {
        Settings.Values.Remove(Prefix + kind.Key());
    }
}
