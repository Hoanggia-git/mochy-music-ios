import Foundation

/// ViewModel loading album metadata and tracklist from InnerTube.
@MainActor
final class AlbumViewModel: ObservableObject {
    @Published var album: Album?
    @Published var isLoading: Bool = false
    @Published var error: String?

    func loadAlbum(browseId: String) async {
        isLoading = true
        error = nil

        do {
            let loaded = try await InnerTubeService.shared.fetchAlbum(browseId: browseId)
            album = loaded
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
