import SwiftUI

/// Sheet allowing the user to add/remove a track across local playlists or create a new playlist.
struct AddToPlaylistSheet: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var showCreateAlert = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistDescription = ""

    init(track: Track) {
        self.track = track
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mochyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        // Track preview header
                        HStack(spacing: 12) {
                            MochyArtworkView(url: track.artworkURL, cornerRadius: 10)
                                .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.mochyOnSurface)
                                    .lineLimit(1)
                                Text(track.artistsText)
                                    .font(.system(size: 13))
                                    .foregroundColor(.mochySecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .mochyCard(cornerRadius: 14, fillColor: .mochySurfaceVariant)

                        // Create new playlist button
                        Button {
                            newPlaylistName = ""
                            newPlaylistDescription = ""
                            showCreateAlert = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(settings.accentColor.opacity(0.18))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(settings.accentColor)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Create New Playlist")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.mochyOnSurface)
                                    Text("Start a fresh playlist with this track")
                                        .font(.system(size: 12))
                                        .foregroundColor(.mochySecondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .mochyCard(cornerRadius: 14, fillColor: .mochySurface)
                        }
                        .buttonStyle(.plain)

                        // Existing playlists
                        if library.playlists.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 30))
                                    .foregroundColor(.mochySecondary.opacity(0.7))
                                Text("No playlists yet")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.mochyOnSurface)
                                Text("Tap above to create your first playlist.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.mochySecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(library.playlists) { playlist in
                                    let containsTrack = playlist.tracks.contains { $0.id == track.id }
                                    Button {
                                        if containsTrack {
                                            library.removeTrack(trackId: track.id, fromPlaylist: playlist.id)
                                            MochyToastCenter.shared.show("Removed from \(playlist.name)")
                                        } else {
                                            library.addTrack(track, toPlaylist: playlist.id)
                                            MochyToastCenter.shared.show("Added to \(playlist.name)")
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            MochyArtworkView(
                                                url: playlist.artworkURL,
                                                cornerRadius: 10,
                                                placeholderIcon: "music.note.list"
                                            )
                                            .frame(width: 48, height: 48)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(playlist.name)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(.mochyOnSurface)
                                                    .lineLimit(1)
                                                Text("\(playlist.tracks.count) tracks")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.mochySecondary)
                                            }

                                            Spacer()

                                            Image(systemName: containsTrack ? "checkmark.circle.fill" : "plus.circle")
                                                .font(.system(size: 21))
                                                .foregroundColor(containsTrack ? settings.accentColor : .mochySecondary)
                                        }
                                        .padding(10)
                                        .mochyCard(cornerRadius: 14, fillColor: .mochySurface)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(settings.accentColor)
                }
            }
            .alert("New Playlist", isPresented: $showCreateAlert) {
                TextField("Playlist name", text: $newPlaylistName)
                TextField("Description (optional)", text: $newPlaylistDescription)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let created = library.createPlaylist(
                        name: newPlaylistName,
                        description: newPlaylistDescription.isEmpty ? nil : newPlaylistDescription,
                        tracks: [track]
                    )
                    MochyToastCenter.shared.show("Added to \(created.name)")
                    dismiss()
                }
            } message: {
                Text("Enter a name for your new playlist.")
            }
        }
        .preferredColorScheme(.dark)
    }
}
