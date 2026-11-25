import SwiftUI

/// Full YouTube Music search experience with custom AMOLED search bar, live suggestions, filters, and search history.
struct SearchScreen: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @FocusState private var isSearchFocused: Bool
    @State private var showRecognition = false

    private let twoColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            searchBarHeader
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 10)

            filterChipsRow
                .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !viewModel.suggestions.isEmpty && isSearchFocused {
                        suggestionsDropdown
                    } else if viewModel.isLoading {
                        loadingPlaceholders
                    } else if let error = viewModel.error {
                        errorView(error)
                    } else if viewModel.submittedQuery.isEmpty {
                        idleSearchContent
                    } else if !viewModel.hasResults {
                        noResultsView
                    } else {
                        resultsContent
                    }
                }
                .padding(.bottom, player.currentTrack != nil ? 175 : 120)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showRecognition) {
            RecognitionSheet()
        }
    }

    // MARK: - Custom Search Bar

    private var searchBarHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.mochySecondary)

                TextField("Songs, albums, artists, playlists...", text: $viewModel.query)
                    .font(.mochyBody)
                    .foregroundColor(.mochyOnBackground)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.query) { newValue in
                        viewModel.onQueryChanged(newValue)
                    }
                    .onSubmit {
                        isSearchFocused = false
                        Task { await viewModel.search() }
                    }

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.mochySecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.mochyEffectiveSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSearchFocused ? settings.accentColor.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )

            Button {
                showRecognition = true
            } label: {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(settings.accentColor)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.mochyEffectiveSurface)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Filter Chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", isSelected: viewModel.selectedFilter == nil) {
                    Task { await viewModel.selectFilter(nil) }
                }

                ForEach(SearchFilter.allCases) { filter in
                    filterChip(title: filterLabel(filter), isSelected: viewModel.selectedFilter == filter) {
                        Task { await viewModel.selectFilter(filter) }
                    }
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .mochyBackground : .mochyPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? settings.accentColor : Color.mochyEffectiveSurface)
                )
        }
        .buttonStyle(.plain)
    }

    private func filterLabel(_ filter: SearchFilter) -> String {
        switch filter {
        case .songs: return "Songs"
        case .videos: return "Videos"
        case .albums: return "Albums"
        case .artists: return "Artists"
        case .playlists: return "Playlists"
        case .communityPlaylists: return "Community"
        }
    }

    // MARK: - Live Suggestions Dropdown

    private var suggestionsDropdown: some View {
        VStack(spacing: 2) {
            ForEach(viewModel.suggestions) { suggestion in
                Button {
                    isSearchFocused = false
                    Task { await viewModel.search(overrideQuery: suggestion.text) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: suggestion.isHistory ? "clock.arrow.circlepath" : "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.mochySecondary)
                            .frame(width: 24)

                        Text(suggestion.text)
                            .font(.mochyBody)
                            .foregroundColor(.mochyOnBackground)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            viewModel.query = suggestion.text
                        } label: {
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 13))
                                .foregroundColor(.mochySecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Idle Content (Explore Banner + Search History)

    private var idleSearchContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                router.push(.explore)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(settings.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(settings.accentColor.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Explore Charts & Moods")
                            .font(.mochySubheadline)
                            .foregroundColor(.mochyOnBackground)
                        Text("Discover new releases, top charts, and genres")
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochySecondary)
                }
                .padding(14)
                .mochyCard(cornerRadius: 16, fillColor: .mochyEffectiveSurface)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            if library.searchHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.mochySecondary.opacity(0.7))
                    Text("Search YouTube Music")
                        .font(.mochyHeadline)
                        .foregroundColor(.mochyOnBackground)
                    Text("Find songs, music videos, albums, artists, and community playlists.")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent Searches")
                            .font(.mochyHeadline)
                            .foregroundColor(.mochyOnBackground)
                        Spacer()
                        Button("Clear History") {
                            library.clearSearchHistory()
                        }
                        .font(.mochyCaption)
                        .foregroundColor(settings.accentColor)
                    }
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)

                    ForEach(library.searchHistory, id: \.self) { term in
                        HStack(spacing: 12) {
                            Button {
                                isSearchFocused = false
                                Task { await viewModel.search(overrideQuery: term) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 14))
                                        .foregroundColor(.mochySecondary)
                                    Text(term)
                                        .font(.mochyBody)
                                        .foregroundColor(.mochyOnBackground)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                library.removeSearchQuery(term)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.mochySecondary)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var resultsContent: some View {
        if viewModel.selectedFilter == nil {
            ForEach(viewModel.allSections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title)
                        .font(.mochyHeadline)
                        .foregroundColor(.mochyOnBackground)
                        .padding(.horizontal, MochyTheme.screenHorizontalPadding)

                    let sectionTracks = section.items.compactMap { item -> Track? in
                        if case .track(let track) = item { return track }
                        return nil
                    }

                    ForEach(section.items) { item in
                        allSectionRow(item, sectionTracks: sectionTracks)
                    }
                }
            }
        } else {
            switch viewModel.selectedFilter {
            case .albums:
                let albums = viewModel.filteredItems.compactMap { item -> Album? in
                    if case .album(let album) = item { return album }
                    return nil
                }
                LazyVGrid(columns: twoColumns, spacing: 14) {
                    ForEach(albums) { album in
                        AlbumCard(album: album) {
                            router.push(.album(id: album.browseId ?? album.id))
                        }
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            case .artists:
                let artists = viewModel.filteredItems.compactMap { item -> Artist? in
                    if case .artist(let artist) = item { return artist }
                    return nil
                }
                ForEach(artists) { artist in
                    artistRow(artist)
                }

            case .playlists, .communityPlaylists:
                let playlists = viewModel.filteredItems.compactMap { item -> YouTubePlaylist? in
                    if case .playlist(let playlist) = item { return playlist }
                    return nil
                }
                ForEach(playlists) { playlist in
                    playlistRow(playlist)
                }

            case .songs, .videos, .none:
                let tracks = viewModel.filteredItems.compactMap { item -> Track? in
                    if case .track(let track) = item { return track }
                    return nil
                }
                ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                    TrackRowView(track: track) {
                        player.play(tracks: tracks, startIndex: idx)
                    }
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                }
            }

            if viewModel.continuation != nil {
                HStack {
                    Spacer()
                    if viewModel.isLoadingMore {
                        ProgressView().tint(settings.accentColor)
                    } else {
                        Color.clear
                            .frame(height: 24)
                            .onAppear {
                                Task { await viewModel.loadMore() }
                            }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func allSectionRow(_ item: HomeSectionItem, sectionTracks: [Track]) -> some View {
        switch item {
        case .track(let track):
            let idx = sectionTracks.firstIndex(where: { $0.id == track.id }) ?? 0
            TrackRowView(track: track) {
                player.play(tracks: sectionTracks.isEmpty ? [track] : sectionTracks, startIndex: idx)
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)

        case .album(let album):
            Button {
                router.push(.album(id: album.browseId ?? album.id))
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: album.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            RoundedRectangle(cornerRadius: 10).fill(Color.mochyEffectiveSurface)
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(album.name)
                            .font(.mochySubheadline)
                            .foregroundColor(.mochyOnBackground)
                            .lineLimit(1)
                        Text("Album • \(album.artistsText)")
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.mochySecondary)
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

        case .artist(let artist):
            artistRow(artist)

        case .playlist(let playlist):
            playlistRow(playlist)
        }
    }

    private func artistRow(_ artist: Artist) -> some View {
        Button {
            router.push(.artist(id: artist.browseId ?? artist.id))
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: artist.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Circle().fill(Color.mochyEffectiveSurface)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.mochySecondary))
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(artist.name)
                        .font(.mochySubheadline)
                        .foregroundColor(.mochyOnBackground)
                        .lineLimit(1)
                    Text(artist.subscriberCount ?? "Artist")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.mochySecondary)
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func playlistRow(_ playlist: YouTubePlaylist) -> some View {
        Button {
            router.push(.playlist(id: playlist.id, isLocal: false))
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: playlist.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        RoundedRectangle(cornerRadius: 10).fill(Color.mochyEffectiveSurface)
                            .overlay(Image(systemName: "music.note.list").foregroundColor(.mochySecondary))
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.mochySubheadline)
                        .foregroundColor(.mochyOnBackground)
                        .lineLimit(1)
                    Text(playlist.author ?? "Playlist")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.mochySecondary)
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading & Empty States

    private var loadingPlaceholders: some View {
        VStack(spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                ShimmerRowPlaceholder()
            }
        }
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.magnifyingglass")
                .font(.system(size: 38))
                .foregroundColor(.mochySecondary)
            Text("No results for \"\(viewModel.submittedQuery)\"")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
            Text("Try different keywords or switch filters above.")
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundColor(.mochyRed)
            Text(message)
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Retry") {
                Task { await viewModel.search() }
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
