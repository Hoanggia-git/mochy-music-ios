import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var isSearching = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Searching YouTube Music...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Try Again") {
                            Task { await performSearch() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Search songs, artists, or albums")
                            .font(.headline)
                        Text("Powered by InnerTube + LRCLIB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(results) { track in
                            TrackRowView(track: track) {
                                player.play(track: track, inQueue: results)
                            }
                        }

                        if player.currentTrack != nil {
                            Color.clear
                                .frame(height: 68)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Songs, artists...")
            .onSubmit(of: .search) {
                Task { await performSearch() }
            }
        }
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSearching = true
        errorText = nil
        do {
            results = try await InnerTubeService.shared.searchSongs(query: trimmed)
            if results.isEmpty {
                errorText = "No tracks found for \"\(trimmed)\"."
            }
        } catch {
            errorText = error.localizedDescription
        }
        isSearching = false
    }
}
