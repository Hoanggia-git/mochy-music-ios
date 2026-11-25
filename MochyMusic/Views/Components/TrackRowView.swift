import SwiftUI
import UIKit

/// Clean AMOLED track row with artwork, active playback indicator, download/explicit badges, swipe actions, and menu sheet.
struct TrackRowView: View {
    let track: Track
    let index: Int?
    let onTap: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var showMenuSheet = false

    init(track: Track, index: Int? = nil, onTap: @escaping () -> Void) {
        self.track = track
        self.index = index
        self.onTap = onTap
    }

    private var isCurrentTrack: Bool {
        player.currentTrack?.id == track.id
    }

    private var isDownloaded: Bool {
        library.isDownloaded(track.id) || track.isLocal
    }

    private var isDownloading: Bool {
        downloadManager.isDownloading(track.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let index {
                Text("\(index)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(isCurrentTrack ? settings.accentColor : .mochySecondary)
                    .frame(width: 24, alignment: .center)
            }

            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack {
                        MochyArtworkView(
                            url: track.artworkURL,
                            cornerRadius: min(10, CGFloat(settings.thumbnailCornerRadius)),
                            placeholderIcon: track.isVideo ? "play.rectangle.fill" : "music.note"
                        )
                        .frame(width: 50, height: 50)

                        if isCurrentTrack {
                            RoundedRectangle(cornerRadius: min(10, CGFloat(settings.thumbnailCornerRadius)), style: .continuous)
                                .fill(Color.black.opacity(0.55))
                                .frame(width: 50, height: 50)

                            MiniPlayingBars(isPlaying: player.isPlaying, color: settings.accentColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(track.title)
                                .font(.system(size: 15 * settings.fontSizePreset.scale, weight: isCurrentTrack ? .bold : .semibold))
                                .foregroundColor(isCurrentTrack ? settings.accentColor : .mochyOnSurface)
                                .lineLimit(1)

                            if track.explicit {
                                Text("E")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Color.mochySecondary.opacity(0.85))
                                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            }
                        }

                        HStack(spacing: 5) {
                            if isDownloading {
                                ProgressView(value: downloadManager.downloadProgress[track.id] ?? 0)
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.55)
                                    .frame(width: 12, height: 12)
                                    .tint(settings.accentColor)
                            } else if isDownloaded {
                                Image(systemName: track.isLocal ? "internaldrive.fill" : "arrow.down.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.mochyGreen)
                            }

                            Text(track.artistsText)
                                .font(.system(size: 13 * settings.fontSizePreset.scale))
                                .foregroundColor(.mochySecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 6)

                    if library.isFavorite(track) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.mochyRed.opacity(0.9))
                    }

                    Text(track.formattedDuration)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.mochySecondary.opacity(0.85))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showMenuSheet = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.mochySecondary)
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More options for \(track.title)")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            swipeActionButton(for: settings.swipeRightAction)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            swipeActionButton(for: settings.swipeLeftAction)
        }
        .contextMenu {
            Button {
                player.playNext(track)
                MochyToastCenter.shared.show("Playing next: \(track.title)")
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                player.addToQueue(track)
                MochyToastCenter.shared.show("Added to Queue")
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }

            Button {
                library.toggleFavorite(track)
            } label: {
                Label(
                    library.isFavorite(track) ? "Remove Favorite" : "Favorite",
                    systemImage: library.isFavorite(track) ? "heart.slash" : "heart"
                )
            }

            Button {
                showMenuSheet = true
            } label: {
                Label("More Options", systemImage: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $showMenuSheet) {
            SongMenuSheet(track: track)
        }
    }

    @ViewBuilder
    private func swipeActionButton(for action: SwipeAction) -> some View {
        switch action {
        case .addToQueue:
            Button {
                player.addToQueue(track)
                MochyToastCenter.shared.show("Added to Queue")
            } label: {
                Label("Queue", systemImage: "text.append")
            }
            .tint(.mochyBlue)
        case .addToPlaylist:
            Button {
                showMenuSheet = true
            } label: {
                Label("Playlist", systemImage: "text.badge.plus")
            }
            .tint(.mochyMauve)
        case .download:
            Button {
                if library.isDownloaded(track.id) {
                    downloadManager.deleteDownload(trackId: track.id)
                    MochyToastCenter.shared.show("Removed download")
                } else {
                    downloadManager.download(track: track)
                    MochyToastCenter.shared.show("Downloading \(track.title)")
                }
            } label: {
                Label(
                    library.isDownloaded(track.id) ? "Delete" : "Download",
                    systemImage: library.isDownloaded(track.id) ? "trash" : "arrow.down.circle"
                )
            }
            .tint(.mochyGreen)
        case .like:
            Button {
                library.toggleFavorite(track)
            } label: {
                Label(
                    library.isFavorite(track) ? "Unlike" : "Like",
                    systemImage: library.isFavorite(track) ? "heart.slash.fill" : "heart.fill"
                )
            }
            .tint(.mochyRed)
        case .remove:
            Button(role: .destructive) {
                library.removeFavorite(track)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

/// Compact 3-bar animated equalizer indicator shown over the currently playing track artwork.
struct MiniPlayingBars: View {
    let isPlaying: Bool
    var color: Color = .mochyPrimary

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { timeline in
            let t = isPlaying ? timeline.date.timeIntervalSinceReferenceDate : 0
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = isPlaying ? (0.35 + 0.65 * abs(sin(t * 5.2 + Double(index) * 1.4))) : 0.3
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: 3, height: 18 * wave)
                }
            }
            .frame(height: 18, alignment: .bottom)
        }
    }
}
