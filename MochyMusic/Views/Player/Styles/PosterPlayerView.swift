import SwiftUI

/// Editorial Poster layout with full-bleed blurred artwork, bold oversized typography, and floating pill controls.
struct PosterPlayerView: View {
    let track: Track
    let handlers: PlayerActionHandlers

    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var colorExtractor = ArtworkColorExtractor.shared

    private var accentTint: Color {
        colorExtractor.color(for: track.thumbnailURL, fallback: settings.accentColor)
    }

    var body: some View {
        ZStack {
            // Full-bleed blurred artwork poster background
            GeometryReader { proxy in
                MochyArtworkView(url: track.artworkURL, cornerRadius: 0)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 26)
                    .scaleEffect(1.12)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.35),
                                accentTint.opacity(0.25),
                                Color.black.opacity(0.92)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                PlayerTopBar(subtitle: "Editorial Poster", track: track, handlers: handlers)

                Spacer(minLength: 8)

                // Framed crisp poster artwork inset
                HStack {
                    MochyArtworkView(url: track.artworkURL, cornerRadius: 20)
                        .frame(width: 210, height: 210)
                        .shadow(color: .black.opacity(0.55), radius: 22, y: 12)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 12) {
                        Button { library.toggleFavorite(track) } label: {
                            Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                                .font(.system(size: 20))
                                .foregroundColor(library.isFavorite(track) ? .mochyRed : .white)
                                .frame(width: 46, height: 46)
                                .glassBackground(intensity: 0.7, tint: .black, cornerRadius: 23)
                        }

                        Button(action: handlers.onOpenLyrics) {
                            Image(systemName: "quote.bubble")
                                .font(.system(size: 19))
                                .foregroundColor(.white)
                                .frame(width: 46, height: 46)
                                .glassBackground(intensity: 0.7, tint: .black, cornerRadius: 23)
                        }

                        Button(action: handlers.onOpenQueue) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 19))
                                .foregroundColor(.white)
                                .frame(width: 46, height: 46)
                                .glassBackground(intensity: 0.7, tint: .black, cornerRadius: 23)
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Bold editorial typography
                VStack(alignment: .leading, spacing: 6) {
                    if let album = track.album?.name {
                        Text(album.uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.6)
                            .foregroundColor(accentTint)
                            .lineLimit(1)
                    }

                    Text(track.title)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text(track.artistsText)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)

                // Seekbar
                VStack(spacing: 4) {
                    WavySlider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        range: 0...max(1, player.duration),
                        isWavy: settings.sliderStyle == .wavy,
                        activeColor: .white,
                        isPlaying: player.isPlaying
                    )
                    HStack {
                        Text(PlayerTimeFormatter.format(player.currentTime))
                        Spacer()
                        Text(PlayerTimeFormatter.endTimestampText(currentTime: player.currentTime, duration: player.duration))
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.68))
                }
                .padding(.horizontal, 24)

                // Floating Pill Transport Controls
                HStack {
                    Spacer()
                    PlayerTransportRow(accentColor: accentTint, playButtonSize: 58)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .glassBackground(intensity: 0.85, tint: .mochySurfaceVariant, cornerRadius: 38)
                    Spacer()
                }
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            colorExtractor.extractIfNeeded(from: track.thumbnailURL)
        }
    }
}
