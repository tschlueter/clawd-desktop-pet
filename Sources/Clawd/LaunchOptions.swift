import AppKit

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
///
/// Szenen als GIF aufnehmen (für die README), immer im Spielplatz, hell und stumm:
/// - `--record <datei.gif>` – ein Clawd fällt in den Spielplatz; aufgenommen wird ab der Landung
/// - `--record-seconds <s>` – Länge der Aufnahme (Standard 8)
/// - `--record-from-start` – schon den Fall in den Spielplatz aufnehmen
/// - `--drop x,y` – bei Aufnahmen relativ zur unteren linken Ecke des Spielplatzes
/// - `--record-rect x,y,b,h` – nur diesen Ausschnitt (Punkte, von unten links im Spielplatz)
/// - `--record-scale <f>` – Auflösung (Standard 2)
/// - `--playground-size BxH` – Größe des Spielplatz-Fensters
/// - `--script "0.5:wave,2:jump"` – Aktionen, Sekunden nach der Landung (siehe `PetController.runScript`)
/// - zusammen mit `--encounter <art>`: zwei Clawds landen nebeneinander und spielen diese Begegnung
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
    var record: String?
    var recordSeconds: Double = 8
    var recordFromStart = false
    var recordRect: CGRect?
    var recordScale: CGFloat = 2
    var playgroundSize: NSSize?
    var script: [(time: Double, step: String)] = []

    /// Irgendein Entwickler-Ablauf aktiv? Dann wird geloggt.
    var isDebugging: Bool {
        if case .normal = scenario { return demo != nil || playground || record != nil }
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
        record = value(after: "--record")
        recordSeconds = value(after: "--record-seconds").flatMap(Double.init) ?? 8
        recordFromStart = arguments.contains("--record-from-start")
        if let p = value(after: "--record-rect")?.split(separator: ",").compactMap({ Double($0) }), p.count == 4 {
            recordRect = CGRect(x: p[0], y: p[1], width: p[2], height: p[3])
        }
        recordScale = value(after: "--record-scale").flatMap(Double.init).map { CGFloat($0) } ?? 2
        if let p = value(after: "--playground-size")?.split(separator: "x").compactMap({ Double($0) }), p.count == 2 {
            playgroundSize = NSSize(width: p[0], height: p[1])
        }
        script = (value(after: "--script") ?? "").split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let t = Double(parts[0]) else { return nil }
            return (t, String(parts[1]))
        }
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
