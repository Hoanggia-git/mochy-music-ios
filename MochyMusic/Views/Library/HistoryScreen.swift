import SwiftUI

/// Date-grouped listening history screen with timestamps and clear history confirmation.
struct HistoryScreen: View {
    @StateObject private var viewModel = LibraryViewModel()
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    @State private var showClearConfirm = false

    private var groupedSections: [(title: String, entries: [HistoryEntry])] {
        viewModel.groupedHistory(library.recentlyPlayed)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                searchHeader

                if groupedSections.isEmpty {
                    emptyState
                } else {
                    let allTracks = library.recentlyPlayed.map(\.track)
                    ForEach(groupedSections, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.mochyHeadline)
                                .foregroundColor(.mochyOnBackground)
                                .padding(.horizontal, MochyTheme.screenHorizontalPadding)

                            LazyVStack(spacing: 4) {
                                ForEach(group.entries) { entry in
                                    HStack(spacing: 8) {
                                        TrackRowView(track: entry.track) {
                                            let idx = allTracks.firstIndex(where: { $0.id == entry.track.id }) ?? 0
                                            player.play(tracks: allTracks, startIndex: idx)
                                        }

                                        Text(entry.playedAt.formatted(date: .omitted, time: .shortened))
                                            .font(.mochyMono)
                                            .foregroundColor(.mochySecondary)
                                    }
                                }
                            }
                            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, player.currentTrack != nil ? 150 : 96)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !library.recentlyPlayed.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        showClearConfirm = true
                    }
                    .foregroundColor(.mochyRed)
                }
            }
        }
        .confirmationDialog("Clear listening history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                library.clearRecentlyPlayed()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.mochySecondary)
            TextField("Filter history...", text: $viewModel.searchText)
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
        .padding(.horizontal, MochyTheme.screenHorizontalPadding)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.mochySecondary)
            Text("No Listening History")
                .font(.mochyHeadline)
                .foregroundColor(.mochyOnBackground)
            Text("Songs you play will show up here grouped by date.")
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}
