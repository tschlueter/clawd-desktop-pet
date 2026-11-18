/// Etwas, das ein Clawd auf Kommando vorführt: aus dem Demo-Menü (Option-Klick) oder
/// über die Startargumente `--demo` und `--force`.
enum DemoAction {
    /// Verhalten, das der Controller selbst spielt.
    enum Behavior: String, CaseIterable {
        case wave, look, sit, sleep, yawn, sneeze, dizzy
        /// Verstecken wie bei einer Vollbild-App: ducken, Arme über den Kopf, dann vorsichtig hervorkommen.
        case hide
        case coding, music
        case barbell, rope
        /// Mit Magnetschuhen von einer Fensterkante zur nächsten springen.
        case wallJump
        /// Zum Dock-Ende laufen und auf den Boden daneben hüpfen.
        case hopOff
        /// Neigung vorspielen: Clawd rutscht zur Seite wie bei einem gekippten MacBook.
        case slide
        /// Hoch hinauf und fallen – Regenschirm bzw. Ballon bremsen, sanfte Landung, durchschnaufen.
        case umbrella, balloon
    }

    case behavior(Behavior)
    case job(Job.Type)
    case encounter(Encounter.Kind)

    /// Aus einem Startargument: `"wave"`, `"job:windows"` oder `"enc:hug"`.
    init?(argument: String) {
        if argument.hasPrefix("job:") {
            guard let type = Jobs.named(String(argument.dropFirst(4))) else { return nil }
            self = .job(type)
        } else if argument.hasPrefix("enc:") {
            guard let kind = Encounter.Kind(rawValue: String(argument.dropFirst(4))) else { return nil }
            self = .encounter(kind)
        } else if let behavior = Behavior(rawValue: argument) {
            self = .behavior(behavior)
        } else if let type = Jobs.builtIn.first(where: { $0.name == argument }) {
            self = .job(type) // "eat", "sweep", "tennis" – wie früher ohne "job:"
        } else {
            return nil
        }
    }

    /// Kurzname für Logs, im selben Format wie das Startargument.
    var name: String {
        switch self {
        case .behavior(let b): b.rawValue
        case .job(let type): "job:\(type.name)"
        case .encounter(let kind): "enc:\(kind.rawValue)"
        }
    }
}
