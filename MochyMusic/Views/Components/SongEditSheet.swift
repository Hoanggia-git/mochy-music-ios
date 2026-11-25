import SwiftUI

/// Metadata editor sheet allowing users to customize title, artist, album, genre, year, and explicit tag.
struct SongEditSheet: View {
    let track: Track
    let onSave: (Track) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    @State private var title: String
    @State private var artistText: String
    @State private var albumName: String
    @State private var genre: String
    @State private var yearText: String
    @State private var isExplicit: Bool

    init(track: Track, onSave: @escaping (Track) -> Void) {
        self.track = track
        self.onSave = onSave
        _title = State(initialValue: track.title)
        _artistText = State(initialValue: track.artists.map(\.name).joined(separator: ", "))
        _albumName = State(initialValue: track.album?.name ?? "")
        _genre = State(initialValue: track.genre ?? "")
        _yearText = State(initialValue: track.year.map { String($0) } ?? "")
        _isExplicit = State(initialValue: track.explicit)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mochyBackground.ignoresSafeArea()

                Form {
                    Section {
                        HStack(spacing: 14) {
                            MochyArtworkView(url: track.artworkURL, cornerRadius: 12)
                                .frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title.isEmpty ? track.title : title)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.mochyOnSurface)
                                    .lineLimit(1)
                                Text(artistText.isEmpty ? "Unknown Artist" : artistText)
                                    .font(.system(size: 13))
                                    .foregroundColor(.mochySecondary)
                                    .lineLimit(1)
                            }
                        }
                        .listRowBackground(Color.mochySurfaceVariant)
                    }

                    Section("Track Metadata") {
                        TextField("Title", text: $title)
                        TextField("Artist(s) (comma-separated)", text: $artistText)
                        TextField("Album", text: $albumName)
                        TextField("Genre", text: $genre)
                        TextField("Year", text: $yearText)
                            .keyboardType(.numberPad)
                        Toggle("Explicit Content", isOn: $isExplicit)
                            .tint(settings.accentColor)
                    }
                    .listRowBackground(Color.mochySurfaceVariant)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Song Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.mochySecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(settings.accentColor)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveChanges() {
        var updated = track
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let parsedArtists = artistText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { idx, name -> Artist in
                if idx < track.artists.count {
                    var existing = track.artists[idx]
                    existing.name = name
                    return existing
                }
                return Artist(name: name, isLocal: track.isLocal)
            }

        if !parsedArtists.isEmpty {
            updated.artists = parsedArtists
        }

        let trimmedAlbum = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAlbum.isEmpty {
            updated.album = nil
        } else if var existingAlbum = track.album {
            existingAlbum.name = trimmedAlbum
            updated.album = existingAlbum
        } else {
            updated.album = Album(
                id: "edited_album_\(track.id)",
                name: trimmedAlbum,
                artists: updated.artists,
                thumbnailURL: track.thumbnailURL,
                isLocal: track.isLocal
            )
        }

        let trimmedGenre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.genre = trimmedGenre.isEmpty ? nil : trimmedGenre
        updated.year = Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))
        updated.explicit = isExplicit

        onSave(updated)
        MochyToastCenter.shared.show("Updated track metadata")
        dismiss()
    }
}
