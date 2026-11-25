import SwiftUI
import UIKit

/// Bedside Nightstand Player supporting both `.bedside` (giant quiet clock + swipeable song card) and `.bedsideTiles` (two-tile split view).
struct BedsidePlayerView: View {
    let track: Track
    let isTilesMode: Bool
    let handlers: PlayerActionHandlers

    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var lyricsManager = LyricsManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var colorExtractor = ArtworkColorExtractor.shared

    @State private var swipeOffset: CGFloat = 0

    private var accentTint: Color {
        colorExtractor.color(for: track.thumbnailURL, fallback: settings.accentColor)
    }

    private var activeLyricLine: String {
        guard lyricsManager.currentTrackId == track.id,
              let lines = lyricsManager.currentLyrics?.syncedLines,
              let idx = lyricsManager.activeLineIndex(at: player.currentTime),
              lines.indices.contains(idx) else {
            return "Tap for synced lyrics"
        }
        return lines[idx].text
    }

    var body: some View {
        ZStack {
            Color.mochyBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                PlayerTopBar(subtitle: isTilesMode ? "Bedside Tiles" : "Bedside Clock", track: track, handlers: handlers)

                if isTilesMode {
                    bedsideTilesLayout
                } else {
                    bedsideClockLayout
                }
            }
            .padding(.bottom, 18)
        }
        .onAppear {
            colorExtractor.extractIfNeeded(from: track.thumbnailURL)
        }
    }

    // MARK: - Giant Clock + Swipeable Card (.bedside)

    private var bedsideClockLayout: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)

            TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                VStack(spacing: 6) {
                    Text(Self.clockFormatter.string(from: context.date))
                        .font(.system(size: 76, weight: .thin, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .monospacedDigit()

                    Text(Self.dateFormatter.string(from: context.date).uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.8)
                        .foregroundColor(accentTint.opacity(0.85))
                }
            }

            if let sleep = player.sleepTimerRemaining {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                    Text("Sleep timer • \(PlayerTimeFormatter.format(sleep))")
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(accentTint)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(accentTint.opacity(0.14))
                .clipShape(Capsule())
            }

            Spacer(minLength: 8)

            // Swipeable quiet nightstand song card
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    MochyArtworkView(url: track.artworkURL, cornerRadius: 12)
                        .frame(width: 62, height: 62)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(track.artistsText)
                            .font(.system(size: 13))
                            .foregroundColor(.mochySecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 42))
                            .foregroundColor(accentTint)
                    }
                }

                WavySlider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    range: 0...max(1, player.duration),
                    isWavy: false,
                    activeColor: accentTint,
                    inactiveColor: Color.white.opacity(0.14),
                    isPlaying: player.isPlaying
                )

                HStack {
                    Button(action: handlers.onOpenSleepTimer) {
                        Label("Sleep Timer", systemImage: "moon.zzz")
                    }
                    Spacer()
                    Text("Swipe card to skip")
                        .font(.system(size: 11))
                        .foregroundColor(.mochySecondary.opacity(0.6))
                    Spacer()
                    Button(action: handlers.onOpenQueue) {
                        Label("Queue", systemImage: "list.bullet")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.mochySecondary)
            }
            .padding(18)
            .mochyCard(cornerRadius: 22, fillColor: .mochySurface)
            .offset(x: swipeOffset)
            .padding(.horizontal, 20)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        swipeOffset = value.translation.width * 0.45
                    }
                    .onEnded { value in
                        if value.translation.width < -70 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            player.next()
                        } else if value.translation.width > 70 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            player.previous()
                        }
                        withAnimation(MochyTheme.snappySpring) {
                            swipeOffset = 0
                        }
                    }
            )
        }
    }

    // MARK: - Two-Tile Split View (.bedsideTiles)

    private var bedsideTilesLayout: some View {
        VStack(spacing: 14) {
            // Top Tile: Clock + Live Lyrics
            VStack(spacing: 14) {
                TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Self.clockFormatter.string(from: context.date))
                            .font(.system(size: 46, weight: .light, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()

                        Spacer()

                        Text(Self.dateFormatter.string(from: context.date))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.mochySecondary)
                    }
                }

                Divider().background(Color.white.opacity(0.08))

                Button(action: handlers.onOpenLyrics) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOW LYRIC")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(accentTint)
                        Text(activeLyricLine)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .mochyCard(cornerRadius: 22, fillColor: .mochySurface)
            .padding(.horizontal, 18)

            // Bottom Tile: Music Player Tile
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    MochyArtworkView(url: track.artworkURL, cornerRadius: 16)
                        .frame(width: 94, height: 94)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text(track.artistsText)
                            .font(.system(size: 14))
                            .foregroundColor(.mochySecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

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
                    .foregroundColor(.mochySecondary)
                }

                PlayerTransportRow(accentColor: accentTint, playButtonSize: 60)
            }
            .padding(18)
            .mochyCard(cornerRadius: 22, fillColor: .mochySurface)
            .padding(.horizontal, 18)

            Spacer(minLength: 4)
        }
    }

    private static let clockFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"
        return df
    }()
}
