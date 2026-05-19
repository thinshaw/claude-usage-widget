using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ClaudeWidget.Models;
using ClaudeWidget.Services;
using Windows.Storage;

namespace ClaudeWidget.ViewModels;

/// <summary>
/// Mirrors the Swift AppState: owns accounts, theme selection, refresh loop,
/// and exposes commands for the UI to call.
/// </summary>
public sealed partial class AppState : ObservableObject
{
    [ObservableProperty] private Theme theme;
    [ObservableProperty] private bool isRefreshing;
    [ObservableProperty] private string? lastError;
    [ObservableProperty] private double? peakUtilization;

    public ObservableObservableList<Account> Accounts { get; } = new();

    private readonly ClaudeAIUsageProvider _provider = new();
    private readonly System.Threading.Timer _refreshTimer;
    private const int RefreshIntervalSeconds = 60;

    public AppState()
    {
        // Restore theme from local settings (default: Mica).
        var savedTheme = ApplicationData.Current.LocalSettings.Values["selectedThemeId"] as string;
        theme = savedTheme switch
        {
            "sciFi" => Theme.SciFi,
            _ => Theme.Mica
        };

        Accounts.Add(new Account { Kind = AccountKind.Personal, Label = "Personal",
            SelectedOrgUuid = OrgIdStore.Load(AccountKind.Personal) });
        Accounts.Add(new Account { Kind = AccountKind.Work, Label = "Work",
            SelectedOrgUuid = OrgIdStore.Load(AccountKind.Work) });

        _refreshTimer = new System.Threading.Timer(_ => _ = RefreshAllAsync(),
            null, TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(RefreshIntervalSeconds));

        _ = InitialLoadAsync();
    }

    partial void OnThemeChanged(Theme value)
    {
        ApplicationData.Current.LocalSettings.Values["selectedThemeId"] =
            value == Theme.SciFi ? "sciFi" : "mica";
    }

    private async Task InitialLoadAsync()
    {
        foreach (var account in Accounts)
        {
            if (SessionCookieStore.Has(account.Kind))
                await LoadOrganizationsAsync(account.Kind);
        }
        await RefreshAllAsync();
    }

    [RelayCommand]
    public async Task RefreshAllAsync()
    {
        IsRefreshing = true;
        LastError = null;

        try
        {
            var tasks = Accounts
                .Where(a => a.IsConfigured)
                .Select(async a =>
                {
                    try
                    {
                        if (!SessionCookieStore.Has(a.Kind))
                        {
                            // No cookie → no real data. UI will show "configure me".
                            return;
                        }
                        var usage = await _provider.FetchUsageAsync(a.Kind);
                        a.Usage = usage;
                    }
                    catch (Exception ex)
                    {
                        // Suppress error if we have stale-but-recent data (don't
                        // shout "session expired" while the last-good numbers are
                        // still on screen).
                        if (a.Usage == null)
                            LastError = $"{a.Kind.DisplayName()}: {ex.Message}";
                    }
                })
                .ToArray();
            await Task.WhenAll(tasks);

            // Update peak across all configured accounts (drives tray label).
            var peaks = Accounts
                .Where(a => a.Usage != null)
                .Select(a => a.Usage!.PeakUtilization)
                .ToList();
            PeakUtilization = peaks.Count > 0 ? peaks.Max() : null;

            // Tell anyone bound to Accounts that things changed
            OnPropertyChanged(nameof(Accounts));
        }
        finally
        {
            IsRefreshing = false;
        }
    }

    public bool SaveSessionCookie(AccountKind kind, string cookie)
    {
        if (!SessionCookieStore.Save(kind, cookie)) return false;
        // New cookie = potentially different orgs. Reset any selection.
        OrgIdStore.Clear(kind);
        var account = Accounts.First(a => a.Kind == kind);
        account.SelectedOrgUuid = null;
        account.AvailableOrgs = new();
        account.Usage = null;

        _ = Task.Run(async () =>
        {
            await LoadOrganizationsAsync(kind);
            await RefreshAllAsync();
        });
        return true;
    }

    public bool ClearSessionCookie(AccountKind kind)
    {
        var ok = SessionCookieStore.Delete(kind);
        OrgIdStore.Clear(kind);
        var account = Accounts.First(a => a.Kind == kind);
        account.Usage = null;
        account.AvailableOrgs = new();
        account.SelectedOrgUuid = null;
        OnPropertyChanged(nameof(Accounts));
        return ok;
    }

    public bool HasSessionCookie(AccountKind kind) => SessionCookieStore.Has(kind);

    public async Task LoadOrganizationsAsync(AccountKind kind)
    {
        if (!SessionCookieStore.Has(kind)) return;
        var orgs = await _provider.FetchOrganizationsForAsync(kind);
        var account = Accounts.First(a => a.Kind == kind);
        account.AvailableOrgs = orgs;
        var cached = OrgIdStore.Load(kind);
        if (!string.IsNullOrEmpty(cached) && orgs.Any(o => o.Uuid == cached))
        {
            account.SelectedOrgUuid = cached;
        }
        OnPropertyChanged(nameof(Accounts));
    }

    public void SetSelectedOrg(AccountKind kind, string uuid)
    {
        OrgIdStore.Save(kind, uuid);
        var account = Accounts.First(a => a.Kind == kind);
        account.SelectedOrgUuid = uuid;
        account.Usage = null;
        _ = RefreshAllAsync();
    }
}

/// <summary>
/// Convenience alias so we don't pull in a separate ObservableCollection import
/// at the top — exposes the same surface for UI binding.
/// </summary>
public sealed class ObservableObservableList<T> : System.Collections.ObjectModel.ObservableCollection<T> { }
