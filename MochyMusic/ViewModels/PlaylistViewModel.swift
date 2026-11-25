import Foundation

/// ViewModel loading remote YouTube playlists and continuation tracks.
@MainActor
final class PlaylistViewModel: ObservableObject {
    @Published var playlist: YouTubePlaylist?
    @Published var tracks: [Track] = []
    @Published var continuation: String?
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var error: String?

    func loadPlaylist(browseId: String) async {
        isLoading = true
        error = nil

        do {
            let loaded = try await InnerTubeService.shared.fetchPlaylist(browseId: browseId, loadAllContinuations: true)
            playlist = loaded
            tracks = loaded.tracks
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, let token = continuation, !token.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await InnerTubeService.shared.fetchPlaylistContinuation(continuation: token)
            let existing = Set(tracks.map(\.id))
            let newTracks = page.tracks.filter { !existing.contains($0.id) }
            tracks.append(contentsOf: newTracks)
            continuation = page.continuation
        } catch {
            // Preserve loaded tracks if continuation fails
        }
    }
}
