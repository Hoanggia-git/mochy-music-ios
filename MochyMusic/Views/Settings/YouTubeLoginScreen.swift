import SwiftUI
import WebKit

struct YouTubeLoginScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var innerTube = InnerTubeService.shared

    @State private var loadProgress: Double = 0
    @State private var isLoadingPage: Bool = false
    @State private var showLoginWebView: Bool = false
    @State private var isVerifyingAccount: Bool = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var reloadTrigger = UUID()

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            if isLoadingPage && (!innerTube.isSignedIn || showLoginWebView) {
                ProgressView(value: loadProgress)
                    .progressViewStyle(.linear)
                    .tint(settings.accentColor)
            }

            if innerTube.isSignedIn && !showLoginWebView {
                connectedAccountView
            } else {
                YouTubeAuthWebView(
                    reloadTrigger: reloadTrigger,
                    loadProgress: $loadProgress,
                    isLoading: $isLoadingPage,
                    onCookiesCaptured: { cookieString, visitorData, dataSyncId in
                        handleCapturedSession(
                            cookieString: cookieString,
                            visitorData: visitorData,
                            dataSyncId: dataSyncId
                        )
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("YouTube Music Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if !innerTube.isSignedIn || showLoginWebView {
                        Button {
                            reloadTrigger = UUID()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(settings.accentColor)
                        }
                    }

                    if innerTube.isSignedIn {
                        Button("Đăng xuất") {
                            signOut()
                        }
                        .font(.mochyCaption.weight(.semibold))
                        .foregroundColor(.mochyRed)
                    }
                }
            }
        }
        .onAppear {
            showLoginWebView = !innerTube.isSignedIn
        }
    }

    // MARK: - Connected Account Summary

    private var connectedAccountView: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.mochyRed.opacity(0.18))
                            .frame(width: 72, height: 72)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.mochyRed)
                    }

                    VStack(spacing: 4) {
                        Text(settings.ytAccountName.isEmpty ? "YouTube Music Account" : settings.ytAccountName)
                            .font(.mochyTitle)
                            .foregroundColor(.white)

                        if !settings.ytAccountHandle.isEmpty {
                            Text(settings.ytAccountHandle)
                                .font(.mochyBody)
                                .foregroundColor(settings.accentColor)
                        }
                        if !settings.ytAccountEmail.isEmpty {
                            Text(settings.ytAccountEmail)
                                .font(.mochyCaption)
                                .foregroundColor(.mochySecondary)
                        }
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.mochyGreen)
                            .frame(width: 8, height: 8)
                        Text("Đã kết nối phiên InnerTube (SAPISIDHASH)")
                            .font(.mochyCaption.weight(.semibold))
                            .foregroundColor(.mochyGreen)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.mochyGreen.opacity(0.14)))
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                        .fill(settings.pureBlack ? Color.mochySurface : Color.mochySurface0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusLarge, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                MochySettingsCard(title: "Đồng bộ YouTube Music") {
                    MochySettingsToggleRow(
                        title: "Bật đồng bộ thư viện YouTube",
                        subtitle: "Hiển thị nhạc đã thích & playlist từ tài khoản YouTube",
                        icon: "arrow.triangle.2.circlepath",
                        tint: .mochyRed,
                        isOn: $settings.ytmSync
                    )

                    MochySettingsDivider()

                    MochySettingsToggleRow(
                        title: "Đồng bộ bài hát đã thích",
                        subtitle: "Tải danh sách FEmusic_liked_videos từ YouTube Music",
                        icon: "heart.fill",
                        tint: .mochyPink,
                        isOn: $settings.ytSyncLikedSongs
                    )

                    MochySettingsDivider()

                    MochySettingsToggleRow(
                        title: "Ghi nhận lịch sử phát lên YouTube",
                        subtitle: "Gửi lượt phát để cải thiện gợi ý trên tài khoản",
                        icon: "clock.arrow.circlepath",
                        tint: .mochyBlue,
                        isOn: $settings.ytReportPlays
                    )
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.mochyCaption)
                        .foregroundColor(.mochyGreen)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.mochyCaption)
                        .foregroundColor(.mochyRed)
                }

                VStack(spacing: 10) {
                    Button {
                        Task { await refreshAccountProfile() }
                    } label: {
                        HStack {
                            if isVerifyingAccount {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                            }
                            Text("Làm mới thông tin tài khoản")
                        }
                        .font(.mochyBody.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(settings.accentColor))
                    }
                    .disabled(isVerifyingAccount)

                    Button {
                        showLoginWebView = true
                        reloadTrigger = UUID()
                    } label: {
                        Text("Đăng nhập lại qua WebView")
                            .font(.mochyBody.weight(.medium))
                            .foregroundColor(.mochyOnSurface)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.mochySurfaceVariant))
                    }

                    Button {
                        signOut()
                    } label: {
                        Text("Đăng xuất khỏi YouTube Music")
                            .font(.mochyBody.weight(.semibold))
                            .foregroundColor(.mochyRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.mochyRed.opacity(0.14)))
                    }
                }
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 110)
        }
    }

    // MARK: - Actions

    private func handleCapturedSession(cookieString: String, visitorData: String, dataSyncId: String) {
        guard !isVerifyingAccount else { return }
        isVerifyingAccount = true
        errorMessage = nil

        settings.ytInnerTubeCookie = cookieString
        if !visitorData.isEmpty {
            settings.ytVisitorData = visitorData
        }
        if !dataSyncId.isEmpty {
            settings.ytDataSyncId = dataSyncId
        }
        settings.ytmSync = true

        innerTube.cookie = cookieString
        if !visitorData.isEmpty {
            innerTube.visitorData = visitorData
        }
        if !dataSyncId.isEmpty {
            innerTube.dataSyncId = dataSyncId
        }

        Task {
            do {
                _ = try await innerTube.fetchAccountInfo()
                isVerifyingAccount = false
                showLoginWebView = false
                dismiss()
            } catch {
                isVerifyingAccount = false
                showLoginWebView = false
                statusMessage = "Đã lưu cookie phiên đăng nhập YouTube Music."
                errorMessage = "Không đọc được hồ sơ: \(error.localizedDescription)"
            }
        }
    }

    private func refreshAccountProfile() async {
        isVerifyingAccount = true
        errorMessage = nil
        statusMessage = nil
        defer { isVerifyingAccount = false }
        do {
            let info = try await innerTube.fetchAccountInfo()
            let display = info.name ?? info.handle ?? "YouTube Account"
            statusMessage = "Đã cập nhật tài khoản: \(display)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signOut() {
        innerTube.signOutYouTube()
        settings.ytmSync = false
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) {
            showLoginWebView = true
            reloadTrigger = UUID()
        }
    }
}

// MARK: - WKWebView Wrapper

private struct YouTubeAuthWebView: UIViewRepresentable {
    let reloadTrigger: UUID
    @Binding var loadProgress: Double
    @Binding var isLoading: Bool
    let onCookiesCaptured: (String, String, String) -> Void

    private let loginURL = URL(string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com")!

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"

        context.coordinator.observe(webView)
        context.coordinator.lastTrigger = reloadTrigger
        webView.load(URLRequest(url: loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastTrigger != reloadTrigger {
            context.coordinator.lastTrigger = reloadTrigger
            context.coordinator.didCaptureSession = false
            webView.load(URLRequest(url: loginURL))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: YouTubeAuthWebView
        private var progressObservation: NSKeyValueObservation?
        private var loadingObservation: NSKeyValueObservation?
        var lastTrigger: UUID?
        var didCaptureSession = false

        init(_ parent: YouTubeAuthWebView) {
            self.parent = parent
        }

        deinit {
            progressObservation?.invalidate()
            loadingObservation?.invalidate()
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.parent.loadProgress = view.estimatedProgress
                }
            }
            loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.parent.isLoading = view.isLoading
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didCaptureSession,
                  let currentURL = webView.url,
                  let host = currentURL.host?.lowercased(),
                  host.contains("music.youtube.com") else {
                return
            }

            let cookieStore = WKWebsiteDataStore.default().httpCookieStore
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let relevant = cookies.filter {
                    let dom = $0.domain.lowercased()
                    return dom.contains("youtube.com") || dom.contains("google.com")
                }

                let hasAuthCookie = relevant.contains {
                    $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID" || $0.name == "SID"
                }
                guard hasAuthCookie else { return }

                let cookieHeader = relevant
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")

                let js = """
                (function() {
                    var v = '';
                    var d = '';
                    try {
                        if (window.ytcfg && typeof window.ytcfg.get === 'function') {
                            v = window.ytcfg.get('VISITOR_DATA') || '';
                            d = window.ytcfg.get('DATASYNC_ID') || '';
                        }
                    } catch (e) {}
                    return { visitorData: String(v), dataSyncId: String(d) };
                })();
                """

                DispatchQueue.main.async {
                    webView.evaluateJavaScript(js) { result, _ in
                        guard !self.didCaptureSession else { return }
                        self.didCaptureSession = true
                        let dict = result as? [String: Any]
                        let visitorData = dict?["visitorData"] as? String ?? ""
                        let dataSyncId = dict?["dataSyncId"] as? String ?? ""
                        self.parent.onCookiesCaptured(cookieHeader, visitorData, dataSyncId)
                    }
                }
            }
        }
    }
}
