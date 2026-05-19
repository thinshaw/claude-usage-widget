using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using ClaudeWidget.Models;
using ClaudeWidget.ViewModels;

namespace ClaudeWidget.Views;

/// <summary>
/// Settings window — code-defined for now. The next Claude Code session on
/// Windows can swap to XAML in Visual Studio for nicer iteration. Two tabs:
/// General (theme picker) and Accounts (cookie + org picker per account).
/// </summary>
public sealed class SettingsWindow : Window
{
    private readonly AppState _state;

    public SettingsWindow(AppState state)
    {
        _state = state;
        Title = "Claude Usage — Settings";
        AppWindow.Resize(new Windows.Graphics.SizeInt32(560, 520));
        BuildContent();
    }

    private void BuildContent()
    {
        var pivot = new Pivot();
        pivot.Items.Add(BuildGeneralTab());
        pivot.Items.Add(BuildAccountsTab());
        Content = pivot;
    }

    private PivotItem BuildGeneralTab()
    {
        var tab = new PivotItem { Header = "General" };
        var stack = new StackPanel { Padding = new Thickness(16), Spacing = 12 };

        stack.Children.Add(new TextBlock
        {
            Text = "Theme",
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });
        var themeCombo = new ComboBox
        {
            ItemsSource = Enum.GetValues(typeof(Theme)),
            SelectedItem = _state.Theme,
            Width = 220,
        };
        themeCombo.SelectionChanged += (_, _) =>
        {
            if (themeCombo.SelectedItem is Theme t) _state.Theme = t;
        };
        stack.Children.Add(themeCombo);

        stack.Children.Add(new TextBlock
        {
            Text = "Refresh runs automatically every minute. The tray icon shows your peak utilization.",
            FontSize = 12,
            Opacity = 0.7,
        });

        var refresh = new Button { Content = "Refresh now" };
        refresh.Click += async (_, _) => await _state.RefreshAllAsync();
        stack.Children.Add(refresh);

        tab.Content = stack;
        return tab;
    }

    private PivotItem BuildAccountsTab()
    {
        var tab = new PivotItem { Header = "Accounts" };
        var stack = new StackPanel { Padding = new Thickness(16), Spacing = 16 };

        foreach (var account in _state.Accounts)
        {
            stack.Children.Add(BuildAccountRow(account));
        }

        stack.Children.Add(new TextBlock
        {
            Text = "Paste the sessionKey cookie from each account's claude.ai session. See README for the full step-by-step.",
            FontSize = 12,
            Opacity = 0.7,
            TextWrapping = TextWrapping.Wrap,
        });

        tab.Content = new ScrollViewer { Content = stack };
        return tab;
    }

    private UIElement BuildAccountRow(Account account)
    {
        var panel = new StackPanel { Spacing = 6 };

        panel.Children.Add(new TextBlock
        {
            Text = account.Kind.DisplayName(),
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            FontSize = 14
        });

        var cookieBox = new PasswordBox { PlaceholderText = "sk-ant-sid02-...", Width = 360 };
        var rowButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var saveBtn = new Button { Content = "Save" };
        saveBtn.Click += (_, _) =>
        {
            var v = cookieBox.Password?.Trim() ?? "";
            if (string.IsNullOrEmpty(v)) return;
            _state.SaveSessionCookie(account.Kind, v);
            cookieBox.Password = "";
        };
        var clearBtn = new Button { Content = "Clear" };
        clearBtn.Click += (_, _) => _state.ClearSessionCookie(account.Kind);
        rowButtons.Children.Add(saveBtn);
        rowButtons.Children.Add(clearBtn);

        var cookieRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        cookieRow.Children.Add(cookieBox);
        cookieRow.Children.Add(rowButtons);
        panel.Children.Add(cookieRow);

        if (account.AvailableOrgs.Count > 0)
        {
            panel.Children.Add(new TextBlock { Text = "Organization", FontSize = 12 });
            var combo = new ComboBox
            {
                Width = 360,
                ItemsSource = account.AvailableOrgs,
                DisplayMemberPath = nameof(Organization.Name),
                SelectedValuePath = nameof(Organization.Uuid),
                SelectedValue = account.SelectedOrgUuid,
            };
            combo.SelectionChanged += (_, _) =>
            {
                if (combo.SelectedValue is string uuid)
                    _state.SetSelectedOrg(account.Kind, uuid);
            };
            panel.Children.Add(combo);
        }

        return new Border
        {
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(12),
            Child = panel,
        };
    }
}
