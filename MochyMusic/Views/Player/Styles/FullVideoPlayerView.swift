import SwiftUI
import AVFoundation
import UIKit

/// Full-bleed looping Canvas / Video player background via `CanvasService.shared` with translucent overlay controls & lyrics pane.
struct FullVideoPlayerView: View {
    let track: Track
    let handlers: PlayerActionHandlers

    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var canvasService = CanvasService.shared
    @ObservedObject private var lyricsManager = LyricsManager.shared
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var videoURL: URL?
    @State private var showInlineLyrics = false

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
            Color.mochyBackground.ignoresSafeArea()

            if let videoURL {
                LoopingCanvasVideoView(url: videoURL, isPlaying: player.isPlaying)
                    .ignoresSafeArea()
            } else {
                // Graceful atmospheric fallback while canvas loads or when unavailable
                GeometryReader { proxy in
                    MochyArtworkView(url: track.artworkURL, cornerRadius: 0)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 18)
                        .scaleEffect(player.isPlaying ? 1.08 : 1.02)
                        .animation(.easeInOut(duration: 3.0), value: player.isPlaying)
                }
                .ignoresSafeArea()
            }

            // Readability vignette
            LinearGradient(
                colors: [
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                PlayerTopBar(subtitle: videoURL != nil ? "Canvas Video" : "Ambient Stage", track: track, handlers: handlers)

                Spacer()

                if showInlineLyrics {
                    inlineLyricsPane
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let line = activeLyricLine {
                    Text(line)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .glassBackground(intensity: 0.65, tint: .black, cornerRadius: 16)
                        .padding(.horizontal, 24)
                        .onTapGesture {
                            withAnimation(MochyTheme.snappySpring) {
                                showInlineLyrics.toggle()
                            }
                        }
                }

                // Overlay metadata & controls
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        MochyArtworkView(url: track.artworkURL, cornerRadius: 10)
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(track.artistsText)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            withAnimation(MochyTheme.snappySpring) {
                                showInlineLyrics.toggle()
                            }
                        } label: {
                            Image(systemName: showInlineLyrics ? "quote.bubble.fill" : "quote.bubble")
                                .font(.system(size: 19))
                                .foregroundColor(showInlineLyrics ? settings.accentColor : .white)
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }

                        Button { library.toggleFavorite(track) } label: {
                            Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                                .font(.system(size: 19))
                                .foregroundColor(library.isFavorite(track) ? .mochyRed : .white)
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                    }

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
                        .foregroundColor(.white.opacity(0.7))
                    }

                    PlayerTransportRow(accentColor: settings.accentColor, playButtonSize: 64)
                }
                .padding(18)
                .glassBackground(intensity: 0.72, tint: .black, cornerRadius: 24, borderOpacity: 0.16)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .task(id: track.id) {
            await loadCanvas()
        }
    }

    private var inlineLyricsPane: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let lines = lyricsManager.currentLyrics?.syncedLines, !lines.isEmpty {
                        let activeIdx = lyricsManager.activeLineIndex(at: player.currentTime)
                        ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                            let isActive = idx == activeIdx
                            Text(line.text)
                                .font(.system(size: isActive ? 19 : 15, weight: isActive ? .bold : .medium))
                                .foregroundColor(isActive ? .white : .white.opacity(0.45))
                                .id(idx)
                                .onTapGesture {
                                    player.seek(to: line.time)
                                }
                        }
                    } else if let plain = lyricsManager.currentLyrics?.plainText {
                        Text(plain)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    } else {
                        Text("No lyrics available for this track.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxHeight: 220)
            .glassBackground(intensity: 0.75, tint: .black, cornerRadius: 20)
            .padding(.horizontal, 16)
            .onChange(of: lyricsManager.activeLineIndex(at: player.currentTime)) { newIdx in
                if let newIdx {
                    withAnimation { proxy.scrollTo(newIdx, anchor: .center) }
                }
            }
        }
    }

    private func loadCanvas() async {
        videoURL = nil
        if let canvas = await canvasService.fetchCanvas(for: track) {
            videoURL = canvas
        } else if track.isVideo, let ytVideo = await canvasService.fetchYouTubeVideoStream(videoId: track.id) {
            videoURL = ytVideo
        }
    }
}

/// Silent looping `AVQueuePlayer` + `AVPlayerLayer` wrapper for background canvas video playback.
private struct LoopingCanvasVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        context.coordinator.configure(url: url, in: view)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if context.coordinator.currentURL != url {
            context.coordinator.configure(url: url, in: uiView)
        }
        if isPlaying {
            context.coordinator.queuePlayer?.play()
        } else {
            context.coordinator.queuePlayer?.pause()
        }
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator {
        var queuePlayer: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var currentURL: URL?

        func configure(url: URL, in view: PlayerContainerView) {
            currentURL = url
            let item = AVPlayerItem(url: url)
            let qPlayer = AVQueuePlayer()
            qPlayer.isMuted = true
            let playerLooper = AVPlayerLooper(player: qPlayer, templateItem: item)
            view.playerLayer.player = qPlayer
            view.playerLayer.videoGravity = .resizeAspectFill
            self.queuePlayer = qPlayer
            self.looper = playerLooper
            qPlayer.play()
        }
    }
}
