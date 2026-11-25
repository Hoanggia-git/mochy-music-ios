import SwiftUI
import UIKit

/// Shared actions passed from `NowPlayingView` into every `PlayerStyle` layout.
struct PlayerActionHandlers {
    var onDismiss: () -> Void
    var onOpenQueue: () -> Void
    var onOpenLyrics: () -> Void
    var onOpenAudioLab: () -> Void
    var onOpenSleepTimer: () -> Void
    var onOpenShare: () -> Void
    var onOpenMenu: () -> Void
}

/// Shared time formatting and seekbar helpers across Mochy player styles.
enum PlayerTimeFormatter {
    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func endTimestampText(currentTime: TimeInterval, duration: TimeInterval) -> String {
        let mode = PlayerEndTimestamp(rawValue: AppSettings.shared.playerEndTimestampRaw) ?? .timeLeft
        if mode == .timeLeft {
            let remaining = max(0, duration - currentTime)
            return "-\(format(remaining))"
        }
        return format(duration)
    }
}

/// Reusable top bar for full-screen player styles (dismiss chevron, source label, AudioLab/style/menu buttons).
struct PlayerTopBar: View {
    let subtitle: String
    let track: Track
    let handlers: PlayerActionHandlers

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 12) {
            Button(action: handlers.onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 1) {
                Text("PLAYING FROM")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.3)
                    .foregroundColor(.white.opacity(0.6))
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Section("Player Style") {
                    ForEach(PlayerStyle.allCases) { style in
                        Button {
                            withAnimation(MochyTheme.springAnimation) {
                                settings.playerStyle = style
                            }
                        } label: {
                            HStack {
                                Text(style.displayName)
                                if settings.playerStyle == style {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Button(action: handlers.onOpenAudioLab) {
                    Label("AudioLab & EQ", systemImage: "slider.vertical.3")
                }
                Button(action: handlers.onOpenSleepTimer) {
                    Label("Sleep Timer", systemImage: "moon.zzz")
                }
                Button(action: handlers.onOpenShare) {
                    Label("Share Song", systemImage: "square.and.arrow.up")
                }
                Button(action: handlers.onOpenMenu) {
                    Label("Song Options", systemImage: "ellipsis.circle")
                }
            } label: {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

/// Reusable transport controls row (Shuffle, Previous, Play/Pause, Next, Repeat).
struct PlayerTransportRow: View {
    @EnvironmentObject private var player: AudioPlayerManager
    var accentColor: Color = .white
    var playButtonSize: CGFloat = 68

    var body: some View {
        HStack(spacing: 26) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(player.isShuffled ? accentColor : .white.opacity(0.65))
                    .overlay(alignment: .bottom) {
                        if player.isShuffled {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 4, height: 4)
                                .offset(y: 7)
                        }
                    }
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: playButtonSize, height: playButtonSize)
                        .shadow(color: accentColor.opacity(0.35), radius: 14, y: 5)

                    if player.isLoading {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: playButtonSize * 0.38, weight: .bold))
                            .foregroundColor(.black)
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                }
            }
            .scaleEffect(player.isPlaying ? 1.0 : 0.96)
            .animation(MochyTheme.snappySpring, value: player.isPlaying)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(player.repeatMode != .off ? accentColor : .white.opacity(0.65))
                    .overlay(alignment: .bottom) {
                        if player.repeatMode != .off {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 4, height: 4)
                                .offset(y: 7)
                        }
                    }
            }
        }
    }
}
