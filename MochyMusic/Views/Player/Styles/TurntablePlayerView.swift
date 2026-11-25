import SwiftUI
import UIKit

/// Spinning vinyl record player with center artwork label and interactive tonearm acting as seek indicator.
struct TurntablePlayerView: View {
    let track: Track
    let handlers: PlayerActionHandlers

    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var colorExtractor = ArtworkColorExtractor.shared

    @State private var accumulatedAngle: Double = 0
    @State private var lastTick: Date = Date()

    private var accentTint: Color {
        colorExtractor.color(for: track.thumbnailURL, fallback: settings.accentColor)
    }

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(1.0, max(0.0, player.currentTime / player.duration))
    }

    /// Tonearm swings from 18° (outer edge) to 42° (inner groove) as track progresses.
    private var tonearmDegrees: Double {
        if !player.isPlaying && player.currentTime == 0 {
            return 4.0
        }
        return 18.0 + progress * 24.0
    }

    var body: some View {
        ZStack {
            Color.mochyBackground.ignoresSafeArea()
            RadialGradient(
                colors: [accentTint.opacity(0.28), Color.mochyBackground],
                center: .center,
                startRadius: 30,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                PlayerTopBar(subtitle: "Turntable", track: track, handlers: handlers)

                Spacer(minLength: 4)

                // Vinyl Platter + Tonearm
                ZStack(alignment: .topTrailing) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !player.isPlaying)) { timeline in
                        let angle = rotationAngle(at: timeline.date)
                        vinylDisc
                            .rotationEffect(.degrees(angle))
                    }
                    .frame(width: 286, height: 286)

                    tonearmAssembly
                        .offset(x: 10, y: -12)
                }
                .frame(width: 310, height: 300)

                // Track Info + RPM badge
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("33⅓ RPM")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(accentTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accentTint.opacity(0.16))
                            .clipShape(Capsule())

                        Text(String(format: "%.2fx", player.playbackSpeed))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Text(track.title)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(track.artistsText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)

                // Interactive Seekbar
                VStack(spacing: 4) {
                    WavySlider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        range: 0...max(1, player.duration),
                        isWavy: settings.sliderStyle == .wavy,
                        activeColor: accentTint,
                        isPlaying: player.isPlaying
                    )
                    HStack {
                        Text(PlayerTimeFormatter.format(player.currentTime))
                        Spacer()
                        Text(PlayerTimeFormatter.endTimestampText(currentTime: player.currentTime, duration: player.duration))
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 26)

                PlayerTransportRow(accentColor: accentTint, playButtonSize: 64)

                // Bottom quick bar
                HStack(spacing: 24) {
                    Button { library.toggleFavorite(track) } label: {
                        Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                            .foregroundColor(library.isFavorite(track) ? .mochyRed : .white.opacity(0.75))
                    }
                    Button(action: handlers.onOpenLyrics) {
                        Image(systemName: "quote.bubble")
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Button(action: handlers.onOpenAudioLab) {
                        Image(systemName: "slider.vertical.3")
                            .foregroundColor(.white.opacity(0.75))
                    }
                    Button(action: handlers.onOpenQueue) {
                        Image(systemName: "list.bullet")
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .font(.system(size: 19, weight: .semibold))
                .padding(.top, 4)

                Spacer(minLength: 4)
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            colorExtractor.extractIfNeeded(from: track.thumbnailURL)
            lastTick = Date()
        }
    }

    private func rotationAngle(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
        let speedFactor = Double(player.playbackSpeed)
        return (elapsed * 45.0 * speedFactor).truncatingRemainder(dividingBy: 360)
    }

    private var vinylDisc: some View {
        ZStack {
            // Outer vinyl platter
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x1A1A1D), Color(hex: 0x050506)],
                        center: .center,
                        startRadius: 40,
                        endRadius: 145
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.8), radius: 24, y: 10)

            // Concentric vinyl grooves
            ForEach([68, 82, 96, 110, 124, 134], id: \.self) { radius in
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
                    .frame(width: CGFloat(radius * 2), height: CGFloat(radius * 2))
            }

            // Center album art label
            MochyArtworkView(url: track.artworkURL, isCircular: true)
                .frame(width: 112, height: 112)
                .overlay(Circle().stroke(accentTint.opacity(0.6), lineWidth: 2))

            // Spindle hole
            Circle()
                .fill(Color.black)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
        }
    }

    private var tonearmAssembly: some View {
        ZStack(alignment: .top) {
            // Pivot base
            Circle()
                .fill(Color(hex: 0x2B2B30))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))

            // Tonearm shaft + cartridge head
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.85), Color.gray],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 6, height: 158)

                RoundedRectangle(cornerRadius: 4)
                    .fill(accentTint)
                    .frame(width: 14, height: 24)
                    .rotationEffect(.degrees(16))
            }
            .offset(y: 22)
            .rotationEffect(.degrees(tonearmDegrees), anchor: UnitPoint(x: 0.5, y: 0.1))
            .animation(MochyTheme.springAnimation, value: tonearmDegrees)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let normalized = min(1.0, max(0.0, Double((value.location.y - 30) / 150)))
                    player.seek(to: normalized * max(1, player.duration))
                }
        )
    }
}
