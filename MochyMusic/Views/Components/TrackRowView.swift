import SwiftUI

struct TrackRowView: View {
    let track: Track
    let onTap: () -> Void

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @State private var showPlaylistPicker = false

    private var isCurrent: Bool {
        player.currentTrack?.id == track.id
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: track.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        ZStack {
                            Color.secondary.opacity(0.2)
                            Image(systemName: "music.note")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundColor(isCurrent ? .accentColor : .primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if library.isDownloaded(track) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        }
                        Text(track.artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !track.formattedDuration.isEmpty {
                    Text(track.formattedDuration)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Menu {
                    Button {
                        library.toggleFavorite(track)
                    } label: {
                        Label(
                            library.isFavorite(track) ? "Remove Favorite" : "Add to Favorites",
                            systemImage: library.isFavorite(track) ? "heart.slash" : "heart"
                        )
                    }

                    Button {
                        showPlaylistPicker = true
                    } label: {
                        Label("Add to Playlist", systemImage: "text.badge.plus")
                    }

                    if library.isDownloaded(track) {
                        Button(role: .destructive) {
                            library.removeDownload(track)
                        } label: {
                            Label("Remove Download", systemImage: "trash")
                        }
                    } else if library.downloadingIDs.contains(track.id) {
                        Label("Downloading...", systemImage: "arrow.down.circle")
                    } else {
                        Button {
                            Task {
                                await library.downloadTrack(track)
                            }
                        } label: {
                            Label("Download Offline", systemImage: "arrow.down.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPlaylistPicker) {
            PlaylistPickerSheet(track: track)
        }
    }
}

struct PlaylistPickerSheet: View {
    let track: Track
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("New Playlist") {
                    HStack {
                        TextField("Playlist name", text: $newName)
                        Button("Create") {
                            library.createPlaylist(name: newName)
                            newName = ""
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Your Playlists") {
                    if library.playlists.isEmpty {
                        Text("No playlists yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(library.playlists) { playlist in
                            Button {
                                library.addTrack(track, toPlaylist: playlist.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(playlist.name)
                                    Spacer()
                                    Text("\(playlist.tracks.count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
