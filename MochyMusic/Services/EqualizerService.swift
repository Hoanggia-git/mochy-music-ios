import Foundation
import AVFoundation

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

/// AVAudioEngine-based 10-band parametric equalizer, reverb, pitch shift, and bass boost service.
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
        for (index, rawGain) in bands.enumerated() where index < eqNode.bands.count {
            var gain = rawGain
            if bassBoostEnabled && index <= 2 {
                let boost: [Float] = [5.0, 4.0, 2.5]
                gain = min(12.0, gain + boost[index])
            }
            eqNode.bands[index].gain = isEnabled ? gain : 0
        }

        reverbNode.wetDryMix = isEnabled ? max(0, min(100, reverbMix)) : 0
        timePitchNode.pitch = isEnabled ? max(-1200, min(1200, pitchShiftCents)) : 0
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
