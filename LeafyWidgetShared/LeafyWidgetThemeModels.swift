import Foundation

nonisolated enum LeafyThemeColorPreferenceRaw: String, CaseIterable, Sendable {
    case green
    case tiffanyBlue
    case candyPink
    case custom

    static let defaultCustomColorHex = "#9DC183"

    static func storedValue(_ rawValue: String?) -> LeafyThemeColorPreferenceRaw {
        switch rawValue {
        case green.rawValue:
            return .green
        case tiffanyBlue.rawValue:
            return .tiffanyBlue
        case candyPink.rawValue:
            return .candyPink
        case custom.rawValue:
            return .custom
        case .some:
            return .custom
        default:
            return .green
        }
    }
}

nonisolated enum LeafyAppIconAppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case green
    case tiffanyBlue
    case candyPink

    static let storageKey = "appIconAppearancePreference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green:
            return "鼠尾草绿"
        case .tiffanyBlue:
            return "蒂芙尼蓝"
        case .candyPink:
            return "糖果莓粉"
        }
    }

    var themePreferenceRaw: LeafyThemeColorPreferenceRaw {
        switch self {
        case .green:
            return .green
        case .tiffanyBlue:
            return .tiffanyBlue
        case .candyPink:
            return .candyPink
        }
    }

    static func storedValue(_ rawValue: String?) -> LeafyAppIconAppearancePreference {
        switch rawValue {
        case green.rawValue:
            return .green
        case tiffanyBlue.rawValue:
            return .tiffanyBlue
        case candyPink.rawValue:
            return .candyPink
        case "followTheme":
            return .green
        default:
            return .green
        }
    }
}

nonisolated struct LeafyWidgetThemeSnapshot: Codable, Hashable, Sendable {
    var preferenceRaw: String
    var customColorHex: String

    static let fallback = LeafyWidgetThemeSnapshot(
        preferenceRaw: LeafyThemeColorPreferenceRaw.green.rawValue,
        customColorHex: LeafyThemeColorPreferenceRaw.defaultCustomColorHex
    )

    var preference: LeafyThemeColorPreferenceRaw {
        LeafyThemeColorPreferenceRaw.storedValue(preferenceRaw)
    }
}

nonisolated enum LeafyWidgetThemePalette: Hashable, Sendable {
    struct ColorComponents: Codable, Hashable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        nonisolated init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        nonisolated init(_ red: Double, _ green: Double, _ blue: Double) {
            self.init(red: red, green: green, blue: blue)
        }

        var normalizedRed: Double { red / 255 }
        var normalizedGreen: Double { green / 255 }
        var normalizedBlue: Double { blue / 255 }
    }

    static func baseColor(for snapshot: LeafyWidgetThemeSnapshot) -> ColorComponents {
        switch snapshot.preference {
        case .green:
            return color(ColorComponents(157, 193, 131))
        case .tiffanyBlue:
            return color(ColorComponents(129, 216, 208))
        case .candyPink:
            return color(ColorComponents(251, 96, 149))
        case .custom:
            return color(rgbComponents(fromHex: snapshot.customColorHex) ?? ColorComponents(157, 193, 131))
        }
    }

    static func emphasisColor(for snapshot: LeafyWidgetThemeSnapshot) -> ColorComponents {
        switch snapshot.preference {
        case .green:
            return color(ColorComponents(95, 127, 78))
        case .tiffanyBlue:
            return color(ColorComponents(43, 127, 122))
        case .candyPink:
            return color(ColorComponents(184, 50, 104))
        case .custom:
            let base = rgbComponents(fromHex: snapshot.customColorHex) ?? ColorComponents(157, 193, 131)
            return color(mix(base, with: ColorComponents(0, 0, 0), amount: 0.42))
        }
    }

    static func softColor(for snapshot: LeafyWidgetThemeSnapshot) -> ColorComponents {
        switch snapshot.preference {
        case .green:
            return color(ColorComponents(236, 244, 231))
        case .tiffanyBlue:
            return color(ColorComponents(232, 249, 247))
        case .candyPink:
            return color(ColorComponents(255, 237, 244))
        case .custom:
            let base = rgbComponents(fromHex: snapshot.customColorHex) ?? ColorComponents(157, 193, 131)
            return color(mix(base, with: ColorComponents(255, 255, 255), amount: 0.84))
        }
    }

    static func courseAccentColors(for snapshot: LeafyWidgetThemeSnapshot) -> [ColorComponents] {
        let base = rgb(for: snapshot)
        return [0.42, 0.36, 0.30, 0.24].map { whiteRatio in
            color(mix(base, with: ColorComponents(255, 255, 255), amount: whiteRatio))
        }
    }

    static func rgbComponents(fromHex hex: String?) -> ColorComponents? {
        guard var raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let value = Int(raw, radix: 16) else {
            return nil
        }

        return ColorComponents(
            red: Double((value >> 16) & 0xFF),
            green: Double((value >> 8) & 0xFF),
            blue: Double(value & 0xFF)
        )
    }

    private static func rgb(for snapshot: LeafyWidgetThemeSnapshot) -> ColorComponents {
        baseColor(for: snapshot)
    }

    private static func color(_ rgb: ColorComponents) -> ColorComponents {
        ColorComponents(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func mix(_ base: ColorComponents, with target: ColorComponents, amount: Double) -> ColorComponents {
        ColorComponents(
            red: base.red + (target.red - base.red) * amount,
            green: base.green + (target.green - base.green) * amount,
            blue: base.blue + (target.blue - base.blue) * amount
        )
    }

}

nonisolated enum LeafyWidgetThemeStore {
    static func load() -> LeafyWidgetThemeSnapshot {
        if let data = appGroupDefaults.data(forKey: LeafyWidgetConstants.themeSnapshotKey),
           let snapshot = try? JSONDecoder().decode(LeafyWidgetThemeSnapshot.self, from: data) {
            return snapshot
        }

        return LeafyWidgetThemeSnapshot(
            preferenceRaw: appGroupDefaults.string(forKey: LeafyWidgetConstants.themePreferenceKey) ?? LeafyWidgetThemeSnapshot.fallback.preferenceRaw,
            customColorHex: appGroupDefaults.string(forKey: LeafyWidgetConstants.themeCustomColorHexKey) ?? LeafyWidgetThemeSnapshot.fallback.customColorHex
        )
    }

    static func save(preferenceRaw: String, customHex: String) {
        let snapshot = LeafyWidgetThemeSnapshot(preferenceRaw: preferenceRaw, customColorHex: customHex)
        appGroupDefaults.set(snapshot.preferenceRaw, forKey: LeafyWidgetConstants.themePreferenceKey)
        appGroupDefaults.set(snapshot.customColorHex, forKey: LeafyWidgetConstants.themeCustomColorHexKey)

        if let data = try? JSONEncoder().encode(snapshot) {
            appGroupDefaults.set(data, forKey: LeafyWidgetConstants.themeSnapshotKey)
        }
    }

    private static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: LeafyWidgetConstants.appGroupIdentifier) ?? .standard
    }
}
