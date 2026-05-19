using H.NotifyIcon;
using Microsoft.UI.Xaml;
using ClaudeWidget.ViewModels;
using ClaudeWidget.Views;

namespace ClaudeWidget;

public partial class App : Application
{
    public static AppState State { get; private set; } = null!;
    private TaskbarIcon? _trayIcon;
    private TrayPopupWindow? _popup;
    private SettingsWindow? _settings;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        State = new AppState();

        _trayIcon = new TaskbarIcon
        {
            ToolTipText = "Claude Usage",
            // App icon will be resolved from Assets/AppIcon.ico at build time.
            // If you re-skin, replace that file and rebuild.
        };
        _trayIcon.ForceCreate();

        // Left-click: toggle the dropdown popup
        _trayIcon.LeftClickCommand = new RelayCommand(_ => TogglePopup());
        _trayIcon.RightClickCommand = new RelayCommand(_ => ShowContextMenu());
    }

    public void TogglePopup()
    {
        if (_popup is null)
        {
            _popup = new TrayPopupWindow(State, OpenSettings);
        }
        _popup.ToggleVisibility();
    }

    public void OpenSettings()
    {
        if (_settings is null || _settings.AppWindow is null)
        {
            _settings = new SettingsWindow(State);
        }
        _settings.Activate();
    }

    public void ShowContextMenu()
    {
        // Minimum viable: just open settings on right click for now.
        // TODO (Windows session): proper context menu with Open / Settings / Quit.
        OpenSettings();
    }

    /// <summary>Tiny ICommand impl so we don't need a whole MVVM toolkit pull here.</summary>
    private sealed class RelayCommand : System.Windows.Input.ICommand
    {
        private readonly Action<object?> _action;
        public RelayCommand(Action<object?> action) => _action = action;
        public event EventHandler? CanExecuteChanged;
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => _action(parameter);
    }
}
