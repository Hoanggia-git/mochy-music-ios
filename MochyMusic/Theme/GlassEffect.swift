import SwiftUI
import UIKit

/// UIKit-backed blur view for configurable frosted glass surfaces.
struct VisualEffectBlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    var intensity: Double

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
        uiView.alpha = CGFloat(min(1.0, max(0.0, intensity)))
    }
}

/// Configurable glass/frosted-blur ViewModifier respecting `AppSettings` blur controls.
struct GlassEffectModifier: ViewModifier {
    var intensity: Double
    var tintColor: Color
    var cornerRadius: CGFloat
    var borderOpacity: Double

    @ObservedObject private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        let effectiveIntensity = settings.blurEnabled
            ? min(1.0, max(0.0, intensity * (settings.blurIntensity / 25.0)))
            : 0.0

        content
            .background(
                ZStack {
                    if settings.blurEnabled {
                        VisualEffectBlurView(
                            style: settings.blurQuality == "LOW" ? .systemThinMaterialDark : .systemUltraThinMaterialDark,
                            intensity: effectiveIntensity
                        )
                        tintColor.opacity(0.28)
                    } else {
                        tintColor.opacity(0.92)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(borderOpacity),
                                Color.white.opacity(borderOpacity * 0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }
}

extension View {
    /// Applies Mochy Music's frosted glass backdrop with configurable intensity, tint, and corner radius.
    func glassBackground(
        intensity: Double = 0.85,
        tint: Color = .mochySurface0,
        cornerRadius: CGFloat = 16,
        borderOpacity: Double = 0.14
    ) -> some View {
        modifier(
            GlassEffectModifier(
                intensity: intensity,
                tintColor: tint,
                cornerRadius: cornerRadius,
                borderOpacity: borderOpacity
            )
        )
    }
}
