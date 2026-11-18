import AppKit

/// Eine Arbeit, die ein einzelner Clawd erledigt – ein kleines Drehbuch in Phasen
/// (hingehen → Werkzeug raus → arbeiten → fertig). Steuert Clawd wie eine Begegnung über
/// die Puppen-Schnittstelle des Controllers; eigene Effekte (Funkeln, Müllsack …) liegen als
/// Layer auf der Bühne und werden bei Ende oder Abbruch entfernt.
class Job {
    unowned let c: PetController
    var pose = Encounter.Pose()
    private(set) var finished = false
    /// Aufgeräumt (beendet oder abgebrochen): Danach werden keine Effekte mehr gezeigt.
    private var retired = false
    let startedAt = CACurrentMediaTime()
    /// Länger dauert keine Arbeit; danach beendet der Controller sie (Sicherheitsnetz).
    static let maxDuration: TimeInterval = 120
    private var script = Choreography()
    var walked: CGFloat = 0
    /// Aus dem Demo-Menü (oder `--force`) gestartet – manche Arbeiten zeigen dann ihre ausführlichste Form.
    var isDemo = false
    private let effects: EffectLayers

    class var name: String { "job" }
    class func isPossible(_ c: PetController) -> Bool { true }

    required init(_ c: PetController) {
        self.c = c
        effects = EffectLayers(stage: c.stage)
    }

    /// Pro Tick; Unterklassen überschreiben.
    func step(now: CFTimeInterval, dt: TimeInterval) {}

    // MARK: Hilfen

    var px: CGFloat { c.px }
    var world: World { c.world }
    var phase: Int { script.phase }

    /// Sekunden seit Beginn der aktuellen Phase.
    func t(_ now: CFTimeInterval) -> TimeInterval { script.elapsed(now) }

    func next(_ now: CFTimeInterval) { script.next(now) }

    /// Zu einer bestimmten Phase springen (z. B. für Wiederholungen).
    func go(to phase: Int, now: CFTimeInterval) { script.go(to: phase, now: now) }

    func once(_ key: String) -> Bool { script.once(key) }

    func finish(walkAway: Bool = false) {
        guard !finished else { return }
        finished = true
        cleanup()
        c.finishJob(walkAway: walkAway)
    }

    /// Beenden, ohne den Controller zurückzusetzen – er übernimmt selbst (z. B. Clawd fliegt mit
    /// Schwung weiter, siehe `PetController.swing`).
    func retire() {
        guard !finished else { return }
        finished = true
        cleanup()
    }

    /// Effekte ausblenden: Sie verschwinden nach kurzer Zeit (auch bei Abbruch mitten in der Arbeit).
    func cleanup() {
        retired = true
        effects.fadeOutAll(lifetime: 0.8, fade: 0.6)
    }

    func walkFrame(stride: CGFloat = 1) -> ClawdSprite.Frame {
        ClawdSprite.walkFrame(walked: walked, px: px, stride: stride)
    }

    /// Geht zur Mitte x; true, wenn angekommen. Weite Wege zur Arbeit gehen zügig.
    @discardableResult
    func walk(to x: CGFloat, speed factor: CGFloat = 1, dt: TimeInterval) -> Bool {
        let hurry: CGFloat = abs(x - c.center) > 250 ? 1.8 : 1
        let (arrived, distance) = c.step(toward: x, speed: factor * hurry, dt: dt)
        walked += distance
        return arrived
    }

    /// Effekt-Layer auf der Bühne zeigen (Ursprung unten links, global).
    func showEffect(_ key: String, _ frame: ClawdSprite.Frame, origin: CGPoint, scale: CGFloat, opacity: Float = 1,
                    mirrored: Bool = false, shadow: Bool = false, behind: Bool = false) {
        guard !retired else { return }
        effects.show(key, frame, origin: origin, scale: scale, opacity: opacity, mirrored: mirrored, shadow: shadow,
                     behind: behind)
    }

    /// Effekt um seinen Mittelpunkt gedreht zeigen.
    func showRotated(_ key: String, _ frame: ClawdSprite.Frame, center: CGPoint, scale: CGFloat, angle: CGFloat) {
        guard !retired else { return }
        effects.show(key, frame, center: center, scale: scale, angle: angle)
    }

    /// Einfarbige Fläche (global) zeigen, z. B. frische Farbe.
    func showRect(_ key: String, _ rect: CGRect, color: CGColor) {
        guard !retired else { return }
        effects.showRect(key, rect, color: color)
    }

    /// Effekt nach der Arbeit liegen lassen; die Bühne lässt ihn später verblassen.
    func leaveBehind(_ key: String, lifetime: TimeInterval) {
        guard let layer = effects.detach(key) else { return }
        c.stage?.leave(layer, lifetime: lifetime)
    }

    func hideEffect(_ key: String) {
        effects.hide(key)
    }

    /// Glyphe kurz über dem Kopf zeigen (Fragezeichen, Glühbirne, Häkchen …).
    func showAboveHead(_ key: String, _ glyph: ClawdSprite.Frame, opacity: Float = 1) {
        guard !retired else { return }
        effects.show(key, glyph, centerX: c.center, bottom: c.groundY + 9.5 * px, scale: px * 0.8, opacity: opacity)
    }

    /// Richtung mit mehr Platz auf der aktuellen Fläche.
    func roomierDirection() -> CGFloat {
        guard let r = c.centerRange else { return c.facing }
        return (r.upperBound - c.center) >= (c.center - r.lowerBound) ? 1 : -1
    }
}

/// Alle Arbeiten; neue einfach hier eintragen.
enum Jobs {
    static let all: [Job.Type] = [
        WindowCleaningJob.self, IconPolishJob.self, TrashOutJob.self, WaterPlantJob.self,
        HammerJob.self, PaintJob.self, BoxJob.self, ScrewJob.self,
        BugHuntJob.self, CodeReviewJob.self, ServerJob.self, WhiteboardJob.self,
        CoffeeJob.self, MailJob.self, LaundryJob.self, FilesJob.self, CallJob.self,
        RubberDuckJob.self, DeployRocketJob.self, TestsGreenJob.self, FireJob.self,
        PrinterJob.self, PostitJob.self, StampJob.self, PomodoroJob.self,
        DeadlinePanicJob.self, NightShiftJob.self, CablesJob.self, ShipItJob.self,
        PaperPlaneJob.self, KiteJob.self, CookingJob.self, ArcheryJob.self, MagicJob.self,
        ConsoleGamingJob.self, PCGamingJob.self,
        PlanJob.self, TerminalJob.self, SearchJob.self, SubagentsJob.self, ThinkingHatsJob.self,
        SecurityCheckJob.self, DatabaseMigrationJob.self, DashboardJob.self, PrototypeJob.self,
    ]

    /// Eingebaute Beschäftigungen, die der Controller selbst auslöst (nicht im Zufalls-Pool).
    static let builtIn: [Job.Type] = [EatingJob.self, SweepingJob.self, TennisJob.self, FlowCodingJob.self,
                                      GrappleJob.self, JetpackJob.self]

    /// Gewicht pro Job: 3 = häufig (ruhiger Alltag), 2 = normal, 1 = selten (spektakulär).
    static let weights: [String: Double] = [
        "review": 3, "duck": 3, "tests": 3, "coffee": 3, "pomodoro": 3, "stamp": 3,
        "files": 3, "postits": 3, "whiteboard": 3, "windows": 3, "polish": 3,
        "bug": 2, "server": 2, "call": 2, "mail": 2, "water": 2, "hammer": 2,
        "paint": 2, "box": 2, "screw": 2, "cables": 2, "laundry": 2, "night": 2,
        "plane": 2, "kite": 2, "cook": 2, "archery": 2, "magic": 2, "console": 2, "pcgame": 2,
        "plan": 3, "terminal": 3, "search": 3, "subagents": 2, "hats": 2,
        "security": 2, "migration": 2, "dashboard": 2, "prototype": 2,
        "deploy": 1, "fire": 1, "printer": 1, "deadline": 1, "shipit": 1, "trash": 1,
    ]

    // MARK: Wochenende

    /// Freizeit – am Wochenende häufiger.
    static let leisure: Set<String> = ["plane", "kite", "cook", "archery", "magic", "console", "pcgame"]
    /// Haushalt – unabhängig vom Wochentag.
    static let chores: Set<String> = ["windows", "polish", "trash", "water", "laundry", "coffee", "mail"]
    /// Am Wochenende: Freizeit × 2,5, Arbeit × 0,35 (Haushalt bleibt).
    static let weekendLeisureFactor = 2.5
    static let weekendWorkFactor = 0.35

    /// Zum Testen per Startargument (`--weekend` / `--weekday`); sonst gilt der Kalender.
    static var weekendOverride: Bool?
    static var isWeekend: Bool { weekendOverride ?? Calendar.current.isDateInWeekend(Date()) }

    static func weight(_ name: String, weekend: Bool) -> Double {
        let base = weights[name] ?? 2
        guard weekend else { return base }
        if leisure.contains(name) { return base * weekendLeisureFactor }
        if chores.contains(name) { return base }
        return base * weekendWorkFactor
    }

    /// Gewichtete Auswahl unter den hier möglichen Jobs; die zuletzt gemachten werden
    /// ausgelassen (außer es bliebe sonst keiner übrig).
    static func pick(from possible: [Job.Type], avoiding recent: [String]) -> Job.Type? {
        var rng = SystemRandomNumberGenerator()
        return pick(from: possible, avoiding: recent, weekend: isWeekend, using: &rng)
    }

    static func pick(from possible: [Job.Type], avoiding recent: [String], weekend: Bool = false,
                     using rng: inout some RandomNumberGenerator) -> Job.Type? {
        let fresh = possible.filter { !recent.contains($0.name) }
        let pool = fresh.isEmpty ? possible : fresh
        let total = pool.reduce(0) { $0 + weight($1.name, weekend: weekend) }
        guard total > 0 else { return pool.randomElement(using: &rng) }
        var r = Double.random(in: 0..<total, using: &rng)
        for type in pool {
            let w = weight(type.name, weekend: weekend)
            if r < w { return type }
            r -= w
        }
        return pool.last
    }

    static func possible(for c: PetController) -> [Job.Type] {
        if case .wall = c.surfaceKind { return [] } // an der Wand wird nur gelaufen
        return all.filter { $0.isPossible(c) }
    }

    static func named(_ name: String) -> Job.Type? {
        (all + builtIn).first { $0.name == name }
    }
}
