import Foundation

enum AppLanguage {
    static let preferenceKey = "appLanguage"
    static var selected: String {
        let value = UserDefaults.standard.string(forKey: preferenceKey)
        return ["it", "en"].contains(value ?? "") ? value! : (Locale.preferredLanguages.first?.hasPrefix("it") == true ? "it" : "en")
    }
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        let root = Bundle.module
        #else
        let root = Bundle.main
        #endif
        guard let path = root.path(forResource: selected, ofType: "lproj"), let bundle = Bundle(path: path) else { return root }
        return bundle
    }
}

/// Use for non-SwiftUI strings and dynamic labels; SwiftUI literals use the same .strings files.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLanguage.bundle.localizedString(forKey: key, value: key, table: nil)
    return String(format: format, locale: Locale(identifier: AppLanguage.selected), arguments: arguments)
}
