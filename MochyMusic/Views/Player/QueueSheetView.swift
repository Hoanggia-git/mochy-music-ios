import SwiftUI
import UIKit

/// Interactive Up Next queue sheet supporting drag-to-reorder, swipe-to-remove, tap-to-jump, clear, and save as playlist.
struct QueueSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var showSavePlaylistAlert = false
    @State private var playlistName = ""
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mochyBackground.ignoresSafeArea()

                if player.queue.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 40))
                            .foregroundColor(.mochySecondary.opacity(0.6))
                        Text("Queue is Empty")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.mochyOnSurface)
                        Text("Play a song or add tracks to build your Up Next queue.")
                            .font(.system(size: 13))
                            .foregroundColor(.mochySecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                } else {
                    VStack(spacing: 0) {
                        queueControlsBar

                        List {
                            ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
                                queueRow(track: track, index: index)
                                    .listRowBackground(
                                        index == player.currentIndex
                                            ? settings.accentColor.opacity(0.12)
                                            : Color.mochyBackground
                                    )
                                    .listRowSeparatorTint(Color.white.opacity(0.07))
                            }
                            .onMove { source, destination in
                                player.moveQueueItem(from: source, to: destination)
                            }
                            .onDelete { offsets in
                                for idx in offsets.sorted(by: >) {
                                    player.removeFromQueue(at: idx)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .environment(\.editMode, $editMode)
                    }
                }
            }
            .navigationTitle("Up Next (\(player.queue.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button {
                            playlistName = "Queue • \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))"
                            showSavePlaylistAlert = true
                        } label: {
                            Label("Save Queue as Playlist", systemImage: "text.badge.plus")
                        }

                        Button(role: .destructive) {
                            player.clearQueue()
                            MochyToastCenter.shared.show("Cleared upcoming queue")
                        } label: {
                            Label("Clear Up Next", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.mochyPrimary)
                    }
                    .disabled(player.queue.isEmpty)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(settings.accentColor)
                }
            }
            .alert("Save Queue as Playlist", isPresented: $showSavePlaylistAlert) {
                TextField("Playlist name", text: $playlistName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let created = library.createPlaylist(name: playlistName, tracks: player.queue)
                    MochyToastCenter.shared.show("Saved \(created.tracks.count) tracks to \(created.name)")
                }
            } message: {
                Text("Create a new local playlist from the current queue.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var queueControlsBar: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                player.toggleShuffle()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(player.isShuffled ? .black : .mochyOnSurface)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(player.isShuffled ? settings.accentColor : Color.mochySurfaceVariant)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                player.cycleRepeatMode()
            } label: {
                Label(repeatTitle, systemImage: player.repeatMode.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(player.repeatMode != .off ? .black : .mochyOnSurface)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(player.repeatMode != .off ? settings.accentColor : Color.mochySurfaceVariant)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(totalRemainingDurationText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.mochySecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mochySurface)
    }

    private func queueRow(track: Track, index: Int) -> some View {
        let isCurrent = index == player.currentIndex
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            player.play(tracks: player.queue, startIndex: index)
        } label: {
            HStack(spacing: 12) {
                MochyArtworkView(url: track.artworkURL, cornerRadius: 8)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.5))
                            MiniPlayingBars(isPlaying: player.isPlaying, color: settings.accentColor)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: isCurrent ? .bold : .semibold))
                        .foregroundColor(isCurrent ? settings.accentColor : .mochyOnSurface)
                        .lineLimit(1)
                    Text(track.artistsText)
                        .font(.system(size: 12))
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(track.formattedDuration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.mochySecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var repeatTitle: String {
        switch player.repeatMode {
        case .off: return "Repeat Off"
        case .all: return "Repeat All"
        case .one: return "Repeat One"
        }
    }

    private var totalRemainingDurationText: String {
        let remaining = player.queue.dropFirst(max(0, player.currentIndex))
            .compactMap(\.durationSeconds)
            .reduce(0, +)
        let mins = remaining / 60
        let hrs = mins / 60
        if hrs > 0 {
            return "\(hrs)h \(mins % 60)m"
        }
        return "\(mins)m left"
    }
}
