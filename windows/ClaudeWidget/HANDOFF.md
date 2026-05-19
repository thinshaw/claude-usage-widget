# HANDOFF — ClaudeWidget Windows port

You're (probably) a fresh Claude Code session starting up on Toby's Windows PC. This document is the only context you have about what this project is and how to continue it. Read it end-to-end before writing any code.

## What this is

`ClaudeWidget` is a native macOS menu-bar widget that shows live Claude.ai usage for up to two accounts (Personal + Work). The macOS version is shipped at v0.1.0 — repo: <https://github.com/thinshaw/claude-usage-widget>, source: `mac/ClaudeWidget/` … wait, no — *this repo* IS the ClaudeWidget repo. The macOS source is at the repo root (`Sources/`, `Resources/`, `project.yml`). This `windows/ClaudeWidget/` directory is a Windows port that was scaffolded on the Mac side and pushed but never compiled. **You're picking up the Windows port.**

This is a personal project for Toby, not Nucor work. Even though Toby works at Nucor and his Windows machine may be a managed Nucor laptop, the project doesn't follow Nucor's "Entra ID auth / Azure AI Foundry / brand kit" guidance — skip all that.

## Goal

Get the Windows port compiling, running, and producing real numbers from claude.ai, then package it as a portable .zip that Toby can share with teammates. Visual fidelity to the Mac version is nice but not critical — function over form.

## What's already here

Read every file under `windows/ClaudeWidget/`. Quick map:

- `ClaudeWidget.csproj` — WinUI 3 + .NET 8 project. Unpackaged (`<WindowsPackageType>None</WindowsPackageType>`). Targets x64 and ARM64. Self-contained build.
- `app.manifest` — DPI awareness, Windows 10/11 compat.
- `App.xaml` / `App.xaml.cs` — application entry. Creates `AppState`, the tray icon (H.NotifyIcon), the popup window, the settings window.
- `Models/Account.cs` — `AccountKind`, `Account`, `AccountUsage`, `UsageWindow`, `ExtraUsage`, `Organization`. Direct port of Swift models.
- `Models/Theme.cs` — Theme enum (Mica vs SciFi) and accent colors.
- `Services/SessionCookieStore.cs` — Per-account sessionKey storage in **Windows Credential Manager**. Targets stored under `ClaudeWidget:session-cookie:<kind>`.
- `Services/OrgIdStore.cs` — Per-account org UUID cache in `ApplicationData.LocalSettings`.
- `Services/ClaudeAIUsageProvider.cs` — **The critical HTTP layer.** Talks to `claude.ai/api/organizations` and `claude.ai/api/organizations/{uuid}/usage`. Read the comments inside carefully; there are several non-obvious things that took the macOS version many iterations to discover.
- `ViewModels/AppState.cs` — Holds accounts + theme + refresh timer. Mirrors the Swift `AppState`.
- `Views/TrayPopupWindow.cs` — The dropdown shown when you click the tray icon. **Code-defined UI** (not XAML), minimal layout. Likely needs polish.
- `Views/SettingsWindow.cs` — Settings window with General (theme) and Accounts (cookie + org picker) tabs. Also code-defined UI.

There is **no `Assets/AppIcon.ico`** yet — you'll need to generate one or copy from the Mac project. The Mac one is at `../../Resources/AppIcon.icns` (which won't work directly on Windows; ICO format needed).

## Endpoint details — DO NOT REDISCOVER

The macOS version went through many iterations to figure these out. Don't repeat the work. Just verify the C# implementation matches.

### Auth

- Cookie name: **`sessionKey`** (case-sensitive). The cookie value starts with `sk-ant-sid02-` and is ~110 chars long.
- Get it from claude.ai → Safari/Chrome Web Inspector → Storage → Cookies → `claude.ai` → `sessionKey` → copy value.
- Stored in Windows Credential Manager (not in plaintext on disk).

### Endpoints

```
GET https://claude.ai/api/organizations           — returns array of orgs (uuid, name, ...)
GET https://claude.ai/api/organizations/{uuid}/usage  — returns usage JSON
```

### Required headers (lessons learned)

```
Cookie: sessionKey=<value>
anthropic-client-platform: web_claude_ai
Origin: https://claude.ai
Referer: https://claude.ai/settings/usage
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) ...Chrome/130...
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: same-origin
Accept: */*
```

**Do NOT send `Content-Type: application/json` on GETs.** It triggers Cloudflare WAF rules and increases 401 rate.

### Cookie isolation — load-bearing

`HttpClientHandler.UseCookies` **must be `false`**. Otherwise `HttpClient` will silently merge cookies from previous responses across requests, and a second account's request will inherit the first account's sessionKey. Both accounts then resolve to the same org. This is the same bug we hit on macOS. See `ClaudeAIUsageProvider.cs` line ~30.

### Response shape

```json
{
  "five_hour":        null | { "utilization": 0..100, "resets_at": "ISO8601" },
  "seven_day":        null | { ... },
  "seven_day_opus":   null | { ... },
  "seven_day_sonnet": null | { ... },
  "extra_usage": {
    "is_enabled":     true,
    "monthly_limit":  27500,    // CENTS — divide by 100 for dollars
    "used_credits":   22149.0,  // CENTS
    "utilization":    80.54,    // 0..100 (percent)
    "currency":       "USD",
    "disabled_reason": null
  }
}
```

- `utilization` arrives as a **percentage 0..100**. The parser normalizes to 0..1.
- `monthly_limit` and `used_credits` are in **cents**. `27500` = `$275.00`. Divide by 100 before display.
- All time-window fields can be `null`. An account with only `extra_usage` populated and all windows null is a valid state (typically an Anthropic Console org rather than a Pro/Max subscription).

### Org auto-pick

A single cookie can have access to multiple orgs (e.g. a Pro subscription + an Anthropic Console org). The right one for a given slot is user-chosen via the Settings → Accounts org picker. If no selection exists, the provider iterates orgs and uses the first one whose `/usage` endpoint returns 200.

## Build & run

You need:
- **Visual Studio 2022** (Community is fine), with workloads:
  - .NET desktop development
  - Windows App SDK C# templates
- **Windows 10 19041 / Windows 11 SDK** installed via VS Installer
- Internet for first-time NuGet restore

Steps:

```powershell
cd C:\path\to\claude-usage-widget\windows\ClaudeWidget
dotnet restore
dotnet build -c Debug
dotnet run -c Debug
```

Or open `ClaudeWidget.csproj` in Visual Studio, set it as the startup project, and hit F5.

**Expected first-compile issues** (these are not bugs in the code, they're things you may need to fix because I scaffolded this on a Mac and couldn't compile):

1. **Package versions** in `ClaudeWidget.csproj` may need bumping. If `dotnet restore` complains about a version that no longer exists, replace with the latest stable. Critical packages:
   - `Microsoft.WindowsAppSDK` (>= 1.5)
   - `H.NotifyIcon.WinUI` (>= 2.0)
   - `CommunityToolkit.Mvvm` (>= 8.0)
   - `CredentialManagement` (1.0.2 — small wrapper around Win32 wincred, may need to swap for a different package if this one's abandoned)

2. **`Microsoft.UI.Xaml.Controls` import in `App.xaml`** — if the `XamlControlsResources` element fails to resolve, you may need a different namespace prefix. WinUI 3 templates usually generate the right thing; check what a fresh `dotnet new winui3` template uses.

3. **`OverlappedPresenter.SetBorderAndTitleBar`** in `TrayPopupWindow.cs` — API name may differ across SDK versions. If it doesn't resolve, look for `SetTitleBar` / `SetBorder` separately.

4. **The icon** — `App.xaml.cs` creates a `TaskbarIcon` but doesn't load an actual icon resource. You need to generate `Assets/AppIcon.ico` (16/32/48/256 px) and reference it. ImageMagick can do this: `magick Mac-icon-512.png -define icon:auto-resize=256,128,64,48,32,16 AppIcon.ico`.

5. **`Application.Current.Exit()`** in the popup's Quit handler may not exist on `Microsoft.UI.Xaml.Application` — check the actual API.

If any of those fail, **fix and continue**, don't roll back the architecture.

## What still needs UI work

The popup and settings windows are intentionally minimal — I built them code-first so the next session (you) can iterate in the Visual Studio designer. Suggested polish:

- Replace plain `Border` containers with Mica-backdrop'd panels for the macOS Liquid Glass parity
- Wire up the Sci-Fi theme — cyan accents on dark background, similar to the macOS sci-fi theme (see `mac/Sources/Theme.swift` for reference)
- Make the popup auto-close when it loses focus (currently it stays open)
- The tray icon's right-click context menu is a stub — wire up proper menu with "Open" / "Settings" / "Refresh" / "Quit"
- Tray icon label / tooltip should update with the live percentage like the macOS menu bar does

## Packaging for distribution

Toby wants a clean install for teammates. Target:

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false
```

That produces a folder under `bin/Release/net8.0-windows10.0.19041.0/win-x64/publish/`. Zip the contents, rename to `ClaudeWidget-<version>-win-x64.zip`, and that's the artifact.

**First-launch friction on receivers' machines:**

- **SmartScreen warning** — unsigned executables show "Windows protected your PC". Recipients need to click "More info" → "Run anyway". This is the Windows equivalent of macOS Gatekeeper's right-click → Open dance. Document it in `windows/ClaudeWidget/README.md`.
- **Nucor managed laptops** may block this entirely via Group Policy / AppLocker. If Toby reports the .zip approach doesn't work for his team, the next step is **MSIX packaging with code signing**. That requires either an EV cert (~$300/yr) or getting the IT team to add a self-signed cert to the company's trusted publisher list. Don't go down that road until you confirm the simple path doesn't work.

## Once it works, do the GitHub release

The macOS release is at <https://github.com/thinshaw/claude-usage-widget/releases/tag/v0.1.0>. The Windows build should ship as **v0.2.0** (or whatever you choose) with the Windows .zip attached. Use the same pattern:

```powershell
gh release create v0.2.0 path\to\ClaudeWidget-0.2.0-win-x64.zip --title "v0.2.0 — Windows support" --notes "First Windows build..."
```

Update the **root README.md** with download / install instructions for both platforms.

## Tone / approach notes for the agent

Toby's pattern across this project:
- Direct, terse responses preferred
- Wants UI seen in browser/app before declaring done
- Doesn't want trailing summaries explaining what you just did
- Doesn't want comments in code explaining the obvious; only WHY-comments when behavior is non-obvious
- Uses `/loop` for waits; uses the advisor tool when stuck or before substantive work
- Has occasionally typed commands with typos — be helpful, give exact copy-paste-ready strings rather than abstract instructions

When you're done with a meaningful milestone (it compiles / it shows real numbers / the .zip is built), pause and tell Toby. Don't run away with the keyboard.

Good luck.
