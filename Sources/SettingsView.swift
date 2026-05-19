import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            AccountsTab().tabItem { Label("Accounts", systemImage: "person.2") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 380)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $state.theme) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Refresh") {
                Button {
                    Task { await state.refreshAll() }
                } label: {
                    Label("Refresh usage now", systemImage: "arrow.clockwise")
                }
                Text("Usage refreshes automatically every minute while the app is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct AccountsTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            ForEach($state.accounts) { $account in
                AccountRow(account: $account)
            }
            Section {
                Text("Paste the sessionKey cookie from each account's claude.ai session. Get it from Safari → Web Inspector → Storage → Cookies → claude.ai → sessionKey (it's a long base64 string). Cookies are stored in your macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct AccountRow: View {
    @EnvironmentObject var state: AppState
    @Binding var account: Account
    @State private var cookieDraft: String = ""
    @State private var message: String?
    @State private var messageIsError: Bool = false

    var body: some View {
        Section(account.kind.displayName) {
            Toggle("Enabled", isOn: $account.isConfigured)
            TextField("Label", text: $account.label)
                .disabled(!account.isConfigured)

            HStack(spacing: 8) {
                SecureField(
                    state.hasSessionCookie(for: account.kind) ? "•••••••• (saved)" : "sessionKey value",
                    text: $cookieDraft
                )
                .textFieldStyle(.roundedBorder)
                .disabled(!account.isConfigured)

                Button("Save") { save() }
                    .disabled(!account.isConfigured || cookieDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Clear") { clear() }
                    .disabled(!state.hasSessionCookie(for: account.kind))
            }

            if let msg = message {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(messageIsError ? .red : .secondary)
            }

            if let usage = account.usage {
                LabeledContent("Plan", value: usage.planLabel)
                if let primary = usage.primaryWindow {
                    LabeledContent(primary.label) {
                        Text("\(Int(round(primary.utilization * 100)))% used")
                            .monospacedDigit()
                    }
                }
                if let extra = usage.extra, extra.isEnabled {
                    LabeledContent("Extra usage") {
                        Text("\(Int(round(extra.utilization * 100)))% of $\(Int(extra.monthlyLimit))")
                            .monospacedDigit()
                    }
                }
            } else if account.isConfigured && !state.hasSessionCookie(for: account.kind) {
                Text("Showing mock data — paste a sessionKey cookie to fetch live usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if account.isConfigured {
                Text("Waiting for first refresh…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let trimmed = cookieDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if state.saveSessionCookie(trimmed, for: account.kind) {
            cookieDraft = ""
            message = "Saved. Refreshing usage…"
            messageIsError = false
        } else {
            message = "Failed to save to Keychain."
            messageIsError = true
        }
    }

    private func clear() {
        _ = state.clearSessionCookie(for: account.kind)
        cookieDraft = ""
        message = "Cookie removed."
        messageIsError = false
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Widget")
                .font(.title3.weight(.semibold))
            Text("Version 0.1.0")
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            Text("A menu-bar companion that surfaces your Claude usage for up to two accounts. Lives in the system menu — no Dock icon.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
