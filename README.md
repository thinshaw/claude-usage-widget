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

## Install

### Easy: download the DMG

1. Grab the latest `ClaudeWidget-x.y.z.dmg` from the [Releases](https://github.com/thinshaw/claude-usage-widget/releases) page
2. Open the DMG and drag `ClaudeWidget.app` onto the `Applications` shortcut
3. **First launch:** right-click `ClaudeWidget` in Applications → **Open** → confirm **Open** in the Gatekeeper dialog. (The app is ad-hoc signed — no paid Developer ID — so macOS asks once. After the first approval, normal double-click works.)

The sparkles icon should appear in your menu bar. From there, click it → **Settings…** to paste session cookies.

### From source

```bash
brew install xcodegen          # one-time
git clone https://github.com/thinshaw/claude-usage-widget.git
cd claude-usage-widget
./scripts/make-dmg.sh          # produces build/ClaudeWidget-x.y.z.dmg
open build/ClaudeWidget-*.dmg
```

Or skip the DMG and run directly out of the build folder:

```bash
xcodegen
xcodebuild -project ClaudeWidget.xcodeproj \
           -scheme ClaudeWidget \
           -configuration Release \
           -derivedDataPath build/ build
open build/Build/Products/Release/ClaudeWidget.app
```

## Setup — pasting your sessionKey cookie

The widget authenticates by borrowing the `sessionKey` cookie from your existing claude.ai login. No passwords, no API keys, no telemetry. The cookie is stored only in your macOS Keychain under service `com.tobyhinshaw.claudewidget`.

You'll do this **once per account** when you first install the widget, and **again whenever the cookie expires** (probably every 1–3 months). When that happens the widget will show a red `Session expired — re-paste your sessionKey cookie.` notice; just repeat these steps.

### Step-by-step (Safari)

> First time? Make sure the Develop menu is on:
> **Safari menu → Settings… → Advanced → ✅ "Show features for web developers"**

1. **Open https://claude.ai in Safari** and sign into the account you want to track. For your **second** account, do this in a Safari **Private** window (`File → New Private Window`) so the first account stays signed in too.

2. **Open Web Inspector**: press **⌥⌘I** (Option-Command-I), or `Develop menu → Show Web Inspector`.

3. **Click the Storage tab** at the top of the inspector. (Not Network. Not Console. **Storage**.)

4. In the left sidebar of the Storage tab, expand **Cookies** and click **`claude.ai`**.

5. You'll see a table of cookies. Find the row named **`sessionKey`** (sorting by Name column makes it easier). The value will be a very long string that starts with `sk-ant-sid02-…` and is about 110 characters long.

6. **Triple-click** the value to select the whole thing, then **⌘C** to copy.

7. Open ClaudeWidget → click the menu-bar sparkles icon → **Settings…** → **Accounts** tab.

8. Expand the section for the account (**Personal** or **Work**) you're configuring.

9. Paste into the **sessionKey value** field → click **Save**.

10. If the account has access to more than one Anthropic org (e.g. a personal claude.ai subscription plus an API Console org), an **Organization** dropdown will appear under that account once the cookie is saved. Pick whichever org you want this slot to track. You can swap later.

That's it. Within ~60 seconds you should see live numbers on the menu bar dropdown.

### Cheat sheet

```
Safari → claude.ai → log in
⌥⌘I → Storage tab → Cookies → claude.ai → sessionKey → copy value
ClaudeWidget menu → Settings → Accounts → paste → Save → pick org
```

### Troubleshooting

- **`Session expired — re-paste your sessionKey cookie.`** — your cookie aged out. Repeat the steps above. Same as the first install, just one slot at a time.
- **`No accessible organizations.`** — the cookie didn't reach claude.ai's auth check. Usually means you copied the cookie name instead of the value, or copied an old/expired cookie. Try again, making sure you're copying the long `sk-ant-sid02-…` value field, not the `sessionKey` name field.
- **Numbers are wrong / look like the other account's** — wrong org selected. Open Settings → Accounts → change the Organization dropdown for that slot.
- **No Storage tab in Web Inspector** — older Safari, or Web Inspector got swapped to a tab without that view. Try closing and reopening with ⌥⌘I.

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
