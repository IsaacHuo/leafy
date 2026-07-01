import Foundation
import ImageIO
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

enum TimetableBackgroundDisplayMode: String, CaseIterable, Identifiable {
    case fill
    case fit

    var id: String { rawValue }

    func title(language: AppLanguagePreference) -> String {
        switch self {
        case .fill:
            return L10n.text("铺满裁切", language: language)
        case .fit:
            return L10n.text("完整显示", language: language)
        }
    }

    var contentMode: ContentMode {
        switch self {
        case .fill:
            return .fill
        case .fit:
            return .fit
        }
    }
}

struct TimetableBackgroundPalette: Equatable {
    nonisolated static let fallbackLightHexes = [
        "#DAE7D0", "#D4E4C9", "#CEE0C1", "#C8DCBA", "#C2D8B2", "#BCD5AB", "#B6D1A3"
    ]
    nonisolated static let fallbackDarkHexes = [
        "#31452C", "#394E32", "#2C3D29", "#43593A", "#354A30", "#48603F", "#3B5235"
    ]

    let lightHexes: [String]
    let darkHexes: [String]

    nonisolated static let fallback = TimetableBackgroundPalette(
        lightHexes: fallbackLightHexes,
        darkHexes: fallbackDarkHexes
    )
}

struct TimetableBackgroundImportResult {
    let filename: String
    let palette: TimetableBackgroundPalette
}

enum TimetableBackgroundStore {
    static let isEnabledKey = "timetableBackground.isEnabled"
    static let filenameKey = "timetableBackground.filename"
    static let displayModeKey = "timetableBackground.displayMode"
    static let imageOpacityKey = "timetableBackground.imageOpacity"
    static let blurRadiusKey = "timetableBackground.blurRadius"
    static let overlayOpacityKey = "timetableBackground.overlayOpacity"
    static let courseCardOpacityKey = "timetableBackground.courseCardOpacity"
    static let lightPaletteKey = "timetableBackground.lightPalette"
    static let darkPaletteKey = "timetableBackground.darkPalette"

    static let defaultImageOpacity = 0.32
    static let defaultBlurRadius = 0.0
    static let defaultOverlayOpacity = 0.10
    static let defaultCourseCardOpacity = 0.50

    static func importImageData(_ data: Data, replacing oldFilename: String?) async throws -> TimetableBackgroundImportResult {
        try await Task.detached(priority: .userInitiated) {
            let processed = try TimetableBackgroundImageProcessor.process(data)
            let filename = "background-\(UUID().uuidString.lowercased()).jpg"
            let url = directoryURL.appendingPathComponent(filename)
            let fileManager = FileManager.default

            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try processed.jpegData.write(to: url, options: [.atomic])

            if let oldFilename, !oldFilename.isEmpty, oldFilename != filename {
                try? removeBackgroundFile(named: oldFilename)
            }

            return TimetableBackgroundImportResult(
                filename: filename,
                palette: processed.palette
            )
        }.value
    }

    nonisolated static func image(filename: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            imageSynchronously(filename: filename)
        }.value
    }

    nonisolated private static func imageSynchronously(filename: String) -> UIImage? {
        guard !filename.isEmpty else { return nil }
        let url = directoryURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let imageOptions = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, imageOptions) else {
            return nil
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return UIImage(cgImage: cgImage, size: .zero)
        #endif
    }

    static func removeBackground(filename: String) throws {
        guard !filename.isEmpty else { return }
        try removeBackgroundFile(named: filename)
    }

    static func serialize(hexes: [String]) -> String {
        hexes.joined(separator: ",")
    }

    static func colors(from serializedHexes: String) -> [Color] {
        serializedHexes
            .split(separator: ",")
            .map { String($0) }
            .compactMap { TimetableBackgroundRGB(hex: $0) }
            .map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    static func notifySettingsDidChange() {
        NotificationCenter.default.post(name: .timetableBackgroundSettingsDidChange, object: nil)
    }

    nonisolated private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TimetableBackground", isDirectory: true)
    }

    nonisolated private static func removeBackgroundFile(named filename: String) throws {
        let url = directoryURL.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

}

extension Notification.Name {
    static let timetableBackgroundSettingsDidChange = Notification.Name("timetableBackgroundSettingsDidChange")
}

enum TimetableBackgroundImageProcessor {
    nonisolated private static let maxPixelDimension: CGFloat = 1800
    nonisolated private static let maxBytes = 1_200_000

    nonisolated static func process(_ data: Data) throws -> (jpegData: Data, palette: TimetableBackgroundPalette) {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw TimetableBackgroundImageError.invalidImage
        }

        let thumbnail = try makeThumbnail(from: imageSource)
        let jpegData = try encodeJPEG(image: thumbnail)
        let palette = TimetableBackgroundPaletteExtractor.palette(from: thumbnail)
        return (jpegData, palette)
    }

    nonisolated private static func makeThumbnail(from source: CGImageSource) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelDimension),
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw TimetableBackgroundImageError.invalidImage
        }
        return image
    }

    nonisolated private static func encodeJPEG(image: CGImage) throws -> Data {
        let qualities: [CGFloat] = [0.84, 0.76, 0.68, 0.58, 0.48, 0.38]
        var candidate = image
        var longestSide = CGFloat(max(image.width, image.height))
        var smallestData: Data?

        for _ in 0..<4 {
            for quality in qualities {
                guard let data = jpegData(from: candidate, quality: quality) else { continue }
                if smallestData == nil || data.count < (smallestData?.count ?? Int.max) {
                    smallestData = data
                }
                if data.count <= maxBytes {
                    return data
                }
            }

            longestSide *= 0.82
            guard let resized = resizedImage(candidate, maxPixelDimension: longestSide) else {
                break
            }
            candidate = resized
        }

        guard let smallestData else {
            throw TimetableBackgroundImageError.invalidImage
        }
        return smallestData
    }

    nonisolated private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    nonisolated private static func resizedImage(_ image: CGImage, maxPixelDimension: CGFloat) -> CGImage? {
        let longestSide = CGFloat(max(image.width, image.height))
        guard longestSide > maxPixelDimension else { return image }

        let ratio = maxPixelDimension / longestSide
        let width = max(1, Int((CGFloat(image.width) * ratio).rounded()))
        let height = max(1, Int((CGFloat(image.height) * ratio).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

enum TimetableBackgroundImageError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return L10n.text("无法读取这张图片，请换一张底图。")
        }
    }
}

struct TimetableBackgroundRGB: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    nonisolated init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    nonisolated init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let value = Int(raw, radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255
        )
    }

    nonisolated var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    nonisolated var hsb: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return (hue, saturation, brightness)
    }
}

enum TimetableBackgroundPaletteExtractor {
    nonisolated static func palette(from image: CGImage) -> TimetableBackgroundPalette {
        let samples = sampleColors(from: image)
        return palette(from: samples)
    }

    nonisolated static func palette(from samples: [TimetableBackgroundRGB]) -> TimetableBackgroundPalette {
        let candidates = dominantColors(from: samples)
        guard !candidates.isEmpty else {
            return .fallback
        }

        let offsets: [CGFloat] = [0, 0.055, -0.055, 0.11, -0.11, 0.165, -0.165]
        let lightBrightness: [CGFloat] = [0.92, 0.88, 0.94, 0.89, 0.93, 0.87, 0.91]
        let darkBrightness: [CGFloat] = [0.30, 0.34, 0.27, 0.32, 0.36, 0.29, 0.33]

        let lightHexes = (0..<7).map { index in
            let source = candidates[index % candidates.count].hsb
            let hueOffset = candidates.count < 4 ? offsets[index] : offsets[index] * 0.45
            return colorHex(
                hue: source.hue + hueOffset,
                saturation: min(max(source.saturation * 0.34 + 0.10, 0.12), 0.30),
                brightness: lightBrightness[index]
            )
        }

        let darkHexes = (0..<7).map { index in
            let source = candidates[index % candidates.count].hsb
            let hueOffset = candidates.count < 4 ? offsets[index] * 0.72 : offsets[index] * 0.32
            return colorHex(
                hue: source.hue + hueOffset,
                saturation: min(max(source.saturation * 0.32 + 0.16, 0.18), 0.38),
                brightness: darkBrightness[index]
            )
        }

        return TimetableBackgroundPalette(lightHexes: lightHexes, darkHexes: darkHexes)
    }

    nonisolated private static func sampleColors(from image: CGImage) -> [TimetableBackgroundRGB] {
        let sampleSize = 72
        let bytesPerPixel = 4
        let bytesPerRow = sampleSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: sampleSize,
                height: sampleSize,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))
            return true
        }

        guard didDraw else { return [] }

        var colors: [TimetableBackgroundRGB] = []
        colors.reserveCapacity(sampleSize * sampleSize)
        var index = 0
        while index < pixels.count {
            colors.append(TimetableBackgroundRGB(
                red: CGFloat(pixels[index]) / 255,
                green: CGFloat(pixels[index + 1]) / 255,
                blue: CGFloat(pixels[index + 2]) / 255
            ))
            index += bytesPerPixel
        }
        return colors
    }

    nonisolated private static func dominantColors(from samples: [TimetableBackgroundRGB]) -> [TimetableBackgroundRGB] {
        struct Bucket {
            var count: CGFloat = 0
            var weightedRed: CGFloat = 0
            var weightedGreen: CGFloat = 0
            var weightedBlue: CGFloat = 0
            var score: CGFloat = 0
        }

        var buckets: [Int: Bucket] = [:]

        for sample in samples {
            let hsb = sample.hsb
            guard hsb.brightness > 0.14,
                  hsb.saturation > 0.10
            else {
                continue
            }
            if hsb.brightness > 0.96, hsb.saturation < 0.22 {
                continue
            }

            let hueBin = min(Int((hsb.hue * 24).rounded(.down)), 23)
            let saturationBin = min(Int((hsb.saturation * 4).rounded(.down)), 3)
            let brightnessBin = min(Int((hsb.brightness * 4).rounded(.down)), 3)
            let key = hueBin * 100 + saturationBin * 10 + brightnessBin
            let centeredBrightness = 1 - min(abs(hsb.brightness - 0.58) * 1.35, 0.75)
            let weight = max(0.2, hsb.saturation) * centeredBrightness

            var bucket = buckets[key] ?? Bucket()
            bucket.count += 1
            bucket.weightedRed += sample.red * weight
            bucket.weightedGreen += sample.green * weight
            bucket.weightedBlue += sample.blue * weight
            bucket.score += weight
            buckets[key] = bucket
        }

        let ranked = buckets.values
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                Double(lhs.score) * log(Double(lhs.count + 1)) > Double(rhs.score) * log(Double(rhs.count + 1))
            }
            .map {
                TimetableBackgroundRGB(
                    red: $0.weightedRed / $0.score,
                    green: $0.weightedGreen / $0.score,
                    blue: $0.weightedBlue / $0.score
                )
            }

        var selected: [TimetableBackgroundRGB] = []
        for color in ranked {
            let hue = color.hsb.hue
            let isDistinct = selected.allSatisfy { hueDistance(hue, $0.hsb.hue) > 0.045 }
            if isDistinct {
                selected.append(color)
            }
            if selected.count == 4 {
                break
            }
        }

        return selected
    }

    nonisolated private static func colorHex(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> String {
        let normalizedHue = hue - floor(hue)
        let color = UIColor(
            hue: normalizedHue,
            saturation: min(max(saturation, 0), 1),
            brightness: min(max(brightness, 0), 1),
            alpha: 1
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return TimetableBackgroundRGB(red: red, green: green, blue: blue).hexString
    }

    nonisolated private static func hueDistance(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let distance = abs(first - second)
        return min(distance, 1 - distance)
    }
}
