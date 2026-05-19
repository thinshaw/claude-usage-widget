import SwiftUI

@main
struct ClaudeWidgetApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
                .preferredColorScheme(state.theme.preferredColorScheme)
        } label: {
            MenuBarLabel()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(state.theme.preferredColorScheme)
        }
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
            if let pct = state.combinedRemainingPercent {
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}
