import SwiftUI

// MARK: - Shared Settings UI Building Blocks

struct MochySettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content
    @ObservedObject private var settings = AppSettings.shared

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundColor(.mochySecondary)
                    .padding(.horizontal, 6)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                    .fill(settings.pureBlack ? Color.mochySurface : Color.mochySurface0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous))
        }
    }
}

struct MochySettingsRowIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 34, height: 34)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
        }
    }
}

struct MochySettingsNavRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let tint: Color
    var trailingValue: String? = nil
    @ObservedObject private var settings = AppSettings.shared

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        tint: Color = .mochyPrimary,
        trailingValue: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.trailingValue = trailingValue
    }

    var body: some View {
        HStack(spacing: 12) {
            MochySettingsRowIcon(systemName: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)
                if let subtitle, !subtitle.isEmpty, !settings.hideSettingsDescriptions {
                    Text(subtitle)
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let trailingValue {
                Text(trailingValue)
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.mochySecondary.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct MochySettingsToggleRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let tint: Color
    @Binding var isOn: Bool
    @ObservedObject private var settings = AppSettings.shared

    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        tint: Color = .mochyPrimary,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                MochySettingsRowIcon(systemName: icon, tint: tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.mochyBody.weight(.medium))
                        .foregroundColor(.mochyOnSurface)
                    if let subtitle, !subtitle.isEmpty, !settings.hideSettingsDescriptions {
                        Text(subtitle)
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .tint(settings.accentColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct MochySettingsDivider: View {
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.06))
            .padding(.leading, 60)
    }
}

// MARK: - Main Settings Screen

struct MochySettingsScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var router = NavigationRouter.shared
    @ObservedObject private var scrobble = ScrobbleService.shared
    @ObservedObject private var innerTube = InnerTubeService.shared
    @ObservedObject private var discordRPC = DiscordRPCService.shared

    @State private var showLyricsSort = false
    @State private var showSetupWizard = false
    @State private var showRecognitionSheet = false

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                profileHeaderCard

                // Quick Highlights Row (Recap + Shazam + AudioLab)
                quickActionsRow

                MochySettingsCard(title: "Âm thanh & Trình phát") {
                    Button {
                        router.push(.equalizer)
                    } label: {
                        MochySettingsNavRow(
                            title: "AudioLab & Equalizer",
                            subtitle: "EQ 10 băng tần, Bass Boost, Reverb & Pitch",
                            icon: "slider.vertical.3",
                            tint: settings.accentColor,
                            trailingValue: EqualizerService.shared.isEnabled ? "Bật" : "Tắt"
                        )
                    }
                    .buttonStyle(.plain)

                    MochySettingsDivider()

                    NavigationLink {
                        PlaybackSettingsScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Phát nhạc & Âm thanh",
                            subtitle: "Chất lượng stream, Crossfade, Crossmix & Chuẩn hóa",
                            icon: "waveform.path.ecg",
                            tint: .mochyBlue,
                            trailingValue: settings.audioQuality.displayName
                        )
                    }
                    .buttonStyle(.plain)

                    MochySettingsDivider()

                    NavigationLink {
                        NowPlayingSettingsScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Now Playing & Giao diện phát",
                            subtitle: "Kiểu trình phát, thanh tua, bo góc & hiệu ứng mờ",
                            icon: "play.square.stack.fill",
                            tint: .mochyMauve,
                            trailingValue: settings.playerStyle.displayName
                        )
                    }
                    .buttonStyle(.plain)
                }

                MochySettingsCard(title: "Cá nhân hóa & Lời bài hát") {
                    NavigationLink {
                        AppBehaviourSettingsScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Giao diện & Cử chỉ",
                            subtitle: "AMOLED đen thuần, màu nhấn, cỡ chữ & thao tác vuốt",
                            icon: "paintbrush.fill",
                            tint: .mochyPink,
                            trailingValue: settings.accentPreset.displayName
                        )
                    }
                    .buttonStyle(.plain)

                    MochySettingsDivider()

                    Button {
                        showLyricsSort = true
                    } label: {
                        MochySettingsNavRow(
                            title: "Lời bài hát & Nhà cung cấp",
                            subtitle: "Sắp xếp thứ tự ưu tiên LRCLIB, BetterLyrics, Genius...",
                            icon: "text.quote",
                            tint: .mochyTeal,
                            trailingValue: "\(settings.lyricsProviderOrder.count) nguồn"
                        )
                    }
                    .buttonStyle(.plain)
                }

                MochySettingsCard(title: "Thư viện, Đồng bộ & Tích hợp") {
                    NavigationLink {
                        YouTubeLoginScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Tài khoản YouTube Music",
                            subtitle: innerTube.isSignedIn
                                ? (settings.ytAccountHandle.isEmpty ? "Đã kết nối YouTube Music" : settings.ytAccountHandle)
                                : "Đăng nhập để đồng bộ Bài hát đã thích & Playlist",
                            icon: "play.rectangle.fill",
                            tint: .mochyRed,
                            trailingValue: innerTube.isSignedIn
                                ? (settings.ytAccountName.isEmpty ? "Đã kết nối" : settings.ytAccountName)
                                : "Đăng nhập"
                        )
                    }
                    .buttonStyle(.plain)

                    MochySettingsDivider()

                    NavigationLink {
                        ModulesScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Mô-đun nguồn phát (FLAC / JioSaavn)",
                            subtitle: "Monochrome Lossless FLAC, JioSaavn AAC & Chẩn đoán",
                            icon: "shippingbox.fill",
                            tint: .mochyTeal,
                            trailingValue: preferredSourceLabel
                        )
                    }
                    .buttonStyle(.plain)

                    MochySettingsDivider()

                    NavigationLink {
                        DiscordScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Discord Rich Presence",
                            subtitle: "Hiển thị bài hát đang nghe trực tiếp trên Discord",
                            icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                            tint: .mochyLavender,
                            trailingValue: discordRPC.statusText
                        )
                    }
                    .buttonStyle(.plain)

                    MochySettingsDivider()

                    NavigationLink {
                        ImportSyncScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Nhập & Đồng bộ Playlist",
                            subtitle: "Spotify, Apple Music, TIDAL, CSV / văn bản",
                            icon: "square.and.arrow.down.on.square.fill",
                            tint: .mochyGreen
                        )
                    }
                    .buttonStyle(.plain)

                    MochySettingsDivider()

                    NavigationLink {
                        IntegrationsScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Tích hợp & Mô-đun",
                            subtitle: "Last.fm, Discord RPC, ShazamKit & InnerTube",
                            icon: "puzzlepiece.extension.fill",
                            tint: .mochyYellow,
                            trailingValue: scrobble.isAuthenticated ? "@\(scrobble.username)" : nil
                        )
                    }
                    .buttonStyle(.plain)

                    MochySettingsDivider()

                    NavigationLink {
                        StorageAndBackupScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Bộ nhớ & Sao lưu",
                            subtitle: "Nhạc ngoại tuyến, bộ đệm, xuất/khôi phục JSON",
                            icon: "externaldrive.fill",
                            tint: .mochySapphire,
                            trailingValue: ByteCountFormatter.string(
                                fromByteCount: library.totalDownloadSizeBytes,
                                countStyle: .file
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }

                MochySettingsCard(title: "Khác") {
                    NavigationLink {
                        RecapScreen()
                    } label: {
                        MochySettingsNavRow(
                            title: "Listening Recap & Thống kê",
                            subtitle: "Thời gian nghe, nghệ sĩ và bài hát nghe nhiều nhất",
                            icon: "chart.bar.xaxis",
                            tint: .mochyPeach
                        )
                    }
                    .buttonStyle(.plain)

                    MochySettingsDivider()

                    Button {
                        showSetupWizard = true
                    } label: {
                        MochySettingsNavRow(
                            title: "Trình hướng dẫn thiết lập",
                            subtitle: "Xem lại onboarding giao diện, phong cách & hồ sơ",
                            icon: "wand.and.stars",
                            tint: .mochyLavender
                        )
                    }
                    .buttonStyle(.plain)
                }

                aboutCreditsCard
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showLyricsSort) {
            LyricsProviderSortSheet()
        }
        .sheet(isPresented: $showRecognitionSheet) {
            RecognitionSheet()
        }
        .fullScreenCover(isPresented: $showSetupWizard) {
            SetupWizardScreen {
                showSetupWizard = false
            }
        }
    }

    // MARK: - Subviews

    private var profileHeaderCard: some View {
        NavigationLink {
            ProfileScreen()
        } label: {
            HStack(spacing: 14) {
                MochyAvatarBadge(
                    picUri: settings.profilePicUri,
                    accent: settings.accentColor,
                    size: 56
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(settings.username)
                            .font(.mochyHeadline)
                            .foregroundColor(.mochyOnSurface)
                            .lineLimit(1)

                        Text("#\(settings.profileCardNumber)")
                            .font(.mochyMono)
                            .foregroundColor(settings.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(settings.accentColor.opacity(0.15)))
                    }

                    Text("\(library.favorites.count) yêu thích • \(library.playlists.count) playlist • \(library.downloadedTracks.count) tải xuống")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.mochySecondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                settings.accentColor.opacity(0.16),
                                settings.pureBlack ? Color.mochySurface : Color.mochySurface0
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                    .stroke(settings.accentColor.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            NavigationLink {
                RecapScreen()
            } label: {
                quickPill(title: "Recap", icon: "sparkles", tint: .mochyPeach)
            }
            .buttonStyle(.plain)

            Button {
                showRecognitionSheet = true
            } label: {
                quickPill(title: "Nhận diện", icon: "shazam.logo.fill", tint: .mochyBlue)
            }
            .buttonStyle(.plain)

            NavigationLink {
                ImportSyncScreen()
            } label: {
                quickPill(title: "Import", icon: "arrow.down.doc.fill", tint: .mochyGreen)
            }
            .buttonStyle(.plain)
        }
    }

    private func quickPill(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
            Text(title)
                .font(.mochyCaption.weight(.semibold))
                .foregroundColor(.mochyOnSurface)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusMedium, style: .continuous)
                .fill(settings.pureBlack ? Color.mochySurface : Color.mochySurface0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusMedium, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var aboutCreditsCard: some View {
        MochySettingsCard(title: "Thông tin & Giấy phép") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(settings.accentColor.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "music.note.house.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(settings.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mochy Music iOS")
                            .font(.mochyHeadline)
                            .foregroundColor(.mochyOnSurface)
                        Text("Bản port SwiftUI • Phiên bản 1.0.0 • GPL-3.0")
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                    }
                    Spacer()
                }

                Divider().background(Color.white.opacity(0.06))

                VStack(alignment: .leading, spacing: 6) {
                    if let repoURL = URL(string: "https://github.com/realidkroo/Mochy-Music") {
                        Link(destination: repoURL) {
                            creditRow(label: "Mã nguồn gốc", value: "realidkroo/Mochy-Music", icon: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    if let lrclibURL = URL(string: "https://lrclib.net") {
                        Link(destination: lrclibURL) {
                            creditRow(label: "Lời bài hát đồng bộ", value: "lrclib.net", icon: "text.bubble")
                        }
                    }
                    creditRow(label: "Giấy phép mã nguồn mở", value: "GNU GPL v3.0", icon: "doc.plaintext")
                }
            }
            .padding(14)
        }
    }

    private var preferredSourceLabel: String {
        switch settings.preferredAudioSource {
        case "monochrome": return "Monochrome FLAC"
        case "jiosaavn": return "JioSaavn AAC"
        default: return "InnerTube"
        }
    }

    private func creditRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.mochySecondary)
                .frame(width: 18)
            Text(label)
                .font(.mochyCaption)
                .foregroundColor(.mochySecondary)
            Spacer()
            Text(value)
                .font(.mochyCaption.weight(.semibold))
                .foregroundColor(settings.accentColor)
        }
    }
}

// MARK: - Reusable Profile Avatar Badge

struct MochyAvatarBadge: View {
    let picUri: String
    let accent: Color
    var size: CGFloat = 52

    private var parsedEmojiAndColor: (emoji: String, color: Color) {
        if picUri.hasPrefix("emoji:") {
            let payload = String(picUri.dropFirst(6))
            let parts = payload.split(separator: "|", maxSplits: 1).map(String.init)
            let emoji = parts.first?.isEmpty == false ? parts[0] : "🎧"
            let bgColor = parts.count > 1 ? Color(hexString: parts[1]) : accent
            return (emoji, bgColor)
        }
        return ("🎧", accent)
    }

    var body: some View {
        let info = parsedEmojiAndColor
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [info.color.opacity(0.85), info.color.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Text(info.emoji)
                .font(.system(size: size * 0.48))
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
        )
    }
}
