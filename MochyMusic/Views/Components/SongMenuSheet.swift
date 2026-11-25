import SwiftUI

/// Full Mochy Music track action menu sheet (Queue, Favorite, Playlists, Download, Album/Artist, Edit, Share, Lyrics).
struct SongMenuSheet: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var router = NavigationRouter.shared

    @State private var showAddToPlaylist = false
    @State private var showEditSheet = false
    @State private var showShareSheet = false
    @State private var showLyricsSheet = false
    @State private var currentTrackModel: Track

    init(track: Track) {
        self.track = track
        _currentTrackModel = State(initialValue: track)
    }

    private var isFavorite: Bool {
        library.isFavorite(currentTrackModel)
    }

    private var isDownloaded: Bool {
        library.isDownloaded(currentTrackModel.id)
    }

    private var isDownloading: Bool {
        downloadManager.isDownloading(currentTrackModel.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mochyBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        headerCard

                        // Quick primary action row
                        HStack(spacing: 10) {
                            quickActionPill(
                                title: isFavorite ? "Favorited" : "Favorite",
                                icon: isFavorite ? "heart.fill" : "heart",
                                tint: isFavorite ? .mochyRed : .mochyPrimary
                            ) {
                                library.toggleFavorite(currentTrackModel)
                            }

                            quickActionPill(
                                title: "Queue",
                                icon: "text.append",
                                tint: .mochyPrimary
                            ) {
                                player.addToQueue(currentTrackModel)
                                MochyToastCenter.shared.show("Added to Queue")
                                dismiss()
                            }

                            quickActionPill(
                                title: "Share",
                                icon: "square.and.arrow.up",
                                tint: .mochyPrimary
                            ) {
                                showShareSheet = true
                            }
                        }

                        // Detailed actions list
                        VStack(spacing: 2) {
                            menuRow(
                                icon: "text.line.first.and.arrowtriangle.forward",
                                title: "Play Next",
                                subtitle: "Insert right after current song"
                            ) {
                                player.playNext(currentTrackModel)
                                MochyToastCenter.shared.show("Playing next: \(currentTrackModel.title)")
                                dismiss()
                            }

                            menuRow(
                                icon: "text.badge.plus",
                                title: "Add to Playlist",
                                subtitle: "Save to one of your playlists"
                            ) {
                                showAddToPlaylist = true
                            }

                            if !currentTrackModel.isLocal {
                                menuRow(
                                    icon: isDownloaded
                                        ? "trash"
                                        : (isDownloading ? "xmark.circle" : "arrow.down.circle"),
                                    title: isDownloaded
                                        ? "Remove Download"
                                        : (isDownloading ? "Cancel Download" : "Download for Offline"),
                                    subtitle: isDownloading
                                        ? "Downloading \(Int((downloadManager.downloadProgress[currentTrackModel.id] ?? 0) * 100))%"
                                        : (isDownloaded ? "Delete local audio file" : settings.downloadQuality.displayName),
                                    iconColor: isDownloaded ? .mochyRed : .mochyGreen
                                ) {
                                    if isDownloaded {
                                        downloadManager.deleteDownload(trackId: currentTrackModel.id)
                                        MochyToastCenter.shared.show("Removed download")
                                    } else if isDownloading {
                                        downloadManager.cancelDownload(trackId: currentTrackModel.id)
                                    } else {
                                        downloadManager.download(track: currentTrackModel)
                                        MochyToastCenter.shared.show("Downloading \(currentTrackModel.title)")
                                    }
                                    dismiss()
                                }
                            }

                            if let album = currentTrackModel.album {
                                menuRow(
                                    icon: "opticaldisc",
                                    title: "Go to Album",
                                    subtitle: album.name
                                ) {
                                    dismiss()
                                    router.push(.album(id: album.browseId ?? album.id))
                                }
                            }

                            if let artist = currentTrackModel.artists.first {
                                menuRow(
                                    icon: "person.wave.2",
                                    title: "Go to Artist",
                                    subtitle: artist.name
                                ) {
                                    dismiss()
                                    router.push(.artist(id: artist.browseId ?? artist.id))
                                }
                            }

                            menuRow(
                                icon: "quote.bubble",
                                title: "View Lyrics",
                                subtitle: "Synced & plain lyrics stage"
                            ) {
                                showLyricsSheet = true
                            }

                            menuRow(
                                icon: "pencil",
                                title: "Edit Metadata",
                                subtitle: "Customize title, artist, album & tags"
                            ) {
                                showEditSheet = true
                            }

                            menuRow(
                                icon: "dot.radiowaves.left.and.right",
                                title: "Start Radio",
                                subtitle: "Play similar songs from this track"
                            ) {
                                startRadio()
                            }
                        }
                        .padding(6)
                        .mochyCard(cornerRadius: 16, fillColor: .mochySurface)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Song Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.mochySecondary)
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistSheet(track: currentTrackModel)
            }
            .sheet(isPresented: $showEditSheet) {
                SongEditSheet(track: currentTrackModel) { updated in
                    applyMetadataEdit(updated)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSongSheet(track: currentTrackModel)
            }
            .sheet(isPresented: $showLyricsSheet) {
                NavigationStack {
                    LyricsScreen(trackOverride: currentTrackModel)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showLyricsSheet = false }
                                    .foregroundColor(.mochyPrimary)
                            }
                        }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            MochyArtworkView(
                url: currentTrackModel.artworkURL,
                cornerRadius: 12,
                placeholderIcon: "music.note"
            )
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(currentTrackModel.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.mochyOnSurface)
                        .lineLimit(2)

                    if currentTrackModel.explicit {
                        Text("E")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.mochySecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(currentTrackModel.artistsText)
                    .font(.system(size: 13))
                    .foregroundColor(.mochySecondary)
                    .lineLimit(1)

                if let albumName = currentTrackModel.album?.name, !albumName.isEmpty {
                    Text("\(albumName) • \(currentTrackModel.formattedDuration)")
                        .font(.system(size: 11))
                        .foregroundColor(.mochySecondary.opacity(0.75))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(14)
        .mochyCard(cornerRadius: 16, fillColor: .mochySurfaceVariant)
    }

    private func quickActionPill(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.mochyOnSurface)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .mochyCard(cornerRadius: 14, fillColor: .mochySurfaceVariant)
        }
        .buttonStyle(.plain)
    }

    private func menuRow(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = .mochyPrimary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.mochyOnSurface)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.mochySecondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func applyMetadataEdit(_ updated: Track) {
        currentTrackModel = updated

        if player.currentTrack?.id == updated.id {
            player.currentTrack = updated
        }
        if let qIdx = player.queue.firstIndex(where: { $0.id == updated.id }) {
            player.queue[qIdx] = updated
        }
        if let fIdx = library.favorites.firstIndex(where: { $0.id == updated.id }) {
            library.favorites[fIdx] = updated
            PersistenceManager.shared.saveFavorites(library.favorites)
        }
        for pIdx in library.playlists.indices {
            var changed = false
            for tIdx in library.playlists[pIdx].tracks.indices where library.playlists[pIdx].tracks[tIdx].id == updated.id {
                library.playlists[pIdx].tracks[tIdx] = updated
                changed = true
            }
            if changed {
                library.playlists[pIdx].lastUpdatedDate = Date()
            }
        }
        PersistenceManager.shared.savePlaylists(library.playlists)
    }

    private func startRadio() {
        Task {
            do {
                let upNext = try await InnerTubeService.shared.fetchUpNext(videoId: currentTrackModel.id)
                let combined = [currentTrackModel] + upNext.filter { $0.id != currentTrackModel.id }
                player.play(tracks: combined, startIndex: 0)
                MochyToastCenter.shared.show("Started Radio for \(currentTrackModel.title)")
                dismiss()
            } catch {
                player.play(track: currentTrackModel)
                dismiss()
            }
        }
    }
}
