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
        let themeSnapshot = LeafyWidgetThemeSnapshot(
            preferenceRaw: preferenceRaw,
            customColorHex: customColorHex
        )
        let iconPreference = migratedIconPreference(
            rawValue: iconPreferenceRaw,
            themeSnapshot: themeSnapshot
        )

        if iconPreferenceRaw == "followTheme" {
            UserDefaults.standard.set(
                iconPreference.rawValue,
                forKey: LeafyAppIconAppearancePreference.storageKey
            )
        }

        LeafyWidgetThemeStore.save(preferenceRaw: preferenceRaw, customHex: customColorHex)
        WidgetCenter.shared.reloadTimelines(ofKind: LeafyWidgetConstants.widgetKind)
        applyIconIfNeeded(iconPreference: iconPreference)
    }

    static func applyIconIfNeeded(
        iconPreference: LeafyAppIconAppearancePreference
    ) {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else { return }

        let iconName = alternateIconName(iconPreference: iconPreference)
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
        iconPreference: LeafyAppIconAppearancePreference
    ) -> String? {
        let resolvedTheme = iconPreference.themePreferenceRaw

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

    static func migratedIconPreference(
        rawValue: String,
        themeSnapshot: LeafyWidgetThemeSnapshot
    ) -> LeafyAppIconAppearancePreference {
        guard rawValue == "followTheme" else {
            return LeafyAppIconAppearancePreference.storedValue(rawValue)
        }

        switch themeSnapshot.preference {
        case .green:
            return .green
        case .tiffanyBlue:
            return .tiffanyBlue
        case .candyPink:
            return .candyPink
        case .custom:
            return .green
        }
    }
}

extension LeafyAppIconAppearancePreference {
    func title(language: AppLanguagePreference) -> String {
        L10n.text(title, language: language)
    }
}
