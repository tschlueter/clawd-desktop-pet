import AppKit

// MARK: - Büro

/// Drucker-Stau: zwei Blätter, dann blinkt es rot – rütteln, treten, Papierflut.
final class PrinterJob: Job {
    override class var name: String { "printer" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var dir: CGFloat = 1

    private func drawPrinter(jammed: Bool, shake: CGFloat = 0, now: CFTimeInterval) {
        let s = px
        let frame = ClawdSprite.printer(lightOn: Int(now / 0.25) % 2 == 0, jammed: jammed)
        let x = c.center + dir * 9 * px + shake * px - (dir < 0 ? CGFloat(frame[0].count) * s : 0)
        showEffect("printer", frame, origin: CGPoint(x: x, y: c.groundY), scale: s)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") { dir = c.facing }
            // Zwei Blätter kommen heraus
            drawPrinter(jammed: false, now: now)
            for i in 0..<2 where t >= Double(i) * 0.9 {
                if once("print\(i)") { c.say(.print) }
            }
            let sheet = t.truncatingRemainder(dividingBy: 0.9) / 0.9
            let sx = c.center + dir * (13 + CGFloat(sheet) * 3) * px
            showEffect("sheet", ClawdSprite.paperSheet, origin: CGPoint(x: sx, y: c.groundY + 3 * px * (1 - CGFloat(sheet))), scale: px * 0.6)
            pose = Encounter.Pose(sprite: ClawdSprite.stand)
            if t >= 1.8 {
                hideEffect("sheet")
                next(now)
            }
        case 1:
            // Stau! Rot blinkt, Clawd wartet, wird ungeduldig
            drawPrinter(jammed: true, now: now)
            if once("beep") { c.say(.alarm) }
            pose = Encounter.Pose(sprite: t < 1.0 ? ClawdSprite.lookCycle[Int(t / 0.3) % 4] : ClawdSprite.angryStand)
            if t >= 1.6 { next(now) }
        case 2:
            // Rütteln …
            let shake: CGFloat = Int(t / 0.08) % 2 == 0 ? 0.5 : -0.5
            drawPrinter(jammed: true, shake: shake, now: now)
            pose = Encounter.Pose(sprite: ClawdSprite.scold[Int(t / 0.1) % 2])
            if t >= 1.0 { next(now) }
        case 3:
            // … und ein Tritt!
            drawPrinter(jammed: true, shake: t < 0.2 ? 1 : 0, now: now)
            pose = Encounter.Pose(sprite: t < 0.3 ? ClawdSprite.squash : ClawdSprite.flail)
            if once("kick") { c.say(.wallPock) }
            if t >= 0.5 { next(now) }
        case 4:
            // Papierflut
            drawPrinter(jammed: false, now: now)
            if once("flood") { c.say(.print); c.say(oneOf: [.eep, .oiExcited, .weeh]) }
            pose = Encounter.Pose(sprite: ClawdSprite.flail, particles: .paper)
            if t >= 1.6 { next(now) }
        default:
            drawPrinter(jammed: false, now: now)
            pose = Encounter.Pose(sprite: ClawdSprite.stand, particles: .sweat)
            if t >= 1.2 { finish() }
        }
    }
}

/// Post-its kleben: entlang der Fensterkante bunte Zettel ankleben, zurücktreten, nicken.
final class PostitJob: Job {
    override class var name: String { "postits" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard case .window = c.surfaceKind, let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 100
    }

    private var dir: CGFloat = 1
    private var placed = 0
    private var nextAt: CGFloat = 0
    private var pauseUntil: CFTimeInterval = 0
    private var distance: CGFloat = 0
    private let colors: [Character] = ["3", "1", "2", "v", "3"]

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
                if let r = c.centerRange {
                    distance = min(dir > 0 ? r.upperBound - c.center : c.center - r.lowerBound, 110)
                }
            }
            if now < pauseUntil {
                pose = Encounter.Pose(sprite: ClawdSprite.sit)
            } else if walked >= nextAt, placed < colors.count {
                // Zettel vorne unterhalb der Kante ankleben
                let note = ClawdSprite.postit(colors[placed])
                let x = c.center + dir * 9 * px - 1.5 * px * 0.9
                showEffect("note\(placed)", note, origin: CGPoint(x: x, y: c.groundY - 4 * px), scale: px * 0.9)
                c.say(.pock)
                placed += 1
                nextAt = walked + 20
                pauseUntil = now + 0.5
            } else {
                let step = c.walkSpeed * 0.6 * CGFloat(dt)
                c.moveCenter(to: c.center + dir * step)
                walked += step
                pose = Encounter.Pose(sprite: walkFrame())
            }
            if placed >= colors.count || walked >= distance { next(now) }
        case 1:
            // Zurücktreten und betrachten
            pose = Encounter.Pose(sprite: t < 1.0 ? ClawdSprite.lookCycle[Int(t / 0.35) % 4] : ClawdSprite.sitNod)
            if t >= 1.6 { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("done"), c.isChatty { c.say(.happy) }
            if t >= 0.8 {
                for i in 0..<placed { leaveBehind("note\(i)", lifetime: 40) }
                finish()
            }
        }
    }
}

/// Stempeln: Blatt für Blatt einen Stempel drauf – zum Schluss ein grünes Häkchen ("Approved").
final class StampJob: Job {
    override class var name: String { "stamp" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var dir: CGFloat = 1

    private func drawStack(stamped: Bool) {
        let s = px * 0.8
        let frame = ClawdSprite.paperStack(stamped: stamped)
        let w = CGFloat(frame[0].count) * s
        showEffect("stack", frame, origin: CGPoint(x: c.center + dir * 10 * px - w / 2, y: c.groundY), scale: s)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") { dir = c.facing }
            let cycle = Int(t / 0.7)
            let down = t.truncatingRemainder(dividingBy: 0.7) >= 0.45
            if down, once("stamp\(cycle)") { c.say(.wallPock) }
            drawStack(stamped: down || t.truncatingRemainder(dividingBy: 0.7) < 0.15)
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.rubberStamp(down: down))
            if t >= 3.5 { next(now) }
        default:
            drawStack(stamped: true)
            showAboveHead("ok", ClawdSprite.checkGlyph, opacity: Float(sin(.pi * min(t / 1.4, 1))))
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("approved") { c.say(.happy) }
            if t >= 1.4 { finish() }
        }
    }
}

/// Pomodoro: tippen, bis der Tomaten-Wecker klingelt – dann strecken und kurz Pause.
final class PomodoroJob: Job {
    override class var name: String { "pomodoro" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var dir: CGFloat = 1

    private func drawTimer(shake: CGFloat = 0) {
        let s = px * 0.8
        let w = CGFloat(ClawdSprite.tomatoTimer[0].count) * s
        // Hinter Clawd (gegen die Blickrichtung)
        showEffect("timer", ClawdSprite.tomatoTimer,
                   origin: CGPoint(x: c.center - dir * 10 * px - w / 2 + shake * px, y: c.groundY), scale: s)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") { dir = c.facing }
            drawTimer()
            pose = Encounter.Pose(sprite: ClawdSprite.codeType[Int(t / 0.12) % 2], particles: .code)
            if t >= 5.0 { next(now) }
        case 1:
            // Riiing!
            drawTimer(shake: Int(t / 0.06) % 2 == 0 ? 0.4 : -0.4)
            if once("ding") { c.say(.ding) }
            pose = Encounter.Pose(sprite: ClawdSprite.flail, lift: t < 0.3 ? 1 : 0)
            if t >= 1.0 { next(now) }
        case 2:
            // Strecken
            drawTimer()
            pose = Encounter.Pose(sprite: ClawdSprite.yawnStretch, lift: 1)
            if t >= 1.0 { next(now) }
        default:
            // Kurz entspannen
            drawTimer()
            pose = Encounter.Pose(sprite: ClawdSprite.musicGroove[0])
            if once("ahh"), c.isChatty { c.say(.happy) }
            if t >= 1.8 { finish() }
        }
    }
}
