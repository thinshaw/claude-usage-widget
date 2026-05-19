using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using ClaudeWidget.Models;
using ClaudeWidget.ViewModels;

namespace ClaudeWidget.Views;

/// <summary>
/// The tray dropdown — Windows analog of the macOS MenuBarExtra popup.
/// Renders the per-account usage cards. Minimal first-pass layout; iterate on
/// Windows with the Visual Studio XAML designer.
/// </summary>
public sealed class TrayPopupWindow : Window
{
    private readonly AppState _state;
    private readonly Action _openSettings;
    private bool _isVisible;

    public TrayPopupWindow(AppState state, Action openSettings)
    {
        _state = state;
        _openSettings = openSettings;

        Title = "Claude Usage";
        // Hide from taskbar — tray-popup style window.
        if (AppWindow.Presenter is OverlappedPresenter p)
        {
            p.IsResizable = false;
            p.IsMaximizable = false;
            p.IsMinimizable = false;
            p.SetBorderAndTitleBar(false, false);
        }
        AppWindow.IsShownInSwitchers = false;
        AppWindow.Resize(new SizeInt32(340, 420));

        BuildContent();
        SystemBackdrop = new MicaBackdrop();
        Closed += (_, _) => _isVisible = false;
        AppWindow.Hide();
    }

    public void ToggleVisibility()
    {
        if (_isVisible) { AppWindow.Hide(); _isVisible = false; }
        else { PositionNearTray(); AppWindow.Show(); _isVisible = true; }
    }

    private void PositionNearTray()
    {
        // Bottom-right of the primary monitor, ~24px above the taskbar.
        var display = DisplayArea.Primary;
        var area = display.WorkArea;
        var w = AppWindow.Size.Width;
        var h = AppWindow.Size.Height;
        AppWindow.Move(new PointInt32(
            area.X + area.Width - w - 12,
            area.Y + area.Height - h - 12));
    }

    private void BuildContent()
    {
        var root = new StackPanel
        {
            Padding = new Thickness(16),
            Spacing = 12,
        };

        var header = new TextBlock
        {
            Text = "Claude Usage",
            FontSize = 16,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        };
        root.Children.Add(header);

        foreach (var account in _state.Accounts)
        {
            root.Children.Add(BuildAccountCard(account));
        }

        var footer = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        var settingsBtn = new HyperlinkButton { Content = "Settings…" };
        settingsBtn.Click += (_, _) => _openSettings();
        footer.Children.Add(settingsBtn);

        var quitBtn = new HyperlinkButton { Content = "Quit" };
        quitBtn.Click += (_, _) => Application.Current.Exit();
        footer.Children.Add(quitBtn);

        root.Children.Add(footer);

        Content = root;
    }

    private UIElement BuildAccountCard(Account account)
    {
        var panel = new StackPanel
        {
            Padding = new Thickness(12),
            Spacing = 6,
            CornerRadius = new CornerRadius(12),
            Background = new SolidColorBrush(Colors.Transparent),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
        };

        var headerRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        headerRow.Children.Add(new TextBlock
        {
            Text = account.Label,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            FontSize = 14
        });
        if (account.Usage is { } u)
        {
            headerRow.Children.Add(new TextBlock
            {
                Text = u.PlanLabel,
                FontSize = 11,
                Opacity = 0.7,
                VerticalAlignment = VerticalAlignment.Center
            });
        }
        panel.Children.Add(headerRow);

        if (account.Usage is null)
        {
            panel.Children.Add(new TextBlock
            {
                Text = SessionCookieStoreHasCookie(account)
                    ? "Loading…"
                    : "Paste a sessionKey in Settings to get started.",
                Opacity = 0.7,
                FontSize = 12
            });
            return panel;
        }

        if (account.Usage.Windows.Count == 0)
            panel.Children.Add(new TextBlock { Text = "No active limits right now.", Opacity = 0.7, FontSize = 12 });

        foreach (var w in account.Usage.Windows)
        {
            panel.Children.Add(BuildWindowRow(w.Label,
                $"{Math.Round(w.Utilization * 100)}%",
                w.ResetsAt is { } r ? $"resets {Humanize(r)}" : null,
                w.Utilization));
        }

        if (account.Usage.Extra is { IsEnabled: true } e)
        {
            panel.Children.Add(BuildWindowRow(
                "Extra usage",
                $"{Math.Round(e.Utilization * 100)}%",
                $"· ${e.UsedCredits:F0} / ${e.MonthlyLimit:F0}",
                e.Utilization));
        }

        return panel;
    }

    private static UIElement BuildWindowRow(string label, string pct, string? trailing, double util)
    {
        var stack = new StackPanel { Spacing = 4 };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        row.Children.Add(new TextBlock { Text = label, FontSize = 12 });
        row.Children.Add(new TextBlock { Text = pct, FontSize = 12, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        if (trailing != null)
            row.Children.Add(new TextBlock { Text = trailing, FontSize = 11, Opacity = 0.6 });
        stack.Children.Add(row);

        var bar = new ProgressBar
        {
            Value = util * 100,
            Maximum = 100,
            Height = 4,
        };
        stack.Children.Add(bar);
        return stack;
    }

    private static string Humanize(DateTimeOffset when)
    {
        var span = when - DateTimeOffset.Now;
        if (span.TotalDays >= 1) return $"in {(int)span.TotalDays}d {span.Hours}h";
        if (span.TotalHours >= 1) return $"in {(int)span.TotalHours}h {span.Minutes}m";
        if (span.TotalMinutes >= 1) return $"in {(int)span.TotalMinutes}m";
        return "soon";
    }

    private static bool SessionCookieStoreHasCookie(Account account)
        => Services.SessionCookieStore.Has(account.Kind);
}
