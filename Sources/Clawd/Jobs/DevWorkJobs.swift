import AppKit

// MARK: - Entwickler-Jobs 2

/// Rubber-Duck-Debugging: am Laptop der Ente das Problem erklären, sie quietscht – bis die Idee kommt.
final class RubberDuckJob: Job {
    override class var name: String { "duck" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Erklären (Clawd) und Quietschen (Ente) im Wechsel
            let turn = Int(t / 1.1)
            let clawdTalks = turn % 2 == 0
            if clawdTalks, once("talk\(turn)"), c.isChatty { c.say(.murmur) }
            if !clawdTalks, once("squeak\(turn)") { c.say(.squeak) }
            let bob = !clawdTalks && t.truncatingRemainder(dividingBy: 1.1) < 0.3
            pose = Encounter.Pose(sprite: clawdTalks ? ClawdSprite.sit : ClawdSprite.sitRead,
                                  prop: ClawdSprite.rubberDuck(bob: bob), bubble: clawdTalks, laptop: true)
            if t >= 4.4 { next(now) }
        case 1:
            // Moment mal …
            pose = Encounter.Pose(sprite: [ClawdSprite.sit, ClawdSprite.sitRead, ClawdSprite.sit, ClawdSprite.sitBlink][Int(t / 0.4) % 4],
                                  prop: ClawdSprite.rubberDuck(bob: false), laptop: true)
            showAboveHead("idea", ClawdSprite.questionGlyph)
            if t >= 1.2 { next(now) }
        default:
            // Aha!
            pose = Encounter.Pose(sprite: ClawdSprite.musicGroove[Int(t / 0.25) % 2],
                                  prop: ClawdSprite.rubberDuck(bob: Int(t / 0.2) % 2 == 0), laptop: true)
            showAboveHead("idea", ClawdSprite.lightbulbGlyph)
            if once("aha") { c.say(.happy) }
            if t >= 1.4 { finish() }
        }
    }
}

/// Deploy-Rakete: Commits einladen, Countdown, Start – die Rakete fliegt aus dem Bildschirm.
final class DeployRocketJob: Job {
    override class var name: String { "deploy" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var dir: CGFloat = 1
    private var rocketX: CGFloat = 0
    private var rocketY: CGFloat = 0

    private func drawRocket(flames: Bool, now: CFTimeInterval) {
        let s = px * 0.9
        let w = CGFloat(ClawdSprite.rocket[0].count) * s
        showEffect("rocket", ClawdSprite.rocket, origin: CGPoint(x: rocketX - w / 2, y: rocketY), scale: s,
                   shadow: true)
        if flames {
            let f = ClawdSprite.rocketFlames[Int(now / 0.08) % 2]
            showEffect("flame", f, origin: CGPoint(x: rocketX - CGFloat(f[0].count) * s / 2, y: rocketY - 3 * s), scale: s)
        }
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = c.facing
                rocketX = c.center + dir * 13 * px
                rocketY = c.groundY
            }
            drawRocket(flames: false, now: now)
            // Drei Commits einladen: hinten holen, vorne einladen
            let load = Int(t / 1.0)
            let local = t.truncatingRemainder(dividingBy: 1.0)
            c.face(local < 0.4 ? -dir : dir)
            pose = Encounter.Pose(sprite: local < 0.4 ? ClawdSprite.sit : ClawdSprite.wave[1])
            if local >= 0.4, local < 0.9 {
                let p = CGFloat((local - 0.4) / 0.5)
                let from = c.center, to = rocketX
                showEffect("commit", ClawdSprite.commitBox,
                           origin: CGPoint(x: from + (to - from) * p - px, y: c.groundY + (4 + 4 * sin(.pi * p)) * px), scale: px)
            } else {
                hideEffect("commit")
            }
            if local >= 0.9, once("loaded\(load)") { c.say(.wallPock) }
            if t >= 3.0 {
                c.face(dir)
                next(now)
            }
        case 1:
            // Countdown 3 – 2 – 1
            drawRocket(flames: false, now: now)
            let n = 3 - Int(t / 0.7)
            if n >= 1 {
                showAboveHead("count", ClawdSprite.digits[n - 1])
                if once("beep\(n)") { c.say(.beep) }
            }
            pose = Encounter.Pose(sprite: ClawdSprite.wave[1])
            if t >= 2.1 {
                hideEffect("count")
                next(now)
            }
        case 2:
            // Liftoff!
            if once("launch") { c.say(.launch) }
            let p = CGFloat(t)
            rocketY = c.groundY + 40 * p * p * p + 20 * p
            drawRocket(flames: true, now: now)
            pose = Encounter.Pose(sprite: ClawdSprite.flail, lift: t < 0.5 ? 1 : 0)
            if t >= 2.2 {
                hideEffect("rocket")
                hideEffect("flame")
                next(now)
            }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("yay") { c.say(.happy) }
            if t >= 1.0 { finish() }
        }
    }
}

/// Tests werden grün: Kästchen springen eins nach dem anderen von Rot auf Grün; zum Schluss Konfetti.
final class TestsGreenJob: Job {
    override class var name: String { "tests" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private func drawPanel(green: Int, now: CFTimeInterval) {
        let frame = ClawdSprite.testPanel(green: green, blinkOn: Int(now / 0.3) % 2 == 0)
        let s = px * 0.7
        let w = CGFloat(frame[0].count) * s
        showEffect("panel", frame, origin: CGPoint(x: c.center - w / 2, y: c.groundY + 10 * px), scale: s)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Tippen; alle 0,7 s wird ein Test grün – der letzte hakt
            let green = min(Int(t / 0.7), 5)
            if green > 0, once("g\(green)") { c.say(.pock) }
            drawPanel(green: green, now: now)
            let typing = ClawdSprite.codeType[Int(t / 0.12) % 2]
            pose = Encounter.Pose(sprite: typing, particles: .code)
            if t >= 3.8 { next(now) }
        case 1:
            // Der letzte bleibt rot … grummel, nochmal ran
            drawPanel(green: 5, now: now)
            pose = Encounter.Pose(sprite: t < 0.8 ? ClawdSprite.angryStand : ClawdSprite.codeType[Int(t / 0.08) % 2])
            if once("grr"), c.isChatty { c.say(.murmur) }
            if t >= 1.8 { next(now) }
        default:
            // Alles grün!
            drawPanel(green: 6, now: now)
            if once("green") { c.say(.happy) }
            pose = Encounter.Pose(sprite: Int(t / 0.25) % 2 == 0 ? ClawdSprite.flail : ClawdSprite.happyStand,
                                  particles: .confetti, lift: Int(t / 0.25) % 2 == 0 ? 1 : 0)
            if t >= 2.0 { finish() }
        }
    }
}

/// Feuer in Produktion: Flammen auf dem Server-Rack, Alarm – Clawd holt den Feuerlöscher.
final class FireJob: Job {
    override class var name: String { "fire" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var dir: CGFloat = 1
    private var rackX: CGFloat = 0
    private var flames: CGFloat = 1 // 1 = lichterloh, 0 = gelöscht

    private func drawRack(ok: Bool, now: CFTimeInterval) {
        let s = px * 0.9
        let rack = ClawdSprite.miniRack(ok: ok, blinkOn: Int(now / 0.2) % 2 == 0)
        showEffect("rack", rack, origin: CGPoint(x: rackX - 2 * s, y: c.groundY), scale: s)
        if flames > 0.05 {
            let f = ClawdSprite.flameFrames[Int(now / 0.1) % 2]
            showEffect("fire", f, origin: CGPoint(x: rackX - 3 * s * 0.8, y: c.groundY + 9 * s), scale: s * 0.8,
                       opacity: Float(flames))
        } else {
            hideEffect("fire")
        }
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = c.facing
                rackX = c.center + dir * 14 * px
            }
            // Alarm! Erschrecken
            drawRack(ok: false, now: now)
            if once("alarm1") { c.say(.alarm) }
            if t >= 0.9, once("alarm2") { c.say(.alarm) }
            pose = Encounter.Pose(sprite: t < 0.5 ? ClawdSprite.flail : ClawdSprite.angryStand)
            if t >= 1.4 { next(now) }
        case 1:
            // Kurz weg, Feuerlöscher holen
            drawRack(ok: false, now: now)
            c.face(-dir)
            pose = Encounter.Pose(sprite: walkFrame(stride: 1.4))
            walked += c.walkSpeed * 2 * CGFloat(dt)
            if t >= 0.6 {
                c.face(dir)
                next(now)
            }
        case 2:
            // Löschen
            drawRack(ok: false, now: now)
            if once("spray") { c.say(.pour) }
            flames = max(0, 1 - CGFloat(t / 2.2))
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.extinguisher, particles: .foam)
            if t >= 2.4 { next(now) }
        default:
            drawRack(ok: true, now: now)
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, particles: .sweat)
            if t >= 1.4 { finish() }
        }
    }
}
