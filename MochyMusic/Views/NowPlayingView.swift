import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var isDraggingSlider = false
    @State private var sliderValue: TimeInterval = 0

    var body: some View {
        NavigationStack {
            Group {
                if let track = player.currentTrack {
                    VStack(spacing: 20) {
                        if showLyrics {
                            LyricsPanelView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            artworkView(for: track)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        if let errorMessage = player.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        trackHeader(for: track)
                        scrubberView
                        transportControls
                        bottomActions(for: track)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                } else {
                    Text("No track selected")
                        .foregroundColor(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(showLyrics ? "Lyrics" : "Now Playing")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showQueue) {
                QueueSheetView()
            }
            .onAppear {
                sliderValue = player.currentTime
            }
            .onChange(of: player.currentTime) { newTime in
                if !isDraggingSlider {
                    sliderValue = newTime
                }
            }
        }
    }

    private func artworkView(for track: Track) -> some View {
        AsyncImage(url: track.artworkURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            default:
                ZStack {
                    Color.secondary.opacity(0.2)
                    Image(systemName: "music.note")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .padding(.vertical, 8)
    }

    private func trackHeader(for track: Track) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                library.toggleFavorite(track)
            } label: {
                Image(systemName: library.isFavorite(track) ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(library.isFavorite(track) ? .pink : .secondary)
            }
        }
    }

    private var scrubberView: some View {
        VStack(spacing: 4) {
            Slider(
                value: $sliderValue,
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isDraggingSlider = editing
                    if !editing {
                        player.seek(to: sliderValue)
                    }
                }
            )
            .tint(.accentColor)

            HStack {
                Text(formatTime(isDraggingSlider ? sliderValue : player.currentTime))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 28) {
            Button {
                player.isShuffled.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundColor(player.isShuffled ? .accentColor : .secondary)
            }

            Button {
                player.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 68, height: 68)
                    if player.isLoading {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.black)
                    }
                }
            }

            Button {
                player.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundColor(player.repeatMode == .off ? .secondary : .accentColor)
            }
        }
        .foregroundColor(.primary)
    }

    private func bottomActions(for track: Track) -> some View {
        HStack(spacing: 36) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLyrics.toggle()
                }
            } label: {
                Label("Lyrics", systemImage: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.subheadline)
                    .foregroundColor(showLyrics ? .accentColor : .secondary)
            }

            if library.isDownloaded(track) {
                Button {
                    library.removeDownload(track)
                } label: {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            } else if library.downloadingIDs.contains(track.id) {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Saving...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Button {
                    Task { await library.downloadTrack(track) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct LyricsPanelView: View {
    @EnvironmentObject private var player: AudioPlayerManager

    private var activeLineIndex: Int? {
        guard let lines = player.lyrics?.syncedLines, !lines.isEmpty else { return nil }
        let now = player.currentTime
        return lines.lastIndex(where: { $0.time <= now + 0.2 })
    }

    var body: some View {
        Group {
            if player.isLoadingLyrics {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Fetching lyrics from LRCLIB...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let lyrics = player.lyrics {
                if lyrics.hasSynced {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(lyrics.syncedLines.enumerated()), id: \.element.id) { index, line in
                                    let isActive = index == activeLineIndex
                                    Button {
                                        player.seek(to: line.time)
                                    } label: {
                                        Text(line.text)
                                            .font(isActive ? .title3.bold() : .body.weight(.medium))
                                            .foregroundColor(isActive ? .primary : .secondary.opacity(0.6))
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 32)
                        }
                        .onChange(of: activeLineIndex) { newIndex in
                            if let newIndex {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(newIndex, anchor: .center)
                                }
                            }
                        }
                    }
                } else if let plain = lyrics.plainText {
                    ScrollView {
                        Text(plain)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 16)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.quarternote.3")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No lyrics found for this track")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct QueueSheetView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
                    Button {
                        player.play(track: track, inQueue: player.queue)
                    } label: {
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.body.weight(index == player.currentIndex ? .semibold : .regular))
                                    .foregroundColor(index == player.currentIndex ? .accentColor : .primary)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if index == player.currentIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
