import SwiftUI
import UIKit

/// Timeline Player layout featuring a deterministic waveform timeline scrubber, chronological queue strip, and live lyrics ticker.
struct TimelinePlayerView: View {
    let track: Track
    let handlers: PlayerActionHandlers

    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var lyricsManager = LyricsManager.shared
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var colorExtractor = ArtworkColorExtractor.shared

    private var accentTint: Color {
        colorExtractor.color(for: track.thumbnailURL, fallback: settings.accentColor)
    }

    private var activeLyricLine: String {
        guard lyricsManager.currentTrackId == track.id,
              let lines = lyricsManager.currentLyrics?.syncedLines,
              let idx = lyricsManager.activeLineIndex(at: player.currentTime),
              lines.indices.contains(idx) else {
            return lyricsManager.currentLyrics?.plainText?.components(separatedBy: .newlines).first ?? "Synced lyrics ticker ready"
        }
        return lines[idx].text
    }

    var body: some View {
        ZStack {
            Color.mochyBackground.ignoresSafeArea()
            LinearGradient(
                colors: [accentTint.opacity(0.24), Color.mochyBackground],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                PlayerTopBar(subtitle: "Timeline", track: track, handlers: handlers)

                // Compact header card
                HStack(spacing: 14) {
                    MochyArtworkView(url: track.artworkURL, cornerRadius: 14)
                        .frame(width: 78, height: 78)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text(track.artistsText)
                            .font(.system(size: 14))
                            .foregroundColor(.mochySecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button { library.toggleFavorite(track) } label: {
                        Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                            .font(.system(size: 20))
                            .foregroundColor(library.isFavorite(track) ? .mochyRed : .white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 20)

                // Live Lyrics Ticker
                Button(action: handlers.onOpenLyrics) {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.and.mic")
                            .foregroundColor(accentTint)
                        Text(activeLyricLine)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.mochySecondary)
                    }
                    .padding(14)
                    .mochyCard(cornerRadius: 16, fillColor: .mochySurfaceVariant)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                // Waveform Timeline Scrubber
                VStack(spacing: 8) {
                    WaveformScrubberBar(
                        trackId: track.id,
                        currentTime: player.currentTime,
                        duration: max(1, player.duration),
                        accentColor: accentTint,
                        onSeek: { player.seek(to: $0) }
                    )
                    .frame(height: 82)

                    HStack {
                        Text(PlayerTimeFormatter.format(player.currentTime))
                        Spacer()
                        Text(PlayerTimeFormatter.endTimestampText(currentTime: player.currentTime, duration: player.duration))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.mochySecondary)
                }
                .padding(14)
                .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
                .padding(.horizontal, 20)

                // Chronological Queue Strip
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CHRONOLOGICAL QUEUE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(.mochySecondary)
                        Spacer()
                        Button("Manage", action: handlers.onOpenQueue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(accentTint)
                    }
                    .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(player.queue.enumerated()), id: \.offset) { idx, item in
                                let isCurrent = idx == player.currentIndex
                                Button {
                                    player.play(tracks: player.queue, startIndex: idx)
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        MochyArtworkView(url: item.artworkURL, cornerRadius: 10)
                                            .frame(width: 68, height: 68)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(isCurrent ? accentTint : Color.clear, lineWidth: 2)
                                            )

                                        Text(item.title)
                                            .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                                            .foregroundColor(isCurrent ? accentTint : .mochyOnSurface)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 72)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer(minLength: 4)

                PlayerTransportRow(accentColor: accentTint, playButtonSize: 64)
                    .padding(.bottom, 18)
            }
        }
        .onAppear {
            colorExtractor.extractIfNeeded(from: track.thumbnailURL)
        }
    }
}

/// Interactive waveform timeline scrubber with deterministic bar amplitudes seeded by track ID.
private struct WaveformScrubberBar: View {
    let trackId: String
    let currentTime: TimeInterval
    let duration: TimeInterval
    let accentColor: Color
    let onSeek: (TimeInterval) -> Void

    private let barCount = 48

    private var amplitudes: [CGFloat] {
        var seed = trackId.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) ^ UInt64($1.value) }
        return (0..<barCount).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            let val = Double((seed >> 32) & 0xFFFF) / 65535.0
            return CGFloat(0.22 + 0.78 * val)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let progress = min(1.0, max(0.0, currentTime / max(1, duration)))
            let bars = amplitudes
            let w = max(1, proxy.size.width)

            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { idx in
                    let barRatio = Double(idx) / Double(barCount)
                    let isPassed = barRatio <= progress
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isPassed ? accentColor : Color.white.opacity(0.2))
                        .frame(maxWidth: .infinity)
                        .frame(height: proxy.size.height * bars[idx])
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = Double(max(0, min(1, value.location.x / w)))
                        onSeek(ratio * duration)
                    }
            )
        }
    }
}
