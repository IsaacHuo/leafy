import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AppDisplaySizePreference: String, CaseIterable, Identifiable {
    case compact = "compact"
    case standard = "standard"
    case comfortable = "comfortable"
    case spacious = "spacious"

    var id: String { rawValue }

    func title(language: AppLanguagePreference) -> String {
        switch self {
        case .compact:
            return L10n.text("紧凑", language: language)
        case .standard:
            return L10n.text("标准", language: language)
        case .comfortable:
            return L10n.text("舒适", language: language)
        case .spacious:
            return L10n.text("宽松", language: language)
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .compact:
            return .xSmall
        case .standard:
            return .small
        case .comfortable:
            return .medium
        case .spacious:
            return .large
        }
    }

    var fontScale: CGFloat {
        switch self {
        case .compact:
            return 0.88
        case .standard:
            return 0.94
        case .comfortable:
            return 1.0
        case .spacious:
            return 1.08
        }
    }

    var controlScale: CGFloat {
        switch self {
        case .compact:
            return 0.88
        case .standard:
            return 0.94
        case .comfortable:
            return 1.0
        case .spacious:
            return 1.06
        }
    }

    var listRowMinHeight: CGFloat {
        switch self {
        case .compact:
            return 40
        case .standard:
            return 42
        case .comfortable:
            return 44
        case .spacious:
            return 48
        }
    }
}

typealias AppFontSizePreference = AppDisplaySizePreference

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    nonisolated static let storageKey = "appAppearancePreference"
    nonisolated private static let legacyForcesDarkModeKey = "appForcesDarkMode"

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    func title(language: AppLanguagePreference) -> String {
        switch self {
        case .system:
            return L10n.text("跟随系统", language: language)
        case .light:
            return L10n.text("浅色", language: language)
        case .dark:
            return L10n.text("深色", language: language)
        }
    }

    func detail(language: AppLanguagePreference) -> String {
        switch self {
        case .system:
            return L10n.text("使用系统外观设置", language: language)
        case .light:
            return L10n.text("始终使用浅色外观", language: language)
        case .dark:
            return L10n.text("始终使用深色外观", language: language)
        }
    }

    static func storedValue(_ rawValue: String?) -> AppAppearancePreference {
        switch rawValue {
        case system.rawValue:
            return .system
        case light.rawValue:
            return .light
        case dark.rawValue:
            return .dark
        default:
            return .light
        }
    }

    nonisolated static func migrateStoredAppearanceIfNeeded(userDefaults: UserDefaults = .standard) {
        guard userDefaults.string(forKey: storageKey) == nil else { return }
        let migratedValue = userDefaults.bool(forKey: legacyForcesDarkModeKey) ? dark.rawValue : light.rawValue
        userDefaults.set(migratedValue, forKey: storageKey)
    }
}

enum AppThemeColorPreference: String, CaseIterable, Identifiable {
    case green = "green"
    case tiffanyBlue = "tiffanyBlue"
    case candyPink = "candyPink"
    case custom = "custom"

    nonisolated static let storageKey = "appThemeColorPreference"
    nonisolated static let customColorHexKey = "appThemeCustomColorHex"
    nonisolated static let defaultCustomColorHex = "#9DC183"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green: return "鼠尾草绿"
        case .tiffanyBlue: return "蒂芙尼蓝"
        case .candyPink: return "糖果莓粉"
        case .custom: return "自定义"
        }
    }

    func title(language: AppLanguagePreference) -> String {
        L10n.text(title, language: language)
    }

    nonisolated static func storedValue(_ rawValue: String?) -> AppThemeColorPreference {
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

    var swatchColor: Color {
        AppTheme.accent(for: self)
    }

    nonisolated static func migrateStoredThemeIfNeeded(userDefaults: UserDefaults = .standard) {
        guard let rawValue = userDefaults.string(forKey: storageKey),
              ![green.rawValue, tiffanyBlue.rawValue, candyPink.rawValue, custom.rawValue].contains(rawValue)
        else {
            return
        }

        if userDefaults.string(forKey: customColorHexKey) == nil {
            userDefaults.set(legacyColorHex(for: rawValue), forKey: customColorHexKey)
        }
        userDefaults.set(custom.rawValue, forKey: storageKey)
    }

    nonisolated static func color(fromHex hex: String?) -> Color {
        let rgb = rgbComponents(fromHex: hex) ?? rgbComponents(fromHex: defaultCustomColorHex)!
        return Color(red: rgb.red / 255, green: rgb.green / 255, blue: rgb.blue / 255)
    }

    nonisolated static func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        #if canImport(UIKit)
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return defaultCustomColorHex
        }
        #elseif canImport(AppKit)
        guard let converted = uiColor.usingColorSpace(.deviceRGB) else {
            return defaultCustomColorHex
        }
        red = converted.redComponent
        green = converted.greenComponent
        blue = converted.blueComponent
        alpha = converted.alphaComponent
        #endif

        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    nonisolated static func rgbComponents(fromHex hex: String?) -> (red: Double, green: Double, blue: Double)? {
        guard var raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let value = Int(raw, radix: 16) else {
            return nil
        }

        return (
            Double((value >> 16) & 0xFF),
            Double((value >> 8) & 0xFF),
            Double(value & 0xFF)
        )
    }

    nonisolated private static func legacyColorHex(for rawValue: String) -> String {
        switch rawValue {
        case "sunnyAmber", "champagne", "antiqueOchre", "warmTaupe":
            return "#FBBC54"
        case "coralPink":
            return "#FC5E70"
        case "tangerine", "peachOrange", "terracotta":
            return "#FF8531"
        case "lemonYellow":
            return "#FFCA3A"
        case "limeGreen", "pistachio":
            return "#8AC926"
        case "aquaCyan", "powderBlue", "smokyJade":
            return "#00AEEF"
        case "orchidPurple", "periwinkle", "softLilac":
            return "#C095E4"
        case "roseGold", "dustyRose", "damsonPlum":
            return "#FB6095"
        default:
            return defaultCustomColorHex
        }
    }
}

private struct LeafyThemeColorPreferenceKey: EnvironmentKey {
    static let defaultValue = AppThemeColorPreference.green
}

extension EnvironmentValues {
    var leafyThemeColorPreference: AppThemeColorPreference {
        get { self[LeafyThemeColorPreferenceKey.self] }
        set { self[LeafyThemeColorPreferenceKey.self] = newValue }
    }
}

enum AppTheme {
    private struct ThemePalette {
        let base: Color
        let emphasis: Color
        let soft: Color
        let textOnAccent: Color
        let courseCards: [Color]
    }

    private typealias RGB = (red: Double, green: Double, blue: Double)

    private static let themeColorPreferenceKey = AppThemeColorPreference.storageKey

    private static var themeColorPreference: AppThemeColorPreference {
        AppThemeColorPreference.storedValue(UserDefaults.standard.string(forKey: themeColorPreferenceKey))
    }

    private static var palette: ThemePalette {
        palette(for: themeColorPreference)
    }

    private static func color(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }

    private static func color(_ rgb: RGB) -> Color {
        color(rgb.red, rgb.green, rgb.blue)
    }

    private static func generatedCourseCards(from base: RGB) -> [Color] {
        [0.62, 0.56, 0.50, 0.44, 0.38, 0.32, 0.26].map { whiteRatio in
            color(
                base.red + (255 - base.red) * whiteRatio,
                base.green + (255 - base.green) * whiteRatio,
                base.blue + (255 - base.blue) * whiteRatio
            )
        }
    }

    private static func makePalette(base: RGB, emphasis: RGB, soft: RGB, textOnAccent: Color) -> ThemePalette {
        ThemePalette(
            base: color(base),
            emphasis: color(emphasis),
            soft: color(soft),
            textOnAccent: textOnAccent,
            courseCards: generatedCourseCards(from: base)
        )
    }

    private static func customPalette() -> ThemePalette {
        let base = AppThemeColorPreference.rgbComponents(
            fromHex: UserDefaults.standard.string(forKey: AppThemeColorPreference.customColorHexKey)
        ) ?? (157, 193, 131)
        let emphasis = mix(base, with: (0, 0, 0), amount: 0.42)
        let soft = mix(base, with: (255, 255, 255), amount: 0.84)
        let luminance = (base.red * 0.299 + base.green * 0.587 + base.blue * 0.114) / 255
        let textOnAccent: Color = luminance > 0.58 ? color(28, 34, 31) : .white

        return makePalette(
            base: base,
            emphasis: emphasis,
            soft: soft,
            textOnAccent: textOnAccent
        )
    }

    private static func mix(_ base: RGB, with target: RGB, amount: Double) -> RGB {
        (
            red: base.red + (target.red - base.red) * amount,
            green: base.green + (target.green - base.green) * amount,
            blue: base.blue + (target.blue - base.blue) * amount
        )
    }

    private static func palette(for preference: AppThemeColorPreference) -> ThemePalette {
        switch preference {
        case .green:
            return ThemePalette(
                base: color(157, 193, 131),
                emphasis: color(95, 127, 78),
                soft: color(236, 244, 231),
                textOnAccent: color(32, 53, 31),
                courseCards: generatedCourseCards(from: (157, 193, 131))
            )
        case .tiffanyBlue:
            return ThemePalette(
                base: color(129, 216, 208),
                emphasis: color(43, 127, 122),
                soft: color(232, 249, 247),
                textOnAccent: color(21, 55, 53),
                courseCards: generatedCourseCards(from: (129, 216, 208))
            )
        case .candyPink:
            return makePalette(
                base: (251, 96, 149),
                emphasis: (184, 50, 104),
                soft: (255, 237, 244),
                textOnAccent: color(58, 14, 34)
            )
        case .custom:
            return customPalette()
        }
    }

    // MARK: - Semantic Colors
    static var leafyGreen: Color { palette.base }
    static var leafyGreenEmphasis: Color { palette.emphasis }
    static var leafyGreenSoft: Color { palette.soft }

    static var accent: Color { palette.base }
    static var accentSecondary: Color { palette.base }
    static var accentTertiary: Color { palette.base }
    static var accentEmphasis: Color { palette.emphasis }
    static var accentSoft: Color { palette.soft }

    static let background = Color(uiColor: .systemGroupedBackground)
    static let backgroundSecondary = Color(uiColor: .secondarySystemGroupedBackground)
    static let groupedBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let groupedBackgroundSecondary = Color(uiColor: .tertiarySystemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardElevated = Color(uiColor: .systemBackground)
    static let fill = Color(uiColor: .tertiarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator).opacity(0.12)

    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(uiColor: .tertiaryLabel)
    static var textOnAccent: Color { palette.textOnAccent }

    static func accent(for preference: AppThemeColorPreference) -> Color {
        palette(for: preference).base
    }

    static func accentEmphasis(for preference: AppThemeColorPreference) -> Color {
        palette(for: preference).emphasis
    }

    static func accentSoft(for preference: AppThemeColorPreference) -> Color {
        palette(for: preference).soft
    }

    static func textOnAccent(for preference: AppThemeColorPreference) -> Color {
        palette(for: preference).textOnAccent
    }

    static func floatingChromeSelectedBackground(
        for preference: AppThemeColorPreference,
        colorScheme: ColorScheme
    ) -> Color {
        colorScheme == .dark
            ? accent(for: preference).opacity(0.24)
            : accentSoft(for: preference).opacity(0.96)
    }

    static func floatingChromeIconBackground(
        for preference: AppThemeColorPreference,
        isSelected: Bool,
        colorScheme: ColorScheme
    ) -> Color {
        if isSelected {
            return accent(for: preference)
        }
        return colorScheme == .dark ? accent(for: preference).opacity(0.18) : accentSoft(for: preference)
    }

    static func floatingChromePanelTint(
        for preference: AppThemeColorPreference,
        colorScheme: ColorScheme
    ) -> Color? {
        colorScheme == .dark ? Color.black.opacity(0.22) : nil
    }

    static func floatingChromePanelFallbackFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.86)
            : Color(uiColor: .systemBackground).opacity(0.9)
    }

    static func imagePreviewBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black : .white
    }

    static let warning = Color.orange
    static let danger = Color.red
    static let destructive = danger

    // MARK: - Materials & Effects
    static let topBarMaterial: Material = .ultraThinMaterial
    static let tabBarMaterial: Material = .thinMaterial
    static let chromeMaterial: Material = .regularMaterial

    static var aura: Color { leafyGreen.opacity(0.16) }
    static var auraStrong: Color { leafyGreen.opacity(0.24) }

    // MARK: - Backgrounds
    static let adaptiveBackground = background
    static let adaptiveSecondaryBackground = backgroundSecondary
    static let softBackground = background
    static let softBackgroundSecondary = backgroundSecondary
    static let softFill = fill.opacity(0.92)
    static let cardBackground = card.opacity(0.92)

    static var pageGradient: LinearGradient {
        pageGradient(for: themeColorPreference)
    }

    static func pageGradient(for preference: AppThemeColorPreference) -> LinearGradient {
        LinearGradient(
            colors: [
                background,
                accent(for: preference).opacity(0.08),
                background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var subtleGreenGradient: LinearGradient {
        LinearGradient(
            colors: [leafyGreen.opacity(0.16), leafyGreen.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var loginGradientA: Color { leafyGreenSoft }
    static var loginGradientB: Color { leafyGreen }
    static var loginGradientC: Color { leafyGreen }

    static var featureTints: [Color] {
        Array(repeating: leafyGreen, count: 7)
    }

    static var courseCardColors: [Color] { palette.courseCards }
    static var courseCardGreens: [Color] { courseCardColors }

    static func courseCardColor(for name: String, themeColorPreferenceRaw: String? = nil) -> Color {
        let preference = themeColorPreferenceRaw.map(AppThemeColorPreference.storedValue) ?? themeColorPreference
        return courseCardColor(for: name, themeColorPreference: preference)
    }

    static func courseCardColor(for name: String, themeColorPreference: AppThemeColorPreference) -> Color {
        let colors = palette(for: themeColorPreference).courseCards
        return courseCardColor(for: name, colors: colors)
    }

    static func courseCardColor(for name: String, colors: [Color]) -> Color {
        guard !colors.isEmpty else { return palette.courseCards[0] }
        return colors[stableCourseColorIndex(for: name, colorCount: colors.count)]
    }

    static func stableCourseColorIndex(for name: String, colorCount: Int) -> Int {
        guard colorCount > 0 else { return 0 }
        guard !name.isEmpty else { return 0 }

        var hashValue: UInt32 = 0
        for char in name.unicodeScalars {
            hashValue = hashValue &* 31 &+ char.value
        }

        return Int(hashValue % UInt32(colorCount))
    }

}

enum AppRadius {
    static let large: CGFloat = 24
    static let medium: CGFloat = 16
    static let small: CGFloat = 12
}

enum AppSpacing {
    static let page: CGFloat = 20
    static let section: CGFloat = 24
    static let card: CGFloat = 16
    static let compact: CGFloat = 12
    static let micro: CGFloat = 8
    static let rootTop: CGFloat = 16
}

enum AppShadow {
    static let y: CGFloat = 2
    static let radius: CGFloat = 10

    static func color(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light ? Color.black.opacity(0.05) : Color.clear
    }
}

private struct LeafyFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

private struct LeafyControlScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var leafyFontScale: CGFloat {
        get { self[LeafyFontScaleKey.self] }
        set { self[LeafyFontScaleKey.self] = newValue }
    }

    var leafyControlScale: CGFloat {
        get { self[LeafyControlScaleKey.self] }
        set { self[LeafyControlScaleKey.self] = newValue }
    }
}

// MARK: - Backward compatibility during UI migration
enum UIConstants {
    static let cornerRadiusLarge: CGFloat = AppRadius.large
    static let cornerRadiusSmall: CGFloat = AppRadius.medium

    static func floatingShadow(for colorScheme: ColorScheme) -> Color {
        AppShadow.color(for: colorScheme)
    }
}

// MARK: - Typography
extension View {
    func leafyBrandLargeTitle() -> some View {
        modifier(LeafyScaledSystemFontModifier(baseSize: 32, weight: .bold))
    }

    func responsiveLargeTitle() -> some View {
        modifier(LeafyScaledSystemFontModifier(baseSize: 32, weight: .bold))
    }

    func title1() -> some View {
        modifier(LeafyScaledSystemFontModifier(baseSize: 26, weight: .semibold))
    }

    func title2() -> some View {
        modifier(LeafyScaledSystemFontModifier(baseSize: 20, weight: .semibold))
    }

    func leafyBody() -> some View {
        modifier(LeafyScaledSystemFontModifier(baseSize: 16, weight: .regular))
    }

    func leafyHeadline() -> some View {
        modifier(LeafyScaledSystemFontModifier(baseSize: 16, weight: .semibold))
    }

    func leafySubheadline() -> some View {
        modifier(LeafyScaledSystemFontModifier(baseSize: 14, weight: .regular))
    }

    func leafyTitle3() -> some View {
        modifier(LeafyScaledSystemFontModifier(baseSize: 18, weight: .semibold))
    }

    func microCaption() -> some View {
        modifier(LeafyScaledSystemFontModifier(baseSize: 11, weight: .regular))
            .lineSpacing(2)
    }
}

private struct LeafyScaledSystemFontModifier: ViewModifier {
    @Environment(\.leafyFontScale) private var leafyFontScale

    let baseSize: CGFloat
    let weight: Font.Weight
    var design: Font.Design = .default

    func body(content: Content) -> some View {
        content.font(.system(size: baseSize * leafyFontScale, weight: weight, design: design))
    }
}
