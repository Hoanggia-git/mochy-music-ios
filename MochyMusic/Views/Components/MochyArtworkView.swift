import SwiftUI
import UIKit

/// Extracts dominant/ambient accent colors from track artwork URLs with an in-memory cache.
@MainActor
final class ArtworkColorExtractor: ObservableObject {
    static let shared = ArtworkColorExtractor()

    @Published private(set) var cachedColors: [String: Color] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    func color(for urlString: String?, fallback: Color = .mochyPrimary) -> Color {
        guard let urlString, !urlString.isEmpty else { return fallback }
        return cachedColors[urlString] ?? fallback
    }

    func extractIfNeeded(from urlString: String?) {
        guard let urlString,
              !urlString.isEmpty,
              cachedColors[urlString] == nil,
              !inFlight.contains(urlString),
              let url = URL(string: urlString) else {
            return
        }

        inFlight.insert(urlString)
        Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  let extracted = Self.dominantColor(from: image) else {
                await MainActor.run {
                    self.inFlight.remove(urlString)
                }
                return
            }

            await MainActor.run {
                self.cachedColors[urlString] = extracted
                self.inFlight.remove(urlString)
            }
        }
    }

    nonisolated private static func dominantColor(from image: UIImage) -> Color? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 12
        let height = 12
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rTotal: Double = 0
        var gTotal: Double = 0
        var bTotal: Double = 0
        var weightTotal: Double = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = Double(rawData[offset]) / 255.0
                let g = Double(rawData[offset + 1]) / 255.0
                let b = Double(rawData[offset + 2]) / 255.0
                let maxC = max(r, max(g, b))
                let minC = min(r, min(g, b))
                let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                let brightness = maxC

                // Prefer vibrant mid-to-bright tones over pure black/white
                let weight = (0.25 + saturation * 1.6) * (brightness > 0.08 ? 1.0 : 0.2)
                rTotal += r * weight
                gTotal += g * weight
                bTotal += b * weight
                weightTotal += weight
            }
        }

        guard weightTotal > 0 else { return nil }
        var r = rTotal / weightTotal
        var g = gTotal / weightTotal
        var b = bTotal / weightTotal

        // Lift very dark averages slightly so AMOLED gradients stay visible
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        if lum < 0.22 {
            let boost = 0.22 / max(0.05, lum)
            r = min(0.85, r * boost)
            g = min(0.85, g * boost)
            b = min(0.85, b * boost)
        }

        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

/// Reusable AMOLED-styled artwork image view with smooth placeholder and optional circular or rounded shape.
struct MochyArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 12
    var isCircular: Bool = false
    var placeholderIcon: String = "music.note"

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
        .clipShape(clipShape)
    }

    private var clipShape: AnyShape {
        if isCircular {
            return AnyShape(Circle())
        }
        return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Color.mochySurfaceVariant
            Image(systemName: placeholderIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.mochySecondary.opacity(0.6))
        }
    }
}
