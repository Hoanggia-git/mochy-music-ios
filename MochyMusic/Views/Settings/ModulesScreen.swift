import SwiftUI

struct ModulesScreen: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var monochrome = MonochromeService.shared
    @ObservedObject private var jiosaavn = JioSaavnService.shared
    @ObservedObject private var player = AudioPlayerManager.shared

    @State private var newServerURL: String = ""
    @State private var isAddingServer = false
    @State private var serverFeedback: String?
    @State private var isTestingServers = false
    @State private var serverTestResult: String?

    @State private var isTestingJioSaavn = false
    @State private var jioSaavnTestResult: String?

    @State private var diagQuery: String = ""
    @State private var isRunningDiag = false
    @State private var diagTrackTitle: String?
    @State private var diagResults: [DiagnosticRow] = []

    private let audioSources: [(id: String, title: String, subtitle: String)] = [
        ("innertube", "YouTube Music (InnerTube)", "Mặc định · Ổn định, hỗ trợ mọi bài hát"),
        ("monochrome", "Monochrome Lossless FLAC", "Ưu tiên FLAC 16-bit / Hi-Res 24-bit"),
        ("jiosaavn", "JioSaavn AAC", "Ưu tiên AAC 320 kbps từ JioSaavn")
    ]

    private let jioQualities: [(id: String, label: String)] = [
        ("320", "320 kbps (Cao nhất)"),
        ("160", "160 kbps (Cân bằng)"),
        ("96", "96 kbps (Tiết kiệm)")
    ]

    struct DiagnosticRow: Identifiable {
        let id: String
        let sourceName: String
        let badge: String?
        let detail: String
        let isSuccess: Bool
    }

    init() {}

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                preferredSourceCard
                monochromeCard
                jioSaavnCard
                diagnosticsCard
            }
            .padding(.horizontal, MochyTheme.screenHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(Color.mochyEffectiveBackground.ignoresSafeArea())
        .navigationTitle("Mô-đun nguồn phát")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Preferred Audio Source

    private var preferredSourceCard: some View {
        MochySettingsCard(title: "Nguồn phát ưu tiên (Preferred Source)") {
            ForEach(Array(audioSources.enumerated()), id: \.element.id) { index, source in
                let isSelected = settings.preferredAudioSource == source.id
                Button {
                    withAnimation(MochyTheme.snappySpring) {
                        settings.preferredAudioSource = source.id
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(isSelected ? settings.accentColor : .mochySecondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title)
                                .font(.mochyBody.weight(.semibold))
                                .foregroundColor(.mochyOnSurface)
                            Text(source.subtitle)
                                .font(.mochyCaption)
                                .foregroundColor(.mochySecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < audioSources.count - 1 {
                    MochySettingsDivider()
                }
            }
        }
    }

    // MARK: - Monochrome FLAC

    private var monochromeCard: some View {
        MochySettingsCard(title: "Monochrome Lossless FLAC") {
            MochySettingsToggleRow(
                title: "Bật Monochrome FLAC",
                subtitle: "Tự động phân giải FLAC / Hi-Res FLAC cho chất lượng Lossless",
                icon: "waveform.badge.magnifyingglass",
                tint: .mochyTeal,
                isOn: $settings.monochromeEnabled
            )

            MochySettingsDivider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Danh sách máy chủ (\(monochrome.servers.count))")
                    .font(.mochyCaption.weight(.semibold))
                    .foregroundColor(.mochySecondary)

                ForEach(monochrome.servers) { server in
                    HStack(spacing: 10) {
                        Image(systemName: server.builtIn ? "server.rack" : "globe")
                            .foregroundColor(.mochyTeal)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .font(.mochyBody.weight(.medium))
                                .foregroundColor(.mochyOnSurface)
                            Text("\(server.kind) • \(server.url)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.mochySecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if server.builtIn {
                            Text("Mặc định")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.mochyTeal)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.mochyTeal.opacity(0.16)))
                        } else {
                            Button {
                                monochrome.removeServer(url: server.url)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.mochyRed)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochySurfaceVariant))
                }

                HStack(spacing: 8) {
                    TextField("Thêm URL máy chủ (vd: https://...)", text: $newServerURL)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.mochyCaption)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochySurfaceVariant))
                        .foregroundColor(.mochyOnSurface)

                    Button {
                        Task { await addCustomServer() }
                    } label: {
                        if isAddingServer {
                            ProgressView().tint(.black)
                                .frame(width: 60, height: 36)
                                .background(RoundedRectangle(cornerRadius: 10).fill(settings.accentColor))
                        } else {
                            Text("Thêm")
                                .font(.mochyCaption.weight(.bold))
                                .foregroundColor(.black)
                                .frame(width: 60, height: 36)
                                .background(RoundedRectangle(cornerRadius: 10).fill(settings.accentColor))
                        }
                    }
                    .disabled(newServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingServer)
                }

                if let serverFeedback {
                    Text(serverFeedback)
                        .font(.mochyCaption)
                        .foregroundColor(serverFeedback.contains("Added") ? .mochyGreen : .mochyYellow)
                }

                Button {
                    Task {
                        isTestingServers = true
                        serverTestResult = await monochrome.testServers()
                        isTestingServers = false
                    }
                } label: {
                    HStack {
                        if isTestingServers { ProgressView().tint(settings.accentColor) }
                        Text(isTestingServers ? "Đang kiểm tra máy chủ..." : "Kiểm tra kết nối máy chủ")
                            .font(.mochyCaption.weight(.semibold))
                    }
                    .foregroundColor(settings.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(settings.accentColor.opacity(0.14)))
                }
                .buttonStyle(.plain)

                if let serverTestResult {
                    Text(serverTestResult)
                        .font(.mochyCaption)
                        .foregroundColor(.mochyTeal)
                }
            }
            .padding(14)
        }
    }

    // MARK: - JioSaavn AAC

    private var jioSaavnCard: some View {
        MochySettingsCard(title: "JioSaavn AAC") {
            MochySettingsToggleRow(
                title: "Bật JioSaavn AAC",
                subtitle: "Tìm và giải mã luồng nhạc AAC trực tiếp từ JioSaavn",
                icon: "music.quarternote.3",
                tint: .mochyGreen,
                isOn: $settings.jiosaavnEnabled
            )

            MochySettingsDivider()

            HStack {
                MochySettingsRowIcon(systemName: "dial.high.fill", tint: .mochyGreen)
                Text("Chất lượng JioSaavn")
                    .font(.mochyBody.weight(.medium))
                    .foregroundColor(.mochyOnSurface)
                Spacer()
                Picker("", selection: $settings.jiosaavnQuality) {
                    ForEach(jioQualities, id: \.id) { item in
                        Text(item.label).tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(settings.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            MochySettingsDivider()

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task {
                        isTestingJioSaavn = true
                        jioSaavnTestResult = await jiosaavn.testConnection()
                        isTestingJioSaavn = false
                    }
                } label: {
                    HStack {
                        if isTestingJioSaavn { ProgressView().tint(.mochyGreen) }
                        Text(isTestingJioSaavn ? "Đang kiểm tra JioSaavn..." : "Kiểm tra kết nối JioSaavn")
                            .font(.mochyCaption.weight(.semibold))
                    }
                    .foregroundColor(.mochyGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochyGreen.opacity(0.14)))
                }
                .buttonStyle(.plain)

                if let jioSaavnTestResult {
                    Text(jioSaavnTestResult)
                        .font(.mochyCaption)
                        .foregroundColor(jioSaavnTestResult.hasPrefix("Connected") ? .mochyGreen : .mochyRed)
                }
            }
            .padding(14)
        }
    }

    // MARK: - Live Stream Diagnostics

    private var diagnosticsCard: some View {
        MochySettingsCard(title: "Chẩn đoán luồng phát (Live Stream Diagnostics)") {
            VStack(alignment: .leading, spacing: 12) {
                TextField(
                    player.currentTrack.map { "Mặc định: \($0.title) - \($0.artistsText)" } ?? "Nhập tên bài hát để kiểm tra...",
                    text: $diagQuery
                )
                .textFieldStyle(.plain)
                .font(.mochyCaption)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochySurfaceVariant))
                .foregroundColor(.mochyOnSurface)

                Button {
                    Task { await runDiagnostics() }
                } label: {
                    HStack(spacing: 8) {
                        if isRunningDiag {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "stethoscope")
                        }
                        Text(isRunningDiag ? "Đang kiểm tra cả 3 nguồn..." : "Chạy chẩn đoán đa nguồn")
                    }
                    .font(.mochyBody.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(settings.accentColor))
                }
                .disabled(isRunningDiag)

                if let diagTrackTitle {
                    Text("Bài hát kiểm tra: \(diagTrackTitle)")
                        .font(.mochyCaption.weight(.semibold))
                        .foregroundColor(settings.accentColor)
                }

                ForEach(diagResults) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: row.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(row.isSuccess ? .mochyGreen : .mochyRed)
                            Text(row.sourceName)
                                .font(.mochyBody.weight(.semibold))
                                .foregroundColor(.mochyOnSurface)
                            Spacer()
                            if let badge = row.badge {
                                Text(badge)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.mochyTeal)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.mochyTeal.opacity(0.16)))
                            }
                        }
                        Text(row.detail)
                            .font(.mochyCaption)
                            .foregroundColor(.mochySecondary)
                            .lineLimit(3)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.mochySurfaceVariant))
                }
            }
            .padding(14)
        }
    }

    // MARK: - Actions

    private func addCustomServer() async {
        isAddingServer = true
        serverFeedback = nil
        let input = newServerURL
        let err = await monochrome.addServer(urlString: input)
        isAddingServer = false
        if let err {
            serverFeedback = err
        } else {
            newServerURL = ""
            serverFeedback = "Added server successfully."
        }
    }

    private func runDiagnostics() async {
        isRunningDiag = true
        diagResults = []
        defer { isRunningDiag = false }

        let targetTrack: Track
        let trimmed = diagQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let found = try? await InnerTubeService.shared.searchSongs(query: trimmed).first {
                targetTrack = found
            } else {
                targetTrack = Track(id: "diag", title: trimmed, artists: [])
            }
        } else if let current = player.currentTrack {
            targetTrack = current
        } else {
            if let found = try? await InnerTubeService.shared.searchSongs(query: "Daft Punk Get Lucky").first {
                targetTrack = found
            } else {
                targetTrack = Track(id: "5NV6Rdv1a3I", title: "Get Lucky", artists: [Artist(name: "Daft Punk")])
            }
        }

        diagTrackTitle = "\(targetTrack.title) — \(targetTrack.artistsText)"

        var rows: [DiagnosticRow] = []

        // 1. InnerTube
        do {
            let stream = try await InnerTubeService.shared.resolveStream(videoId: targetTrack.id, quality: settings.audioQuality)
            let rate = stream.sampleRate.map { "\($0) Hz" } ?? "N/A"
            rows.append(DiagnosticRow(
                id: "innertube",
                sourceName: "YouTube InnerTube",
                badge: stream.formattedBadge,
                detail: "Codec: \(stream.codecs) • Bitrate: \(stream.bitrate / 1000) kbps • Sample Rate: \(rate)",
                isSuccess: true
            ))
        } catch {
            rows.append(DiagnosticRow(
                id: "innertube",
                sourceName: "YouTube InnerTube",
                badge: nil,
                detail: error.localizedDescription,
                isSuccess: false
            ))
        }

        // 2. Monochrome FLAC
        do {
            let stream = try await monochrome.resolveStream(for: targetTrack)
            let rate = stream.sampleRate.map { "\($0) Hz" } ?? "44100 Hz"
            rows.append(DiagnosticRow(
                id: "monochrome",
                sourceName: "Monochrome FLAC",
                badge: stream.formattedBadge,
                detail: "Codec: \(stream.codecs) • MIME: \(stream.mimeType) • Sample Rate: \(rate)",
                isSuccess: true
            ))
        } catch {
            rows.append(DiagnosticRow(
                id: "monochrome",
                sourceName: "Monochrome FLAC",
                badge: nil,
                detail: error.localizedDescription,
                isSuccess: false
            ))
        }

        // 3. JioSaavn AAC
        do {
            let stream = try await jiosaavn.resolveStream(for: targetTrack, quality: settings.jiosaavnQuality)
            rows.append(DiagnosticRow(
                id: "jiosaavn",
                sourceName: "JioSaavn AAC",
                badge: stream.formattedBadge,
                detail: "Codec: \(stream.codecs) • Bitrate: \(stream.bitrate / 1000) kbps • MIME: \(stream.mimeType)",
                isSuccess: true
            ))
        } catch {
            rows.append(DiagnosticRow(
                id: "jiosaavn",
                sourceName: "JioSaavn AAC",
                badge: nil,
                detail: error.localizedDescription,
                isSuccess: false
            ))
        }

        diagResults = rows
    }
}
