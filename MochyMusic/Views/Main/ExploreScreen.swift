import SwiftUI

/// Explore & Discover view showcasing New Releases, Charts, Moods & Genres, and Trending songs.
struct ExploreScreen: View {
    @StateObject private var viewModel = ExploreViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    private let twoColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private let fallbackMoodPalette: [Color] = [
        .mochyPeach, .mochyMauve, .mochyBlue, .mochyGreen,
        .mochyPink, .mochyTeal, .mochyLavender, .mochyRed
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                if viewModel.isLoading && viewModel.newReleases.isEmpty && viewModel.moodsAndGenres.isEmpty {
                    loadingState
                } else if let error = viewModel.error, viewModel.newReleases.isEmpty && viewModel.moodsAndGenres.isEmpty {
                    errorView(error)
                } else {
                    if !viewModel.newReleases.isEmpty {
                        newReleasesSection
                    }

                    if !viewModel.moodsAndGenres.isEmpty {
                        moodsAndGenresSection
                    }

                    if !viewModel.trendingTracks.isEmpty {
                        chartsAndTrendingSection
                    }

                    ForEach(viewModel.exploreSections) { section in
                        extraExploreSection(section)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, player.currentTrack != nil ? 175 : 120)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.loadExploreFeed()
        }
        .task {
            await viewModel.loadExploreFeedIfNeeded()
        }
    }

    // MARK: - New Releases

    private var newReleasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Releases")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.newReleases) { album in
                        AlbumCard(album: album) {
                            router.push(.album(id: album.browseId ?? album.id))
                        }
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }

    // MARK: - Moods & Genres

    private var moodsAndGenresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Moods & Genres")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            LazyVGrid(columns: twoColumns, spacing: 10) {
                ForEach(Array(viewModel.moodsAndGenres.enumerated()), id: \.element.id) { index, item in
                    let stripeColor: Color = {
                        if let hex = item.stripeColorHex {
                            return Color(hex: hex)
                        }
                        return fallbackMoodPalette[index % fallbackMoodPalette.count]
                    }()

                    Button {
                        router.push(.browse(browseId: item.browseId, title: item.title, params: item.params))
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(stripeColor)
                                .frame(width: 6, height: 32)

                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.mochyOnBackground)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .mochyCard(cornerRadius: 12, fillColor: .mochyEffectiveSurface)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }

    // MARK: - Charts & Trending

    private var chartsAndTrendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Charts & Trending")
                    .font(.mochyHeadline)
                    .foregroundColor(.mochyOnBackground)
                Spacer()
                Button {
                    let tracks = viewModel.trendingTracks
                    if !tracks.isEmpty {
                        player.play(tracks: tracks, startIndex: 0)
                    }
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.mochyBackground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(settings.accentColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            VStack(spacing: 2) {
                let topTracks = Array(viewModel.trendingTracks.prefix(20))
                ForEach(Array(topTracks.enumerated()), id: \.element.id) { idx, track in
                    TrackRowView(track: track, index: idx + 1) {
                        player.play(tracks: topTracks, startIndex: idx)
                    }
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }

    // MARK: - Additional Explore Sections

    @ViewBuilder
    private func extraExploreSection(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(section.items) { item in
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
                        case .track(let track):
                            TrackRowView(track: track) {
                                player.play(track: track)
                            }
                            .frame(width: 280)
                        }
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }

    // MARK: - Loading & Error

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        ShimmerCardPlaceholder()
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }

            VStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    ShimmerRowPlaceholder()
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundColor(.mochySecondary)
            Text(message)
                .font(.mochyBody)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") {
                Task { await viewModel.loadExploreFeed() }
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}
