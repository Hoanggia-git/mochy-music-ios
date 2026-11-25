import SwiftUI

/// Main Library hub with profile greeting, 2x2 quick actions, swipe-to-delete playlists, recently played, and create playlist FAB.
struct LibraryScreen: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @State private var showCreatePlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistDescription = ""

    private let twoColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section {
                    headerView
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    quickActionGrid
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    HStack {
                        Text("Your Playlists")
                            .font(.mochyHeadline)
                            .foregroundColor(.mochyOnBackground)
                        Spacer()
                        Button {
                            router.push(.importMusic)
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(settings.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if library.playlists.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 30))
                                .foregroundColor(.mochySecondary)
                            Text("No playlists yet")
                                .font(.mochySubheadline)
                                .foregroundColor(.mochyOnBackground)
                            Text("Create a playlist or import from Spotify, Apple Music, or CSV.")
                                .font(.mochyCaption)
                                .foregroundColor(.mochySecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .mochyCard(cornerRadius: 16, fillColor: .mochyEffectiveSurface)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(library.playlists) { playlist in
                            Button {
                                router.push(.localPlaylist(id: playlist.id))
                            } label: {
                                playlistRow(playlist)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    library.deletePlaylist(playlist)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }

                if !library.recentlyPlayed.isEmpty {
                    Section {
                        recentlyPlayedSection
                            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                Section {
                    Color.clear
                        .frame(height: player.currentTrack != nil ? 140 : 88)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())

            // Floating Action Button to create playlist
            Button {
                newPlaylistName = ""
                newPlaylistDescription = ""
                showCreatePlaylistAlert = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.mochyBackground)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(settings.accentColor))
                    .shadow(color: settings.accentColor.opacity(0.35), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18)
            .padding(.bottom, player.currentTrack != nil ? 148 : 84)
        }
        .navigationBarHidden(true)
        .alert("New Playlist", isPresented: $showCreatePlaylistAlert) {
            TextField("Playlist name", text: $newPlaylistName)
            TextField("Description (optional)", text: $newPlaylistDescription)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let desc = newPlaylistDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                library.createPlaylist(
                    name: newPlaylistName,
                    description: desc.isEmpty ? nil : desc
                )
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Button {
                router.push(.profile)
            } label: {
                Circle()
                    .fill(settings.accentColor.opacity(0.2))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text(String(settings.username.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(settings.accentColor)
                    )
                    .overlay(Circle().stroke(settings.accentColor.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your Library")
                    .font(MochyTheme.titleFont(size: 26))
                    .foregroundColor(.mochyOnBackground)
                Text(settings.username)
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
            }

            Spacer()

            Button {
                router.push(.recap)
            } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.mochyPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.mochyEffectiveSurface))
            }
            .buttonStyle(.plain)

            Button {
                newPlaylistName = ""
                newPlaylistDescription = ""
                showCreatePlaylistAlert = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(settings.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.mochyEffectiveSurface))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 2x2 Quick Action Grid

    private var quickActionGrid: some View {
        LazyVGrid(columns: twoColumns, spacing: 12) {
            quickActionTile(
                title: "Favorites",
                countText: "\(library.favorites.count) songs",
                icon: "heart.fill",
                tint: .mochyRed
            ) {
                router.push(.favorites)
            }

            quickActionTile(
                title: "Downloads",
                countText: "\(library.downloadedTracks.count) offline",
                icon: "arrow.down.circle.fill",
                tint: .mochyGreen
            ) {
                router.push(.downloads)
            }

            quickActionTile(
                title: "History",
                countText: "\(library.recentlyPlayed.count) played",
                icon: "clock.arrow.circlepath",
                tint: .mochyBlue
            ) {
                router.push(.history)
            }

            quickActionTile(
                title: "Local Files",
                countText: "\(library.localTracks.count) files",
                icon: "folder.fill",
                tint: .mochyPeach
            ) {
                router.push(.localFiles)
            }
        }
    }

    private func quickActionTile(
        title: String,
        countText: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.16)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.mochyOnBackground)
                    Text(countText)
                        .font(.system(size: 11))
                        .foregroundColor(.mochySecondary)
                }
                Spacer()
            }
            .padding(12)
            .mochyCard(cornerRadius: 14, fillColor: .mochyEffectiveSurface)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playlist Row

    private func playlistRow(_ playlist: UserPlaylist) -> some View {
        HStack(spacing: 12) {
            playlistMosaic(for: playlist)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.mochySubheadline)
                    .foregroundColor(.mochyOnBackground)
                    .lineLimit(1)
                Text("\(playlist.tracks.count) song\(playlist.tracks.count == 1 ? "" : "s")")
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.mochySecondary)
        }
        .padding(10)
        .mochyCard(cornerRadius: 14, fillColor: .mochyEffectiveSurface)
    }

    @ViewBuilder
    private func playlistMosaic(for playlist: UserPlaylist) -> some View {
        let covers = Array(playlist.tracks.prefix(4))
        if covers.count >= 4 {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                ForEach(covers) { track in
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.mochySurfaceVariant
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipped()
                }
            }
        } else {
            AsyncImage(url: playlist.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.mochySurfaceVariant)
                        .overlay(
                            Image(systemName: "music.note.list")
                                .foregroundColor(.mochySecondary)
                        )
                }
            }
        }
    }

    // MARK: - Recently Played

    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recently Played")
                    .font(.mochyHeadline)
                    .foregroundColor(.mochyOnBackground)
                Spacer()
                Button("See All") {
                    router.push(.history)
                }
                .font(.mochyCaption)
                .foregroundColor(settings.accentColor)
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    let tracks = Array(library.recentlyPlayed.prefix(15).map(\.track))
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                        Button {
                            player.play(tracks: tracks, startIndex: idx)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: track.artworkURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    default:
                                        RoundedRectangle(cornerRadius: 12).fill(Color.mochyEffectiveSurface)
                                    }
                                }
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                Text(track.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.mochyOnBackground)
                                    .lineLimit(1)
                                Text(track.artistsText)
                                    .font(.system(size: 11))
                                    .foregroundColor(.mochySecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 112)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }
}
