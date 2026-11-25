import SwiftUI
import UIKit

/// 10-band parametric equalizer screen with Bezier frequency response graph, AutoEQ presets, custom preset management, and Bass Boost.
struct EqualizerScreen: View {
    @ObservedObject private var eq = EqualizerService.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var showSavePresetAlert = false
    @State private var newPresetName = ""
    @State private var activeBandIndex: Int?

    init() {}

    var body: some View {
        ZStack {
            Color.mochyBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    masterControlCard
                    frequencyCurveCard
                    bandSlidersCard
                    bassBoostCard
                    presetsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .padding(.bottom, 90)
            }
        }
        .navigationTitle("10-Band Equalizer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reset") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(MochyTheme.snappySpring) {
                        eq.resetToFlat()
                    }
                    MochyToastCenter.shared.show("Equalizer reset to Flat")
                }
                .foregroundColor(settings.accentColor)
            }
        }
        .alert("Save Custom Preset", isPresented: $showSavePresetAlert) {
            TextField("Preset name", text: $newPresetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let saved = eq.saveCustomPreset(name: newPresetName)
                newPresetName = ""
                MochyToastCenter.shared.show("Saved preset: \(saved.name)")
            }
        } message: {
            Text("Save your current 10-band curve as a custom EQ preset.")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Master Control

    private var masterControlCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(eq.isEnabled ? settings.accentColor.opacity(0.2) : Color.mochySurfaceVariant)
                    .frame(width: 44, height: 44)
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(eq.isEnabled ? settings.accentColor : .mochySecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Parametric EQ")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.mochyOnSurface)
                Text(eq.isEnabled ? "Active • \(eq.currentPreset.name)" : "Bypassed")
                    .font(.system(size: 12))
                    .foregroundColor(.mochySecondary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(eq.isEnabled ? Color.mochyGreen : Color.mochySecondary)
                        .frame(width: 6, height: 6)
                    Text("Live on Stream + Local Audio (MTAudioProcessingTap)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(eq.isEnabled ? .mochyGreen : .mochySecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Toggle("", isOn: $eq.isEnabled)
                .labelsHidden()
                .tint(settings.accentColor)
        }
        .padding(14)
        .mochyCard(cornerRadius: 16, fillColor: .mochySurface)
    }

    // MARK: - Bezier Frequency Response Curve

    private var frequencyCurveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FREQUENCY RESPONSE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundColor(.mochySecondary)

                Spacer()

                if let idx = activeBandIndex, eq.bands.indices.contains(idx) {
                    Text("\(EQPreset.bandLabels[idx])Hz: \(String(format: "%+.1f dB", eq.bands[idx]))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(settings.accentColor)
                } else {
                    Text("-12 dB to +12 dB")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.mochySecondary.opacity(0.75))
                }
            }

            EQBezierCurveView(
                bands: effectiveDisplayBands,
                accentColor: eq.isEnabled ? settings.accentColor : .mochySecondary,
                isEnabled: eq.isEnabled
            )
            .frame(height: 140)
        }
        .padding(14)
        .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
    }

    private var effectiveDisplayBands: [Float] {
        var result = eq.bands
        if eq.bassBoostEnabled {
            let boost: [Float] = [5.0, 4.0, 2.5]
            for i in 0..<min(3, result.count) {
                result[i] = min(12.0, result[i] + boost[i])
            }
        }
        return result
    }

    // MARK: - 10 Vertical Band Sliders

    private var bandSlidersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("10-BAND GRAPHIC FADERS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .foregroundColor(.mochySecondary)

                Spacer()

                Button {
                    newPresetName = ""
                    showSavePresetAlert = true
                } label: {
                    Label("Save", systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(settings.accentColor)
                }
            }

            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    EQVerticalBandSlider(
                        label: EQPreset.bandLabels[index],
                        gain: Binding(
                            get: { eq.bands.indices.contains(index) ? eq.bands[index] : 0 },
                            set: { newValue in
                                eq.updateBand(at: index, gain: newValue)
                            }
                        ),
                        accentColor: eq.isEnabled ? settings.accentColor : .mochySecondary,
                        isActive: activeBandIndex == index,
                        onDragStateChanged: { dragging in
                            activeBandIndex = dragging ? index : nil
                        }
                    )
                }
            }
            .frame(height: 210)
            .opacity(eq.isEnabled ? 1.0 : 0.55)
        }
        .padding(14)
        .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
    }

    // MARK: - Bass Boost

    private var bassBoostCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(eq.bassBoostEnabled ? .mochyPeach : .mochySecondary)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Bass Boost")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.mochyOnSurface)
                Text("Adds +5dB / +4dB / +2.5dB sub-bass shelf (32–125Hz)")
                    .font(.system(size: 12))
                    .foregroundColor(.mochySecondary)
            }

            Spacer()

            Toggle("", isOn: $eq.bassBoostEnabled)
                .labelsHidden()
                .tint(.mochyPeach)
        }
        .padding(14)
        .mochyCard(cornerRadius: 16, fillColor: .mochySurface)
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRESETS & AUTOEQ")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundColor(.mochySecondary)

            if !eq.customPresets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Presets")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mochySecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(eq.customPresets) { preset in
                                presetChip(preset: preset, isCustom: true)
                            }
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(EQPreset.builtInPresets) { preset in
                    presetChip(preset: preset, isCustom: false)
                }
            }
        }
        .padding(14)
        .mochyCard(cornerRadius: 18, fillColor: .mochySurface)
    }

    private func presetChip(preset: EQPreset, isCustom: Bool) -> some View {
        let isSelected = eq.currentPreset.id == preset.id
        return HStack(spacing: 8) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(MochyTheme.snappySpring) {
                    eq.selectPreset(preset)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: preset.id == "headphone_autoeq" ? "headphones" : "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? .black : settings.accentColor)

                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .black : .mochyOnSurface)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isCustom {
                Button {
                    eq.deleteCustomPreset(preset)
                    MochyToastCenter.shared.show("Deleted \(preset.name)")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .black.opacity(0.7) : .mochySecondary)
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? settings.accentColor : Color.mochySurfaceVariant)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }
}

/// Smooth Bezier frequency response curve graph rendered via SwiftUI Canvas.
struct EQBezierCurveView: View {
    let bands: [Float]
    let accentColor: Color
    var isEnabled: Bool = true

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let midY = h / 2

            // Horizontal dB grid lines (+12, +6, 0, -6, -12)
            for db in [-12.0, -6.0, 0.0, 6.0, 12.0] {
                let y = midY - CGFloat(db / 12.0) * (h * 0.42)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: w, y: y))
                let isZero = db == 0.0
                context.stroke(
                    line,
                    with: .color(Color.white.opacity(isZero ? 0.2 : 0.07)),
                    style: StrokeStyle(lineWidth: isZero ? 1.0 : 0.6, dash: isZero ? [] : [4, 4])
                )
            }

            guard bands.count >= 2 else { return }
            let points: [CGPoint] = bands.enumerated().map { idx, gain in
                let x = CGFloat(idx) / CGFloat(bands.count - 1) * (w - 16) + 8
                let normalized = CGFloat(max(-12, min(12, gain)) / 12.0)
                let y = midY - normalized * (h * 0.42)
                return CGPoint(x: x, y: y)
            }

            var curve = Path()
            curve.move(to: points[0])
            for i in 0..<(points.count - 1) {
                let p0 = points[i]
                let p1 = points[i + 1]
                let midX = (p0.x + p1.x) / 2
                curve.addCurve(
                    to: p1,
                    control1: CGPoint(x: midX, y: p0.y),
                    control2: CGPoint(x: midX, y: p1.y)
                )
            }

            // Fill under curve relative to 0 dB line
            var fillPath = curve
            fillPath.addLine(to: CGPoint(x: points.last!.x, y: midY))
            fillPath.addLine(to: CGPoint(x: points.first!.x, y: midY))
            fillPath.closeSubpath()

            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [accentColor.opacity(isEnabled ? 0.35 : 0.12), accentColor.opacity(0.02)]),
                    startPoint: CGPoint(x: w / 2, y: 0),
                    endPoint: CGPoint(x: w / 2, y: h)
                )
            )

            context.stroke(
                curve,
                with: .color(accentColor),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            )

            // Draw nodes
            for pt in points {
                let dotRect = CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7)
                context.fill(Path(ellipseIn: dotRect), with: .color(accentColor))
            }
        }
    }
}

/// Interactive vertical EQ band fader (-12 dB to +12 dB).
private struct EQVerticalBandSlider: View {
    let label: String
    @Binding var gain: Float
    let accentColor: Color
    let isActive: Bool
    let onDragStateChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%+.0f", gain))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(isActive ? accentColor : .mochySecondary)
                .frame(height: 14)

            GeometryReader { proxy in
                let h = max(1, proxy.size.height)
                let normalized = CGFloat((gain + 12.0) / 24.0) // 0 at bottom, 1 at top
                let thumbY = (1.0 - normalized) * h
                let centerY = h / 2

                ZStack {
                    Capsule()
                        .fill(Color.mochySurfaceVariant)
                        .frame(width: 5)

                    // Active fill from 0 dB center to thumb
                    let fillTop = min(thumbY, centerY)
                    let fillHeight = max(2, abs(thumbY - centerY))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accentColor)
                        .frame(width: 5, height: fillHeight)
                        .position(x: proxy.size.width / 2, y: fillTop + fillHeight / 2)

                    Circle()
                        .fill(isActive ? Color.white : accentColor)
                        .frame(width: isActive ? 18 : 14, height: isActive ? 18 : 14)
                        .shadow(color: accentColor.opacity(0.45), radius: isActive ? 6 : 2)
                        .position(x: proxy.size.width / 2, y: max(8, min(h - 8, thumbY)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            onDragStateChanged(true)
                            let ratio = 1.0 - Float(max(0, min(1, gesture.location.y / h)))
                            let newGain = (ratio * 24.0) - 12.0
                            gain = (newGain * 2).rounded() / 2
                        }
                        .onEnded { _ in
                            onDragStateChanged(false)
                        }
                )
            }

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.mochySecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
