import SwiftUI

struct LyricsProviderSortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var providers: [LyricsProvider] = []
    @State private var editMode: EditMode = .active

    init() {}

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(providers) { provider in
                        HStack(spacing: 12) {
                            Image(systemName: "text.quote")
                                .foregroundColor(isEnabled(provider) ? settings.accentColor : .mochySecondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName)
                                    .font(.mochyBody.weight(.medium))
                                    .foregroundColor(.mochyOnSurface)
                                Text(providerSubtitle(provider))
                                    .font(.mochyCaption)
                                    .foregroundColor(.mochySecondary)
                            }

                            Spacer()

                            Toggle("", isOn: binding(for: provider))
                                .labelsHidden()
                                .tint(settings.accentColor)
                        }
                        .listRowBackground(settings.pureBlack ? Color.mochySurface : Color.mochySurface0)
                    }
                    .onMove(perform: moveProviders)
                } header: {
                    Text("Kéo thả để sắp xếp thứ tự ưu tiên tìm lời bài hát")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                } footer: {
                    Text("Mochy Music sẽ lần lượt truy vấn từ trên xuống dưới cho đến khi tìm được lời đồng bộ hoặc lời thường.")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())
            .environment(\.editMode, $editMode)
            .navigationTitle("Nguồn lời bài hát")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Mặc định") {
                        resetOrder()
                    }
                    .foregroundColor(.mochyRed)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(settings.accentColor)
                }
            }
            .onAppear {
                loadOrder()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadOrder() {
        var current = settings.lyricsProviderOrder
        for p in LyricsProvider.allCases where !current.contains(p) {
            current.append(p)
        }
        providers = current
    }

    private func moveProviders(from source: IndexSet, to destination: Int) {
        providers.move(fromOffsets: source, toOffset: destination)
        settings.lyricsProviderOrder = providers
    }

    private func resetOrder() {
        withAnimation(MochyTheme.snappySpring) {
            providers = LyricsProvider.allCases
            settings.lyricsProviderOrder = LyricsProvider.allCases
            settings.enableLrcLib = true
            settings.enableBetterLyrics = true
            settings.enableGenius = true
            settings.enableMusixmatch = true
            settings.enableKugou = true
            settings.enableSimpMusic = true
            settings.enableYouLyPlus = true
            settings.enablePaxsenix = true
            settings.enableNetEase = false
            settings.enableQQMusic = false
            settings.enableDeezer = false
            settings.enableLrcRed = false
            settings.enableUnison = false
        }
    }

    private func isEnabled(_ provider: LyricsProvider) -> Bool {
        switch provider {
        case .lrclib: return settings.enableLrcLib
        case .betterLyrics: return settings.enableBetterLyrics
        case .genius: return settings.enableGenius
        case .musixmatch: return settings.enableMusixmatch
        case .kugou: return settings.enableKugou
        case .simpMusic: return settings.enableSimpMusic
        case .youLyPlus: return settings.enableYouLyPlus
        case .paxsenix: return settings.enablePaxsenix
        case .netEase: return settings.enableNetEase
        case .qqMusic: return settings.enableQQMusic
        case .deezer: return settings.enableDeezer
        case .lrcRed: return settings.enableLrcRed
        case .unison: return settings.enableUnison
        }
    }

    private func binding(for provider: LyricsProvider) -> Binding<Bool> {
        switch provider {
        case .lrclib: return $settings.enableLrcLib
        case .betterLyrics: return $settings.enableBetterLyrics
        case .genius: return $settings.enableGenius
        case .musixmatch: return $settings.enableMusixmatch
        case .kugou: return $settings.enableKugou
        case .simpMusic: return $settings.enableSimpMusic
        case .youLyPlus: return $settings.enableYouLyPlus
        case .paxsenix: return $settings.enablePaxsenix
        case .netEase: return $settings.enableNetEase
        case .qqMusic: return $settings.enableQQMusic
        case .deezer: return $settings.enableDeezer
        case .lrcRed: return $settings.enableLrcRed
        case .unison: return $settings.enableUnison
        }
    }

    private func providerSubtitle(_ provider: LyricsProvider) -> String {
        switch provider {
        case .lrclib: return "Lời đồng bộ thời gian thực (lrclib.net)"
        case .betterLyrics: return "Lời karaoke từng từ / TTML"
        case .genius: return "Lời bài hát đầy đủ & chú giải"
        case .musixmatch: return "Kho lời quốc tế đồng bộ"
        case .youLyPlus: return "LyricsPlus đa nguồn Apple/Spotify"
        case .simpMusic: return "API lời đồng bộ theo Video ID"
        default: return "Nguồn bổ sung"
        }
    }
}
