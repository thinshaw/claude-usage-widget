using CredentialManagement;
using ClaudeWidget.Models;

namespace ClaudeWidget.Services;

/// <summary>
/// Per-account session cookie storage in the Windows Credential Manager.
/// Mirrors the macOS implementation: each account gets its own slot keyed by
/// AccountKind. Service: "ClaudeWidget", target: "session-cookie:&lt;kind&gt;".
/// </summary>
public static class SessionCookieStore
{
    private const string TargetPrefix = "ClaudeWidget:session-cookie:";

    public static bool Save(AccountKind kind, string cookie)
    {
        var trimmed = (cookie ?? "").Trim();
        var target = TargetPrefix + kind.Key();
        // Delete any existing entry first so Save is idempotent.
        Delete(kind);
        if (string.IsNullOrEmpty(trimmed)) return true;

        using var cred = new Credential
        {
            Target = target,
            Username = kind.Key(),
            Password = trimmed,
            Type = CredentialType.Generic,
            PersistanceType = PersistanceType.LocalComputer,
        };
        return cred.Save();
    }

    public static string? Load(AccountKind kind)
    {
        var target = TargetPrefix + kind.Key();
        using var cred = new Credential { Target = target };
        return cred.Load() && !string.IsNullOrEmpty(cred.Password) ? cred.Password : null;
    }

    public static bool Delete(AccountKind kind)
    {
        var target = TargetPrefix + kind.Key();
        using var cred = new Credential { Target = target };
        // Delete returns false if not found, which is fine for our purposes.
        cred.Delete();
        return true;
    }

    public static bool Has(AccountKind kind) => !string.IsNullOrEmpty(Load(kind));
}
