import Foundation

/// Playback repeat behavior.
enum RepeatMode: String, Codable, CaseIterable {
    case off
    case one
    case all

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }
}

/// Visual layout style for the full-screen Now Playing view (matches Mochy Music Android `PlayerStyle`).
enum PlayerStyle: String, Codable, CaseIterable, Identifiable {
    case flagship
    case turntable
    case video
    case ipod
    case poster
    case timeline
    case lyrics
    case bedside
    case bedsideTiles
    case compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flagship: return "Flagship"
        case .turntable: return "Turntable"
        case .video: return "Full Video"
        case .ipod: return "iPod"
        case .poster: return "Poster"
        case .timeline: return "Timeline"
        case .lyrics: return "Lyrics Stage"
        case .bedside: return "Bedside Clock"
        case .bedsideTiles: return "Bedside"
        case .compact: return "Compact"
        }
    }
}

/// Stream audio quality tier (matches Mochy Music `AudioQuality`).
enum StreamQuality: String, Codable, CaseIterable, Identifiable {
    case auto
    case low
    case medium
    case high
    case lossless
    case hiResLossless
    case dolbyAtmos

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Tự động"
        case .low: return "Thấp"
        case .medium: return "Trung bình"
        case .high: return "Cao"
        case .lossless: return "Lossless"
        case .hiResLossless: return "Hi-Res Lossless"
        case .dolbyAtmos: return "Dolby Atmos"
        }
    }
}

/// Resolved playable stream returned by `InnerTubeService.resolveStream`.
struct ResolvedStream: Codable, Hashable {
    var url: URL
    var userAgent: String?
    var isAudioOnly: Bool
    var itag: Int
    var mimeType: String
    var codecs: String
    var bitrate: Int
    var sampleRate: Int?
    var contentLength: Int64
    var loudnessDb: Double?

    init(
        url: URL,
        userAgent: String? = nil,
        isAudioOnly: Bool = true,
        itag: Int = 140,
        mimeType: String = "audio/mp4",
        codecs: String = "mp4a.40.2",
        bitrate: Int = 128_000,
        sampleRate: Int? = 44100,
        contentLength: Int64 = 0,
        loudnessDb: Double? = nil
    ) {
        self.url = url
        self.userAgent = userAgent
        self.isAudioOnly = isAudioOnly
        self.itag = itag
        self.mimeType = mimeType
        self.codecs = codecs
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.contentLength = contentLength
        self.loudnessDb = loudnessDb
    }
}

/// Entry in the playback queue.
struct QueueItem: Identifiable, Codable, Hashable {
    let id: UUID
    var track: Track
    var addedAt: Date

    init(id: UUID = UUID(), track: Track, addedAt: Date = Date()) {
        self.id = id
        self.track = track
        self.addedAt = addedAt
    }
}

/// Seekbar slider style.
enum SliderStyle: String, Codable, CaseIterable, Identifiable {
    case defaultStyle
    case wavy
    case slim

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultStyle: return "Mặc định"
        case .wavy: return "Sóng"
        case .slim: return "Mảnh"
        }
    }
}

/// Gesture action when swiping track rows.
enum SwipeAction: String, Codable, CaseIterable, Identifiable {
    case addToQueue
    case addToPlaylist
    case download
    case like
    case remove

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .addToQueue: return "Thêm vào hàng chờ"
        case .addToPlaylist: return "Thêm vào playlist"
        case .download: return "Tải xuống"
        case .like: return "Yêu thích"
        case .remove: return "Xóa"
        }
    }
}

/// Crossmix audio transition effect layered on play/pause/skip fades.
enum TransportEffect: String, Codable, CaseIterable, Identifiable {
    case off
    case echo
    case rewind
    case tapeStop
    case farAway
    case reverbWash
    case filterSweep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Không"
        case .echo: return "Echo"
        case .rewind: return "Rewind"
        case .tapeStop: return "Tape Stop"
        case .farAway: return "Fade to Far"
        case .reverbWash: return "Reverb Wash"
        case .filterSweep: return "Filter Sweep"
        }
    }
}
