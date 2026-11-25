import SwiftUI
import UIKit

/// Authentic iPod Classic UI with top LCD screen (Now Playing / Browse Library / Playlists / Songs) and interactive Click Wheel.
struct IPodPlayerView: View {
    let track: Track
    let handlers: PlayerActionHandlers

    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var settings = AppSettings.shared

    enum IPodScreenMode {
        case mainMenu
        case nowPlaying
        case playlists
        case songs
        case favorites
    }

    @State private var screenMode: IPodScreenMode = .nowPlaying
    @State private var selectedIndex: Int = 0
    @State private var lastWheelAngle: Double?
    @State private var angleAccumulator: Double = 0

    private let mainMenuItems = ["Now Playing", "Songs (Queue)", "Favorites", "Playlists", "Shuffle All"]

    private var ipodTheme: IpodTheme {
        IpodTheme(rawValue: settings.ipodThemeRaw) ?? .trueDark
    }

    private var bodyGradient: [Color] {
        switch ipodTheme {
        case .silver:
            return [Color(hex: 0xD8DADC), Color(hex: 0xAEB2B7)]
        case .black:
            return [Color(hex: 0x242428), Color(hex: 0x111114)]
        case .u2:
            return [Color(hex: 0x1E1E22), Color(hex: 0x0B0B0D)]
        case .trueDark:
            return [Color(hex: 0x121214), Color(hex: 0x050506)]
        }
    }

    private var wheelColor: Color {
        let pref = IpodWheelColor(rawValue: settings.ipodWheelColorRaw) ?? .theme
        switch pref {
        case .white: return Color(hex: 0xF1F2F4)
        case .black: return Color(hex: 0x1D1D20)
        case .red: return Color(hex: 0xD92B2B)
        case .theme:
            return ipodTheme == .u2 ? Color(hex: 0xD92B2B) : (ipodTheme == .silver ? Color(hex: 0xEFEFF2) : Color(hex: 0x1C1C20))
        }
    }

    private var wheelGlyphColor: Color {
        let pref = IpodWheelColor(rawValue: settings.ipodWheelColorRaw) ?? .theme
        if pref == .white || (pref == .theme && ipodTheme == .silver) {
            return Color.black.opacity(0.75)
        }
        return Color.white.opacity(0.85)
    }

    var body: some View {
        ZStack {
            Color.mochyBackground.ignoresSafeArea()

            VStack(spacing: 14) {
                PlayerTopBar(subtitle: "iPod Classic", track: track, handlers: handlers)

                // iPod Device Shell
                VStack(spacing: 22) {
                    lcdScreen
                    clickWheel
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: bodyGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.7), radius: 24, y: 12)
                .padding(.horizontal, 22)

                Spacer(minLength: 4)
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - LCD Screen

    private var lcdScreen: some View {
        VStack(spacing: 0) {
            // Classic iPod status bar
            HStack {
                Image(systemName: player.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 10))
                Text(lcdTitle)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Image(systemName: "battery.100")
                    .font(.system(size: 12))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0xDCE5EE), Color(hex: 0xB8C7D6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // LCD Content
            Group {
                switch screenMode {
                case .nowPlaying:
                    lcdNowPlayingView
                case .mainMenu:
                    lcdListView(items: mainMenuItems)
                case .songs:
                    let titles = player.queue.map { "\($0.title) — \($0.artistsText)" }
                    lcdListView(items: titles.isEmpty ? ["Queue is empty"] : titles)
                case .favorites:
                    let titles = library.favorites.map { "\($0.title) — \($0.artistsText)" }
                    lcdListView(items: titles.isEmpty ? ["No favorites yet"] : titles)
                case .playlists:
                    let titles = library.playlists.map { "\($0.name) (\($0.tracks.count))" }
                    lcdListView(items: titles.isEmpty ? ["No playlists yet"] : titles)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0xF4F7FA))
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.85), lineWidth: 3)
        )
    }

    private var lcdTitle: String {
        switch screenMode {
        case .mainMenu: return "iPod"
        case .nowPlaying: return "Now Playing"
        case .playlists: return "Playlists"
        case .songs: return "Queue"
        case .favorites: return "Favorites"
        }
    }

    private var lcdNowPlayingView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                MochyArtworkView(url: track.artworkURL, cornerRadius: 6)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(player.currentIndex + 1) of \(max(1, player.queue.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.gray)

                    Text(track.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .lineLimit(2)

                    Text(track.artistsText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black.opacity(0.7))
                        .lineLimit(1)

                    if let album = track.album?.name {
                        Text(album)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Classic blue iPod progress bar
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    let pct = player.duration > 0 ? min(1, max(0, player.currentTime / player.duration)) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.25))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0x58A6FF), Color(hex: 0x1D6CE0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: proxy.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 9)

                HStack {
                    Text(PlayerTimeFormatter.format(player.currentTime))
                    Spacer()
                    Text(PlayerTimeFormatter.endTimestampText(currentTime: player.currentTime, duration: player.duration))
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.black.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func lcdListView(items: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, title in
                        let isSelected = idx == min(selectedIndex, items.count - 1)
                        HStack {
                            Text(title)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .black)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(isSelected ? .white : .gray)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            isSelected
                                ? LinearGradient(colors: [Color(hex: 0x4E9CFF), Color(hex: 0x1A68DB)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [Color.clear, Color.clear], startPoint: .top, endPoint: .bottom)
                        )
                        .id(idx)
                        .onTapGesture {
                            selectedIndex = idx
                            handleCenterSelect()
                        }
                    }
                }
            }
            .onChange(of: selectedIndex) { newVal in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(newVal, anchor: .center)
                }
            }
        }
    }

    // MARK: - Click Wheel

    private var clickWheel: some View {
        ZStack {
            Circle()
                .fill(wheelColor)
                .frame(width: 224, height: 224)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.25), lineWidth: 1)
                )
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            let center = CGPoint(x: 112, y: 112)
                            let angle = atan2(value.location.y - center.y, value.location.x - center.x)
                            if let prev = lastWheelAngle {
                                var delta = angle - prev
                                if delta > .pi { delta -= 2 * .pi }
                                if delta < -.pi { delta += 2 * .pi }
                                angleAccumulator += delta
                                let stepThreshold = 0.36
                                if abs(angleAccumulator) >= stepThreshold {
                                    let dir = angleAccumulator > 0 ? 1 : -1
                                    angleAccumulator = 0
                                    handleWheelStep(direction: dir)
                                }
                            }
                            lastWheelAngle = angle
                        }
                        .onEnded { _ in
                            lastWheelAngle = nil
                            angleAccumulator = 0
                        }
                )

            // Cardinal buttons on wheel
            VStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    handleMenuPress()
                } label: {
                    Text("MENU")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(wheelGlyphColor)
                        .padding(10)
                }
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    player.togglePlayPause()
                } label: {
                    Image(systemName: "playpause.fill")
                        .font(.system(size: 15))
                        .foregroundColor(wheelGlyphColor)
                        .padding(10)
                }
            }
            .frame(height: 204)

            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    player.previous()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 15))
                        .foregroundColor(wheelGlyphColor)
                        .padding(10)
                }
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    player.next()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 15))
                        .foregroundColor(wheelGlyphColor)
                        .padding(10)
                }
            }
            .frame(width: 204)

            // Center Select Button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                handleCenterSelect()
            } label: {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: bodyGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
            }
        }
        .frame(width: 224, height: 224)
    }

    // MARK: - Click Wheel Logic

    private func handleWheelStep(direction: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        if screenMode == .nowPlaying {
            player.seek(to: player.currentTime + Double(direction) * 5.0)
            return
        }
        let maxCount = currentListCount
        guard maxCount > 0 else { return }
        selectedIndex = max(0, min(maxCount - 1, selectedIndex + direction))
    }

    private func handleMenuPress() {
        selectedIndex = 0
        switch screenMode {
        case .nowPlaying:
            screenMode = .mainMenu
        case .mainMenu:
            screenMode = .nowPlaying
        case .playlists, .songs, .favorites:
            screenMode = .mainMenu
        }
    }

    private func handleCenterSelect() {
        switch screenMode {
        case .nowPlaying:
            screenMode = .mainMenu
            selectedIndex = 0
        case .mainMenu:
            switch selectedIndex {
            case 0:
                screenMode = .nowPlaying
            case 1:
                selectedIndex = 0
                screenMode = .songs
            case 2:
                selectedIndex = 0
                screenMode = .favorites
            case 3:
                selectedIndex = 0
                screenMode = .playlists
            case 4:
                if !library.favorites.isEmpty {
                    player.play(tracks: library.favorites.shuffled(), startIndex: 0)
                } else if !player.queue.isEmpty {
                    player.toggleShuffle()
                }
                screenMode = .nowPlaying
            default:
                break
            }
        case .songs:
            if player.queue.indices.contains(selectedIndex) {
                player.play(tracks: player.queue, startIndex: selectedIndex)
                screenMode = .nowPlaying
            }
        case .favorites:
            if library.favorites.indices.contains(selectedIndex) {
                player.play(tracks: library.favorites, startIndex: selectedIndex)
                screenMode = .nowPlaying
            }
        case .playlists:
            if library.playlists.indices.contains(selectedIndex) {
                let pl = library.playlists[selectedIndex]
                if !pl.tracks.isEmpty {
                    player.play(tracks: pl.tracks, startIndex: 0)
                    screenMode = .nowPlaying
                }
            }
        }
    }

    private var currentListCount: Int {
        switch screenMode {
        case .mainMenu: return mainMenuItems.count
        case .songs: return max(1, player.queue.count)
        case .favorites: return max(1, library.favorites.count)
        case .playlists: return max(1, library.playlists.count)
        case .nowPlaying: return 0
        }
    }
}
