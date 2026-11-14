import AppKit

/// Denkhüte: Clawd geht ein Problem nacheinander mit verschiedenfarbigen Hüten an – jeder Hut steht
/// für eine Denkweise (nach Edward de Bonos Methode der sechs Denkhüte). Jede Runde beginnt und endet
/// mit dem blauen Hut. Beim Wechsel fliegt der alte Hut nach hinten weg, der neue fällt von oben auf den Kopf.
final class ThinkingHatsJob: Job {
    enum Hat: Int, CaseIterable {
        case blue, white, red, black, yellow, green

        var frame: ClawdSprite.Frame { ClawdSprite.thinkingHats[rawValue] }
        /// Rot ist bewusst kurz – ein Bauchgefühl, kein Urteil.
        var duration: TimeInterval { self == .red ? 1.5 : 3 }
    }

    override class var name: String { "hats" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    /// Abfolgen aus der Methode; das Demo-Menü zeigt die längste mit allen sechs Hüten.
    static let programs: [[Hat]] = [
        [.blue, .white, .green, .blue],                        // erste Ideen
        [.blue, .black, .green, .blue],                        // schnelles Feedback
        [.blue, .white, .green, .yellow, .black, .red, .blue], // zwischen Möglichkeiten wählen
    ]
    static let switchTime: TimeInterval = 0.6

    private lazy var program: [Hat] = isDemo ? Self.programs[2] : Self.programs.randomElement() ?? Self.programs[0]
    private var worn: Hat?
    private var tossed: (hat: Hat, arc: BallArc, spin: CGFloat)?

    /// Wo ein Hut auf dem Kopf sitzt (wie `ClawdNode.layoutHat`, im stehenden Sprite).
    private var hatOrigin: CGPoint {
        let headTop = CGFloat(ClawdSprite.rows - ClawdSprite.headRow(ClawdSprite.stand)) * px
        return CGPoint(x: c.center - CGFloat(ClawdSprite.columns) / 2 * px, y: c.groundY + headTop - px)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        updateTossedHat(now)

        // Zum Schluss den letzten Hut abwerfen und zufrieden sein.
        guard phase < program.count else {
            if once("lastToss") { toss(now) }
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if t >= 1.0 { finish() }
            return
        }

        let hat = program[phase]
        if t < Self.switchTime {
            if once("toss\(phase)") { toss(now) }
            // Neuer Hut fällt von oben auf den Kopf.
            let p = CGFloat(t / Self.switchTime)
            let drop = (1 - p) * (1 - p) * 30 * px
            showEffect("newHat", hat.frame, origin: CGPoint(x: hatOrigin.x, y: hatOrigin.y + drop), scale: px / 2,
                       mirrored: c.facing < 0, shadow: ClawdSprite.hasShadow(hat.frame))
            pose = Encounter.Pose(sprite: ClawdSprite.lookCycle[0])
            return
        }
        if once("on\(phase)") {
            hideEffect("newHat")
            worn = hat
            c.say(.plop)
        }
        let a = t - Self.switchTime
        think(hat, a, first: phase == 0)
        if a >= hat.duration {
            hideEffect("glyph")
            hideEffect("paper")
            next(now)
        }
    }

    /// Was Clawd mit dem jeweiligen Hut tut.
    private func think(_ hat: Hat, _ a: TimeInterval, first: Bool) {
        var sprite = ClawdSprite.stand
        var particles = ClawdNode.Particles.none
        var lift: CGFloat = 0
        switch hat {
        case .blue where first:
            // Überblick: Worum geht es eigentlich?
            aboveHat(ClawdSprite.questionGlyph)
            sprite = ClawdSprite.lookCycle[Int(a / 0.6) % ClawdSprite.lookCycle.count]
        case .blue:
            // Fazit
            aboveHat(ClawdSprite.checkGlyph)
            sprite = ClawdSprite.happyStand
            if once("done") { c.say(.happy) }
        case .white:
            // Fakten: Blatt lesen und mitzählen.
            let s = px * 0.8
            showEffect("paper", ClawdSprite.paperSheet,
                       origin: CGPoint(x: c.center + c.facing * 5 * px - 2 * s, y: c.groundY + 2.5 * px), scale: s)
            aboveHat(ClawdSprite.digits[Int(a / 0.8) % ClawdSprite.digits.count])
        case .red:
            // Bauchgefühl: kurz und herzlich.
            aboveHat(ClawdSprite.heartGlyph)
            sprite = ClawdSprite.happyStand
            lift = a < 0.3 ? 1 : 0
        case .black:
            // Risiken: skeptisch den Kopf schütteln.
            aboveHat(ClawdSprite.warningGlyph)
            sprite = ClawdSprite.lookCycle[Int(a / 0.25) % 2 == 0 ? 1 : 3]
        case .yellow:
            // Chancen: alles glänzt.
            sprite = ClawdSprite.happyStand
            particles = .sparks
        case .green:
            // Neue Ideen: erst grübeln, dann geht das Licht an.
            if a < 0.8 {
                sprite = ClawdSprite.lookCycle[Int(a / 0.4) % 2 == 0 ? 0 : 2]
            } else {
                aboveHat(ClawdSprite.lightbulbGlyph)
                sprite = ClawdSprite.wave[1]
                if once("idea\(phase)") { c.say(.ding) }
            }
        }
        pose = Encounter.Pose(sprite: sprite, particles: particles, lift: lift, hat: worn?.frame)
    }

    /// Symbol über dem Zylinder (der ist höher als der Platz, den `showAboveHead` lässt).
    private func aboveHat(_ glyph: ClawdSprite.Frame) {
        showEffect("glyph", glyph, origin: CGPoint(x: c.center - CGFloat(glyph[0].count) * px * 0.4,
                                                   y: hatOrigin.y + 6.5 * px), scale: px * 0.8)
    }

    /// Den getragenen Hut nach hinten wegwerfen: Er dreht sich im Bogen davon und verblasst.
    private func toss(_ now: CFTimeInterval) {
        guard let hat = worn else { return }
        worn = nil
        let w = CGFloat(ClawdSprite.columns) * px
        let from = CGPoint(x: hatOrigin.x + w / 2, y: hatOrigin.y + 3 * px)
        let to = CGPoint(x: from.x - c.facing * 45 * px, y: c.groundY + 2 * px)
        tossed = (hat, BallArc(from: from, to: to, start: now, duration: 0.7, arc: 18 * px), c.facing)
    }

    private func updateTossedHat(_ now: CFTimeInterval) {
        guard let (hat, arc, facing) = tossed else { return }
        let p = arc.progress(now)
        guard p < 1 else {
            hideEffect("tossed")
            tossed = nil
            return
        }
        showRotated("tossed", hat.frame, center: arc.position(now), scale: px / 2, angle: CGFloat(p) * 2 * .pi * facing)
    }
}
