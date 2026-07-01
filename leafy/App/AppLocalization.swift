import Foundation
import SwiftUI

nonisolated enum AppLanguagePreference: String, Sendable {
    case zhHans

    var localeIdentifier: String {
        "zh-Hans"
    }

    func weekdayTitle(for day: Int) -> String {
        let index = max(0, min(day - 1, 6))
        return ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index]
    }

    static var current: AppLanguagePreference {
        .zhHans
    }
}

private struct LeafyLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguagePreference.current
}

extension EnvironmentValues {
    var leafyLanguage: AppLanguagePreference {
        get { self[LeafyLanguageKey.self] }
        set { self[LeafyLanguageKey.self] = newValue }
    }
}

nonisolated enum L10n {
    static func text(_ key: String, language: AppLanguagePreference = .current) -> String {
        guard let path = Bundle.main.path(forResource: language.localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return key
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func text(_ key: String, language: AppLanguagePreference = .current, _ arguments: CVarArg...) -> String {
        let format = text(key, language: language)
        return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }
}
