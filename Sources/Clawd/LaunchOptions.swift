import Foundation

/// Entwickler-Logs auf stdout. Bleiben auch im Release verfügbar, damit sich Abläufe ohne
/// Debugger über Startargumente prüfen lassen.
enum DebugLog {
    /// Allgemeine Logs (Begegnungen, Demo); wird von den Startargumenten eingeschaltet.
    static var enabled = false

    static func log(_ text: @autoclosure () -> String) {
        guard enabled else { return }
        write(text())
    }

    /// Ohne Prüfung ausgeben – für Aufrufer mit eigenem Schalter (z. B. ein einzelner Clawd).
    static func write(_ text: String) {
        print(text)
        fflush(stdout)
    }
}

/// Entwickler-Startargumente:
/// - `--drop x,y` – der erste Clawd fällt von dort
/// - `--throw vx` – … und wird seitlich weggeworfen
/// - `--force <aktion>` – der erste Clawd spielt nach der Landung diese Aktion (siehe `DemoAction`)
/// - `--demo <aktion>` – nach 3 s denselben Ablauf wie im Demo-Menü
/// - `--encounter <art>` – zwei Clawds landen nebeneinander und spielen diese Begegnung
/// - `--pair` – zwei Clawds landen nebeneinander (der erste bekommt `--force`)
/// - `--droptest` – ein Clawd wird wie vom Nutzer auf einen anderen fallen gelassen
/// - `--playground` – nach dem Start den Spielplatz öffnen
/// - `--weekend` / `--weekday` – Wochenend-Modus erzwingen bzw. abschalten (sonst gilt der Kalender)
struct LaunchOptions {
    enum Scenario {
        case normal
        case encounter(Encounter.Kind?)
        case pair
        case dropTest
    }

    var scenario: Scenario = .normal
    var drop: CGPoint?
    var throwVX: CGFloat?
    var force: DemoAction?
    var demo: DemoAction?
    var playground = false
    var weekend: Bool?

    /// Irgendein Entwickler-Ablauf aktiv? Dann wird geloggt.
    var isDebugging: Bool {
        if case .normal = scenario { return demo != nil || playground }
        return true
    }

    init(arguments: [String] = CommandLine.arguments) {
        func value(after flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }

        if let parts = value(after: "--drop")?.split(separator: ",").compactMap({ Double($0) }), parts.count == 2 {
            drop = CGPoint(x: parts[0], y: parts[1])
        }
        throwVX = value(after: "--throw").flatMap(Double.init).map { CGFloat($0) }
        force = value(after: "--force").flatMap(DemoAction.init(argument:))
        demo = value(after: "--demo").flatMap(DemoAction.init(argument:))
        playground = arguments.contains("--playground")
        if arguments.contains("--weekend") { weekend = true } else if arguments.contains("--weekday") { weekend = false }

        if let kind = value(after: "--encounter") {
            scenario = .encounter(Encounter.Kind(rawValue: kind))
        } else if arguments.contains("--pair") {
            scenario = .pair
        } else if arguments.contains("--droptest") {
            scenario = .dropTest
        }
    }
}
