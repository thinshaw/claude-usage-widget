using Windows.UI;

namespace ClaudeWidget.Models;

public enum Theme { Mica, SciFi }

public static class ThemeExtensions
{
    public static string DisplayName(this Theme t) => t switch
    {
        Theme.Mica   => "Mica (Windows 11)",
        Theme.SciFi  => "Sci-Fi",
        _ => "Unknown"
    };

    /// <summary>Accent color (Claude orange / cyan).</summary>
    public static Color Accent(this Theme t) => t switch
    {
        Theme.Mica  => Color.FromArgb(0xFF, 0xF0, 0x8C, 0x57),
        Theme.SciFi => Color.FromArgb(0xFF, 0x33, 0xF2, 0xD8),
        _ => Color.FromArgb(0xFF, 0xF0, 0x8C, 0x57)
    };

    public static Color SecondaryAccent(this Theme t) => t switch
    {
        Theme.Mica  => Color.FromArgb(0xFF, 0x73, 0x5F, 0xF2),
        Theme.SciFi => Color.FromArgb(0xFF, 0xF2, 0x4D, 0x8C),
        _ => Color.FromArgb(0xFF, 0x73, 0x5F, 0xF2)
    };
}
