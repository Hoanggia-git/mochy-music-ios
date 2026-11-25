import SwiftUI
import UniformTypeIdentifiers

struct ImportSyncScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var importService = ImportService.shared
    @ObservedObject private var library = LibraryStore.shared

    @AppStorage("spotifyClientId") private var spotifyClientId: String = ""
    @AppStorage("tidalClientId") private var tidalClientId: String = ""

    @State private var showCSVFileImporter = false
    @State private var showTextImportSheet = false
    @State private var showSpotifySheet = false
    @State private var showTidalSheet = false

    @State private var pastedText: String = ""
    @State private var pastedPlaylistName: String = "Imported Playlist"
    @State private var spotifyManualToken: String = ""
    @State private var tidalPlaylistInput: String = ""
    @State private var tidalManualToken: String = ""

    @State private var alertMessage: String?

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let progress = importService.progress {
                    liveProgressCard(progress)
                }

                if let alertMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(settings.accentColor)
                        Text(alertMessage)
                            .font(.mochyCaption)
                            .foregroundColor(.mochyOnSurface)
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: MochyTheme.cornerRadiusMedium, style: .continuous)
                            .fill(settings.accentColor.opacity(0.14))
                    )
                }

                importSourcesCard
                importedReviewCard
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Nhập & Đồng bộ")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showCSVFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleCSVFileResult(result)
        }
        .sheet(isPresented: $showTextImportSheet) {
            textImportModal
        }
        .sheet(isPresented: $showSpotifySheet) {
            spotifyImportModal
        }
        .sheet(isPresented: $showTidalSheet) {
            tidalImportModal
        }
    }

    // MARK: - Live Progress Card

    private func liveProgressCard(_ progress: ImportProgress) -> some View {
        MochySettingsCard(title: "Tiến trình nhập (\(progress.source.displayName))") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(statusText(progress.status))
                        .font(.mochyBody.weight(.semibold))
                        .foregroundColor(.mochyOnSurface)
                    Spacer()
                    Text("\(progress.processedItems)/\(max(progress.totalItems, progress.processedItems))")
                        .font(.mochyMono)
                        .foregroundColor(settings.accentColor)
                }

                ProgressView(value: progress.progress)
                    .tint(settings.accentColor)

                if let current = progress.currentItemName, !current.isEmpty {
                    Text("Đang đối chiếu: \(current)")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 16) {
                    Label("\(progress.matchedItems) khớp", systemImage: "checkmark.circle.fill")
                        .font(.mochyCaption)
                        .foregroundColor(.mochyGreen)
                    Label("\(progress.failedItems) lỗi", systemImage: "xmark.circle.fill")
                        .font(.mochyCaption)
                        .foregroundColor(.mochyRed)

                    Spacer()

                    if importService.isImporting {
                        Button("Hủy") {
                            importService.cancelImport()
                        }
                        .font(.mochyCaption.weight(.bold))
                        .foregroundColor(.mochyRed)
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Import Sources

    private var importSourcesCard: some View {
        MochySettingsCard(title: "Nguồn nhập danh sách phát") {
            Button {
                showSpotifySheet = true
            } label: {
                MochySettingsNavRow(
                    title: "Spotify (OAuth / API)",
                    subtitle: "Đăng nhập Spotify và đối chiếu playlist qua InnerTube",
                    icon: "music.note",
                    tint: .mochyGreen
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            Button {
                startAppleMusicImport()
            } label: {
                MochySettingsNavRow(
                    title: "Apple Music (MusicKit)",
                    subtitle: "Đọc trực tiếp thư viện playlist Apple Music trên iPhone",
                    icon: "music.note.list",
                    tint: .mochyRed
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            Button {
                showTidalSheet = true
            } label: {
                MochySettingsNavRow(
                    title: "TIDAL Playlist",
                    subtitle: "Xác thực OAuth hoặc nhập ID playlist TIDAL",
                    icon: "waveform",
                    tint: .mochySky
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            Button {
                showCSVFileImporter = true
            } label: {
                MochySettingsNavRow(
                    title: "Tệp CSV hoặc TXT",
                    subtitle: "Chọn tệp .csv (Title, Artist) hoặc .txt (Artist - Title)",
                    icon: "doc.text.fill",
                    tint: .mochyPeach
                )
            }
            .buttonStyle(.plain)

            MochySettingsDivider()

            Button {
                showTextImportSheet = true
            } label: {
                MochySettingsNavRow(
                    title: "Dán danh sách văn bản",
                    subtitle: "Dán nhanh danh sách bài hát mỗi dòng một bài",
                    icon: "doc.on.clipboard.fill",
                    tint: .mochyMauve
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Imported Playlists Review

    private var importedReviewCard: some View {
        MochySettingsCard(title: "Playlist đã nhập gần đây") {
            if importService.importedPlaylists.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundColor(.mochySecondary)
                    Text("Chưa có phiên nhập nào trong lần mở này")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary)
                    Text("Tất cả playlist đã lưu vẫn nằm trong tab Thư viện (\(library.playlists.count) playlist).")
                        .font(.mochyCaption)
                        .foregroundColor(.mochySecondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else {
                ForEach(importService.importedPlaylists) { playlist in
                    HStack(spacing: 12) {
                        MochySettingsRowIcon(systemName: playlist.source.iconName, tint: settings.accentColor)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name)
                                .font(.mochyBody.weight(.semibold))
                                .foregroundColor(.mochyOnSurface)
                            Text("\(playlist.matchedTracks.count)/\(playlist.rawTracks.count) bài đã lưu • \(playlist.source.displayName)")
                                .font(.mochyCaption)
                                .foregroundColor(.mochySecondary)
                        }

                        Spacer()

                        if !playlist.matchedTracks.isEmpty {
                            Button {
                                AudioPlayerManager.shared.play(tracks: playlist.matchedTracks, startIndex: 0)
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.black)
                                    .padding(9)
                                    .background(Circle().fill(settings.accentColor))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if playlist.id != importService.importedPlaylists.last?.id {
                        MochySettingsDivider()
                    }
                }
            }
        }
    }

    // MARK: - Modals

    private var textImportModal: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("Tên playlist", text: $pastedPlaylistName)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.mochySurfaceVariant))
                    .foregroundColor(.mochyOnSurface)

                TextEditor(text: $pastedText)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.mochySurfaceVariant))
                    .foregroundColor(.mochyOnSurface)
                    .font(.mochyMono)
                    .overlay(alignment: .topLeading) {
                        if pastedText.isEmpty {
                            Text("Ví dụ:\nSơn Tùng M-TP - Lạc Trôi\nJack - Hồng Nhan\nTitle,Artist")
                                .font(.mochyCaption)
                                .foregroundColor(.mochySecondary)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    let name = pastedPlaylistName
                    let text = pastedText
                    showTextImportSheet = false
                    Task {
                        if let saved = await importService.importFromCSVText(text, playlistName: name) {
                            alertMessage = "Đã lưu playlist \"\(saved.name)\" với \(saved.tracks.count) bài hát."
                        } else {
                            alertMessage = importService.lastError ?? "Không tìm thấy bài hát phù hợp."
                        }
                    }
                } label: {
                    Text("Phân tích & Lưu vào Thư viện")
                        .font(.mochyBody.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(settings.accentColor))
                }
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())
            .navigationTitle("Nhập từ văn bản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showTextImportSheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var spotifyImportModal: some View {
        NavigationStack {
            Form {
                Section("OAuth PKCE (Spotify Developer)") {
                    TextField("Spotify Client ID", text: $spotifyClientId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Đăng nhập Spotify & Nhập Playlist") {
                        showSpotifySheet = false
                        Task {
                            do {
                                let token = try await importService.authenticateSpotify(clientId: spotifyClientId)
                                let raw = try await importService.fetchSpotifyPlaylists(accessToken: token)
                                let saved = await importService.matchAndSavePlaylists(raw, source: .spotify)
                                alertMessage = "Đã nhập \(saved.count) playlist từ Spotify."
                            } catch {
                                alertMessage = "Spotify lỗi: \(error.localizedDescription)"
                            }
                        }
                    }
                    .disabled(spotifyClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Hoặc dùng Access Token trực tiếp") {
                    SecureField("Bearer Access Token", text: $spotifyManualToken)
                    Button("Tải playlist bằng Token") {
                        let token = spotifyManualToken
                        showSpotifySheet = false
                        Task {
                            do {
                                let raw = try await importService.fetchSpotifyPlaylists(accessToken: token)
                                let saved = await importService.matchAndSavePlaylists(raw, source: .spotify)
                                alertMessage = "Đã nhập \(saved.count) playlist từ Spotify."
                            } catch {
                                alertMessage = "Spotify lỗi: \(error.localizedDescription)"
                            }
                        }
                    }
                    .disabled(spotifyManualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())
            .navigationTitle("Spotify Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showSpotifySheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var tidalImportModal: some View {
        NavigationStack {
            Form {
                Section("Thông tin TIDAL") {
                    TextField("TIDAL Client ID", text: $tidalClientId)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("ID hoặc URL Playlist TIDAL", text: $tidalPlaylistInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Hoặc Access Token (tùy chọn)", text: $tidalManualToken)
                }

                Section {
                    Button("Nhập Playlist TIDAL") {
                        let pid = tidalPlaylistInput
                        let manual = tidalManualToken.trimmingCharacters(in: .whitespacesAndNewlines)
                        showTidalSheet = false
                        Task {
                            do {
                                let token: String?
                                if !manual.isEmpty {
                                    token = manual
                                } else {
                                    token = try await importService.authenticateTidal(clientId: tidalClientId)
                                }
                                let playlist = try await importService.fetchTidalPlaylist(playlistId: pid, accessToken: token)
                                let saved = await importService.matchAndSavePlaylists([playlist], source: .tidal)
                                alertMessage = "Đã nhập \(saved.count) playlist từ TIDAL."
                            } catch {
                                alertMessage = "TIDAL lỗi: \(error.localizedDescription)"
                            }
                        }
                    }
                    .disabled(tidalPlaylistInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.mochyEffectiveBackground.ignoresSafeArea())
            .navigationTitle("TIDAL Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showTidalSheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func startAppleMusicImport() {
        Task {
            do {
                let saved = try await importService.importFromAppleMusic()
                alertMessage = "Đã nhập \(saved.count) playlist từ Apple Music."
            } catch {
                alertMessage = "Apple Music: \(error.localizedDescription)"
            }
        }
    }

    private func handleCSVFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    if let saved = try await importService.importFromCSV(fileURL: url) {
                        alertMessage = "Đã nhập playlist \"\(saved.name)\" (\(saved.tracks.count) bài)."
                    } else {
                        alertMessage = importService.lastError ?? "Không đọc được bài hát từ tệp."
                    }
                } catch {
                    alertMessage = "Lỗi đọc tệp CSV: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
    }

    private func statusText(_ status: ImportProgress.ImportStatus) -> String {
        switch status {
        case .preparing: return "Đang chuẩn bị..."
        case .inProgress: return "Đang đọc danh sách..."
        case .matching: return "Đang đối chiếu với YouTube Music..."
        case .completed: return "Hoàn tất nhập dữ liệu"
        case .failed: return "Nhập thất bại"
        case .cancelled: return "Đã hủy"
        }
    }
}
