import SwiftUI

/// AMOLED circular artist card with subscriber count support.
struct ArtistCard: View {
    let artist: Artist
    let onTap: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    private var avatarSize: CGFloat {
        switch settings.gridItemSize {
        case "small": return 114
        case "large": return 148
        default: return 130
        }
    }

    init(artist: Artist, onTap: @escaping () -> Void) {
        self.artist = artist
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 9) {
                MochyArtworkView(
                    url: artist.artworkURL,
                    isCircular: true,
                    placeholderIcon: "person.fill"
                )
                .frame(width: avatarSize, height: avatarSize)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)

                VStack(spacing: 2) {
                    Text(artist.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.mochyOnSurface)
                        .lineLimit(1)

                    if settings.showArtistSubscriberCount,
                       let subscribers = artist.subscriberCount,
                       !subscribers.isEmpty {
                        Text(subscribers)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.mochySecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: avatarSize + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
