import Foundation
import AVFoundation
import CoreMedia
import MediaToolbox
import os

struct EQPreset: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var gains: [Float] // 10 bands in dB (-12.0 ... +12.0)
    var isBuiltIn: Bool

    static let bandFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static let bandLabels: [String] = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    static let builtInPresets: [EQPreset] = [
        EQPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], isBuiltIn: true),
        EQPreset(id: "bass_boost", name: "Bass Boost", gains: [7.5, 6.0, 4.5, 2.5, 0.5, 0, 0, 0, 0, 0], isBuiltIn: true),
        EQPreset(id: "bass_reduce", name: "Bass Reduce", gains: [-7.0, -5.5, -4.0, -2.0, -0.5, 0, 0, 0, 0, 0], isBuiltIn: true),
        EQPreset(id: "treble_boost", name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1.0, 2.5, 4.5, 6.0, 7.0], isBuiltIn: true),
        EQPreset(id: "treble_reduce", name: "Treble Reduce", gains: [0, 0, 0, 0, 0, -1.0, -2.5, -4.5, -6.0, -7.0], isBuiltIn: true),
        EQPreset(id: "vocal", name: "Vocal", gains: [-2.0, -1.5, -0.5, 1.5, 4.0, 5.0, 4.0, 2.0, 0.5, -1.0], isBuiltIn: true),
        EQPreset(id: "rock", name: "Rock", gains: [4.5, 3.5, 1.5, -1.0, -2.0, 0.5, 2.5, 4.0, 4.5, 4.0], isBuiltIn: true),
        EQPreset(id: "pop", name: "Pop", gains: [-1.5, 1.5, 3.5, 4.0, 2.5, 0, -1.5, -1.0, 1.5, 2.5], isBuiltIn: true),
        EQPreset(id: "jazz", name: "Jazz", gains: [3.0, 2.0, 1.0, 2.0, -1.5, -1.5, 0, 1.5, 2.5, 3.5], isBuiltIn: true),
        EQPreset(id: "classical", name: "Classical", gains: [4.0, 3.0, 2.0, 1.5, -1.0, -1.0, 0, 2.0, 3.5, 4.0], isBuiltIn: true),
        EQPreset(id: "electronic", name: "Electronic", gains: [5.5, 4.5, 2.0, 0, -2.0, 1.5, 1.0, 2.5, 4.5, 5.0], isBuiltIn: true),
        EQPreset(id: "hiphop", name: "Hip-Hop", gains: [6.0, 5.0, 2.5, 1.0, -1.5, -1.0, 1.5, 0, 2.0, 3.0], isBuiltIn: true),
        EQPreset(id: "rnb", name: "R&B", gains: [4.5, 6.0, 4.0, 1.0, -1.5, 1.0, 2.5, 2.0, 2.5, 3.0], isBuiltIn: true),
        EQPreset(id: "acoustic", name: "Acoustic", gains: [3.5, 2.5, 1.5, 0.5, 1.5, 2.0, 2.5, 3.0, 2.5, 1.5], isBuiltIn: true),
        EQPreset(id: "piano", name: "Piano", gains: [2.5, 1.5, 0, 2.0, 2.5, 1.5, 3.0, 4.0, 2.5, 1.5], isBuiltIn: true),
        EQPreset(id: "headphone_autoeq", name: "Headphone (Harman AutoEQ)", gains: [4.0, 2.5, -1.0, -1.5, 0.5, 1.5, 3.0, 2.0, -1.0, 1.0], isBuiltIn: true)
    ]
}

// MARK: - Real-Time Thread-Safe DSP Snapshot & Biquad Tap Processor

private struct EQDSPParameters {
    var isEnabled: Bool = false
    var effectiveGains: [Float] = Array(repeating: 0, count: 10)
    var version: UInt64 = 0
}

private final class EQDSPParameterStore {
    static let shared = EQDSPParameterStore()

    private let lockPtr: UnsafeMutablePointer<os_unfair_lock_s>
    private var params = EQDSPParameters()

    private init() {
        lockPtr = UnsafeMutablePointer<os_unfair_lock_s>.allocate(capacity: 1)
        lockPtr.initialize(to: os_unfair_lock())
    }

    deinit {
        lockPtr.deinitialize(count: 1)
        lockPtr.deallocate()
    }

    func update(isEnabled: Bool, gains: [Float]) {
        os_unfair_lock_lock(lockPtr)
        params.isEnabled = isEnabled
        params.effectiveGains = gains
        params.version &+= 1
        os_unfair_lock_unlock(lockPtr)
    }

    func snapshot() -> EQDSPParameters {
        os_unfair_lock_lock(lockPtr)
        let copy = params
        os_unfair_lock_unlock(lockPtr)
        return copy
    }
}

private final class EQTapProcessor {
    private struct BiquadCoeffs {
        var b0: Float = 1
        var b1: Float = 0
        var b2: Float = 0
        var a1: Float = 0
        var a2: Float = 0
    }

    private let maxChannels = 8
    private let bandCount = 10
    private var sampleRate: Float = 44100
    private var channels: Int = 2
    private var isFloatPCM: Bool = true
    private var isNonInterleaved: Bool = true
    private var lastVersion: UInt64 = .max
    private var enabled: Bool = false

    private var coeffs: [BiquadCoeffs]
    private var z1: [Float]
    private var z2: [Float]

    init() {
        self.coeffs = Array(repeating: BiquadCoeffs(), count: bandCount)
        self.z1 = Array(repeating: 0, count: bandCount * maxChannels)
        self.z2 = Array(repeating: 0, count: bandCount * maxChannels)
    }

    func prepare(sampleRate: Float, channels: Int, formatFlags: AudioFormatFlags) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44100
        self.channels = max(1, min(maxChannels, channels))
        self.isFloatPCM = (formatFlags & kAudioFormatFlagIsFloat) != 0
        self.isNonInterleaved = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        self.lastVersion = .max
        for i in 0..<z1.count {
            z1[i] = 0
            z2[i] = 0
        }
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard isFloatPCM, frameCount > 0 else { return }

        let snapshot = EQDSPParameterStore.shared.snapshot()
        enabled = snapshot.isEnabled
        guard enabled else { return }

        if snapshot.version != lastVersion {
            lastVersion = snapshot.version
            recomputeCoefficients(gains: snapshot.effectiveGains)
        }

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        if isNonInterleaved {
            let activeChannels = min(abl.count, channels)
            for ch in 0..<activeChannels {
                guard let rawPtr = abl[ch].mData else { continue }
                let samples = rawPtr.assumingMemoryBound(to: Float.self)
                processChannel(samples: samples, frameCount: frameCount, stride: 1, channelIndex: ch)
            }
        } else if let first = abl.first, let rawPtr = first.mData {
            let samples = rawPtr.assumingMemoryBound(to: Float.self)
            for ch in 0..<channels {
                processChannel(samples: samples + ch, frameCount: frameCount, stride: channels, channelIndex: ch)
            }
        }
    }

    private func processChannel(samples: UnsafeMutablePointer<Float>, frameCount: Int, stride: Int, channelIndex: Int) {
        for band in 0..<bandCount {
            let c = coeffs[band]
            // Unity passthrough optimization when band gain is effectively 0 dB
            if abs(c.b0 - 1.0) < 1e-6 && abs(c.b1) < 1e-6 && abs(c.b2) < 1e-6 {
                continue
            }
            let stateIdx = band * maxChannels + channelIndex
            var s1 = z1[stateIdx]
            var s2 = z2[stateIdx]
            var sampleOffset = 0
            for _ in 0..<frameCount {
                let x = samples[sampleOffset]
                let y = c.b0 * x + s1
                s1 = c.b1 * x - c.a1 * y + s2
                s2 = c.b2 * x - c.a2 * y
                samples[sampleOffset] = max(-1.0, min(1.0, y))
                sampleOffset += stride
            }
            z1[stateIdx] = s1
            z2[stateIdx] = s2
        }
    }

    private func recomputeCoefficients(gains: [Float]) {
        let q: Float = 1.414
        let freqs = EQPreset.bandFrequencies
        for i in 0..<bandCount {
            let gainDb = i < gains.count ? gains[i] : 0
            let freq = freqs[i]
            if abs(gainDb) < 0.05 || freq >= sampleRate * 0.45 {
                coeffs[i] = BiquadCoeffs()
                continue
            }
            let a = powf(10.0, gainDb / 40.0)
            let omega = 2.0 * Float.pi * freq / sampleRate
            let sn = sinf(omega)
            let cs = cosf(omega)
            let alpha = sn / (2.0 * q)

            let b0 = 1.0 + alpha * a
            let b1 = -2.0 * cs
            let b2 = 1.0 - alpha * a
            let a0 = 1.0 + alpha / a
            let a1 = -2.0 * cs
            let a2 = 1.0 - alpha / a

            let invA0 = 1.0 / a0
            coeffs[i] = BiquadCoeffs(
                b0: b0 * invA0,
                b1: b1 * invA0,
                b2: b2 * invA0,
                a1: a1 * invA0,
                a2: a2 * invA0
            )
        }
    }
}

private enum EQTapMixFactory {
    static func makeAudioMix(for asset: AVAsset) async -> AVAudioMix? {
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        let processor = EQTapProcessor()
        let retainedPtr = Unmanaged.passRetained(processor).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retainedPtr,
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<EQTapProcessor>.fromOpaque(storage).release()
            },
            prepare: { tap, _, processingFormat in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let processor = Unmanaged<EQTapProcessor>.fromOpaque(storage).takeUnretainedValue()
                processor.prepare(
                    sampleRate: Float(processingFormat.pointee.mSampleRate),
                    channels: Int(processingFormat.pointee.mChannelsPerFrame),
                    formatFlags: processingFormat.pointee.mFormatFlags
                )
            },
            unprepare: { _ in },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
                guard status == noErr else { return }
                let storage = MTAudioProcessingTapGetStorage(tap)
                let processor = Unmanaged<EQTapProcessor>.fromOpaque(storage).takeUnretainedValue()
                processor.process(bufferList: bufferListInOut, frameCount: Int(numberFramesOut.pointee))
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let createdTap = tap else {
            Unmanaged<EQTapProcessor>.fromOpaque(retainedPtr).release()
            return nil
        }

        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParams.audioTapProcessor = createdTap

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]
        return audioMix
    }
}

// MARK: - EqualizerService

/// AVAudioEngine + MTAudioProcessingTap 10-band parametric equalizer, reverb, pitch shift, and bass boost service.
@MainActor
final class EqualizerService: ObservableObject {
    static let shared = EqualizerService()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
            applyEngineParameters()
        }
    }
    @Published var currentPreset: EQPreset {
        didSet {
            UserDefaults.standard.set(currentPreset.id, forKey: Keys.currentPresetId)
        }
    }
    @Published var bands: [Float] {
        didSet {
            UserDefaults.standard.set(bands, forKey: Keys.bands)
            applyEngineParameters()
        }
    }
    @Published var reverbMix: Float {
        didSet {
            UserDefaults.standard.set(reverbMix, forKey: Keys.reverbMix)
            applyEngineParameters()
        }
    }
    @Published var reverbPreset: AVAudioUnitReverbPreset = .mediumHall {
        didSet {
            reverbNode.loadFactoryPreset(reverbPreset)
        }
    }
    @Published var pitchShiftCents: Float {
        didSet {
            UserDefaults.standard.set(pitchShiftCents, forKey: Keys.pitchShiftCents)
            applyEngineParameters()
        }
    }
    @Published var bassBoostEnabled: Bool {
        didSet {
            UserDefaults.standard.set(bassBoostEnabled, forKey: Keys.bassBoost)
            applyEngineParameters()
        }
    }
    @Published var customPresets: [EQPreset] = []

    // MARK: - AVAudioEngine Audio Graph

    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    let eqNode = AVAudioUnitEQ(numberOfBands: 10)
    let timePitchNode = AVAudioUnitTimePitch()
    let reverbNode = AVAudioUnitReverb()

    private enum Keys {
        static let isEnabled = "mochy_eq_enabled"
        static let currentPresetId = "mochy_eq_preset_id"
        static let bands = "mochy_eq_bands"
        static let reverbMix = "mochy_eq_reverb_mix"
        static let pitchShiftCents = "mochy_eq_pitch_cents"
        static let bassBoost = "mochy_eq_bass_boost"
        static let customPresets = "mochy_eq_custom_presets"
    }

    private init() {
        let defaults = UserDefaults.standard
        let savedPresets = Self.loadCustomPresets()
        self.customPresets = savedPresets

        let savedEnabled = defaults.bool(forKey: Keys.isEnabled)
        let savedBands = (defaults.array(forKey: Keys.bands) as? [NSNumber])?.map { $0.floatValue }
            ?? Array(repeating: Float(0), count: 10)
        let normalizedBands = savedBands.count == 10 ? savedBands : Array(repeating: Float(0), count: 10)

        let savedPresetId = defaults.string(forKey: Keys.currentPresetId) ?? "flat"
        let allPresets = EQPreset.builtInPresets + savedPresets
        let matchedPreset = allPresets.first(where: { $0.id == savedPresetId }) ?? EQPreset.builtInPresets[0]

        self.isEnabled = savedEnabled
        self.bands = normalizedBands
        self.currentPreset = matchedPreset
        self.reverbMix = defaults.float(forKey: Keys.reverbMix)
        self.pitchShiftCents = defaults.float(forKey: Keys.pitchShiftCents)
        self.bassBoostEnabled = defaults.bool(forKey: Keys.bassBoost)

        configureAudioGraph()
        applyEngineParameters()
    }

    var allPresets: [EQPreset] {
        EQPreset.builtInPresets + customPresets
    }

    // MARK: - Public Controls

    func selectPreset(_ preset: EQPreset) {
        currentPreset = preset
        bands = preset.gains
        if !isEnabled && preset.id != "flat" {
            isEnabled = true
        }
    }

    func updateBand(at index: Int, gain: Float) {
        guard bands.indices.contains(index) else { return }
        let clamped = max(-12.0, min(12.0, gain))
        bands[index] = clamped
        currentPreset = EQPreset(id: "custom_unsaved", name: "Custom", gains: bands, isBuiltIn: false)
    }

    func resetToFlat() {
        selectPreset(EQPreset.builtInPresets[0])
        reverbMix = 0
        pitchShiftCents = 0
        bassBoostEnabled = false
    }

    @discardableResult
    func saveCustomPreset(name: String) -> EQPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = EQPreset(
            id: "custom_\(UUID().uuidString)",
            name: trimmed.isEmpty ? "Custom Preset" : trimmed,
            gains: bands,
            isBuiltIn: false
        )
        customPresets.append(preset)
        persistCustomPresets()
        currentPreset = preset
        return preset
    }

    func deleteCustomPreset(_ preset: EQPreset) {
        guard !preset.isBuiltIn else { return }
        customPresets.removeAll { $0.id == preset.id }
        persistCustomPresets()
        if currentPreset.id == preset.id {
            currentPreset = EQPreset.builtInPresets[0]
        }
    }

    // MARK: - AVPlayer Real-Time AudioMix Tap

    func createAudioMix(for asset: AVAsset) async -> AVAudioMix? {
        await EQTapMixFactory.makeAudioMix(for: asset)
    }

    // MARK: - AVAudioEngine Graph Setup & Live DSP Application

    private func configureAudioGraph() {
        for (index, frequency) in EQPreset.bandFrequencies.enumerated() {
            let band = eqNode.bands[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }

        reverbNode.loadFactoryPreset(reverbPreset)
        reverbNode.wetDryMix = 0

        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(timePitchNode)
        engine.attach(reverbNode)

        engine.connect(playerNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: timePitchNode, format: nil)
        engine.connect(timePitchNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: nil)
    }

    func applyEngineParameters() {
        eqNode.bypass = !isEnabled
        var effectiveGains = Array(repeating: Float(0), count: 10)
        let bassOffsets: [Float] = [5.0, 4.0, 2.5]

        for (index, rawGain) in bands.enumerated() where index < eqNode.bands.count {
            var gain = rawGain
            if bassBoostEnabled && index <= 2 {
                gain = min(12.0, gain + bassOffsets[index])
            }
            effectiveGains[index] = gain
            eqNode.bands[index].gain = isEnabled ? gain : 0
        }

        reverbNode.wetDryMix = isEnabled ? max(0, min(100, reverbMix)) : 0
        timePitchNode.pitch = isEnabled ? max(-1200, min(1200, pitchShiftCents)) : 0

        EQDSPParameterStore.shared.update(isEnabled: isEnabled, gains: effectiveGains)
    }

    func startEngineIfNeeded() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    func playLocalFileWithEngine(_ fileURL: URL) throws {
        let audioFile = try AVAudioFile(forReading: fileURL)
        playerNode.stop()
        try startEngineIfNeeded()
        playerNode.scheduleFile(audioFile, at: nil, completionHandler: nil)
        playerNode.play()
    }

    func stopEnginePlayer() {
        playerNode.stop()
    }

    // MARK: - Custom Preset Persistence

    private func persistCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: Keys.customPresets)
        }
    }

    private static func loadCustomPresets() -> [EQPreset] {
        guard let data = UserDefaults.standard.data(forKey: Keys.customPresets),
              let decoded = try? JSONDecoder().decode([EQPreset].self, from: data) else {
            return []
        }
        return decoded
    }
}
