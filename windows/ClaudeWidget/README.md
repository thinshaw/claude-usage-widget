# ClaudeWidget for Windows

The Windows port of the macOS Claude Usage Widget. System-tray app that shows live Claude.ai usage for up to two accounts (Personal + Work).

> **Status:** under active development. The Mac version is shipped and stable; this Windows version was scaffolded on macOS and is awaiting iteration on a real Windows machine. The data layer is complete; the UI is minimal. See [`HANDOFF.md`](HANDOFF.md) for build instructions.

## Install (once builds are released)

1. Download `ClaudeWidget-<version>-win-x64.zip` from [Releases](https://github.com/thinshaw/claude-usage-widget/releases)
2. Extract somewhere — `C:\Tools\ClaudeWidget\` is fine
3. Double-click `ClaudeWidget.exe`
4. **First launch:** Windows SmartScreen will show "Windows protected your PC." Click **More info** → **Run anyway**. This is normal for unsigned apps and only happens the first time.
5. Look for the sparkle icon in your system tray (bottom-right of taskbar). Right-click → Settings to paste your claude.ai sessionKey cookies.

## Setup (sessionKey cookies)

Same as the macOS version. Detailed instructions are in the [main README](../../README.md#setup--how-to-paste-the-cookie-read-me-when-the-widget-says-session-expired). Quick version:

1. Open https://claude.ai in your browser, sign in
2. **Ctrl+Shift+I** to open Dev Tools → **Application** tab (Chrome/Edge) or **Storage** tab (Safari) → **Cookies → claude.ai**
3. Find `sessionKey` → copy its value (long `sk-ant-sid02-…` string)
4. ClaudeWidget tray icon → right-click → **Settings** → **Accounts** → paste under Personal (or Work) → **Save**

If you have access to multiple Anthropic orgs on a single login, a dropdown appears after saving — pick which org each slot tracks.

## What needs re-pasting and when

Session cookies expire eventually — probably every 1–3 months per account. When that happens the widget shows a red `Session expired — re-paste your sessionKey cookie.` notice. Repeat the steps above for that account.

## Building from source

See [`HANDOFF.md`](HANDOFF.md). Short version:

```powershell
# Need Visual Studio 2022 with "Windows App SDK C# templates" workload
cd windows\ClaudeWidget
dotnet restore
dotnet build -c Debug
dotnet run -c Debug
```

To package a portable .zip for sharing:

```powershell
dotnet publish -c Release -r win-x64 --self-contained true
# Zip the contents of bin\Release\net8.0-windows10.0.19041.0\win-x64\publish\
```

## Differences from the macOS version

| | macOS | Windows |
|---|---|---|
| UI framework | SwiftUI | WinUI 3 + .NET 8 |
| Tray / menu bar | `MenuBarExtra` | `H.NotifyIcon` (system tray) |
| Cookie storage | Keychain | Credential Manager |
| Settings storage | `UserDefaults` | `LocalSettings` |
| "Liquid Glass" theme | `.glassEffect()` (macOS 26) | Mica backdrop (Windows 11+) |
| "Sci-Fi" theme | Custom drawing | Custom drawing |
| Install | DMG + drag to Applications | Portable .zip extract |
| First-launch warning | Gatekeeper → right-click Open | SmartScreen → More info → Run anyway |

Data layer (HTTP, cookie auth, parser, refresh loop) is identical — same endpoints, same shape, same gotchas.
