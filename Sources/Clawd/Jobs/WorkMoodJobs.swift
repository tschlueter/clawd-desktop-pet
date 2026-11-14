import AppKit

// MARK: - Arbeits-Stimmungen

/// Deadline-Panik: Kalender mit rotem Kreis, tickende Uhr – hektisch hin und her, dann wild tippen.
final class DeadlinePanicJob: Job {
    override class var name: String { "deadline" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 100
    }

    private var home: CGFloat = 0
    private var dir: CGFloat = 1

    private func drawSigns(_ now: CFTimeInterval) {
        let s = px * 0.7
        showEffect("cal", ClawdSprite.calendar, origin: CGPoint(x: home - 9 * s, y: c.groundY + 11 * px), scale: s)
        showEffect("clock", ClawdSprite.clockFrames[Int(now / 0.5) % 2], origin: CGPoint(x: home + 2 * s, y: c.groundY + 11 * px), scale: s)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                home = c.center
                dir = roomierDirection()
                c.say(oneOf: Voice.Sound.fluster)
            }
            drawSigns(now)
            if Int(t / 0.5) != Int((t - dt) / 0.5) { c.say(.wallPock) } // Ticken
            // Hektisch hin und her
            let target = home + (Int(t / 0.9) % 2 == 0 ? dir : -dir) * 30
            walk(to: target, speed: 2.6, dt: dt)
            pose = Encounter.Pose(sprite: walkFrame(stride: 1.5), particles: .sweat)
            if once("panic"), c.isChatty { c.say(.scold) }
            if t >= 3.6 { next(now) }
        case 1:
            // Wild tippen
            drawSigns(now)
            walk(to: home, speed: 2, dt: dt)
            pose = Encounter.Pose(sprite: ClawdSprite.codeType[Int(t / 0.06) % 2], particles: .code, laptop: true)
            if t >= 3.0 { next(now) }
        default:
            hideEffect("cal"); hideEffect("clock")
            pose = Encounter.Pose(sprite: ClawdSprite.squash, particles: .sweat)
            if once("puh") { c.say(oneOf: [.oof, .uff]) }
            if t >= 1.3 { finish() }
        }
    }
}

/// Nachtschicht: unter der Schreibtischlampe tippen, gähnen, kurz wegnicken, hochschrecken, weiter.
final class NightShiftJob: Job {
    override class var name: String { "night" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var dir: CGFloat = 1

    private func drawDesk() {
        let s = px * 0.9
        showEffect("lamp", ClawdSprite.deskLamp, origin: CGPoint(x: c.center - dir * 11 * px - 3 * s, y: c.groundY), scale: s)
        showEffect("mug", ClawdSprite.mugSmall, origin: CGPoint(x: c.center + dir * 9 * px - 2 * s, y: c.groundY), scale: s * 0.8)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") { dir = c.facing }
            drawDesk()
            pose = Encounter.Pose(sprite: ClawdSprite.codeType[Int(t / 0.15) % 2], particles: .code, laptop: true)
            if t >= 2.5 { next(now) }
        case 1:
            // Gähnen
            drawDesk()
            if once("yawn") { c.say(.yawn) }
            pose = Encounter.Pose(sprite: t < 1.6 ? ClawdSprite.yawnMouth : ClawdSprite.sitBlink, lift: t < 1.6 ? 1 : 0)
            if t >= 2.0 { next(now) }
        case 2:
            // Wegnicken …
            drawDesk()
            pose = Encounter.Pose(sprite: ClawdSprite.sleep, particles: .zzz, laptop: true)
            if t >= 1.0, once("snore") { c.say(.snore) }
            if t >= 2.2 { next(now) }
        case 3:
            // … hochschrecken!
            drawDesk()
            if once("jolt") { c.say(oneOf: Voice.Sound.startled) }
            pose = Encounter.Pose(sprite: ClawdSprite.flail, lift: t < 0.3 ? 2 : 0)
            if t >= 0.6 { next(now) }
        default:
            // Weiter geht's
            drawDesk()
            pose = Encounter.Pose(sprite: ClawdSprite.codeType[Int(t / 0.15) % 2], particles: .code, laptop: true)
            if t >= 2.0 { finish() }
        }
    }
}

/// Kabelsalat entwirren: vor einem Kabelberg kräftig zerren – Kabel fliegen durch die Luft,
/// der Berg schrumpft –, dann zufrieden nicken.
final class CablesJob: Job {
    override class var name: String { "cables" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var dir: CGFloat = 1

    /// Kabelberg vor Clawd (Variante D), wird mit `stage` kleiner.
    private func drawMountain(_ stage: Int, jitter: CGFloat) {
        let s = px / 2
        let f = ClawdSprite.cableMountain(stage: stage)
        let w = CGFloat(f[0].count) * s
        let x = dir > 0 ? c.center + 6 * px : c.center - 6 * px - w
        showEffect("cables", f, origin: CGPoint(x: x + jitter * px * 0.5, y: c.groundY), scale: s, mirrored: dir < 0)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0, 1:
            if once("setup") { dir = c.facing }
            // Kräftig zerren: lange Kabel und Stecker fliegen durch die Luft
            let beat = Int(t / 0.2)
            let tug = beat % 2 == 0
            if tug, once("tug\(phase)\(beat)") { c.say(beat % 4 == 0 ? .wallPock : .swish) }
            let jitter: CGFloat = tug ? (beat % 4 == 0 ? 1 : -1) : 0
            // Der Berg schrumpft mit jedem Zerren ein Stück
            let total = (phase == 0 ? 0 : 2.6) + t
            drawMountain(min(Int(total / 1.3), 3), jitter: jitter)
            pose = Encounter.Pose(sprite: tug ? ClawdSprite.flail : ClawdSprite.wave[1],
                                  particles: .cables, lift: tug ? 1 : 0)
            if phase == 0, t >= 1.0, once("grr"), c.isChatty { c.say(oneOf: [.scold, .grrr]) }
            if t >= 2.6 { next(now) }
        case 2:
            // Geschafft – zufrieden nicken
            drawMountain(3, jitter: 0)
            pose = Encounter.Pose(sprite: t.truncatingRemainder(dividingBy: 0.6) < 0.25 ? ClawdSprite.sitNod : ClawdSprite.happyStand)
            if once("done") { c.say(.happy) }
            if t >= 1.2 { finish() }
        default:
            finish()
        }
    }
}

/// Ship it: Karton zukleben, "SHIP IT" stempeln, mit Schwung wegkicken.
final class ShipItJob: Job {
    override class var name: String { "shipit" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var dir: CGFloat = 1
    private var boxW: CGFloat { CGFloat(ClawdSprite.box[0].count) * px }
    private var boxOrigin: CGPoint { CGPoint(x: c.center + dir * 10 * px - boxW / 2, y: c.groundY) }
    private var stamped = false

    private var boxFrame: ClawdSprite.Frame {
        stamped ? ["nnUUnn", "nrrrrn", "nrrrrn", "nnnnnn", "nnnnnn"] : ClawdSprite.box
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Zukleben
            if once("setup") { dir = c.facing }
            showEffect("box", boxFrame, origin: boxOrigin, scale: px)
            if once("tape") { c.say(.print) }
            pose = Encounter.Pose(sprite: ClawdSprite.wave[Int(t / 0.2) % 2])
            if t >= 1.4 { next(now) }
        case 1:
            // SHIP IT stempeln
            let down = t >= 0.45
            if down, once("stamp") {
                stamped = true
                c.say(.wallPock)
            }
            showEffect("box", boxFrame, origin: boxOrigin, scale: px)
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.rubberStamp(down: down))
            if t >= 1.0 { next(now) }
        case 2:
            // Ausholen und kicken
            pose = Encounter.Pose(sprite: t < 0.35 ? ClawdSprite.squash : ClawdSprite.flail)
            if t >= 0.35, once("kick") {
                c.say(.wallPock)
                c.say(oneOf: Voice.Sound.cheer)
            }
            let p = CGFloat(max(0, min((t - 0.35) / 1.0, 1)))
            let o = boxOrigin
            showEffect("box", boxFrame, origin: CGPoint(x: o.x + dir * 160 * p, y: o.y + 60 * sin(.pi * p * 0.8) - 120 * p * p), scale: px)
            if t >= 1.4 {
                hideEffect("box")
                next(now)
            }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.wave[Int(t / 0.18) % 2])
            if once("bye"), c.isChatty { c.say(.happy) }
            if t >= 1.0 { finish() }
        }
    }
}
