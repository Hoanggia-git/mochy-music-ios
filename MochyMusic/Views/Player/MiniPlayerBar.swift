import SwiftUI
import UIKit

/// Floating AMOLED glass mini player bar positioned above the tab bar with swipe-to-skip and progress line.
struct MiniPlayerBar: View {
    var onTap: () -> Void

    @EnvironmentObject var player: AudioPlayerManager
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var colorExtractor = ArtworkColorExtractor.shared

    @State private var swipeOffset: CGFloat = 0

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    private var accentTint: Color {
        colorExtractor.color(for: player.currentTrack?.thumbnailURL, fallback: settings.accentColor)
    }

    private var progressRatio: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(1.0, max(0.0, player.currentTime / player.duration)))
    }

    var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    MochyArtworkView(
                        url: track.artworkURL,
                        cornerRadius: min(10, CGFloat(settings.thumbnailCornerRadius)),
                        placeholderIcon: "music.note"
                    )
                    .frame(width: 46, height: 46)
                    .shadow(color: accentTint.opacity(0.28), radius: 6, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.mochyOnSurface)
                            .lineLimit(1)

                        Text(track.artistsText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.mochySecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if player.isLoading {
                        ProgressView()
                            .tint(accentTint)
                            .frame(width: 34, height: 34)
                    } else {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.mochyPrimary)
                            .frame(width: 34, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next track")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Thin bottom progress line
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                        Rectangle()
                            .fill(accentTint)
                            .frame(width: proxy.size.width * progressRatio)
                    }
                }
                .frame(height: 2.5)
            }
            .background(
                Group {
                    if settings.pureBlackMiniPlayer {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.mochyBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.clear)
                            .glassBackground(
                                intensity: 0.88,
                                tint: accentTint.opacity(0.28),
                                cornerRadius: 16,
                                borderOpacity: 0.16
                            )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.55), radius: 14, x: 0, y: 6)
            .offset(x: swipeOffset)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            swipeOffset = value.translation.width * 0.45
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < -65 {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            player.next()
                        } else if value.translation.width > 65 {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            player.previous()
                        }
                        withAnimation(MochyTheme.snappySpring) {
                            swipeOffset = 0
                        }
                    }
            )
            .onAppear {
                colorExtractor.extractIfNeeded(from: track.thumbnailURL)
            }
            .onChange(of: track.thumbnailURL) { newURL in
                colorExtractor.extractIfNeeded(from: newURL)
            }
        }
    }
}
