import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore

    @State private var trendingTracks: [Track] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if !library.recentlyPlayed.isEmpty {
                    Section("Recently Played") {
                        ForEach(library.recentlyPlayed.prefix(5)) { track in
                            TrackRowView(track: track) {
                                player.play(track: track, inQueue: library.recentlyPlayed)
                            }
                        }
                    }
                }

                Section("Trending & Picks") {
                    if isLoading && trendingTracks.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading YouTube Music...")
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    } else if let errorText, trendingTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Could not load feed")
                                .font(.headline)
                            Text(errorText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Retry") {
                                Task { await loadFeed() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(trendingTracks) { track in
                            TrackRowView(track: track) {
                                player.play(track: track, inQueue: trendingTracks)
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
            .listStyle(.insetGrouped)
            .navigationTitle("Mochy Music")
            .refreshable {
                await loadFeed()
            }
            .task {
                if trendingTracks.isEmpty {
                    await loadFeed()
                }
            }
        }
    }

    private func loadFeed() async {
        isLoading = true
        errorText = nil
        do {
            let tracks = try await InnerTubeService.shared.fetchHomeTracks()
            trendingTracks = tracks
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
