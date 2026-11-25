import SwiftUI

/// Genre / Mood browse page navigated from ExploreScreen with paginated continuation loading.
struct BrowseScreen: View {
    let browseId: String
    let title: String
    let params: String?

    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @State private var sections: [HomeSection] = []
    @State private var continuation: String?
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var error: String?

    private let twoColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 22) {
                if isLoading && sections.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in
                            ShimmerRowPlaceholder()
                        }
                    }
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                } else if let error, sections.isEmpty {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.mochyBody)
                            .foregroundColor(.mochySecondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadInitial() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accentColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    ForEach(sections) { section in
                        browseSectionView(section)
                    }

                    if continuation != nil {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView().tint(settings.accentColor)
                            } else {
                                Color.clear
                                    .frame(height: 24)
                                    .onAppear {
                                        Task { await loadMore() }
                                    }
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, player.currentTrack != nil ? 150 : 96)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadInitial()
        }
        .task {
            if sections.isEmpty {
                await loadInitial()
            }
        }
    }

    @ViewBuilder
    private func browseSectionView(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !section.title.isEmpty {
                Text(section.title)
                    .font(.mochyHeadline)
                    .foregroundColor(.mochyOnBackground)
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }

            let tracks = section.items.compactMap { item -> Track? in
                if case .track(let track) = item { return track }
                return nil
            }
            let nonTrackItems = section.items.filter {
                if case .track = $0 { return false }
                return true
            }

            if !tracks.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                        TrackRowView(track: track) {
                            player.play(tracks: tracks, startIndex: idx)
                        }
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }

            if !nonTrackItems.isEmpty {
                LazyVGrid(columns: twoColumns, spacing: 14) {
                    ForEach(nonTrackItems) { item in
                        switch item {
                        case .album(let album):
                            AlbumCard(album: album) {
                                router.push(.album(id: album.browseId ?? album.id))
                            }
                        case .artist(let artist):
                            ArtistCard(artist: artist) {
                                router.push(.artist(id: artist.browseId ?? artist.id))
                            }
                        case .playlist(let playlist):
                            PlaylistCard(
                                title: playlist.name,
                                subtitle: playlist.author,
                                thumbnailURL: playlist.thumbnailURL
                            ) {
                                router.push(.playlist(id: playlist.id, isLocal: false))
                            }
                        case .track:
                            EmptyView()
                        }
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }

    private func loadInitial() async {
        isLoading = true
        error = nil
        do {
            let result = try await InnerTubeService.shared.fetchBrowse(browseId: browseId, params: params, continuation: nil)
            sections = result.sections
            continuation = result.continuation
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, let token = continuation, !token.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await InnerTubeService.shared.fetchBrowse(browseId: browseId, params: params, continuation: token)
            sections.append(contentsOf: result.sections)
            continuation = result.continuation
        } catch {
            // Preserve loaded sections
        }
    }
}
