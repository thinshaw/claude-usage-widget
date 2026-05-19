import SwiftUI

enum Theme: String, CaseIterable, Identifiable, Codable {
    case liquidGlass
    case sciFi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .sciFi:       return "Sci-Fi"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .liquidGlass: return nil  // follow system
        case .sciFi:       return .dark
        }
    }

    var accent: Color {
        switch self {
        case .liquidGlass: return Color(red: 0.94, green: 0.55, blue: 0.34) // Claude orange
        case .sciFi:       return Color(red: 0.20, green: 0.95, blue: 0.85) // cyan glow
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .liquidGlass: return Color(red: 0.55, green: 0.45, blue: 0.95)
        case .sciFi:       return Color(red: 0.95, green: 0.30, blue: 0.55)
        }
    }

    var monoFont: Font {
        switch self {
        case .liquidGlass: return .system(size: 12, weight: .medium, design: .rounded).monospacedDigit()
        case .sciFi:       return .system(size: 12, weight: .semibold, design: .monospaced).monospacedDigit()
        }
    }

    var titleFont: Font {
        switch self {
        case .liquidGlass: return .system(size: 14, weight: .semibold, design: .rounded)
        case .sciFi:       return .system(size: 13, weight: .bold, design: .monospaced)
        }
    }
}

struct ThemedPanelBackground: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        switch theme {
        case .liquidGlass:
            content.modifier(LiquidGlassBackground())
        case .sciFi:
            content.modifier(SciFiBackground())
        }
    }
}

private struct LiquidGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.5), .white.opacity(0.1), .clear],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
        }
    }
}

private struct SciFiBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.04, green: 0.07, blue: 0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.20, green: 0.95, blue: 0.85).opacity(0.7),
                                        Color(red: 0.20, green: 0.95, blue: 0.85).opacity(0.15)
                                    ],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .overlay {
                        // scan-line texture
                        GeometryReader { geo in
                            Path { path in
                                let step: CGFloat = 3
                                var y: CGFloat = 0
                                while y < geo.size.height {
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                                    y += step
                                }
                            }
                            .stroke(Color(red: 0.20, green: 0.95, blue: 0.85).opacity(0.04), lineWidth: 1)
                        }
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
            }
    }
}

extension View {
    func themedPanel(_ theme: Theme) -> some View {
        modifier(ThemedPanelBackground(theme: theme))
    }
}
