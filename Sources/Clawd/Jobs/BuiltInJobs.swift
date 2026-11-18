import AppKit

// Eingebaute Beschäftigungen, die der Controller aus Bedürfnissen heraus startet (Hunger,
// Langeweile) oder mit eigener Gewichtung auswählt. Sie stehen nicht in `Jobs.all`, damit sie
// nicht zusätzlich im zufälligen Arbeits-Pool landen.

// MARK: - Essen

/// Nudeln essen. Pro Bissen: eintauchen → hochheben → schlürfen → kauen; danach zufrieden.
final class EatingJob: Job {
    override class var name: String { "eat" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil && !c.isOnWall }

    private let biteDuration: TimeInterval = 2.4
    private let bites = 4
    private let start = CACurrentMediaTime()
    private var lastSound = -1

    private struct Moment {
        var bite: Int
        var pose: ClawdSprite.EatPose
        var slurpStep: Int
        var local: TimeInterval
        var level: Int
        var finished: Bool
        var done: Bool
    }

    /// Wo im Essensablauf sind wir?
    private func moment(_ now: CFTimeInterval) -> Moment {
        let t = now - start
        let bite = Int(t / biteDuration)
        if bite >= bites {
            let after = t - Double(bites) * biteDuration
            return Moment(bite: bites, pose: .chew, slurpStep: 0, local: after, level: 0, finished: true, done: after > 1.2)
        }
        let local = t - Double(bite) * biteDuration
        let pose: ClawdSprite.EatPose
        var slurpStep = 0
        switch local {
        case ..<0.4: pose = .dip
        case ..<1.0: pose = .lift
        case ..<1.45:
            pose = .slurp
            slurpStep = Int((local - 1.0) / 0.15)
        default: pose = .chew
        }
        let level = bites - bite - (pose == .dip ? 0 : 1)
        return Moment(bite: bite, pose: pose, slurpStep: slurpStep, local: local, level: level, finished: false, done: false)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let m = moment(now)
        if m.done {
            c.satisfy(.hunger)
            finish()
            return
        }

        if m.pose == .chew {
            // Kauen: glücklich, im Takt wippend
            let i = m.finished ? 0 : Int(m.local / 0.2) % ClawdSprite.musicGroove.count
            pose = Encounter.Pose(sprite: ClawdSprite.musicGroove[i])
        } else {
            pose = Encounter.Pose(sprite: ClawdSprite.sit, blinkSprite: ClawdSprite.sitBlink)
        }
        pose.prop = ClawdSprite.noodleBowl(level: max(m.level, 0), pose: m.pose, slurpStep: m.slurpStep)
        if m.level > 0 { pose.particles = .steam }

        // Laute einmal pro Abschnitt
        let marker = m.finished ? 999 : m.bite * 4 + (m.pose == .slurp ? 1 : m.pose == .chew ? 2 : 0)
        guard marker != lastSound else { return }
        lastSound = marker
        // Wortkarg schmatzt nur ab und zu, Plappermaul bei jedem Bissen.
        if m.finished {
            c.sayNowAndThen(.happy)
        } else if m.pose == .slurp {
            c.sayNowAndThen(.slurp)
        } else if m.pose == .chew {
            c.sayNowAndThen(.munch)
        }
    }
}

// MARK: - Fegen

/// Auf dem Dock fegen: Staub zusammenkehren, aufs Kehrblech schieben, zum Papierkorb tragen
/// und auskippen – manchmal kitzelt der Staub danach in der Nase.
final class SweepingJob: Job {
    override class var name: String { "sweep" }
    override class func isPossible(_ c: PetController) -> Bool {
        c.surfaceKind == .dock && c.world.trash != nil
    }

    private var dir: CGFloat = 1
    private var distance: CGFloat = 0
    private var swept: CGFloat = 0
    private var lastStroke = -1

    private var strokeLength: CGFloat { ClawdSprite.stepLength * px / 4 }

    /// Wo Clawd stehen muss, damit das Kehrblech über dem Papierkorb hängt.
    private var trashTargetX: CGFloat? {
        guard let trash = world.trash else { return nil }
        let toTrash: CGFloat = trash.midX > c.center ? 1 : -1
        let x = trash.midX - toTrash * 8.5 * px
        let d = world.dock
        return min(max(x, d.minX + c.spriteWidth / 2), d.maxX - c.spriteWidth / 2)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Weit weg vom Papierkorb: in seine Richtung fegen; nah dran: erst von ihm weg.
            if once("setup") {
                guard let trash = world.trash else { finish(); return }
                let toTrash: CGFloat = trash.midX > c.center ? 1 : -1
                dir = abs(trash.midX - c.center) > 260 ? toTrash : -toTrash
                distance = .random(in: 120...220)
            }
            // Langsam fegen; der Staubhaufen wächst.
            let step = c.walkSpeed * 0.5 * CGFloat(dt)
            c.face(dir)
            c.moveCenter(to: c.center + dir * step)
            swept += step
            let stroke = Int(swept / strokeLength)
            if stroke != lastStroke, stroke % 2 == 0 { c.say(.swish) }
            lastStroke = stroke
            pose = Encounter.Pose(sprite: ClawdSprite.walkCycle[stroke % ClawdSprite.walkCycle.count],
                                  prop: ClawdSprite.broom(forward: stroke % 2 == 0), particles: .dust,
                                  dustPile: min(3, 1 + Int(swept / max(distance / 3, 1))))
            let atEdge = c.centerRange.map { c.center <= $0.lowerBound || c.center >= $0.upperBound } ?? true
            if swept >= distance || atEdge {
                c.trace("putzen: zusammenschieben x: \(Int(c.center))")
                next(now)
            }
        case 1:
            // Kehrblech am Boden, Haufen wird Stück für Stück hineingeschoben.
            let pile = max(0, 3 - Int(t / 0.4))
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.dustpan(.ground, full: pile < 3),
                                  dustPile: pile, blinkSprite: ClawdSprite.blink)
            if t >= 1.6 { next(now) }
        case 2:
            // Zügig zum Papierkorb tragen.
            guard let target = trashTargetX else { finish(); return }
            let (arrived, distance) = c.step(toward: target, speed: 1.6, dt: dt)
            walked += distance
            pose = Encounter.Pose(sprite: walkFrame(stride: 1.3), prop: ClawdSprite.dustpan(.carry, full: true))
            if arrived {
                // Zum Papierkorb schauen, dann auskippen.
                if let trash = world.trash { c.face(trash.midX - c.center) }
                c.say(.pour)
                c.trace("putzen: auskippen x: \(Int(c.center)) papierkorb: \(Int(world.trash?.midX ?? -1))")
                next(now)
            }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.dustpan(.tilt, full: t < 0.9),
                                  particles: t < 1.0 ? .dustFall : .none)
            if t >= 1.3 {
                let sneeze = Double.random(in: 0..<1) < 0.35 // der Staub kitzelt in der Nase
                if !sneeze, c.chatty(0.8) { c.say(.happy) }
                finish()
                if sneeze { c.startEmote(.sneeze) }
            }
        }
    }
}

// MARK: - Tennis

/// Tennis gegen eine Wand (Bildschirmrand oder Fensterkante) – eine der Beschäftigungen gegen die Langeweile.
/// Mit Abwechslung: flacher Drive, hoher Lob oder Sprung-Schmetterball; manchmal daneben.
final class TennisJob: Job {
    override class var name: String { "tennis" }
    override class func isPossible(_ c: PetController) -> Bool { !c.isOnWall && wall(for: c) != nil }

    /// Nächste senkrechte Wand in Spielweite: Bildschirmrand oder sichtbare Seitenkante eines Fensters.
    static func wall(for c: PetController) -> CGFloat? {
        let world = c.world
        let ballY = c.groundY + ClawdSprite.racketHitOffset.y * c.px
        var walls: [CGFloat] = []
        if let s = world.screen(containingX: c.center) { walls += [s.frame.minX, s.frame.maxX] }
        for (id, f) in world.windowFrames {
            if case .window(let standingOn) = c.surfaceKind, standingOn == id { continue }
            guard f.minY < ballY, f.maxY > ballY + 8 else { continue }
            // Nur sichtbare Fensterkanten – nicht hinter einem davorliegenden Fenster.
            if f.minX > c.center, world.isEdgeVisible(id, at: CGPoint(x: f.minX, y: ballY)) { walls.append(f.minX) }
            if f.maxX < c.center, world.isEdgeVisible(id, at: CGPoint(x: f.maxX, y: ballY)) { walls.append(f.maxX) }
        }
        return walls
            .filter { abs($0 - c.center) >= 100 && abs($0 - c.center) <= 1000 }
            .min { abs($0 - c.center) < abs($1 - c.center) }
    }

    private struct Flight {
        var path: BallArc
        var towardWall: Bool
        var miss: Bool
    }

    private enum Ball {
        case waiting(until: CFTimeInterval)
        case flying(Flight)
        case bouncing(BouncingBall)
    }

    private var wallX: CGFloat = 0
    private var endAt: CFTimeInterval = 0
    private var ball: Ball = .waiting(until: 0)
    private var swingUntil: CFTimeInterval = 0
    private var swingQueued = false
    private var smashUntil: CFTimeInterval = 0
    /// Nach dem Sprung-Schmetterball noch nicht gelandet.
    private var smashAirborne = false
    private var lookBackUntil: CFTimeInterval = 0

    /// Bogen über eine Strecke: Flugzeit und Scheitelhöhe (über der geraden Linie) wachsen mit ihr.
    /// Lob = höher und langsamer, sonst ein Drive im mittleren Bogen.
    static func arcShape(distance: CGFloat, lob: Bool) -> (duration: TimeInterval, arc: CGFloat) {
        let d = Double(distance)
        if lob {
            return (min(max(d / .random(in: 260...340), 1.0), 2.4), min(distance * .random(in: 0.35...0.5) + 30, 260))
        }
        return (min(max(d / .random(in: 380...480), 0.6), 1.8), min(distance * .random(in: 0.18...0.28) + 20, 180))
    }

    /// Kantenlänge des gezeichneten Balls.
    private var ballSize: CGFloat { CGFloat(ClawdSprite.ball.count) * ballScale }
    private var ballScale: CGFloat { px * ClawdSprite.ballScale }

    private var hitPoint: CGPoint {
        CGPoint(x: c.center + c.facing * ClawdSprite.racketHitOffset.x * px,
                y: c.groundY + ClawdSprite.racketHitOffset.y * px)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        if once("setup") {
            guard let wall = Self.wall(for: c) else { finish(); return }
            wallX = wall
            c.face(wall - c.center)
            ball = .waiting(until: now + 0.8)
            endAt = now + .random(in: 15...30)
        }
        if now >= endAt {
            finish()
            return
        }
        stepBall(now: now, dt: dt)
        if smashAirborne, now >= smashUntil {
            smashAirborne = false
            c.playLanding()
        }
        pose = Encounter.Pose(sprite: now < lookBackUntil ? ClawdSprite.lookCycle[3] : ClawdSprite.stand,
                              prop: ClawdSprite.racket(now < swingUntil ? .swing : .ready),
                              lift: now < smashUntil ? 2 : 0, sporty: true)
        drawBall(now: now)
    }

    /// Schlag Richtung Wand.
    private func strike(now: CFTimeInterval) {
        c.say(.pock)
        swingUntil = now + 0.18
        swingQueued = true
        let from = hitPoint
        // Der Ball trifft die Wand etwas oberhalb der Schlaghöhe – wie nach einem echten Bogen.
        let to = CGPoint(x: wallX - c.facing * ballSize / 2, y: from.y + .random(in: 10...40))
        let distance = abs(to.x - from.x)
        let roll = Double.random(in: 0..<1)
        var path = BallArc(from: from, to: to, start: now, duration: 0, arc: 0)
        if roll < 0.12 {
            smashUntil = now + 0.3 // Schmetterball mit Sprung: schnell und flacher
            smashAirborne = true
            path.duration = max(Double(distance) / 900, 0.35)
            path.arc = min(distance * 0.08 + 10, 60)
        } else {
            (path.duration, path.arc) = Self.arcShape(distance: distance, lob: roll < 0.4)
        }
        ball = .flying(Flight(path: path, towardWall: true, miss: false))
        let shot = roll < 0.12 ? "Schmetterball" : roll < 0.4 ? "Lob" : "Drive"
        c.trace("ball: Schlag \(shot) von \(Int(from.x)) zur Wand \(Int(wallX)) " + String(format: "%.2fs", path.duration))
    }

    /// Rückweg von der Wand zu Clawd; manchmal verfehlt er.
    private func bounceBack(now: CFTimeInterval, from: CGPoint) {
        c.say(.wallPock)
        swingQueued = false
        let miss = Double.random(in: 0..<1) < 0.12
        let target = miss
            ? CGPoint(x: c.center - c.facing * (c.spriteWidth / 2 + 40), y: c.groundY + px)
            : hitPoint
        var path = BallArc(from: from, to: target, start: now, duration: 0, arc: 0)
        (path.duration, path.arc) = Self.arcShape(distance: abs(target.x - from.x), lob: Double.random(in: 0..<1) < 0.3)
        ball = .flying(Flight(path: path, towardWall: false, miss: miss))
        c.trace("ball: Wand " + (miss ? "→ daneben" : "→ zurück"))
    }

    private func stepBall(now: CFTimeInterval, dt: TimeInterval) {
        switch ball {
        case .waiting(let until):
            if now >= until { strike(now: now) }
        case .flying(let f):
            let p = f.path.progress(now)
            // Kurz vor dem Eintreffen ausholen
            if !f.towardWall, !f.miss, !swingQueued, f.path.duration * (1 - p) < 0.1 {
                swingUntil = now + 0.2
                swingQueued = true
            }
            guard p >= 1 else { return }
            if f.towardWall {
                bounceBack(now: now, from: f.path.to)
            } else if f.miss {
                // Daneben: Ball hüpft hinter Clawd weg, er schaut ihm nach.
                lookBackUntil = now + 1.4
                if c.chatty(0.6) { c.say(.murmur) }
                ball = .bouncing(BouncingBall(pos: f.path.to, vel: CGVector(dx: -c.facing * 90, dy: 120), until: now + 1.6))
            } else {
                strike(now: now)
            }
        case .bouncing(var b):
            b.step(dt: dt, floor: c.groundY)
            ball = now >= b.until ? .waiting(until: now + 0.6) : .bouncing(b)
        }
    }

    private func drawBall(now: CFTimeInterval) {
        let position: CGPoint?
        switch ball {
        case .waiting: position = nil
        case .flying(let f): position = f.path.position(now)
        case .bouncing(let b): position = b.pos
        }
        guard let position else {
            hideEffect("ball")
            return
        }
        showEffect("ball", ClawdSprite.ball, origin: CGPoint(x: position.x - ballSize / 2, y: position.y - ballSize / 2),
                   scale: ballScale, shadow: true)
    }
}
