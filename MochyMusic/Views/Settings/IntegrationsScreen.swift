import SwiftUI

struct IntegrationsScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var scrobble = ScrobbleService.shared
    @ObservedObject private var innerTube = InnerTubeService.shared
    @ObservedObject private var discordRPC = DiscordRPCService.shared

    @State private var showLastFmLogin = false
    @State private var showRecognitionSheet = false

    @State private var lfmUserInput = ""
    @State private var lfmPassInput = ""
    @State private var lfmStatusMessage: String?
    @State private var isAuthenticating = false

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                youtubeMusicSection
                lastFmSection
                discordSection
                shazamSection
                builtInModulesSection
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Tích hợp & Mô-đun")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRecognitionSheet) {
            RecognitionSheet()
        }
        .sheet(isPresented: $showLastFmLogin) {
            lastFmAuthSheet
        }
    }

    // MARK: - YouTube Music Sync

    private var youtubeMusicSection: some View {
        MochySettingsCard(title: "YouTube Music Account & Sync") {
            NavigationLink {
                YouTubeLoginScreen()
            } label: {
                MochySettingsNavRow(
                    title: innerTube.isSignedIn
                        ? (settings.ytAccountName.isEmpty ? "Tài khoản YouTube Music" : settings.ytAccountName)
                        : "Đăng nhập YouTube Music",
                    subtitle: innerTube.isSignedIn
                        ? (settings.ytAccountHandle.isEmpty ? "Đã kết nối phiên SAPISIDHASH" : settings.ytAccountHandle)
                        : "Đồng bộ Bài hát đã thích & Playlist từ YouTube Music",
                    icon: "play.rectangle.fill",
                    tint: .mochyRed,
                    trailingValue: innerTube.isSignedIn ? "Đã kết nối" : "Đăng nhập"
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Đồng bộ thư viện YouTube Music",
                subtitle: "Tự động hiển thị Liked Songs & Library Playlists",
                icon: "arrow.triangle.2.circlepath",
                tint: .mochyRed,
                isOn: $settings.ytmSync
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Đồng bộ bài hát đã thích",
                subtitle: "Tải danh sách FEmusic_liked_videos khi đăng nhập",
                icon: "heart.circle.fill",
                tint: .mochyPink,
                isOn: $settings.ytSyncLikedSongs
            )
        }
    }

    // MARK: - Last.fm

    private var lastFmSection: some View {
        MochySettingsCard(title: "Last.fm Scrobbling") {
            HStack(spacing: 12) {
                MochySettingsRowIcon(systemName: "dot.radiowaves.left.and.right", tint: .mochyRed)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scrobble.isAuthenticated ? "Đã đăng nhập: @\(scrobble.username)" : "Chưa kết nối Last.fm")
                        .font(.mochyBody.weight(.semibold))
                        .foregroundColor(.mochyOnSurface)
                    Text(scrobble.isConfigured ? "API Key đã sẵn sàng" : "Chưa cấu hình API Key / Secret")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                }

                Spacer()

                if scrobble.isAuthenticated {
                    Button("Đăng xuất") {
                        scrobble.signOut()
                    }
                    .font(.mochyCaption.weight(.semibold))
                    .foregroundColor(.mochyRed)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.mochyRed.opacity(0.16)))
                } else {
                    Button("Kết nối") {
                        showLastFmLogin = true
                    }
                    .font(.mochyCaption.weight(.semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(settings.accentColor))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Bật Scrobble tự động",
                subtitle: "Gửi lịch sử nghe nhạc lên tài khoản Last.fm",
                icon: "waveform.badge.plus",
                tint: .mochyRed,
                isOn: $settings.lastFmEnabled
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Cập nhật Now Playing",
                subtitle: "Hiển thị bài hát đang phát theo thời gian thực",
                icon: "play.circle.fill",
                tint: .mochyPeach,
                isOn: $settings.lastFmNowPlaying
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Đồng bộ nút Yêu thích (Love)",
                subtitle: "Tự động thả tim trên Last.fm khi thích bài trong Mochy",
                icon: "heart.fill",
                tint: .mochyPink,
                isOn: $settings.lastFmSendLikes
            )

            if let err = scrobble.lastError {
                MochySettingsDivider()
                Text("Lỗi Last.fm: \(err)")
                    .font(.mochyCaption)
                    .foregroundColor(.mochyRed)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Discord Rich Presence

    private var discordSection: some View {
        MochySettingsCard(title: "Discord Rich Presence") {
            NavigationLink {
                DiscordScreen()
            } label: {
                MochySettingsNavRow(
                    title: "Cấu hình & Xem trước Discord RPC",
                    subtitle: "Gateway v9 • Token, loại hoạt động & thẻ xem trước",
                    icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                    tint: .mochyLavender,
                    trailingValue: discordRPC.statusText
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Hiển thị trạng thái trên Discord",
                subtitle: "Chia sẻ bài hát đang nghe (Listening to...) qua RPC",
                icon: "bolt.horizontal.circle.fill",
                tint: .mochyLavender,
                isOn: Binding(
                    get: { settings.discordRPCEnabled },
                    set: { enabled in
                        settings.discordRPCEnabled = enabled
                        if enabled {
                            discordRPC.connectIfNeeded()
                        } else {
                            discordRPC.disconnect()
                        }
                    }
                )
            )
        }
    }

    // MARK: - ShazamKit

    private var shazamSection: some View {
        MochySettingsCard(title: "Nhận diện âm nhạc") {
            Button {
                showRecognitionSheet = true
            } label: {
                MochySettingsNavRow(
                    title: "Mở ShazamKit Music Recognition",
                    subtitle: "Lắng nghe qua micro và tìm bài hát ngay trong Mochy",
                    icon: "shazam.logo.fill",
                    tint: .mochyBlue,
                    trailingValue: "Thử ngay"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Built-in & Audio Source Modules

    private var builtInModulesSection: some View {
        MochySettingsCard(title: "Mô-đun nguồn phát & Lời bài hát") {
            NavigationLink {
                ModulesScreen()
            } label: {
                MochySettingsNavRow(
                    title: "Quản lý Mô-đun nguồn phát",
                    subtitle: "Monochrome FLAC, JioSaavn AAC & Chẩn đoán luồng",
                    icon: "shippingbox.fill",
                    tint: .mochyTeal,
                    trailingValue: settings.preferredAudioSource.capitalized
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            moduleRow(
                name: "Monochrome FLAC",
                description: "\(MonochromeService.shared.servers.count) máy chủ Lossless / Hi-Res",
                status: settings.monochromeEnabled ? "Đã bật" : "Tắt",
                tint: settings.monochromeEnabled ? .mochyTeal : .mochySecondary
            )
            MochySettingsDivider()
            moduleRow(
                name: "JioSaavn AAC",
                description: "Luồng AAC \(settings.jiosaavnQuality) kbps giải mã DES",
                status: settings.jiosaavnEnabled ? "Đã bật" : "Tắt",
                tint: settings.jiosaavnEnabled ? .mochyGreen : .mochySecondary
            )
            MochySettingsDivider()
            moduleRow(
                name: "InnerTube Engine",
                description: "YouTube Music / iOS / AndroidVR API gốc",
                status: "Hoạt động",
                tint: .mochyGreen
            )
            MochySettingsDivider()
            moduleRow(
                name: "LRCLIB",
                description: "Lời bài hát đồng bộ thời gian thực",
                status: settings.enableLrcLib ? "Đã bật" : "Tắt",
                tint: settings.enableLrcLib ? .mochyTeal : .mochySecondary
            )
            MochySettingsDivider()
            moduleRow(
                name: "BetterLyrics",
                description: "Lời bài hát karaoke TTML từng chữ",
                status: settings.enableBetterLyrics ? "Đã bật" : "Tắt",
                tint: settings.enableBetterLyrics ? .mochyMauve : .mochySecondary
            )
            MochySettingsDivider()
            moduleRow(
                name: "Genius & Musixmatch",
                description: "Lời bài hát đầy đủ & đa ngôn ngữ",
                status: (settings.enableGenius || settings.enableMusixmatch) ? "Đã bật" : "Tắt",
                tint: (settings.enableGenius || settings.enableMusixmatch) ? .mochyYellow : .mochySecondary
            )
        }
    }

    private func moduleRow(name: String, description: String, status: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            MochySettingsRowIcon(systemName: "cpu", tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)
                Text(description)
                    .font(.mochyCaption)
                    .foregroundColor(.mochySecondary)
            }
            Spacer()
            Text(status)
                .font(.mochyCaption.weight(.semibold))
                .foregroundColor(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.16)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Last.fm Login Sheet

    private var lastFmAuthSheet: some View {
        NavigationStack {
            Form {
                Section("Cấu hình API Last.fm") {
                    TextField("API Key", text: $settings.lastFmApiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("API Secret", text: $settings.lastFmApiSecret)
                }

                Section("Đăng nhập Web OAuth") {
                    Button {
                        Task {
                            isAuthenticating = true
                            defer { isAuthenticating = false }
                            do {
                                try await scrobble.authenticateWithWebLogin()
                                showLastFmLogin = false
                            } catch {
                                lfmStatusMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack {
                            Text("Đăng nhập qua trình duyệt Last.fm")
                            Spacer()
                            if isAuthenticating { ProgressView() }
                        }
                    }
                    .disabled(!scrobble.isConfigured || isAuthenticating)
                }

                Section("Hoặc đăng nhập bằng mật khẩu") {
                    TextField("Tên đăng nhập Last.fm", text: $lfmUserInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Mật khẩu", text: $lfmPassInput)

                    Button("Đăng nhập") {
                        Task {
                            isAuthenticating = true
                            defer { isAuthenticating = false }
                            do {
                                try await scrobble.signInWithPassword(username: lfmUserInput, password: lfmPassInput)
                                showLastFmLogin = false
                            } catch {
                                lfmStatusMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(!scrobble.isConfigured || lfmUserInput.isEmpty || lfmPassInput.isEmpty || isAuthenticating)
                }

                if let lfmStatusMessage {
                    Section {
                        Text(lfmStatusMessage)
                            .font(.mochyCaption)
                            .foregroundColor(.mochyRed)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())
            .navigationTitle("Kết nối Last.fm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showLastFmLogin = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
