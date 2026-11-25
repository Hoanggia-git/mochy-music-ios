import SwiftUI
import UIKit

/// Stylish shareable song & lyric card generator rendered via `ImageRenderer` (iOS 16+) and shared via `ShareLink`.
struct ShareSongSheet: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lyricsManager = LyricsManager.shared
    @ObservedObject private var colorExtractor = ArtworkColorExtractor.shared
    @ObservedObject private var settings = AppSettings.shared

    enum CardTheme: String, CaseIterable, Identifiable {
        case amoled = "AMOLED"
        case dynamic = "Dynamic"
        case light = "Light"

        var id: String { rawValue }
    }

    @State private var selectedTheme: CardTheme = .dynamic
    @State private var includeLyrics: Bool = false
    @State private var customQuote: String = ""
    @State private var renderedImage: UIImage?

    private var shareURL: URL {
        URL(string: "https://music.youtube.com/watch?v=\(track.id)") ?? URL(string: "https://music.youtube.com")!
    }

    private var accentTint: Color {
        colorExtractor.color(for: track.thumbnailURL, fallback: settings.accentColor)
    }

    private var defaultLyricSnippet: String {
        if let lines = lyricsManager.currentLyrics?.syncedLines, !lines.isEmpty,
           lyricsManager.currentTrackId == track.id {
            return lines.prefix(3).map(\.text).joined(separator: "\n")
        }
        if let plain = lyricsManager.currentLyrics?.plainText, !plain.isEmpty,
           lyricsManager.currentTrackId == track.id {
            return plain.components(separatedBy: .newlines).prefix(3).joined(separator: "\n")
        }
        return "Listening on Mochy Music"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mochyBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        shareCardPreview
                            .padding(.top, 8)

                        // Theme picker
                        Picker("Card Style", selection: $selectedTheme) {
                            ForEach(CardTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)

                        // Lyric quote toggle & editor
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Include Lyrics Quote", isOn: $includeLyrics)
                                .tint(settings.accentColor)

                            if includeLyrics {
                                TextField("Enter lyric lines...", text: $customQuote, axis: .vertical)
                                    .lineLimit(2...4)
                                    .padding(10)
                                    .background(Color.mochySurfaceVariant)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .padding(14)
                        .mochyCard(cornerRadius: 16, fillColor: .mochySurface)

                        // Share actions
                        VStack(spacing: 10) {
                            if let uiImage = renderedImage {
                                ShareLink(
                                    item: Image(uiImage: uiImage),
                                    preview: SharePreview("\(track.title) — \(track.artistsText)", image: Image(uiImage: uiImage))
                                ) {
                                    Label("Share Card Image", systemImage: "photo.on.rectangle.angled")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(settings.accentColor)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }

                            ShareLink(item: shareURL) {
                                Label("Share Track Link", systemImage: "link")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.mochyOnSurface)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .mochyCard(cornerRadius: 14, fillColor: .mochySurfaceVariant)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Share Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(settings.accentColor)
                }
            }
            .onAppear {
                colorExtractor.extractIfNeeded(from: track.thumbnailURL)
                if customQuote.isEmpty {
                    customQuote = defaultLyricSnippet
                }
                renderCardSnapshot()
            }
            .onChange(of: selectedTheme) { _ in renderCardSnapshot() }
            .onChange(of: includeLyrics) { _ in renderCardSnapshot() }
            .onChange(of: customQuote) { _ in renderCardSnapshot() }
        }
        .preferredColorScheme(.dark)
    }

    private var shareCardPreview: some View {
        cardContent
            .frame(width: 320)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.55), radius: 18, x: 0, y: 10)
    }

    @ViewBuilder
    private var cardContent: some View {
        let isLight = selectedTheme == .light
        let primaryText: Color = isLight ? Color.black : Color.white
        let secondaryText: Color = isLight ? Color.black.opacity(0.65) : Color.white.opacity(0.72)

        ZStack {
            switch selectedTheme {
            case .amoled:
                Color(hex: 0x050505)
            case .dynamic:
                LinearGradient(
                    colors: [accentTint.opacity(0.85), Color(hex: 0x0B0B0D)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .light:
                LinearGradient(
                    colors: [Color(hex: 0xF7F7FA), Color(hex: 0xE6E6EF)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    MochyArtworkView(url: track.artworkURL, cornerRadius: 14)
                        .frame(width: 82, height: 82)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(primaryText)
                            .lineLimit(2)

                        Text(track.artistsText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(secondaryText)
                            .lineLimit(1)

                        if let album = track.album?.name {
                            Text(album)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(secondaryText.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if includeLyrics {
                    Text("“\(customQuote.isEmpty ? defaultLyricSnippet : customQuote)”")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(primaryText)
                        .lineSpacing(4)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 14))
                        Text("MOCHY MUSIC")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                    }
                    .foregroundColor(secondaryText)

                    Spacer()

                    Text(track.formattedDuration)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(secondaryText)
                }
            }
            .padding(20)
        }
    }

    @MainActor
    private func renderCardSnapshot() {
        let renderer = ImageRenderer(content: cardContent.frame(width: 340))
        renderer.scale = 3.0
        renderedImage = renderer.uiImage
    }
}
