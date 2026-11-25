import SwiftUI
import WebKit

struct DiscordScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var discordRPC = DiscordRPCService.shared
    @ObservedObject private var player = AudioPlayerManager.shared

    @State private var showDiscordWebLogin = false
    @State private var manualTokenInput = ""

    private let activityTypes: [(id: String, title: String, verb: String)] = [
        ("LISTENING", "Listening", "Listening to"),
        ("PLAYING", "Playing", "Playing"),
        ("WATCHING", "Watching", "Watching"),
        ("COMPETING", "Competing", "Competing in")
    ]

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                discordPreviewCard
                connectionSection
                presenceOptionsSection
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Discord Rich Presence")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDiscordWebLogin) {
            DiscordTokenLoginSheet { capturedToken in
                settings.discordToken = capturedToken
                settings.discordRPCEnabled = true
                discordRPC.connectIfNeeded()
                syncPresence()
            }
        }
        .onAppear {
            manualTokenInput = settings.discordToken
        }
    }

    // MARK: - Live Discord Activity Preview Card

    private var discordPreviewCard: some View {
        let previewTrack = player.currentTrack
        let titleText = previewTrack?.title ?? "Mochy Music"
        let artistText = previewTrack?.artistsText ?? "Đang sẵn sàng phát nhạc"
        let verb = activityTypes.first(where: { $0.id == settings.discordActivityType.uppercased() })?.verb ?? "Listening to"

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    MochyAvatarBadge(picUri: settings.profilePicUri, accent: .mochyLavender, size: 42)
                    Circle()
                        .fill(discordRPC.isConnected ? Color.mochyGreen : Color.mochySecondary)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(hex: 0x111214), lineWidth: 2))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.discordUsername.isEmpty ? settings.username : settings.discordUsername)
                        .font(.mochyBody.weight(.bold))
                        .foregroundColor(.white)
                    Text("\(verb) Mochy Music")
                        .font(.mochyCaption)
                        .foregroundColor(.mochyLavender)
                }

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(discordRPC.isConnected ? Color.mochyGreen : Color.mochySecondary)
                        .frame(width: 7, height: 7)
                    Text(discordRPC.statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(discordRPC.isConnected ? .mochyGreen : .mochySecondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 12) {
                if settings.discordShowArtwork {
                    AsyncImage(url: previewTrack?.artworkURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            ZStack {
                                Color.mochySurfaceVariant
                                Image(systemName: "music.note")
                                    .foregroundColor(.mochyLavender)
                            }
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.mochyBody.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(artistText)
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)

                    if let album = previewTrack?.album?.name, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 11))
                            .foregroundColor(.mochySecondary.opacity(0.8))
                            .lineLimit(1)
                    }

                    if player.duration > 0 {
                        let ratio = min(1.0, max(0.0, player.currentTime / player.duration))
                        VStack(spacing: 3) {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.18))
                                    Capsule().fill(Color.mochyLavender)
                                        .frame(width: proxy.size.width * CGFloat(ratio))
                                }
                            }
                            .frame(height: 4)

                            HStack {
                                Text(formatTime(player.currentTime))
                                Spacer()
                                Text(formatTime(player.duration))
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.mochySecondary)
                        }
                        .padding(.top, 2)
                    }
                }
            }

            if settings.discordShowButtons {
                HStack(spacing: 8) {
                    previewButtonLabel("Listen on YouTube Music")
                    previewButtonLabel("Mochy Music")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                .fill(Color(hex: 0x111214))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                .stroke(Color.mochyLavender.opacity(0.32), lineWidth: 1)
        )
    }

    private func previewButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
    }

    // MARK: - Connection & Token

    private var connectionSection: some View {
        MochySettingsCard(title: "Kết nối Gateway v9") {
            MochySettingsToggleRow(
                title: "Bật Discord Rich Presence",
                subtitle: "Kết nối trực tiếp tới wss://gateway.discord.gg",
                icon: "bolt.horizontal.circle.fill",
                tint: .mochyLavender,
                isOn: Binding(
                    get: { settings.discordRPCEnabled },
                    set: { enabled in
                        settings.discordRPCEnabled = enabled
                        if enabled {
                            discordRPC.connectIfNeeded()
                            syncPresence()
                        } else {
                            discordRPC.disconnect()
                        }
                    }
                )
            )

            MochySettingsDivider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Discord Token")
                        .font(.mochyBody.weight(.medium))
                        .foregroundColor(.mochyOnSurface)
                    Spacer()
                    if !settings.discordToken.isEmpty {
                        Button("Đăng xuất") {
                            settings.discordToken = ""
                            settings.discordUsername = ""
                            manualTokenInput = ""
                            discordRPC.disconnect()
                        }
                        .font(.mochyCaption.weight(.semibold))
                        .foregroundColor(.mochyRed)
                    }
                }

                SecureField("Dán Discord token...", text: $manualTokenInput)
                    .textFieldStyle(.plain)
                    .font(.mochyMono)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochySurfaceVariant))
                    .foregroundColor(.mochyOnSurface)

                HStack(spacing: 10) {
                    Button {
                        showDiscordWebLogin = true
                    } label: {
                        Label("Đăng nhập WebView", systemImage: "safari.fill")
                            .font(.mochyCaption.weight(.semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(settings.accentColor))
                    }
                    .buttonStyle(.plain)

                    Button {
                        let cleaned = manualTokenInput
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        settings.discordToken = cleaned
                        if !cleaned.isEmpty {
                            settings.discordRPCEnabled = true
                            discordRPC.disconnect()
                            discordRPC.connectIfNeeded()
                            syncPresence()
                        }
                    } label: {
                        Text("Lưu & Kết nối")
                            .font(.mochyCaption.weight(.semibold))
                            .foregroundColor(.mochyOnSurface)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochySurfaceVariant))
                    }
                    .buttonStyle(.plain)
                }

                if let error = discordRPC.lastError, !error.isEmpty {
                    Text(error)
                        .font(.mochyCaption)
                        .foregroundColor(.mochyRed)
                }
            }
            .padding(14)
        }
    }

    // MARK: - Presence Customization

    private var presenceOptionsSection: some View {
        MochySettingsCard(title: "Tùy chỉnh hoạt động") {
            HStack {
                MochySettingsRowIcon(systemName: "tag.fill", tint: .mochyLavender)
                Text("Loại hoạt động")
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)
                Spacer()
                Picker("", selection: Binding(
                    get: { settings.discordActivityType },
                    set: { val in
                        settings.discordActivityType = val
                        syncPresence()
                    }
                )) {
                    ForEach(activityTypes, id: \.id) { item in
                        Text(item.title).tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Xóa trạng thái khi tạm dừng",
                subtitle: "Tự động ẩn Rich Presence khi nhấn Pause",
                icon: "pause.circle.fill",
                tint: .mochySecondary,
                isOn: Binding(
                    get: { settings.discordClearOnPause },
                    set: { val in
                        settings.discordClearOnPause = val
                        syncPresence()
                    }
                )
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Hiển thị ảnh bìa bài hát",
                subtitle: "Đính kèm ảnh bìa trên thẻ hoạt động Discord",
                icon: "photo.fill",
                tint: .mochyBlue,
                isOn: Binding(
                    get: { settings.discordShowArtwork },
                    set: { val in
                        settings.discordShowArtwork = val
                        syncPresence()
                    }
                )
            )

            MochySettingsDivider()

            MochySettingsToggleRow(
                title: "Hiển thị nút liên kết",
                subtitle: "Thêm nút \"Listen on YouTube Music\" và \"Mochy Music\"",
                icon: "link",
                tint: .mochyTeal,
                isOn: Binding(
                    get: { settings.discordShowButtons },
                    set: { val in
                        settings.discordShowButtons = val
                        syncPresence()
                    }
                )
            )
        }
    }

    private func syncPresence() {
        discordRPC.updatePresence(
            track: player.currentTrack,
            isPlaying: player.isPlaying,
            currentTime: player.currentTime,
            duration: player.duration
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Discord WebView Login Sheet

private struct DiscordTokenLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onTokenCaptured: (String) -> Void

    @State private var loadProgress: Double = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if loadProgress > 0 && loadProgress < 1.0 {
                    ProgressView(value: loadProgress)
                        .tint(.mochyLavender)
                }

                DiscordWebLoginView(loadProgress: $loadProgress) { token in
                    onTokenCaptured(token)
                    dismiss()
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())
            .navigationTitle("Đăng nhập Discord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct DiscordWebLoginView: UIViewRepresentable {
    @Binding var loadProgress: Double
    let onTokenCaptured: (String) -> Void

    private let loginURL = URL(string: "https://discord.com/login")!

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.observe(webView)
        webView.load(URLRequest(url: loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: DiscordWebLoginView
        private var progressObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?
        private var didCapture = false

        init(_ parent: DiscordWebLoginView) {
            self.parent = parent
        }

        deinit {
            progressObservation?.invalidate()
            urlObservation?.invalidate()
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.parent.loadProgress = view.estimatedProgress
                }
            }
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                self?.attemptTokenExtract(in: view)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            attemptTokenExtract(in: webView)
        }

        private func attemptTokenExtract(in webView: WKWebView) {
            guard !didCapture,
                  let path = webView.url?.path,
                  path.contains("/channels") || path.contains("/app") else {
                return
            }

            let js = """
            (function() {
                try {
                    var direct = window.localStorage.getItem('token');
                    if (direct) return direct;
                } catch (e) {}
                try {
                    var iframe = document.createElement('iframe');
                    document.body.appendChild(iframe);
                    var val = iframe.contentWindow.localStorage.getItem('token');
                    iframe.remove();
                    if (val) return val;
                } catch (e2) {}
                return '';
            })();
            """

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                webView.evaluateJavaScript(js) { [weak self] result, _ in
                    guard let self, !self.didCapture, let raw = result as? String else { return }
                    let cleaned = raw
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    guard !cleaned.isEmpty else { return }
                    self.didCapture = true
                    self.parent.onTokenCaptured(cleaned)
                }
            }
        }
    }
}
