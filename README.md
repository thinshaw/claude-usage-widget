# Claude Usage Widget

A native macOS menu-bar app that surfaces your Claude usage for up to two accounts (personal + work) side-by-side. Built because flipping between the desktop app and a private window just to check "how much do I have left?" got old.

Lives in the menu bar. No Dock icon, no main window. Click the sparkles icon to see your current 5-hour and 7-day windows, optional Opus/Sonnet sub-limits, and extra-usage credits if you have them enabled.

## Features

- **Two-account support** — track personal and work claude.ai accounts side-by-side, each with its own session cookie stored in Keychain
- **Same numbers as the desktop app** — pulls live data from the same `claude.ai/api/organizations/{uuid}/usage` endpoint Settings → Usage uses
- **Two themes** —
  - **Liquid Glass** uses macOS 26 Tahoe's native `.glassEffect()` and follows system light/dark
  - **Sci-Fi** dark panel with cyan accents and a faint scan-line overlay
- **Auto-refresh every 60 seconds**, or hit the refresh button for an immediate poll
- **Per-window utilization bars** — 5-hour, 7-day, Opus 7-day, Sonnet 7-day, and Extra Usage credits
- **Background-only** — `LSUIElement: true`, no Dock icon, no main window. Quit from the menu

## Requirements

- macOS 14.0+ (Liquid Glass effects on macOS 26+, gracefully falls back to `.ultraThinMaterial` below that)
- A claude.ai Pro or Max subscription on each account you want to track
- Xcode 16+ and [xcodegen](https://github.com/yonaskolb/XcodeGen) to build from source

## Build & install

```bash
brew install xcodegen          # one-time
cd ClaudeWidget
xcodegen                       # regenerates ClaudeWidget.xcodeproj
xcodebuild -project ClaudeWidget.xcodeproj \
           -scheme ClaudeWidget \
           -configuration Release \
           -derivedDataPath build/ build
cp -R build/Build/Products/Release/ClaudeWidget.app /Applications/
open /Applications/ClaudeWidget.app
```

The sparkles icon should appear in your menu bar.

## Setup — pasting session cookies

The widget authenticates by reusing the `sessionKey` cookie from your existing claude.ai login. It does not store your password, does not touch the desktop app's storage, and does not phone home.

For each account:

1. Open https://claude.ai in Safari and log in
2. Press **Cmd+Option+I** to open Web Inspector
3. Click the **Storage** tab → **Cookies → claude.ai**
4. Find the row named `sessionKey` and copy its value (the long `sk-ant-sid02-…` string)
5. Open the widget → Settings → **Accounts** → expand Personal (or Work)
6. Paste into the sessionKey field → **Save**

The widget will auto-discover your org UUID via `/api/organizations` and start polling. The cookie is stored in the macOS Keychain under service `com.tobyhinshaw.claudewidget`.

For your second account, log into it in a Safari private window (so the first account stays logged in elsewhere), repeat steps 2–4, and paste into the Work slot in the widget.

## How it works

When you save a cookie, the widget:

1. **Calls `GET https://claude.ai/api/organizations`** with `Cookie: sessionKey=…` to discover your org UUID
2. **Caches the UUID** in `UserDefaults` keyed by account
3. **Polls `GET /api/organizations/{uuid}/usage`** every 60 seconds and on demand
4. **Parses** the response into utilization windows (5-hour, 7-day, Opus 7-day, Sonnet 7-day) plus optional extra-usage credits

The response shape (real, captured 2026-05-19):

```json
{
  "five_hour":           { "utilization": 0..100, "resets_at": "ISO8601" } | null,
  "seven_day":           { "utilization": 0..100, "resets_at": "ISO8601" } | null,
  "seven_day_opus":      { "utilization": 0..100, "resets_at": "ISO8601" } | null,
  "seven_day_sonnet":    { "utilization": 0..100, "resets_at": "ISO8601" } | null,
  "extra_usage": {
    "is_enabled": true,
    "monthly_limit": 275.0,
    "used_credits": 221.49,
    "utilization": 80.54,
    "currency": "USD",
    "disabled_reason": null
  }
}
```

`utilization` arrives as a percentage (0–100); the app normalizes it to 0–1 for the progress bars.

## Caveats

- **`/api/organizations/{uuid}/usage` is not a documented public API.** It's the same endpoint the official Claude desktop app uses, but Anthropic could change or remove it at any time. If that happens, the widget will surface an error and you'll need to re-sniff the new endpoint (see `ClaudeAIUsageProvider.swift`).
- **Session cookies expire.** When a `sessionKey` expires, the widget shows "Session expired — re-paste your sessionKey cookie." Repeat the cookie-paste flow to refresh.
- **Two-account ceiling is hard-coded.** Adding more slots is a small change in `AccountKind` + `AppState.accounts`, but the UI assumes two for now.
- **Org-switching is not exposed.** The widget picks the first org returned by `/api/organizations` per cookie. If you're a member of multiple orgs on the same login and want to switch, clear the cookie and re-save (org cache is wiped on clear).

## Privacy

- Session cookies live in the macOS Keychain under `com.tobyhinshaw.claudewidget`. Nothing is stored in plaintext on disk.
- All network requests go directly to `claude.ai`. No telemetry, no analytics, no third-party services.
- The widget never sees your Anthropic password or any API keys.
- If you uninstall, run `security delete-generic-password -s com.tobyhinshaw.claudewidget` to remove the Keychain entries (or just leave them — they're harmless).

## Source layout

```
ClaudeWidget/
├── project.yml                          # xcodegen config (generates the .xcodeproj)
├── Sources/
│   ├── ClaudeWidgetApp.swift            # @main, MenuBarExtra + Settings scene
│   ├── AppState.swift                   # ObservableObject — accounts, theme, refresh loop
│   ├── Account.swift                    # AccountKind, AccountUsage, UsageWindow, ExtraUsage
│   ├── Theme.swift                      # Liquid Glass + Sci-Fi backgrounds and accents
│   ├── UsageProvider.swift              # Protocol + MockUsageProvider
│   ├── ClaudeAIUsageProvider.swift      # Real provider: claude.ai endpoints
│   ├── SessionCookieStore.swift         # Keychain wrapper for sessionKey
│   ├── OrgIDStore.swift                 # UserDefaults cache for org UUID per account
│   ├── MenuBarContent.swift             # Dropdown UI (AccountCard, UsageWindowRow, etc.)
│   └── SettingsView.swift               # Settings window (General / Accounts / About)
└── Resources/                           # (App icon placeholder — drop AppIcon.icns here)
```

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

Built side-by-side with [Claude Code](https://claude.com/claude-code). The Liquid Glass theme uses macOS 26's `.glassEffect()` API.
