import SwiftUI
import UIKit

/// Mochy Music's signature Flagship player with dynamic artwork gradient, morphing cover art, WavySlider, and bottom action card stack.
struct FlagshipPlayerView: View {
    let track: Track
    let handlers: PlayerActionHandlers
    var isCompactMode: Bool = false

    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var lyricsManager = LyricsManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var colorExtractor = ArtworkColorExtractor.shared

    @State private var isDraggingSeek = false
    @State private var dragSeekValue: Double = 0
    @State private var artworkDragOffset: CGFloat = 0

    private var accentTint: Color {
        colorExtractor.color(for: track.thumbnailURL, fallback: settings.accentColor)
    }

    private var displayTime: Double {
        isDraggingSeek ? dragSeekValue : player.currentTime
    }

    private var activeLyricLine: String? {
        guard lyricsManager.currentTrackId == track.id,
              let lines = lyricsManager.currentLyrics?.syncedLines,
              let idx = lyricsManager.activeLineIndex(at: player.currentTime),
              lines.indices.contains(idx) else {
            return nil
        }
        return lines[idx].text
    }

    var body: some View {
        ZStack {
            // Dynamic extracted artwork gradient backdrop
            ZStack {
                Color.mochyBackground.ignoresSafeArea()

                LinearGradient(
                    colors: [
                        accentTint.opacity(0.45),
                        accentTint.opacity(0.14),
                        Color.mochyBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            VStack(spacing: isCompactMode ? 14 : 18) {
                PlayerTopBar(
                    subtitle: track.album?.name ?? "Mochy Music",
                    track: track,
                    handlers: handlers
                )

                if !settings.hidePlayerThumbnail {
                    coverArtworkView
                        .padding(.horizontal, isCompactMode ? 44 : 26)
                } else {
                    Spacer(minLength: 10)
                }

                // Title, Artist, Explicit, Heart & Menu
                metadataRow
                    .padding(.horizontal, 24)

                // Wavy / Classic Seekbar
                seekbarSection
                    .padding(.horizontal, 24)

                // Transport Controls
                PlayerTransportRow(accentColor: accentTint, playButtonSize: isCompactMode ? 60 : 68)
                    .padding(.vertical, 2)

                // Bottom Card Stack (Lyrics Preview / AudioLab / Queue / Download / Share)
                if !isCompactMode {
                    bottomCardStack
                        .padding(.horizontal, 20)
                } else {
                    compactActionsRow
                        .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 16)
        }
        .onAppear {
            colorExtractor.extractIfNeeded(from: track.thumbnailURL)
        }
        .onChange(of: track.thumbnailURL) { newURL in
            colorExtractor.extractIfNeeded(from: newURL)
        }
    }

    // MARK: - Cover Artwork

    private var coverArtworkView: some View {
        MochyArtworkView(
            url: track.artworkURL,
            cornerRadius: CGFloat(settings.thumbnailCornerRadius),
            placeholderIcon: "music.note"
        )
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: isCompactMode ? 250 : 340)
        .scaleEffect(player.isPlaying ? 1.0 : 0.92)
        .offset(x: artworkDragOffset)
        .shadow(color: accentTint.opacity(player.isPlaying ? 0.38 : 0.16), radius: player.isPlaying ? 26 : 12, y: 12)
        .animation(MochyTheme.springAnimation, value: player.isPlaying)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard settings.swipeToSong else { return }
                    if abs(value.translation.width) > abs(value.translation.height) {
                        artworkDragOffset = value.translation.width * 0.45
                    }
                }
                .onEnded { value in
                    guard settings.swipeToSong else {
                        artworkDragOffset = 0
                        return
                    }
                    if value.translation.width < -75 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        player.next()
                    } else if value.translation.width > 75 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        player.previous()
                    }
                    withAnimation(MochyTheme.snappySpring) {
                        artworkDragOffset = 0
                    }
                }
        )
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.system(size: 21 * settings.fontSizePreset.scale, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if track.explicit {
                        Text("E")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 8) {
                    Text(track.artistsText)
                        .font(.system(size: 15 * settings.fontSizePreset.scale, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)

                    if !settings.hideAudioQualityBadge, let stream = player.currentStream {
                        Text(stream.bitrate > 180_000 ? "HQ" : "AAC")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(accentTint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accentTint.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                library.toggleFavorite(track)
            } label: {
                Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(library.isFavorite(track) ? .mochyRed : .white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.09))
                    .clipShape(Circle())
            }

            Button(action: handlers.onOpenMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.09))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Seekbar

    private var seekbarSection: some View {
        VStack(spacing: 4) {
            WavySlider(
                value: Binding(
                    get: { displayTime },
                    set: { dragSeekValue = $0 }
                ),
                range: 0...max(1, player.duration),
                isWavy: settings.sliderStyle != .defaultStyle && settings.sliderStyle != .slim,
                onEditingChanged: { editing in
                    if editing {
                        dragSeekValue = player.currentTime
                        isDraggingSeek = true
                    } else {
                        player.seek(to: dragSeekValue)
                        isDraggingSeek = false
                    }
                },
                activeColor: .white,
                inactiveColor: Color.white.opacity(0.24),
                isPlaying: player.isPlaying
            )

            HStack {
                Text(PlayerTimeFormatter.format(displayTime))
                Spacer()
                if let sleep = player.sleepTimerRemaining {
                    Label(PlayerTimeFormatter.format(sleep), systemImage: "moon.zzz.fill")
                        .foregroundColor(accentTint)
                    Spacer()
                }
                Text(PlayerTimeFormatter.endTimestampText(currentTime: displayTime, duration: player.duration))
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(0.65))
        }
    }

    // MARK: - Bottom Card Stack

    private var bottomCardStack: some View {
        VStack(spacing: 10) {
            // Live Lyrics Preview Card
            Button(action: handlers.onOpenLyrics) {
                HStack(spacing: 12) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 16))
                        .foregroundColor(accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("LYRICS")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(.white.opacity(0.55))

                        Text(activeLyricLine ?? "Tap to open synced lyrics stage")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .glassBackground(intensity: 0.78, tint: accentTint.opacity(0.35), cornerRadius: 16, borderOpacity: 0.16)
            }
            .buttonStyle(.plain)

            // Quick Utility Action Bar
            HStack(spacing: 10) {
                utilityPill(icon: "slider.vertical.3", label: "AudioLab", action: handlers.onOpenAudioLab)
                utilityPill(icon: "list.bullet", label: "Queue (\(player.queue.count))", action: handlers.onOpenQueue)

                let isDownloaded = library.isDownloaded(track.id)
                let isDownloading = downloadManager.isDownloading(track.id)
                utilityPill(
                    icon: isDownloaded ? "checkmark.circle.fill" : (isDownloading ? "arrow.down.circle.dotted" : "arrow.down.circle"),
                    label: isDownloaded ? "Saved" : (isDownloading ? "Saving" : "Save"),
                    tint: isDownloaded ? .mochyGreen : .white
                ) {
                    if isDownloaded {
                        MochyToastCenter.shared.show("Already saved for offline listening")
                    } else if !track.isLocal {
                        downloadManager.download(track: track)
                        MochyToastCenter.shared.show("Downloading \(track.title)")
                    }
                }

                utilityPill(icon: "square.and.arrow.up", label: "Share", action: handlers.onOpenShare)
            }
        }
    }

    private var compactActionsRow: some View {
        HStack {
            Button(action: handlers.onOpenLyrics) {
                Label("Lyrics", systemImage: "quote.bubble")
            }
            Spacer()
            Button(action: handlers.onOpenAudioLab) {
                Label("AudioLab", systemImage: "slider.vertical.3")
            }
            Spacer()
            Button(action: handlers.onOpenQueue) {
                Label("Queue", systemImage: "list.bullet")
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.white.opacity(0.85))
    }

    private func utilityPill(
        icon: String,
        label: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
