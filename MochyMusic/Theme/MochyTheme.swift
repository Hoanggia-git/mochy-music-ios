import SwiftUI

// MARK: - Hex Color Initializers

extension Color {
    /// Initialize a `Color` from a 24-bit RGB hex integer (e.g. `0x1e1e2e`).
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Initialize a `Color` from a CSS-style hex string (`#RRGGBB` or `RRGGBB`).
    init(hexString: String, alpha: Double = 1.0) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(hex: UInt32(value & 0xFFFFFF), alpha: alpha)
    }
}

// MARK: - Mochy Theme Color Palette (AMOLED Dark + Catppuccin Mocha)

extension Color {
    // True Mochy Music AMOLED Dark Palette (from Android Theme.kt)
    static let mochyBackground = Color(hex: 0x000000)
    static let mochySurface = Color(hex: 0x0D0D0D)
    static let mochySurfaceVariant = Color(hex: 0x1A1A1A)
    static let mochyPrimary = Color(hex: 0xE0E0E0)
    static let mochySecondary = Color(hex: 0xB0B0B0)
    static let mochyPrimaryContainer = Color(hex: 0x333333)
    static let mochySecondaryContainer = Color(hex: 0x2C2C2C)
    static let mochyOnBackground = Color(hex: 0xFFFFFF)
    static let mochyOnSurface = Color(hex: 0xFFFFFF)

    // Catppuccin Mocha Base & Surfaces
    static let mochyBase = Color(hex: 0x1e1e2e)
    static let mochyMantle = Color(hex: 0x181825)
    static let mochyCrust = Color(hex: 0x11111b)
    static let mochySurface0 = Color(hex: 0x313244)
    static let mochySurface1 = Color(hex: 0x45475a)
    static let mochySurface2 = Color(hex: 0x585b70)

    // Catppuccin Mocha Overlays
    static let mochyOverlay0 = Color(hex: 0x6c7086)
    static let mochyOverlay1 = Color(hex: 0x7f849c)
    static let mochyOverlay2 = Color(hex: 0x9399b2)

    // Catppuccin Mocha Typography
    static let mochyText = Color(hex: 0xcdd6f4)
    static let mochySubtext1 = Color(hex: 0xbac2de)
    static let mochySubtext0 = Color(hex: 0xa6adc8)

    // Catppuccin Mocha Accents
    static let mochyPeach = Color(hex: 0xfab387)
    static let mochyMauve = Color(hex: 0xcba6f7)
    static let mochyBlue = Color(hex: 0x89b4fa)
    static let mochyGreen = Color(hex: 0xa6e3a1)
    static let mochyRed = Color(hex: 0xf38ba8)
    static let mochyYellow = Color(hex: 0xf9e2af)
    static let mochyPink = Color(hex: 0xf5c2e7)
    static let mochyTeal = Color(hex: 0x94e2d5)
    static let mochyLavender = Color(hex: 0xb4befe)
    static let mochySky = Color(hex: 0x89dcfe)
    static let mochySapphire = Color(hex: 0x74c7ec)
    static let mochyMaroon = Color(hex: 0xeba0ac)
    static let mochyFlamingo = Color(hex: 0xf2cdcd)
    static let mochyRosewater = Color(hex: 0xf5e0dc)

    /// Active background honoring Pure Black AMOLED toggle.
    static var mochyEffectiveBackground: Color {
        AppSettings.shared.pureBlack ? .mochyBackground : .mochyBase
    }

    /// Active card/surface color honoring Pure Black AMOLED toggle.
    static var mochyEffectiveSurface: Color {
        AppSettings.shared.pureBlack ? .mochySurfaceVariant : .mochySurface0
    }
}

// MARK: - Typography & Layout Tokens

enum MochyTheme {
    static let cornerRadiusSmall: CGFloat = 10
    static let cornerRadiusMedium: CGFloat = 14
    static let cornerRadiusLarge: CGFloat = 18
    static let cardPadding: CGFloat = 14
    static let screenHorizontalPadding: CGFloat = 16
    static let miniPlayerHeight: CGFloat = 64
    static let tabBarHeight: CGFloat = 58

    static var springAnimation: Animation {
        let speed = max(0.25, AppSettings.shared.animationSpeed)
        return .spring(response: 0.38 / speed, dampingFraction: 0.82)
    }

    static var snappySpring: Animation {
        let speed = max(0.25, AppSettings.shared.animationSpeed)
        return .spring(response: 0.28 / speed, dampingFraction: 0.86)
    }

    // Custom Font Styles
    static func titleFont(size: CGFloat = 26) -> Font {
        .system(size: size * AppSettings.shared.fontSizePreset.scale, weight: .bold, design: .rounded)
    }

    static func headlineFont(size: CGFloat = 18) -> Font {
        .system(size: size * AppSettings.shared.fontSizePreset.scale, weight: .semibold, design: .rounded)
    }

    static func bodyFont(size: CGFloat = 15) -> Font {
        .system(size: size * AppSettings.shared.fontSizePreset.scale, weight: .regular, design: .default)
    }

    static func captionFont(size: CGFloat = 12) -> Font {
        .system(size: size * AppSettings.shared.fontSizePreset.scale, weight: .medium, design: .default)
    }
}

extension Font {
    static var mochyTitle: Font { MochyTheme.titleFont() }
    static var mochyHeadline: Font { MochyTheme.headlineFont() }
    static var mochySubheadline: Font { MochyTheme.bodyFont(size: 16).weight(.medium) }
    static var mochyBody: Font { MochyTheme.bodyFont() }
    static var mochyCaption: Font { MochyTheme.captionFont() }
    static var mochyMono: Font { .system(size: 12, weight: .medium, design: .monospaced) }
}

// MARK: - Reusable Theme ViewModifiers

struct MochyGradientBackgroundModifier: ViewModifier {
    var topColor: Color
    var bottomColor: Color

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [topColor.opacity(0.45), bottomColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
    }
}

struct MochyCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var fillColor: Color
    var showBorder: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(showBorder ? 0.08 : 0), lineWidth: 1)
            )
    }
}

struct MochyShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 1.4)
                    .offset(x: phase * proxy.size.width * 1.4)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

extension View {
    func mochyGradientBackground(
        topColor: Color = .mochySurface0,
        bottomColor: Color = .mochyBase
    ) -> some View {
        modifier(MochyGradientBackgroundModifier(topColor: topColor, bottomColor: bottomColor))
    }

    func mochyCard(
        cornerRadius: CGFloat = MochyTheme.cornerRadiusMedium,
        fillColor: Color = .mochySurface0,
        showBorder: Bool = true
    ) -> some View {
        modifier(MochyCardModifier(cornerRadius: cornerRadius, fillColor: fillColor, showBorder: showBorder))
    }

    func mochyShimmer() -> some View {
        modifier(MochyShimmerModifier())
    }
}
