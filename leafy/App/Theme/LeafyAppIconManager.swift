import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import WidgetKit

@MainActor
enum LeafyAppIconManager {
    static func syncTheme(
        preferenceRaw: String,
        customColorHex: String,
        iconPreferenceRaw: String
    ) {
        LeafyWidgetThemeStore.save(preferenceRaw: preferenceRaw, customHex: customColorHex)
        WidgetCenter.shared.reloadTimelines(ofKind: LeafyWidgetConstants.widgetKind)
        applyIconIfNeeded(
            themeSnapshot: LeafyWidgetThemeSnapshot(preferenceRaw: preferenceRaw, customColorHex: customColorHex),
            iconPreference: LeafyAppIconAppearancePreference.storedValue(iconPreferenceRaw)
        )
    }

    static func applyIconIfNeeded(
        themeSnapshot: LeafyWidgetThemeSnapshot,
        iconPreference: LeafyAppIconAppearancePreference
    ) {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else { return }

        let iconName = alternateIconName(themeSnapshot: themeSnapshot, iconPreference: iconPreference)
        guard UIApplication.shared.alternateIconName != iconName else { return }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            #if DEBUG
            if let error {
                print("Leafy alternate icon update failed: \(error)")
            }
            #endif
        }
        #endif
    }

    static func alternateIconName(
        themeSnapshot: LeafyWidgetThemeSnapshot,
        iconPreference: LeafyAppIconAppearancePreference
    ) -> String? {
        let resolvedTheme = iconPreference.themePreferenceRaw ?? LeafyWidgetThemePalette.closestPreset(for: themeSnapshot)

        switch resolvedTheme {
        case .green:
            return nil
        case .tiffanyBlue:
            return "AppIconTiffanyBlue"
        case .candyPink:
            return "AppIconCandyPink"
        case .custom:
            return nil
        }
    }
}

extension LeafyAppIconAppearancePreference {
    func title(language: AppLanguagePreference) -> String {
        L10n.text(title, language: language)
    }
}
