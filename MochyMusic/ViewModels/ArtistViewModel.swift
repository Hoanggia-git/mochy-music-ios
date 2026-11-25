import Foundation

/// ViewModel loading an artist's profile, top songs, discography, and similar artists.
@MainActor
final class ArtistViewModel: ObservableObject {
    @Published var artist: Artist?
    @Published var descriptionText: String?
    @Published var monthlyListeners: String?
    @Published var topSongs: [Track] = []
    @Published var albums: [Album] = []
    @Published var singles: [Album] = []
    @Published var videos: [Track] = []
    @Published var playlists: [YouTubePlaylist] = []
    @Published var similarArtists: [Artist] = []
    @Published var extraSections: [HomeSection] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var isSubscribed: Bool = false

    private let subscribedArtistsKey = "mochy_subscribed_artists"

    func loadArtist(browseId: String) async {
        isLoading = true
        error = nil

        do {
            let result = try await InnerTubeService.shared.fetchArtist(browseId: browseId)
            artist = result.artist
            descriptionText = result.description
            monthlyListeners = result.monthlyListeners
            topSongs = result.topSongs
            albums = result.albums
            singles = result.singles
            videos = result.videos
            playlists = result.playlists
            similarArtists = result.relatedArtists
            extraSections = result.sections
            isSubscribed = loadSubscribedIds().contains(result.artist.id) || loadSubscribedIds().contains(browseId)
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func toggleSubscribe() {
        guard let targetId = artist?.id else { return }
        var ids = loadSubscribedIds()
        if ids.contains(targetId) {
            ids.remove(targetId)
            isSubscribed = false
        } else {
            ids.insert(targetId)
            isSubscribed = true
        }
        UserDefaults.standard.set(Array(ids), forKey: subscribedArtistsKey)
    }

    private func loadSubscribedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: subscribedArtistsKey) ?? [])
    }
}
