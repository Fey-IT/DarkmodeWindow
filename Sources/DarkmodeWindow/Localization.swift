import Foundation

/// Minimal UI localization: German on German systems, English everywhere else.
enum L10n {
    static let isGerman = Locale.preferredLanguages.first?.hasPrefix("de") ?? false

    static func t(_ german: String, _ english: String) -> String {
        isGerman ? german : english
    }
}
