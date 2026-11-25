import SwiftUI

/// All favorited tracks with search filtering, sort options, and Play All / Shuffle controls.
struct FavoritesScreen: View {
    @StateObject private var viewModel = LibraryViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    private var displayedTracks: [Track] {
        viewModel.filteredFavorites(from: library.favorites)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                searchAndSortBar
                playActionsRow

                if displayedTracks.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                            TrackRowView(track: track) {
                                player.play(tracks: displayedTracks, startIndex: index)
                            }
                        }
                    }
                    .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, player.currentTrack != nil ? 150 : 96)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
    }

    private var searchAndSortBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.mochySecondary)
                TextField("Search favorites...", text: $viewModel.searchText)
                    .font(.mochyBody)
                    .foregroundColor(.mochyOnBackground)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.mochySecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.mochyEffectiveSurface))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LibrarySortOption.allCases) { option in
                        let selected = viewModel.sortOption == option
                        Button {
                            viewModel.sortOption = option
                        } label: {
                            Text(option.rawValue)
                                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                                .foregroundColor(selected ? .mochyBackground : .mochyPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(selected ? settings.accentColor : Color.mochyEffectiveSurface))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    private var playActionsRow: some View {
        HStack(spacing: 12) {
            Button {
                guard !displayedTracks.isEmpty else { return }
                player.play(tracks: displayedTracks, startIndex: 0)
            } label: {
                Label("Play All", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.mochyBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
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
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Color.mochyEffectiveSurface))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 40))
                .foregroundColor(.mochySecondary)
            Text(library.favorites.isEmpty ? "No Favorite Songs Yet" : "No Matching Favorites")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
            Text("Tap the heart icon on any song to save it here.")
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}
