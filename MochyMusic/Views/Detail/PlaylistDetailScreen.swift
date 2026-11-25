import SwiftUI

/// Full detail screen supporting both local `UserPlaylist` (editable, reorderable, swipe-to-remove) and remote `YouTubePlaylist`.
struct PlaylistDetailScreen: View {
    private let remotePlaylistId: String?
    private let localPlaylistId: UUID?
    private let isLocal: Bool

    @StateObject private var viewModel = PlaylistViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showAddSongsSheet = false

    init(playlistId: String, isLocal: Bool = false) {
        if isLocal, let uuid = UUID(uuidString: playlistId) {
            self.localPlaylistId = uuid
            self.remotePlaylistId = nil
            self.isLocal = true
        } else {
            self.remotePlaylistId = playlistId
            self.localPlaylistId = nil
            self.isLocal = false
        }
    }

    init(localPlaylistId: UUID) {
        self.localPlaylistId = localPlaylistId
        self.remotePlaylistId = nil
        self.isLocal = true
    }

    private var localPlaylist: UserPlaylist? {
        guard let id = localPlaylistId else { return nil }
        return library.playlists.first { $0.id == id }
    }

    private var displayedTracks: [Track] {
        isLocal ? (localPlaylist?.tracks ?? []) : viewModel.tracks
    }

    private var playlistTitle: String {
        if isLocal {
            return localPlaylist?.name ?? "Playlist"
        }
        return viewModel.playlist?.name ?? "Playlist"
    }

    var body: some View {
        Group {
            if !isLocal && viewModel.isLoading && viewModel.tracks.isEmpty {
                loadingState
            } else if !isLocal, let error = viewModel.error, viewModel.tracks.isEmpty {
                errorState(error)
            } else {
                playlistContent
            }
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle(playlistTitle)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isLocal, let localPlaylist {
                    Button {
                        showAddSongsSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(settings.accentColor)
                    }

                    Menu {
                        Button {
                            renameText = localPlaylist.name
                            showRenameAlert = true
                        } label: {
                            Label("Rename Playlist", systemImage: "pencil")
                        }

                        Button {
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        } label: {
                            Label(editMode == .active ? "Done Reordering" : "Reorder Songs", systemImage: "arrow.up.arrow.down")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.mochyOnBackground)
                    }
                } else if let shareURL = viewModel.playlist?.shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.mochyOnBackground)
                    }
                }
            }
        }
        .alert("Rename Playlist", isPresented: $showRenameAlert) {
            TextField("Playlist name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let id = localPlaylistId {
                    library.renamePlaylist(id: id, newName: renameText)
                }
            }
        }
        .confirmationDialog("Delete this playlist?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = localPlaylistId {
                    library.deletePlaylist(id: id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAddSongsSheet) {
            if let id = localPlaylistId {
                AddSongsToPlaylistSheet(playlistId: id)
            }
        }
        .task {
            if !isLocal, let remoteId = remotePlaylistId, viewModel.playlist == nil {
                await viewModel.loadPlaylist(browseId: remoteId)
            }
        }
    }

    // MARK: - Playlist Content

    private var playlistContent: some View {
        List {
            Section {
                headerBlock
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if displayedTracks.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 38))
                            .foregroundColor(.mochySecondary)
                        Text("No songs in this playlist yet")
                            .font(.mochyHeadline)
                            .foregroundColor(.mochyOnBackground)
                        if isLocal {
                            Button("Add Songs") {
                                showAddSongsSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(settings.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                        TrackRowView(track: track, index: index + 1) {
                            player.play(tracks: displayedTracks, startIndex: index)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { offsets in
                        guard isLocal, let id = localPlaylistId else { return }
                        for idx in offsets.sorted(by: >) {
                            library.removeTrack(at: idx, fromPlaylist: id)
                        }
                    }
                    .onMove { source, destination in
                        guard isLocal, let id = localPlaylistId else { return }
                        library.reorderTracks(inPlaylist: id, from: source, to: destination)
                    }
                }
            }

            if !isLocal && viewModel.continuation != nil {
                Section {
                    HStack {
                        Spacer()
                        ProgressView().tint(settings.accentColor)
                            .onAppear {
                                Task { await viewModel.loadMore() }
                            }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                Color.clear
                    .frame(height: player.currentTrack != nil ? 130 : 80)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Header Block

    private var headerBlock: some View {
        VStack(spacing: 14) {
            playlistArtwork
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.5), radius: 18, x: 0, y: 10)

            VStack(spacing: 4) {
                Text(playlistTitle)
                    .font(MochyTheme.titleFont(size: 24))
                    .foregroundColor(.mochyOnBackground)
                    .multilineTextAlignment(.center)

                if let author = viewModel.playlist?.author, !author.isEmpty, !isLocal {
                    Text("by \(author)")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                }

                Text("\(displayedTracks.count) song\(displayedTracks.count == 1 ? "" : "s") • \(formattedTotalDuration)")
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
            }

            HStack(spacing: 12) {
                Button {
                    guard !displayedTracks.isEmpty else { return }
                    player.play(tracks: displayedTracks, startIndex: 0)
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.mochyBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(settings.accentColor))
                }
                .buttonStyle(.plain)

                Button {
                    guard !displayedTracks.isEmpty else { return }
                    player.play(tracks: displayedTracks.shuffled(), startIndex: 0)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.mochyOnBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.mochyEffectiveSurface))
                }
                .buttonStyle(.plain)
            }

            if !isLocal && !displayedTracks.isEmpty {
                Button {
                    library.createPlaylist(
                        name: playlistTitle,
                        description: viewModel.playlist?.description,
                        tracks: displayedTracks,
                        thumbnailURL: viewModel.playlist?.thumbnailURL
                    )
                } label: {
                    Label("Save Copy to Library", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(settings.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.mochyEffectiveSurface))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var playlistArtwork: some View {
        let mosaicTracks = Array(displayedTracks.prefix(4))
        if isLocal && mosaicTracks.count >= 4 {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                ForEach(mosaicTracks) { track in
                    AsyncImage(url: track.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.mochyEffectiveSurface
                        }
                    }
                    .frame(width: 110, height: 110)
                    .clipped()
                }
            }
        } else {
            let url = isLocal ? localPlaylist?.artworkURL : viewModel.playlist?.artworkURL
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.mochyEffectiveSurface)
                        .overlay(
                            Image(systemName: "music.note.list")
                                .font(.system(size: 48))
                                .foregroundColor(.mochySecondary)
                        )
                }
            }
        }
    }

    private var formattedTotalDuration: String {
        let total = displayedTracks.compactMap(\.durationSeconds).reduce(0, +)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins) min"
    }

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.mochyEffectiveSurface)
                    .frame(width: 220, height: 220)
                    .mochyShimmer()
                ForEach(0..<6, id: \.self) { _ in
                    ShimmerRowPlaceholder()
                }
            }
            .padding()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.mochyBody)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") {
                if let remoteId = remotePlaylistId {
                    Task { await viewModel.loadPlaylist(browseId: remoteId) }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Helper sheet to pick songs from Favorites, History, or Local Files to add to a local playlist.
private struct AddSongsToPlaylistSheet: View {
    let playlistId: UUID

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""

    private var candidateTracks: [Track] {
        var unique: [String: Track] = [:]
        for track in library.favorites + library.recentlyPlayed.map(\.track) + library.localTracks {
            unique[track.id] = track
        }
        let all = Array(unique.values).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artistsText.localizedCaseInsensitiveContains(query)
        }
    }

    private var existingIds: Set<String> {
        Set(library.playlists.first(where: { $0.id == playlistId })?.tracks.map(\.id) ?? [])
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidateTracks) { track in
                    let alreadyAdded = existingIds.contains(track.id)
                    HStack(spacing: 12) {
                        AsyncImage(url: track.artworkURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                RoundedRectangle(cornerRadius: 8).fill(Color.mochyEffectiveSurface)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.mochyBody)
                                .foregroundColor(.mochyOnBackground)
                                .lineLimit(1)
                            Text(track.artistsText)
                                .font(.mochyCaption)
                                .foregroundColor(.mochySecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            if alreadyAdded {
                                library.removeTrack(trackId: track.id, fromPlaylist: playlistId)
                            } else {
                                library.addTrack(track, toPlaylist: playlistId)
                            }
                        } label: {
                            Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 22))
                                .foregroundColor(alreadyAdded ? settings.accentColor : .mochySecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Filter songs in library")
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(settings.accentColor)
                }
            }
        }
    }
}
