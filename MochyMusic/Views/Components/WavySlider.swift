import SwiftUI
import UIKit

/// Mochy Music's signature animated wavy seekbar slider (iOS 16+ Swift 5.0).
struct WavySlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var isWavy: Bool = true
    var onEditingChanged: (Bool) -> Void = { _ in }

    var activeColor: Color = .mochyPrimary
    var inactiveColor: Color = Color.white.opacity(0.22)
    var lineWidth: CGFloat = 3.2
    var isPlaying: Bool = true

    @State private var isDragging: Bool = false
    @ObservedObject private var settings = AppSettings.shared

    private var effectiveWavy: Bool {
        guard isWavy else { return false }
        return settings.sliderStyle != .slim && settings.sliderStyle != .defaultStyle
    }

    private var normalizedProgress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1.0, max(0.0, (value - range.lowerBound) / span))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let height = max(28, proxy.size.height)
            let midY = height / 2
            let thumbX = CGFloat(normalizedProgress) * width
            let shouldAnimate = (isWavy || settings.sliderStyle == .wavy) && settings.sliderStyle != .slim && isPlaying

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimate)) { timeline in
                let phase = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate * 4.5 : 0

                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        let trackY = size.height / 2
                        let activeEndX = max(0, min(size.width, CGFloat(normalizedProgress) * size.width))

                        // Inactive track
                        var inactivePath = Path()
                        inactivePath.move(to: CGPoint(x: activeEndX, y: trackY))
                        inactivePath.addLine(to: CGPoint(x: size.width, y: trackY))
                        context.stroke(
                            inactivePath,
                            with: .color(inactiveColor),
                            style: StrokeStyle(
                                lineWidth: settings.sliderStyle == .slim ? 2.0 : lineWidth,
                                lineCap: .round
                            )
                        )

                        // Active wavy or straight track
                        var activePath = Path()
                        let useWave = (isWavy && settings.sliderStyle != .slim)
                        let amplitude: CGFloat = useWave ? (isPlaying ? 3.2 : 1.4) : 0
                        let wavelength: CGFloat = 22.0
                        let strokeWidth: CGFloat = settings.sliderStyle == .slim ? 2.5 : lineWidth

                        if activeEndX > 0 {
                            if amplitude > 0.1 {
                                let step: CGFloat = 2.0
                                var x: CGFloat = 0
                                while x <= activeEndX {
                                    // Taper wave cleanly to 0 at start & thumb
                                    let edgeFade = min(1.0, min(x / 8.0, (activeEndX - x) / 8.0))
                                    let angle = (x / wavelength) * .pi * 2.0 - CGFloat(phase)
                                    let y = trackY + sin(angle) * amplitude * max(0, edgeFade)
                                    if x == 0 {
                                        activePath.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        activePath.addLine(to: CGPoint(x: x, y: y))
                                    }
                                    x += step
                                }
                                activePath.addLine(to: CGPoint(x: activeEndX, y: trackY))
                            } else {
                                activePath.move(to: CGPoint(x: 0, y: trackY))
                                activePath.addLine(to: CGPoint(x: activeEndX, y: trackY))
                            }

                            context.stroke(
                                activePath,
                                with: .color(activeColor),
                                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }

                    // Thumb knob
                    Circle()
                        .fill(activeColor)
                        .frame(
                            width: isDragging ? 16 : (settings.sliderStyle == .slim ? 10 : 12),
                            height: isDragging ? 16 : (settings.sliderStyle == .slim ? 10 : 12)
                        )
                        .shadow(color: activeColor.opacity(0.45), radius: isDragging ? 6 : 2)
                        .position(x: max(6, min(width - 6, thumbX)), y: midY)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                onEditingChanged(true)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            let fraction = Double(max(0, min(1, gesture.location.x / width)))
                            let span = range.upperBound - range.lowerBound
                            value = range.lowerBound + fraction * span
                        }
                        .onEnded { _ in
                            isDragging = false
                            onEditingChanged(false)
                        }
                )
            }
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(normalizedProgress * 100)) percent")
    }
}
