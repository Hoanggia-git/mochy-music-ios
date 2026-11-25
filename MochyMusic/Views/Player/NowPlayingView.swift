import SwiftUI
import UIKit

/// Master full-screen player switching dynamically across all Mochy PlayerStyles, with queue, lyrics, sleep timer, share, and AudioLab sheets.
struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @State private var showQueueSheet = false
    @State private var showLyricsSheet = false
    @State private var showAudioLabSheet = false
    @State private var showSleepTimerSheet = false
    @State private var showShareSheet = false
    @State private var showMenuSheet = false
    @State private var dismissDragOffset: CGFloat = 0

    init() {}

    private var handlers: PlayerActionHandlers {
        PlayerActionHandlers(
            onDismiss: { closePlayer() },
            onOpenQueue: { showQueueSheet = true },
            onOpenLyrics: { showLyricsSheet = true },
            onOpenAudioLab: { showAudioLabSheet = true },
            onOpenSleepTimer: { showSleepTimerSheet = true },
            onOpenShare: { showShareSheet = true },
            onOpenMenu: { showMenuSheet = true }
        )
    }

    var body: some View {
        ZStack {
            Color.mochyBackground.ignoresSafeArea()

            if let track = player.currentTrack {
                playerContent(for: track)
                    .offset(y: dismissDragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 28)
                            .onChanged { value in
                                guard settings.playerSwipeDownAnywhere else { return }
                                if value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) {
                                    dismissDragOffset = value.translation.height * 0.7
                                }
                            }
                            .onEnded { value in
                                guard settings.playerSwipeDownAnywhere else {
                                    dismissDragOffset = 0
                                    return
                                }
                                if value.translation.height > 130 {
                                    closePlayer()
                                } else {
                                    withAnimation(MochyTheme.snappySpring) {
                                        dismissDragOffset = 0
                                    }
                                }
                            }
                    )
            } else {
                emptyStateView
            }
        }
        .statusBar(hidden: !settings.playerStatusBar)
        .onAppear {
            if settings.keepScreenOn {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: settings.keepScreenOn) { enabled in
            UIApplication.shared.isIdleTimerDisabled = enabled
        }
        .sheet(isPresented: $showQueueSheet) {
            QueueSheetView()
                .environmentObject(player)
        }
        .sheet(isPresented: $showLyricsSheet) {
            NavigationStack {
                LyricsScreen()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showLyricsSheet = false }
                                .foregroundColor(settings.accentColor)
                        }
                    }
            }
            .environmentObject(player)
        }
        .sheet(isPresented: $showAudioLabSheet) {
            NavigationStack {
                AudioLabScreen()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showAudioLabSheet = false }
                                .foregroundColor(settings.accentColor)
                        }
                    }
            }
            .environmentObject(player)
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            SleepTimerSheet()
                .environmentObject(player)
        }
        .sheet(isPresented: $showShareSheet) {
            if let track = player.currentTrack {
                ShareSongSheet(track: track)
            }
        }
        .sheet(isPresented: $showMenuSheet) {
            if let track = player.currentTrack {
                SongMenuSheet(track: track)
                    .environmentObject(player)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func playerContent(for track: Track) -> some View {
        switch settings.playerStyle {
        case .flagship:
            FlagshipPlayerView(track: track, handlers: handlers)
        case .turntable:
            TurntablePlayerView(track: track, handlers: handlers)
        case .video:
            FullVideoPlayerView(track: track, handlers: handlers)
        case .ipod:
            IPodPlayerView(track: track, handlers: handlers)
        case .poster:
            PosterPlayerView(track: track, handlers: handlers)
        case .timeline:
            TimelinePlayerView(track: track, handlers: handlers)
        case .lyrics:
            ZStack(alignment: .top) {
                LyricsScreen(showCompactControls: true)
                    .padding(.top, 46)
                PlayerTopBar(subtitle: "Lyrics Stage", track: track, handlers: handlers)
            }
        case .bedside:
            BedsidePlayerView(track: track, isTilesMode: false, handlers: handlers)
        case .bedsideTiles:
            BedsidePlayerView(track: track, isTilesMode: true, handlers: handlers)
        case .compact:
            FlagshipPlayerView(track: track, handlers: handlers, isCompactMode: true)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: closePlayer) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.mochySurfaceVariant)
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            Spacer()

            Image(systemName: "music.note.house.fill")
                .font(.system(size: 48))
                .foregroundColor(.mochySecondary.opacity(0.6))
            Text("Nothing Playing")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.mochyOnSurface)
            Text("Pick any song from Home, Search, or your Library to start listening.")
                .font(.system(size: 13))
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func closePlayer() {
        dismissDragOffset = 0
        router.dismissNowPlaying()
        dismiss()
    }
}

/// Interactive Sleep Timer configuration sheet.
private struct SleepTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var settings = AppSettings.shared

    private let presets = [5, 10, 15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mochyBackground.ignoresSafeArea()

                VStack(spacing: 18) {
                    if let remaining = player.sleepTimerRemaining {
                        VStack(spacing: 8) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 36))
                                .foregroundColor(settings.accentColor)
                            Text("Stopping playback in")
                                .font(.system(size: 13))
                                .foregroundColor(.mochySecondary)
                            Text(PlayerTimeFormatter.format(remaining))
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)

                            Button("Cancel Timer", role: .destructive) {
                                player.cancelSleepTimer()
                                MochyToastCenter.shared.show("Sleep timer cancelled")
                            }
                            .padding(.top, 4)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                        ForEach(presets, id: \.self) { minutes in
                            Button {
                                player.startSleepTimer(minutes: minutes)
                                MochyToastCenter.shared.show("Sleep timer set for \(minutes) min")
                                dismiss()
                            } label: {
                                Text("\(minutes) min")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.mochyOnSurface)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .mochyCard(cornerRadius: 14, fillColor: .mochySurfaceVariant)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if player.duration > player.currentTime + 2 {
                        Button {
                            let endOfTrack = max(1, player.duration - player.currentTime)
                            player.startSleepTimer(seconds: endOfTrack)
                            MochyToastCenter.shared.show("Stopping at end of track")
                            dismiss()
                        } label: {
                            Label("End of Current Track", systemImage: "stop.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(settings.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(settings.accentColor)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
