import SwiftUI

/// Full Artist detail page with banner/avatar, Play/Shuffle, Subscribe, Top Songs, Albums, Singles & Similar Artists.
struct ArtistScreen: View {
    let browseId: String

    @StateObject private var viewModel = ArtistViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: NavigationRouter

    @State private var showAllTopSongs = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.isLoading && viewModel.artist == nil {
                    loadingState
                } else if let error = viewModel.error, viewModel.artist == nil {
                    errorState(error)
                } else if let artist = viewModel.artist {
                    artistHeroHeader(artist)
                    actionBar(artist)

                    if !viewModel.topSongs.isEmpty {
                        topSongsSection
                    }

                    if !viewModel.albums.isEmpty {
                        albumCarouselSection(title: "Albums", items: viewModel.albums)
                    }

                    if !viewModel.singles.isEmpty {
                        albumCarouselSection(title: "Singles & EPs", items: viewModel.singles)
                    }

                    if !viewModel.playlists.isEmpty {
                        playlistsSection
                    }

                    if !viewModel.similarArtists.isEmpty {
                        similarArtistsSection
                    }

                    if let description = viewModel.descriptionText, !description.isEmpty {
                        aboutSection(description)
                    }
                }
            }
            .padding(.bottom, player.currentTrack != nil ? 150 : 96)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle(viewModel.artist?.name ?? "Artist")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadArtist(browseId: browseId)
        }
    }

    // MARK: - Hero Header

    private func artistHeroHeader(_ artist: Artist) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: artist.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color.mochyEffectiveSurface)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 68))
                                .foregroundColor(.mochySecondary)
                        )
                }
            }
            .frame(height: 270)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.mochyEffectiveBackground.opacity(0.65),
                        Color.mochyEffectiveBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(artist.name)
                    .font(MochyTheme.titleFont(size: 30))
                    .foregroundColor(.mochyOnBackground)

                if let subs = artist.subscriberCount ?? viewModel.monthlyListeners, !subs.isEmpty,
                   settings.showArtistSubscriberCount {
                    Text(subs)
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Action Bar

    private func actionBar(_ artist: Artist) -> some View {
        HStack(spacing: 10) {
            Button {
                if !viewModel.topSongs.isEmpty {
                    player.play(tracks: viewModel.topSongs, startIndex: 0)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.mochyBackground)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(settings.accentColor))
            }
            .buttonStyle(.plain)

            Button {
                if !viewModel.topSongs.isEmpty {
                    player.play(tracks: viewModel.topSongs.shuffled(), startIndex: 0)
                }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.mochyOnBackground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.mochyEffectiveSurface))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                viewModel.toggleSubscribe()
            } label: {
                Text(viewModel.isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(viewModel.isSubscribed ? settings.accentColor : .mochyOnBackground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .stroke(viewModel.isSubscribed ? settings.accentColor : Color.white.opacity(0.25), lineWidth: 1.2)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    // MARK: - Top Songs

    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Top Songs")
                    .font(.mochyHeadline)
                    .foregroundColor(.mochyOnBackground)

                Spacer()

                if viewModel.topSongs.count > 5 {
                    Button(showAllTopSongs ? "Show Less" : "Show All") {
                        withAnimation(MochyTheme.snappySpring) {
                            showAllTopSongs.toggle()
                        }
                    }
                    .font(.mochyCaption)
                    .foregroundColor(settings.accentColor)
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            let visibleTracks = showAllTopSongs ? viewModel.topSongs : Array(viewModel.topSongs.prefix(5))
            VStack(spacing: 2) {
                ForEach(Array(visibleTracks.enumerated()), id: \.element.id) { idx, track in
                    TrackRowView(track: track, index: idx + 1) {
                        player.play(tracks: viewModel.topSongs, startIndex: idx)
                    }
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }

    // MARK: - Discography Carousels

    private func albumCarouselSection(title: String, items: [Album]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { album in
                        AlbumCard(album: album) {
                            router.push(.album(id: album.browseId ?? album.id))
                        }
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Featured Playlists")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.playlists) { playlist in
                        PlaylistCard(
                            title: playlist.name,
                            subtitle: playlist.author,
                            thumbnailURL: playlist.thumbnailURL
                        ) {
                            router.push(.playlist(id: playlist.id, isLocal: false))
                        }
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }

    private var similarArtistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fans Might Also Like")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.similarArtists) { similar in
                        ArtistCard(artist: similar) {
                            router.push(.artist(id: similar.browseId ?? similar.id))
                        }
                    }
                }
                .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            }
        }
    }

    private func aboutSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
            Text(description)
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
                .lineSpacing(4)
        }
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    // MARK: - Loading & Error

    private var loadingState: some View {
        VStack(spacing: 16) {
            Rectangle()
                .fill(Color.mochyEffectiveSurface)
                .frame(height: 270)
                .mochyShimmer()
            ForEach(0..<5, id: \.self) { _ in
                ShimmerRowPlaceholder()
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 38))
                .foregroundColor(.mochySecondary)
            Text(message)
                .font(.mochyBody)
                .foregroundColor(.mochySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") {
                Task { await viewModel.loadArtist(browseId: browseId) }
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
