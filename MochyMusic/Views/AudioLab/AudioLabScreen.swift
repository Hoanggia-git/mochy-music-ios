import SwiftUI
import AVFoundation
import UIKit

/// Mochy Music's AudioLab DSP hub: live visualizer, 8D Spatial panner, Reverb Studio, Pitch/Speed, Crossmix & 10-band EQ shortcut.
struct AudioLabScreen: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var eq = EqualizerService.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var spatialAutoRotate = false
    @State private var spatialSpeed: Double = 0.6
    @State private var spatialAngle: Double = 0.0
    @State private var manualPanX: Double = 0.0
    @State private var manualPanY: Double = -0.35

    private let reverbPresets: [(label: String, preset: AVAudioUnitReverbPreset)] = [
        ("Small Room", .smallRoom),
        ("Medium Hall", .mediumHall),
        ("Large Hall", .largeHall),
        ("Cathedral", .cathedral),
        ("Plate", .plate)
    ]

    init() {}

    var body: some View {
        ZStack {
            Color.mochyBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    visualizerCard
                    equalizerLinkCard
                    spatial8DCard
                    reverbStudioCard
                    pitchAndSpeedCard
                    crossmixQuickCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.bottom, 90)
            }
        }
        .navigationTitle("AudioLab")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    // MARK: - Live Spectrum Visualizer

    private var visualizerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIVE SPECTRUM")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.1)
                        .foregroundColor(.mochySecondary)
                    Text(player.currentTrack?.title ?? "Ready for AudioLab DSP")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.mochyOnSurface)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(player.isPlaying ? Color.mochyGreen : Color.mochySecondary)
                        .frame(width: 7, height: 7)
                    Text(player.isPlaying ? "LIVE" : "IDLE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(player.isPlaying ? .mochyGreen : .mochySecondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.mochySurfaceVariant)
                .clipShape(Capsule())
            }

            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !player.isPlaying)) { timeline in
                let t = player.isPlaying ? timeline.date.timeIntervalSinceReferenceDate : 0
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<24, id: \.self) { idx in
                        let bandIdx = min(9, idx * 10 / 24)
                        let eqGainBoost = eq.isEnabled ? Double(eq.bands[bandIdx] + 12) / 24.0 : 0.5
                        let bassExtra = (eq.bassBoostEnabled && idx < 6) ? 0.18 : 0.0
                        let osc = player.isPlaying
                            ? (0.28 + 0.55 * abs(sin(t * 4.2 + Double(idx) * 0.45)) * abs(cos(t * 2.1 - Double(idx) * 0.2)))
                            : 0.14
                        let heightFactor = min(1.0, max(0.1, osc * (0.6 + eqGainBoost * 0.6) + bassExtra))

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [settings.accentColor, settings.accentColor.opacity(0.35)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 68 * heightFactor)
                    }
                }
                .frame(height: 70, alignment: .bottom)
            }
        }
        .padding(16)
        .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
    }

    // MARK: - Equalizer Hub Link

    private var equalizerLinkCard: some View {
        NavigationLink {
            EqualizerScreen()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(settings.accentColor.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "slider.vertical.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(settings.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("10-Band Equalizer")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.mochyOnSurface)
                        Text(eq.isEnabled ? "Active • \(eq.currentPreset.name)" : "Tap to configure EQ & AutoEQ presets")
                            .font(.system(size: 12))
                            .foregroundColor(.mochySecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochySecondary)
                }

                EQBezierCurveView(
                    bands: eq.bands,
                    accentColor: eq.isEnabled ? settings.accentColor : .mochySecondary,
                    isEnabled: eq.isEnabled
                )
                .frame(height: 62)
            }
            .padding(14)
            .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 8D Audio Spatial Panner

    private var spatial8DCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("8D Spatial Panner", systemImage: "headphones.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.mochyOnSurface)

                Spacer()

                Toggle("Auto Orbit", isOn: $spatialAutoRotate)
                    .labelsHidden()
                    .tint(settings.accentColor)
            }

            HStack(spacing: 16) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !spatialAutoRotate)) { timeline in
                    let angle = spatialAutoRotate
                        ? timeline.date.timeIntervalSinceReferenceDate * spatialSpeed * 2.0
                        : atan2(manualPanY, manualPanX)
                    let orbX = spatialAutoRotate ? cos(angle) * 0.72 : manualPanX
                    let orbY = spatialAutoRotate ? sin(angle) * 0.72 : manualPanY

                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            .frame(width: 112, height: 112)
                        Circle()
                            .stroke(settings.accentColor.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .frame(width: 74, height: 74)

                        // Listener center
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.mochySecondary)

                        // Sound source orb
                        Circle()
                            .fill(settings.accentColor)
                            .frame(width: 16, height: 16)
                            .shadow(color: settings.accentColor.opacity(0.6), radius: 8)
                            .offset(x: orbX * 48, y: orbY * 48)
                    }
                    .frame(width: 116, height: 116)
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                spatialAutoRotate = false
                                let dx = (value.location.x - 58) / 48
                                let dy = (value.location.y - 58) / 48
                                let dist = sqrt(dx * dx + dy * dy)
                                if dist > 1 {
                                    manualPanX = dx / dist
                                    manualPanY = dy / dist
                                } else {
                                    manualPanX = dx
                                    manualPanY = dy
                                }
                            }
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(spatialAutoRotate ? "8D Surround Orbit Active" : "Drag orb to position soundstage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochyOnSurface)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Orbit Speed")
                                .font(.system(size: 12))
                                .foregroundColor(.mochySecondary)
                            Spacer()
                            Text(String(format: "%.1fx", spatialSpeed))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(settings.accentColor)
                        }
                        Slider(value: $spatialSpeed, in: 0.2...2.0)
                            .tint(settings.accentColor)
                    }
                }
            }
        }
        .padding(14)
        .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
    }

    // MARK: - Reverb Studio

    private var reverbStudioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Reverb Studio", systemImage: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.mochyOnSurface)

                Spacer()

                Text("\(Int(eq.reverbMix))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(settings.accentColor)
            }

            Slider(
                value: Binding(
                    get: { Double(eq.reverbMix) },
                    set: {
                        eq.reverbMix = Float($0)
                        if $0 > 0 && !eq.isEnabled { eq.isEnabled = true }
                    }
                ),
                in: 0...100
            )
            .tint(settings.accentColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(reverbPresets, id: \.label) { item in
                        let selected = eq.reverbPreset == item.preset
                        Button {
                            eq.reverbPreset = item.preset
                        } label: {
                            Text(item.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selected ? .black : .mochyOnSurface)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selected ? settings.accentColor : Color.mochySurfaceVariant)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
    }

    // MARK: - Pitch Shift & Speed

    private var pitchAndSpeedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Pitch & Tempo", systemImage: "tuningfork")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.mochyOnSurface)

                Spacer()

                Button("Reset") {
                    eq.pitchShiftCents = 0
                    player.setPlaybackSpeed(1.0)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(settings.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Pitch Shift")
                        .font(.system(size: 13))
                        .foregroundColor(.mochySecondary)
                    Spacer()
                    let semitones = eq.pitchShiftCents / 100.0
                    Text(String(format: "%+.1f st", semitones))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(settings.accentColor)
                }
                Slider(
                    value: Binding(
                        get: { Double(eq.pitchShiftCents) },
                        set: {
                            eq.pitchShiftCents = Float(($0 / 50.0).rounded() * 50.0)
                            if abs($0) > 1 && !eq.isEnabled { eq.isEnabled = true }
                        }
                    ),
                    in: -1200...1200
                )
                .tint(settings.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Playback Speed")
                        .font(.system(size: 13))
                        .foregroundColor(.mochySecondary)
                    Spacer()
                    Text(String(format: "%.2fx", player.playbackSpeed))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(settings.accentColor)
                }
                Slider(
                    value: Binding(
                        get: { Double(player.playbackSpeed) },
                        set: { player.setPlaybackSpeed(Float($0)) }
                    ),
                    in: 0.5...2.0,
                    step: 0.05
                )
                .tint(settings.accentColor)
            }
        }
        .padding(14)
        .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
    }

    // MARK: - Crossmix & Crossfade Quick Card

    private var crossmixQuickCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Crossmix & Crossfade", systemImage: "shuffle.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.mochyOnSurface)

                Spacer()

                Toggle("", isOn: $settings.crossfadeEnabled)
                    .labelsHidden()
                    .tint(settings.accentColor)
            }

            if settings.crossfadeEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Crossfade Duration")
                            .font(.system(size: 13))
                            .foregroundColor(.mochySecondary)
                        Spacer()
                        Text("\(Int(settings.crossfadeDuration))s")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(settings.accentColor)
                    }
                    Slider(value: $settings.crossfadeDuration, in: 1...12, step: 1)
                        .tint(settings.accentColor)
                }
            }

            Picker("Crossmix Mode", selection: $settings.crossmixModeRaw) {
                ForEach(CrossmixMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Transport Transition Effect")
                    .font(.system(size: 13))
                    .foregroundColor(.mochySecondary)
                Spacer()
                Picker("Effect", selection: $settings.transportEffectRaw) {
                    ForEach(TransportEffect.allCases) { effect in
                        Text(effect.displayName).tag(effect.rawValue)
                    }
                }
                .tint(settings.accentColor)
            }
        }
        .padding(14)
        .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
    }
}
