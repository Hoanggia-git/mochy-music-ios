import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore

    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            List {
                Section("Collection") {
                    NavigationLink {
                        TrackCollectionView(title: "Favorites", tracks: library.favorites)
                    } label: {
                        Label {
                            HStack {
                                Text("Favorites")
                                Spacer()
                                Text("\(library.favorites.count)")
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.pink)
                        }
                    }

                    NavigationLink {
                        TrackCollectionView(title: "Downloads", tracks: library.downloadedTracks)
                    } label: {
                        Label {
                            HStack {
                                Text("Downloaded (Offline)")
                                Spacer()
                                Text("\(library.downloadedTracks.count)")
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }

                    NavigationLink {
                        TrackCollectionView(title: "Recently Played", tracks: library.recentlyPlayed)
                    } label: {
                        Label {
                            HStack {
                                Text("Recently Played")
                                Spacer()
                                Text("\(library.recentlyPlayed.count)")
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }

                Section {
                    if library.playlists.isEmpty {
                        Text("Tap + to create a playlist")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(library.playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlistID: playlist.id)
                            } label: {
                                Label {
                                    HStack {
                                        Text(playlist.name)
                                        Spacer()
                                        Text("\(playlist.tracks.count)")
                                            .foregroundColor(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "music.note.list")
                                        .foregroundColor(.purple)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                library.deletePlaylist(id: library.playlists[index].id)
                            }
                        }
                    }
                } header: {
                    Text("Playlists")
                }

                if player.currentTrack != nil {
                    Color.clear
                        .frame(height: 68)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newPlaylistName = ""
                        showNewPlaylistAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Create") {
                    library.createPlaylist(name: newPlaylistName)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showAbout) {
                AboutSheet()
            }
        }
    }
}

struct TrackCollectionView: View {
    let title: String
    let tracks: [Track]

    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        List {
            if tracks.isEmpty {
                Text("Nothing here yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(tracks) { track in
                    TrackRowView(track: track) {
                        player.play(track: track, inQueue: tracks)
                    }
                }
            }

            if player.currentTrack != nil {
                Color.clear
                    .frame(height: 68)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
    }
}

struct PlaylistDetailView: View {
    let playlistID: UUID
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore

    private var playlist: UserPlaylist? {
        library.playlists.first(where: { $0.id == playlistID })
    }

    var body: some View {
        List {
            if let playlist {
                if playlist.tracks.isEmpty {
                    Text("No songs in this playlist yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(playlist.tracks) { track in
                        TrackRowView(track: track) {
                            player.play(track: track, inQueue: playlist.tracks)
                        }
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            library.removeTrack(playlist.tracks[idx], fromPlaylist: playlistID)
                        }
                    }
                }
            }

            if player.currentTrack != nil {
                Color.clear
                    .frame(height: 68)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist?.name ?? "Playlist")
    }
}

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Mochy Music iOS (Unofficial MVP)") {
                    Text("An open-source SwiftUI iOS client inspired by realidkroo/Mochy-Music, licensed under GPL-3.0.")
                        .font(.subheadline)
                }

                Section("Credits") {
                    Text("Original Android App: realidkroo/Mochy-Music")
                    Text("Synced Lyrics API: LRCLIB (lrclib.net)")
                    Text("Stream & Search Protocol: InnerTube")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
