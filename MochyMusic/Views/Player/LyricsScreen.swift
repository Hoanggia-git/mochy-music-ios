import SwiftUI
import UIKit

/// Full synced & plain lyrics stage with auto-scrolling, interlude dots, tap-to-seek, provider switcher, and attribution footer.
struct LyricsScreen: View {
    var trackOverride: Track? = nil
    var showCompactControls: Bool = true

    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var lyricsManager = LyricsManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var colorExtractor = ArtworkColorExtractor.shared

    @State private var userScrolling = false
    @State private var showProviderMenu = false
    @State private var showShareLyrics = false

    private var activeTrack: Track? {
        trackOverride ?? player.currentTrack
    }

    private var activeIndex: Int? {
        guard trackOverride == nil || trackOverride?.id == player.currentTrack?.id else { return nil }
        return lyricsManager.activeLineIndex(at: player.currentTime)
    }

    private var accentTint: Color {
        colorExtractor.color(for: activeTrack?.thumbnailURL, fallback: settings.accentColor)
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                if let track = activeTrack {
                    headerBar(track: track)
                }

                lyricsBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showCompactControls, let track = activeTrack, track.id == player.currentTrack?.id {
                    compactBottomBar
                }
            }
        }
        .onAppear {
            if let track = activeTrack {
                colorExtractor.extractIfNeeded(from: track.thumbnailURL)
                if lyricsManager.currentTrackId != track.id {
                    lyricsManager.loadLyricsInBackground(for: track)
                }
            }
        }
        .onChange(of: activeTrack?.id) { _ in
            if let track = activeTrack {
                colorExtractor.extractIfNeeded(from: track.thumbnailURL)
                if lyricsManager.currentTrackId != track.id {
                    lyricsManager.loadLyricsInBackground(for: track)
                }
            }
        }
        .sheet(isPresented: $showShareLyrics) {
            if let track = activeTrack {
                ShareSongSheet(track: track)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color.mochyBackground.ignoresSafeArea()
            RadialGradient(
                colors: [accentTint.opacity(0.32), Color.mochyBackground],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private func headerBar(track: Track) -> some View {
        HStack(spacing: 12) {
            MochyArtworkView(url: track.artworkURL, cornerRadius: 10)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.mochyOnSurface)
                    .lineLimit(1)
                Text(track.artistsText)
                    .font(.system(size: 12))
                    .foregroundColor(.mochySecondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button {
                    Task {
                        _ = await lyricsManager.fetchLyrics(for: track, forceRefresh: true)
                    }
                } label: {
                    Label("Refresh Lyrics", systemImage: "arrow.clockwise")
                }

                Button {
                    showShareLyrics = true
                } label: {
                    Label("Share Lyric Card", systemImage: "square.and.arrow.up")
                }

                Divider()

                Section("Enabled Providers") {
                    ForEach(settings.lyricsProviderOrder) { provider in
                        Button {
                            promoteProvider(provider, track: track)
                        } label: {
                            HStack {
                                Text(provider.displayName)
                                if lyricsManager.currentLyrics?.source == provider.displayName {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.mochyPrimary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Lyrics Stage

    @ViewBuilder
    private var lyricsBody: some View {
        if lyricsManager.isLoading && lyricsManager.currentLyrics == nil {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(accentTint)
                    .scaleEffect(1.2)
                Text("Searching synced lyrics...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.mochySecondary)
            }
        } else if let result = lyricsManager.currentLyrics,
                  let lines = result.syncedLines,
                  !lines.isEmpty {
            syncedLyricsScrollView(lines: lines, source: result.source)
        } else if let plain = lyricsManager.currentLyrics?.plainText, !plain.isEmpty {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(plain)
                        .font(.system(size: 21 * settings.fontSizePreset.scale, weight: .semibold, design: .rounded))
                        .foregroundColor(.mochyOnSurface.opacity(0.9))
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LyricsSourceFooter(
                        source: lyricsManager.currentLyrics?.source ?? "Plain Text",
                        isSynced: false
                    )
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 42))
                    .foregroundColor(.mochySecondary.opacity(0.55))
                Text("No Lyrics Found")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.mochyOnSurface)
                Text(lyricsManager.errorMessage ?? "Try refreshing or reordering lyrics providers.")
                    .font(.system(size: 13))
                    .foregroundColor(.mochySecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                if let track = activeTrack {
                    Button {
                        Task {
                            _ = await lyricsManager.fetchLyrics(for: track, forceRefresh: true)
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(accentTint)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func syncedLyricsScrollView(lines: [LyricLine], source: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 36)

                    ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                        let isActive = activeIndex == idx
                        let isPast = (activeIndex ?? -1) > idx

                        VStack(alignment: .leading, spacing: 14) {
                            // Show animated interlude dots if gap before this line > 5s
                            if idx > 0 && (line.time - lines[idx - 1].time) > 5.0 {
                                let showInterlude = isInterludeActive(
                                    start: lines[idx - 1].time,
                                    end: line.time
                                )
                                if showInterlude {
                                    InterludeDotsView(accentColor: accentTint)
                                        .padding(.vertical, 6)
                                }
                            }

                            Button {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                if trackOverride == nil || trackOverride?.id == player.currentTrack?.id {
                                    player.seek(to: line.time)
                                    if !player.isPlaying {
                                        player.play()
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(line.text)
                                        .font(.system(
                                            size: (isActive ? 26 : 22) * settings.fontSizePreset.scale,
                                            weight: isActive ? .heavy : .bold,
                                            design: .rounded
                                        ))
                                        .foregroundColor(
                                            isActive
                                                ? .white
                                                : (isPast ? .white.opacity(0.32) : .white.opacity(0.45))
                                        )
                                        .shadow(color: isActive ? accentTint.opacity(0.65) : .clear, radius: isActive ? 14 : 0)
                                        .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
                                        .multilineTextAlignment(.leading)
                                        .animation(MochyTheme.snappySpring, value: isActive)

                                    if let translation = line.translation, !translation.isEmpty {
                                        Text(translation)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(isActive ? accentTint.opacity(0.95) : .white.opacity(0.35))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .id(idx)
                    }

                    LyricsSourceFooter(source: source, isSynced: true)
                        .padding(.top, 20)
                        .padding(.bottom, 50)
                }
                .padding(.horizontal, 22)
            }
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    userScrolling = true
                }
            )
            .onChange(of: activeIndex) { newIndex in
                guard let newIndex, !userScrolling else { return }
                withAnimation(.easeInOut(duration: 0.42)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if userScrolling, let idx = activeIndex {
                    Button {
                        userScrolling = false
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(idx, anchor: .center)
                        }
                    } label: {
                        Label("Sync", systemImage: "scope")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(accentTint)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                    .padding(16)
                }
            }
        }
    }

    private func isInterludeActive(start: TimeInterval, end: TimeInterval) -> Bool {
        let t = player.currentTime
        return t > start + 1.2 && t < end - 0.5
    }

    // MARK: - Compact Bottom Controls

    private var compactBottomBar: some View {
        VStack(spacing: 8) {
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

            HStack(spacing: 28) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.mochyPrimary)
                }

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.white)
                }

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.mochyPrimary)
                }
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.mochyBackground.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func promoteProvider(_ provider: LyricsProvider, track: Track) {
        var order = settings.lyricsProviderOrder.filter { $0 != provider }
        order.insert(provider, at: 0)
        settings.lyricsProviderOrder = order
        Task {
            _ = await lyricsManager.fetchLyrics(for: track, forceRefresh: true)
        }
    }
}

/// Animated 3-dot instrumental interlude indicator shown during long gaps (> 5s) between lyrics.
struct InterludeDotsView: View {
    var accentColor: Color = .mochyPrimary

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { idx in
                    let pulse = 0.45 + 0.55 * sin(t * 3.4 - Double(idx) * 0.7)
                    Circle()
                        .fill(accentColor.opacity(0.5 + 0.45 * pulse))
                        .frame(width: 8, height: 8)
                        .scaleEffect(0.82 + 0.25 * pulse)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
    }
}

/// Attribution footer displaying which provider supplied the lyrics.
struct LyricsSourceFooter: View {
    let source: String
    let isSynced: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSynced ? "waveform.and.mic" : "text.alignleft")
                .font(.system(size: 12))
                .foregroundColor(.mochySecondary)
            Text("Lyrics provided by \(source)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.mochySecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
