import Foundation

/// Ein Wert in den UserDefaults mit Standardwert und optionaler Begrenzung beim Lesen und Schreiben.
@propertyWrapper
struct UserDefault<Value> {
    let key: String
    let defaultValue: Value
    var clamp: (Value) -> Value = { $0 }
    var store: UserDefaults = .standard

    var wrappedValue: Value {
        get { clamp(store.object(forKey: key) as? Value ?? defaultValue) }
        set { store.set(clamp(newValue), forKey: key) }
    }
}

extension UserDefault where Value: Comparable {
    init(_ key: String, default defaultValue: Value, range: ClosedRange<Value>) {
        self.init(key: key, defaultValue: defaultValue, clamp: { min(max($0, range.lowerBound), range.upperBound) })
    }
}

extension UserDefault {
    init(_ key: String, default defaultValue: Value) {
        self.init(key: key, defaultValue: defaultValue)
    }
}

/// Persistente Einstellungen (UserDefaults).
enum Settings {
    // `title` ist jeweils ein Schlüssel für L10n.t(_:)
    static let sizes: [(title: String, pixel: Double)] = [("size.small", 3), ("size.medium", 4), ("size.large", 6)]
    static let speeds: [(title: String, speed: Double)] = [("speed.slow", 25), ("speed.normal", 40), ("speed.fast", 65)]
    /// Gesprächigkeit: Faktor für spontanes Plappern und Summen (Reaktionen wie "Wiiiee" bleiben).
    static let talkLevels: [(title: String, factor: Double)] = [
        ("talk.silent", 0), ("talk.quiet", 0.4), ("talk.normal", 1), ("talk.chatty", 2.5),
    ]

    /// Aktivität: Faktor für aktive vs. ruhige Beschäftigungen.
    static let activityLevels: [(title: String, factor: Double)] = [
        ("activity.lazy", 0.35), ("activity.calm", 0.65), ("activity.normal", 1), ("activity.active", 1.6),
        ("activity.hyper", 2.6),
    ]

    /// Darstellung: "auto" folgt macOS, sonst "light" oder "dark".
    static let appearances: [(title: String, value: String)] = [
        ("appearance.auto", "auto"), ("appearance.light", "light"), ("appearance.dark", "dark"),
    ]

    /// Menüsprache: "auto" folgt macOS (Standard), sonst "de" oder "en". Sprachnamen bleiben unübersetzt.
    static let languages: [(title: String, value: String)] = [
        ("language.auto", "auto"), ("Deutsch", "de"), ("English", "en"),
    ]

    static let maxClawds = 10

    @UserDefault("activity", default: 1) static var activity: Double
    @UserDefault("talkativeness", default: 1) static var talkativeness: Double
    @UserDefault("pixelSize", default: 4) static var pixelSize: Double
    @UserDefault("speed", default: 40) static var speed: Double
    /// Lautstärke 0…1.
    @UserDefault("volume", default: 0.6, range: 0...1) static var volume: Double
    /// Menüsprache; ohne eigene Wahl "auto" (wie macOS). Die Wahl im Menü wird gespeichert.
    @UserDefault("language", default: "auto") static var language: String
    @UserDefault("appearance", default: "auto") static var appearance: String

    /// Die Topfpflanze am Dock: Wachstumsstufe 0…4 und Tag des letzten Gießens.
    @UserDefault("plantStage", default: 0, range: 0...4) static var plantStage: Int
    @UserDefault("plantLastWatered", default: "") static var plantLastWatered: String

    /// Magnetschuhe: an den Seitenkanten von Fenstern hoch- und runterlaufen.
    @UserDefault("magneticShoes", default: false) static var magneticShoes: Bool
    @UserDefault("walkOnWindows", default: true) static var walkOnWindows: Bool
    /// Neigt man das MacBook, rutscht Clawd zur Seite (nur mit Beschleunigungssensor).
    @UserDefault("reactToTilt", default: true) static var reactToTilt: Bool

    /// Alte Einstellungen übernehmen. Den Schalter "Geräusche" gibt es nicht mehr – wer ihn
    /// ausgeschaltet hatte, bekommt stattdessen die Gesprächigkeit "Still".
    static func migrate(store: UserDefaults = .standard) {
        if let soundOn = store.object(forKey: "soundEnabled") as? Bool {
            if !soundOn { store.set(0.0, forKey: "talkativeness") }
            store.removeObject(forKey: "soundEnabled")
        }
    }
}
