import AppKit

/// Gemeinsames für die Gaming-Arbeiten: Clawd sitzt mit dem Rücken zum Betrachter, der Bildschirm
/// steht hinter ihm (aus unserer Sicht) – man schaut ihm über die Schulter.
class GamingJob: Job {
    /// Wie weit die Requisiten links und rechts über Clawds Mitte hinausragen (in Clawd-Pixeln).
    class var halfWidth: CGFloat { 13 }
    var s: CGFloat { px / 2 }
    var spot: CGFloat = 0

    class func hasRoom(_ c: PetController) -> Bool {
        guard c.surfaceKind != nil, !c.isOnWall, let r = c.centerRange else { return false }
        // centerRange ist schon um eine halbe Clawd-Breite (7 px) eingerückt.
        return r.upperBound - r.lowerBound >= 2 * (halfWidth - 7) * c.px + 4
    }

    /// Platz suchen, an dem alle Requisiten auf die Fläche passen.
    func chooseSpot() {
        let margin = (Self.halfWidth - 7) * px
        guard let r = c.centerRange else { spot = c.center; return }
        spot = min(max(c.center, r.lowerBound + margin), max(r.lowerBound + margin, r.upperBound - margin))
    }

    func centered(_ frame: ClawdSprite.Frame, bottom: CGFloat) -> CGPoint {
        CGPoint(x: spot - CGFloat(frame[0].count) * s / 2, y: bottom)
    }
}

// MARK: - Konsole

/// Konsolen-Abend von hinten: Clawd versinkt im Sitzsack vor dem Fernseher und spielt ein
/// Jump-'n'-Run – fällt einmal in die Grube, schafft es im zweiten Anlauf und jubelt.
final class ConsoleGamingJob: GamingJob {
    override class var name: String { "console" }
    override class func isPossible(_ c: PetController) -> Bool { hasRoom(c) }

    private func drawSet(_ scene: ClawdSprite.TVScene, bag: Bool = true) {
        let bench = ClawdSprite.tvBench
        showEffect("bench", bench, origin: centered(bench, bottom: c.groundY), scale: s, behind: true)
        let tv = ClawdSprite.gamingTV(scene)
        showEffect("tv", tv, origin: centered(tv, bottom: c.groundY + CGFloat(bench.count) * s), scale: s, behind: true)
        if bag {
            let front = ClawdSprite.beanbagFront
            showEffect("bag", front, origin: centered(front, bottom: c.groundY), scale: s)
        } else {
            hideEffect("bag")
        }
    }

    /// Ein Durchlauf über das Bild: die Figur springt über Plattformen; `fallAt` = an der Grube scheitern.
    private func run(_ t: TimeInterval, duration: TimeInterval, fallAt: Double? = nil) -> (ClawdSprite.TVScene, lean: Int) {
        var x = min(t / duration, 1)
        if let f = fallAt { x = min(x, f) }
        // Sprünge: über die erste Plattform, über die Grube, auf die Münzen.
        let jumps: [(from: Double, to: Double, height: Double)] = [(0.12, 0.3, 7), (0.42, 0.55, 6), (0.62, 0.82, 11)]
        var lift = 0, lean = 0
        for j in jumps where x > j.from && x < j.to {
            let p = (x - j.from) / (j.to - j.from)
            lift = Int((sin(.pi * p) * j.height).rounded())
            lean = p < 0.5 ? 1 : -1 // beim Absprung mitgehen, bei der Landung zurück
        }
        if let f = fallAt, x >= f { lift = 0 }
        return (.run(x: x, lift: lift), lean)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("spot") { chooseSpot() }
            if walk(to: spot, dt: dt) {
                c.face(1)
                next(now)
            } else {
                pose = Encounter.Pose(sprite: walkFrame())
            }
        case 1:
            // Hinsetzen: Fernseher an, plumps in den Sitzsack
            drawSet(.run(x: 0, lift: 0))
            if once("plop") { c.say(.hop) }
            pose = Encounter.Pose(sprite: ClawdSprite.backSit, lift: t < 0.25 ? 3 : 2)
            if t >= 0.8 { next(now) }
        case 2:
            // Erster Versuch – an der Grube daneben gesprungen
            let (scene, lean) = run(t, duration: 4.0, fallAt: 0.45)
            drawSet(scene)
            pose = Encounter.Pose(sprite: ClawdSprite.backLean(lean), lift: 2)
            if lean != 0, once("jump\(Int(t / 0.4))") { c.say(.pock) }
            if t >= 4.0 * 0.45 { next(now) }
        case 3:
            // Leben verloren: Bild blinkt rot, Clawd sackt zusammen
            drawSet(.fail(blink: Int(t / 0.15) % 2 == 0))
            if once("fail") { c.say(.alarm) }
            if t >= 0.4, once("whine") { c.say(oneOf: Voice.Sound.whine) }
            pose = Encounter.Pose(sprite: ClawdSprite.backSag, lift: 2)
            if t >= 1.6 { next(now) }
        case 4:
            // Zweiter Versuch – klappt
            let (scene, lean) = run(t, duration: 4.0)
            drawSet(scene)
            pose = Encounter.Pose(sprite: ClawdSprite.backLean(lean), lift: 2)
            if lean != 0, once("jump\(Int(t / 0.4))") { c.say(.pock) }
            if t >= 4.0 { next(now) }
        case 5:
            // Ziel! Sterne erscheinen, Clawd springt jubelnd auf
            drawSet(.clear(stars: min(Int(t / 0.3) + 1, 3)))
            if once("cheer") { c.say(oneOf: Voice.Sound.cheer) }
            let hop = t < 1.2 ? CGFloat(abs(sin(t * .pi / 0.4))) * 2 : 0
            pose = Encounter.Pose(sprite: ClawdSprite.backCheer, lift: 2 + hop)
            if t >= 1.8 { next(now) }
        default:
            finish()
        }
    }
}

// MARK: - PC

/// PC-Gaming von hinten: Clawd sitzt mit Headset am Schreibtisch, der Monitor zeigt ein Gefecht.
/// Am Ende gewinnt er (meistens) oder verliert und knurrt.
final class PCGamingJob: GamingJob {
    override class var name: String { "pcgame" }
    override class func isPossible(_ c: PetController) -> Bool { hasRoom(c) }
    override class var halfWidth: CGFloat { 15 }

    private lazy var wins = isDemo || Double.random(in: 0..<1) < 0.7
    private var health = 15

    private func drawSet(now: CFTimeInterval, shot: Double?, hit: Bool, result: ClawdSprite.PCResult? = nil) {
        let rgb = Int(now / 0.2)
        let desk = ClawdSprite.gamingDesk
        showEffect("desk", desk, origin: centered(desk, bottom: c.groundY), scale: s, behind: true)
        let deskTop = c.groundY + CGFloat(desk.count) * s
        let monitor = ClawdSprite.gamingMonitor(shot: shot, enemyHit: hit, health: health, result: result)
        showEffect("monitor", monitor, origin: centered(monitor, bottom: deskTop), scale: s, behind: true)
        let keys = ClawdSprite.gamingKeyboard(phase: rgb)
        showEffect("keys", keys, origin: centered(keys, bottom: deskTop), scale: s, behind: true)
        let tower = ClawdSprite.gamingTower(phase: rgb)
        showEffect("tower", tower, origin: CGPoint(x: spot + 25 * s, y: c.groundY), scale: s, behind: true)
        let chair = ClawdSprite.chairFront
        showEffect("chair", chair, origin: centered(chair, bottom: c.groundY + 0.5 * s), scale: s)
    }

    private func sitting(_ frame: ClawdSprite.Frame, lift: CGFloat = 4) -> Encounter.Pose {
        Encounter.Pose(sprite: ClawdSprite.withHeadset(frame), lift: lift)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("spot") { chooseSpot() }
            if walk(to: spot, dt: dt) {
                c.face(1)
                next(now)
            } else {
                pose = Encounter.Pose(sprite: walkFrame())
            }
        case 1:
            drawSet(now: now, shot: nil, hit: false)
            if once("sit") { c.say(.hop) }
            pose = sitting(ClawdSprite.backSit, lift: t < 0.25 ? 5 : 4)
            if t >= 0.8 { next(now) }
        case 2:
            // Gefecht: Schüsse fliegen, der Gegner trifft auch mal zurück
            let cycle = t.truncatingRemainder(dividingBy: 0.9)
            let round = Int(t / 0.9)
            let shot = cycle < 0.5 ? cycle / 0.5 : nil
            let hit = cycle >= 0.5 && cycle < 0.75
            if cycle < 0.05, once("shot\(round)") { c.say(.plop) }
            if hit, once("hit\(round)") {
                c.say(.pock)
                if round % 2 == 1 { health = max(health - (wins ? 2 : 4), 1) } // Gegentreffer
            }
            drawSet(now: now, shot: shot, hit: hit)
            if round % 3 == 1, once("talk\(round)"), c.isChatty { c.say(.murmur) } // ins Headset
            // Wildes Tippen: hin und her
            let lean = Int(t / 0.18) % 4 == 0 ? -1 : (Int(t / 0.18) % 4 == 2 ? 1 : 0)
            pose = sitting(lean == 0 ? ClawdSprite.backSit : ClawdSprite.backLean(lean))
            if t >= 5.4 { next(now) }
        case 3:
            if wins {
                drawSet(now: now, shot: nil, hit: false, result: .victory)
                if once("win") { c.say(oneOf: [.oiExcited, .happy, .uiii]) }
                let hop = t < 1.2 ? CGFloat(abs(sin(t * .pi / 0.4))) * 2 : 0
                pose = sitting(ClawdSprite.backCheer, lift: 4 + hop)
            } else {
                health = 0
                drawSet(now: now, shot: nil, hit: false, result: .defeat)
                if once("lose") { c.say(.grrr) }
                pose = sitting(ClawdSprite.backSag)
            }
            if t >= 1.8 { next(now) }
        default:
            finish()
        }
    }
}
