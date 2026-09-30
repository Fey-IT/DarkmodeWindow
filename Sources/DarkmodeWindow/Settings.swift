import AppKit

enum FilterMode: String {
    case smartDark
    case dim
}

/// Persistent user settings (UserDefaults).
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var mode: FilterMode {
        get { FilterMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .smartDark }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }

    /// 0.3 ... 1.0
    var brightness: Double {
        get { defaults.object(forKey: "brightness") as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: "brightness") }
    }

    /// Keep regions that are already dark (Teams UI, dark photos) unchanged.
    var adaptive: Bool {
        get { defaults.object(forKey: "adaptive") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "adaptive") }
    }

    /// Periodically jump to the largest bright area (e.g. a shared slide).
    var autoPosition: Bool {
        get { defaults.bool(forKey: "autoPosition") }
        set { defaults.set(newValue, forKey: "autoPosition") }
    }

    var windowFrame: NSRect? {
        get { defaults.string(forKey: "windowFrame").map(NSRectFromString) }
        set { defaults.set(newValue.map(NSStringFromRect), forKey: "windowFrame") }
    }
}
