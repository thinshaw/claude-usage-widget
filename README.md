# Claude Usage Widget

A native menu-bar / system-tray app that surfaces your Claude usage for up to two accounts (personal + work) side-by-side. Built because flipping between the desktop app and a private window just to check "how much do I have left?" got old.

## Platforms

| | macOS | Windows |
|---|---|---|
| **Status** | Shipped (v0.1.0) | In progress — scaffold complete, awaiting iteration on Windows |
| **Source** | `Sources/`, `Resources/`, `project.yml` (repo root) | [`windows/ClaudeWidget/`](windows/ClaudeWidget/) |
| **Install** | [DMG from Releases](https://github.com/thinshaw/claude-usage-widget/releases) → drag to Applications | Portable .zip (coming) |
| **Requires** | macOS 14+ (Liquid Glass on macOS 26+) | Windows 10 1809+ / Windows 11 |

The rest of this README documents the **macOS** version. Windows-specific notes are in [`windows/ClaudeWidget/README.md`](windows/ClaudeWidget/README.md).

Lives in the menu bar. No Dock icon, no main window. Click the sparkles icon to see your current 5-hour and 7-day windows, optional Opus/Sonnet sub-limits, and extra-usage credits if you have them enabled.

## Features

- **Two-account support** — track personal and work claude.ai accounts side-by-side, each with its own session cookie stored locally on disk (user-only readable)
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

## Setup — how to paste the cookie (read me when the widget says "Session expired")

You'll do this once per account at first install, and again any time the widget shows a red `Session expired — re-paste your sessionKey cookie.` notice. Just follow the steps. Don't think.

### One-time only (you've probably already done this)

Open Safari. Click the **Safari** menu (top-left) → **Settings…** → **Advanced** tab → check the box that says **"Show features for web developers"**. Close Settings. That puts a **Develop** menu in Safari's menu bar. You only need to do this once, ever.

### Every time you need to paste a cookie

Do these steps **one account at a time**. Don't try to do Personal and Work in the same Safari window — they'll fight each other.

**1.** Open Safari.

**2.** Go to **https://claude.ai** and sign in with the account you want to update.

> Doing your **second** account? Open a **Private** window first (`File` menu → `New Private Window`), then go to claude.ai in that window. Sign into the second account there. This keeps the first account signed in elsewhere.

**3.** Once you're signed in and you can see your chats, press these three keys at the same time:

```
⌥  +  ⌘  +  I
```

(That's Option, Command, and the letter I.) A panel will open on the right or bottom — that's Web Inspector.

**4.** At the very top of the Web Inspector panel, you'll see a row of tabs: *Elements*, *Network*, *Sources*, *Storage*, etc. Click **Storage**.

**5.** On the left side of the Storage panel, find the **Cookies** section. Click the little triangle next to it to expand it. Underneath, click the line that says **`claude.ai`**.

**6.** A big table appears with one cookie per row. Look at the **Name** column. Find the row whose Name is exactly **`sessionKey`** (not `sessionKeyLC`, just `sessionKey`).

**7.** Look at the **Value** column for that row. It's a long ugly string that looks like:

```
sk-ant-sid02-m1hrec...wwnNj4FE5m1APdNHhGfBA-u-x7dQAA
```

(yours will be different, but the start `sk-ant-sid02-` is the same).

**8.** Click anywhere on that Value cell. Press **⌘A** to select everything, then **⌘C** to copy it.

> If `⌘A` doesn't grab it, try **triple-clicking** the value to select the whole line, then **⌘C**.

**9.** In your menu bar (top-right of your screen), click the orange **sparkle icon** for ClaudeWidget. A dropdown appears. At the bottom of the dropdown, click **Settings…**.

**10.** In the Settings window, click the **Accounts** tab.

**11.** Find the account you're updating (**Personal** or **Work**). Click in the **sessionKey value** field next to it. Press **⌘V** to paste.

**12.** Click **Save**.

**13.** Wait about 5 seconds. If an **Organization** dropdown appears under that account, pick the right one:
   - **Personal slot** → pick the org named after you, or the one whose name you recognize as your personal claude.ai account
   - **Work slot** → pick the org with the API Console / extra-usage budget on it

**14.** Close the Settings window. Click the sparkle icon in the menu bar. The numbers for that account should now be real (not stale or red).

### If something goes wrong

| What the widget shows | What it means | What to do |
|---|---|---|
| `Session expired — re-paste your sessionKey cookie.` | Cookie aged out | Redo steps 1–14 for that account |
| `No accessible organizations.` | You copied the cookie name instead of its value, OR the cookie is already dead | Repeat step 7 carefully — copy the long `sk-ant-sid02-…` string, not the word `sessionKey` |
| Both accounts show identical numbers | Wrong org selected on one of them | Settings → Accounts → change the **Organization** dropdown |
| The Storage tab isn't there | Inspector got into a weird state | Close inspector, press ⌥⌘I again |
| Sparkle icon is gone from menu bar | The app got quit | `open /Applications/ClaudeWidget.app` from Terminal, or find it in Spotlight |

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

- Session cookies live in `~/Library/Application Support/ClaudeWidget/credentials.json` with file permissions `0600` (only your user can read it). On a File-Vault'd Mac the file is also encrypted at rest by the OS.
- All network requests go directly to `claude.ai`. No telemetry, no analytics, no third-party services.
- The widget never sees your Anthropic password or any API keys.
- To uninstall completely: trash `/Applications/ClaudeWidget.app` and `rm -rf "$HOME/Library/Application Support/ClaudeWidget/"`.
- Earlier versions stored cookies in the macOS Keychain. They migrate automatically on first launch of v0.1.1+ and the old Keychain entries are removed.

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
│   ├── SessionCookieStore.swift         # File-backed sessionKey storage (Keychain migration baked in)
│   ├── OrgIDStore.swift                 # UserDefaults cache for org UUID per account
│   ├── MenuBarContent.swift             # Dropdown UI (AccountCard, UsageWindowRow, etc.)
│   └── SettingsView.swift               # Settings window (General / Accounts / About)
└── Resources/                           # (App icon placeholder — drop AppIcon.icns here)
```

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

Built side-by-side with [Claude Code](https://claude.com/claude-code). The Liquid Glass theme uses macOS 26's `.glassEffect()` API.
