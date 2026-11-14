import AppKit

/// Zwei Clawds begegnen sich. Die Begegnung steuert beide wie Puppen: Position, Blickrichtung,
/// Pose, Requisiten, Effekte und Laute – Schritt für Schritt in Phasen.
///
/// `a` ist immer der linke, `b` der rechte Clawd. Wird einer der beiden unterbrochen
/// (hochgehoben, angeklickt, Fenster weg), bricht die Begegnung für beide ab.
final class Encounter {
    enum Kind: String, CaseIterable {
        case greeting, highFive, hug, dance, tag, leapfrog, ballPass, bump
        case presentation, pairProgramming, tugOfWar, coffeeBreak
        /// Rollenspielabend: Spielleiter hinter dem Schirm, der andere würfelt.
        case rpgNight
        /// Zauberpanne: verwandelt den anderen versehentlich in Frosch oder Kaninchen.
        case magicMishap
        /// Brief übergeben – startet nur über die Arbeit "Post austragen".
        case mail

        static var randomKinds: [Kind] { allCases.filter { $0 != .mail } }
    }

    /// Wie ein Clawd in diesem Moment aussieht.
    struct Pose {
        var sprite: ClawdSprite.Frame = ClawdSprite.stand
        var prop: ClawdSprite.Frame?
        var particles: ClawdNode.Particles = .none
        var lift: CGFloat = 0
        var bubble = false
        var sporty = false
        var hat: ClawdSprite.Frame?
        var laptop = false
        var headphones = false
        /// Staubhaufen vor Clawd (0 = keiner, 1…3).
        var dustPile = 0
        /// Wird beim Blinzeln statt `sprite` gezeigt.
        var blinkSprite: ClawdSprite.Frame?
    }

    let kind: Kind
    /// Macht diese Begegnung Laute? Einmal für beide ausgewürfelt (siehe `PetController.beginEvent`).
    let audible: Bool
    let a: PetController
    let b: PetController
    private weak var stage: Stage?
    private(set) var finished = false

    private var script: Choreography
    private var phase: Int { script.phase }
    private var lastStep: CFTimeInterval
    private var poses: [ObjectIdentifier: Pose] = [:]
    private var walked: [ObjectIdentifier: CGFloat] = [:]
    private var marks: [ObjectIdentifier: CGFloat] = [:] // gemerkte Positionen (Tanzen, Zusammenstoß)

    // Effekte auf der Bühne
    private let effects: EffectLayers
    private var starUntil: CFTimeInterval = 0
    private var starPoint = CGPoint.zero
    /// Rollenspielabend: was der Würfel zeigt (20 = Volltreffer, 1 = Patzer).
    private let rpgRoll = Bool.random() ? 20 : 1

    // Fangen
    private var chaser: PetController
    private var runDir: CGFloat = 1
    private var tags = 0
    private var lastTag: CFTimeInterval = 0

    // Bocksprung
    private var front: PetController
    private var leapDir: CGFloat = 1
    private var jumps = 0
    private var jumpFrom: CGFloat = 0
    private var jumpTo: CGFloat = 0

    // Ball zuspielen
    private struct Flight {
        var path: BallArc
        var receiver: PetController
        var miss: Bool
    }
    private var flight: Flight?
    private var bounce: BouncingBall?
    private var server: PetController
    private var serveAt: CFTimeInterval = 0
    private var rallyEnd: CFTimeInterval = 0
    private var swingUntil: [ObjectIdentifier: CFTimeInterval] = [:]
    private var lookBackUntil: [ObjectIdentifier: CFTimeInterval] = [:]
    private var anticipated = false
    private var passDistance: CGFloat = 180

    /// Bei "Post austragen": wer den Brief bringt.
    private var courier: PetController?

    init(kind: Kind, _ c1: PetController, _ c2: PetController, stage: Stage, initiator: PetController? = nil) {
        self.kind = kind
        self.courier = initiator
        if c1.center <= c2.center { a = c1; b = c2 } else { a = c2; b = c1 }
        audible = a.rollEventAudible()
        self.stage = stage
        effects = EffectLayers(stage: stage)
        let now = CACurrentMediaTime()
        script = Choreography(now: now)
        lastStep = now
        chaser = a
        front = b
        server = a
        if let r = a.centerRange {
            passDistance = min(max(r.upperBound - r.lowerBound - 4 * a.px, 130), 230)
        }
        a.beginEncounter(self)
        b.beginEncounter(self)
        log("Begegnung: \(kind.rawValue)")
    }

    // MARK: - Ablauf

    func step(now: CFTimeInterval) {
        guard !finished else { return }
        let dt = min(now - lastStep, 0.05)
        lastStep = now
        // Abbruch, wenn einer nicht mehr mitspielt oder sie nicht mehr auf derselben Fläche stehen.
        guard a.inEncounterState, b.inEncounterState, a.surfaceKind != nil, a.surfaceKind == b.surfaceKind else {
            abort()
            return
        }
        let t = script.elapsed(now)
        // Sicherheitsnetz: wer sich nicht erreicht, gibt auf.
        if phase == 0, t > 10 {
            end(now, walkAway: false)
            return
        }
        switch kind {
        case .greeting: greeting(now, t, dt)
        case .highFive: highFive(now, t, dt)
        case .hug: hug(now, t, dt)
        case .dance: dance(now, t, dt)
        case .tag: tag(now, t, dt)
        case .leapfrog: leapfrog(now, t, dt)
        case .ballPass: ballPass(now, t, dt)
        case .bump: bump(now, t, dt)
        case .mail: mail(now, t, dt)
        case .presentation: presentation(now, t, dt)
        case .pairProgramming: pairProgramming(now, t, dt)
        case .tugOfWar: tugOfWar(now, t, dt)
        case .coffeeBreak: coffeeBreak(now, t, dt)
        case .rpgNight: rpgNight(now, t, dt)
        case .magicMishap: magicMishap(now, t, dt)
        }
        updateEffects(now)
    }

    /// Vom Controller in dessen Darstellungsschritt aufgerufen.
    func applyVisuals(to c: PetController, blinking: Bool) {
        c.applyPose(poses[ObjectIdentifier(c)] ?? Pose(), blinking: blinking)
    }

    func abort() {
        guard !finished else { return }
        log("Begegnung abgebrochen")
        finished = true
        removeEffects()
        a.finishEncounter(walkAway: false)
        b.finishEncounter(walkAway: false)
    }

    private func end(_ now: CFTimeInterval, walkAway: Bool) {
        log("Begegnung beendet")
        finished = true
        removeEffects()
        if walkAway {
            a.face(-1)
            b.face(1)
        }
        a.finishEncounter(walkAway: walkAway)
        b.finishEncounter(walkAway: walkAway)
    }

    private func next(_ now: CFTimeInterval) {
        script.next(now)
        log("  Phase \(phase)")
    }

    private func once(_ key: String) -> Bool { script.once(key) }
    private func other(_ c: PetController) -> PetController { c === a ? b : a }
    private func set(_ c: PetController, _ pose: Pose) { poses[ObjectIdentifier(c)] = pose }
    private func both(_ pose: Pose) { set(a, pose); set(b, pose) }

    private func log(_ text: @autoclosure () -> String) { DebugLog.log(text()) }

    // MARK: - Bewegung

    private func walkFrame(_ c: PetController, lookingBack: Bool = false, stride: CGFloat = 1) -> ClawdSprite.Frame {
        ClawdSprite.walkFrame(walked: walked[ObjectIdentifier(c)] ?? 0, px: c.px, stride: stride, lookingBack: lookingBack)
    }

    /// Geht Richtung x; true, wenn angekommen.
    @discardableResult
    private func walk(_ c: PetController, to x: CGFloat, speed factor: CGFloat, dt: TimeInterval) -> Bool {
        let (arrived, distance) = c.step(toward: x, speed: factor, dt: dt)
        walked[ObjectIdentifier(c), default: 0] += distance
        return arrived
    }

    /// Beide gehen auf den Abstand `spacing` (Mitte zu Mitte) und schauen sich dann an.
    private func approach(spacing: CGFloat, dt: TimeInterval, lookingBack: Bool = false, speed: CGFloat = 1) -> Bool {
        guard let range = a.centerRange else { return true }
        let mid = (a.center + b.center) / 2
        var ta = mid - spacing / 2
        var tb = mid + spacing / 2
        if ta < range.lowerBound { tb += range.lowerBound - ta; ta = range.lowerBound }
        if tb > range.upperBound { ta -= tb - range.upperBound; tb = range.upperBound }
        let doneA = walk(a, to: ta, speed: speed, dt: dt)
        let doneB = walk(b, to: tb, speed: speed, dt: dt)
        for (c, done) in [(a, doneA), (b, doneB)] {
            set(c, Pose(sprite: done ? ClawdSprite.stand : walkFrame(c, lookingBack: lookingBack)))
        }
        if lookingBack {
            // "Ohne zu gucken" aufeinander zu: Blick nach hinten, Laufrichtung zum anderen.
            a.face(1)
            b.face(-1)
        }
        guard doneA, doneB else { return false }
        a.face(1)
        b.face(-1)
        return true
    }

    // MARK: - Begrüßung & Plaudern

    private func greeting(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        switch phase {
        case 0:
            if approach(spacing: 22 * px, dt: dt) { next(now) }
        case 1:
            both(Pose(sprite: ClawdSprite.wave[Int(t / 0.18) % 2]))
            if once("hi-a") { a.say(.happy) }
            if t > 0.9, once("hi-b") { b.say(.happy) }
            if t >= 1.5 { next(now) }
        case 2:
            // Abwechselnd "reden": Sprechblase und Plapperlaut, der andere hört zu und blinzelt.
            let turn = Int(t / 1.1)
            let speaker = turn % 2 == 0 ? a : b
            let local = t.truncatingRemainder(dividingBy: 1.1)
            set(speaker, Pose(sprite: ClawdSprite.stand, bubble: true))
            set(other(speaker), Pose(sprite: local > 0.5 && local < 0.65 ? ClawdSprite.blink : ClawdSprite.stand))
            if once("talk\(turn)"), speaker.isChatty { speaker.say(.murmur) }
            if t >= 4.4 { next(now) }
        default:
            both(Pose(sprite: ClawdSprite.wave[Int(t / 0.18) % 2]))
            if t >= 1.2 { end(now, walkAway: true) }
        }
    }

    // MARK: - High Five

    private func highFive(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        switch phase {
        case 0:
            if approach(spacing: 15 * px, dt: dt, speed: 1.4) { next(now) }
        case 1:
            both(Pose(sprite: ClawdSprite.squash)) // Anlauf: kurz in die Knie
            if t >= 0.3 { next(now) }
        case 2:
            let p = min(t / 0.6, 1)
            both(Pose(sprite: ClawdSprite.wave[0], lift: 5 * sin(.pi * p)))
            if t >= 0.3, once("clap") {
                starPoint = CGPoint(x: (a.center + b.center) / 2, y: a.groundY + 12 * px)
                starUntil = now + 0.45
                a.say(.pock)
            }
            if t >= 0.6 { next(now) }
        default:
            both(Pose(sprite: ClawdSprite.happyStand))
            if once("yay") { b.say(.happy) }
            if t >= 1.0 { end(now, walkAway: true) }
        }
    }

    // MARK: - Umarmung

    private func hug(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        switch phase {
        case 0:
            if approach(spacing: 11 * px, dt: dt) { next(now) }
        case 1:
            set(a, Pose(sprite: ClawdSprite.hugFrame, particles: .hearts))
            set(b, Pose(sprite: ClawdSprite.hugFrame))
            if once("mmh") { a.say(.happy) }
            if t >= 2.6 { next(now) }
        default:
            both(Pose(sprite: ClawdSprite.happyStand))
            if t >= 0.5 { end(now, walkAway: true) }
        }
    }

    // MARK: - Tänzchen

    private func dance(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        switch phase {
        case 0:
            if approach(spacing: 20 * px, dt: dt) {
                marks[ObjectIdentifier(a)] = a.center
                marks[ObjectIdentifier(b)] = b.center
                next(now)
            }
        case 1:
            // Vier Schläge: Hüpfer – Schritt nach links – Hüpfer – Schritt zurück. Beide im Gleichtakt.
            let beatLength = 0.4
            let beat = Int(t / beatLength) % 4
            let bt = CGFloat(t.truncatingRemainder(dividingBy: beatLength) / beatLength)
            let offset: CGFloat
            switch beat {
            case 0: offset = 0
            case 1: offset = -3 * px * bt
            case 2: offset = -3 * px
            default: offset = -3 * px * (1 - bt)
            }
            for c in [a, b] {
                c.moveCenter(to: (marks[ObjectIdentifier(c)] ?? c.center) + offset)
                if beat % 2 == 0 {
                    set(c, Pose(sprite: ClawdSprite.flail, particles: .notes, lift: 2.5 * sin(.pi * bt)))
                } else {
                    set(c, Pose(sprite: ClawdSprite.walkCycle[beat == 1 ? 1 : 3], particles: .notes))
                }
            }
            if once("hum-a") { a.say(.hum) }
            if t >= 2.2, once("hum-b") { b.say(.hum) }
            if t >= 5.2 { next(now) }
        default:
            both(Pose(sprite: ClawdSprite.squash)) // Verbeugung
            if t >= 0.8 { end(now, walkAway: false) }
        }
    }

    // MARK: - Fangen

    private func tag(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        switch phase {
        case 0:
            if approach(spacing: 15 * px, dt: dt) { next(now) }
        case 1:
            // Antippen: "Du bist!"
            set(chaser, Pose(sprite: ClawdSprite.wave[1]))
            set(other(chaser), Pose(sprite: ClawdSprite.stand))
            if t >= 0.25, once("tap") { other(chaser).say(oneOf: Voice.Sound.startled) }
            if t >= 0.5 {
                let runner = other(chaser)
                runDir = runner.center >= chaser.center ? 1 : -1
                lastTag = now
                next(now)
            }
        case 2:
            let runner = other(chaser)
            // Wegrennen; am Rand umdrehen.
            let step = runner.walkSpeed * 2.2 * CGFloat(dt)
            if let r = runner.centerRange, !(r.contains(runner.center + runDir * step)) { runDir *= -1 }
            runner.face(runDir)
            runner.moveCenter(to: runner.center + runDir * step)
            walked[ObjectIdentifier(runner), default: 0] += step
            // Fänger startet kurz verzögert und ist etwas schneller.
            if now - lastTag > 0.5 {
                walk(chaser, to: runner.center, speed: 2.6, dt: dt)
            }
            set(runner, Pose(sprite: walkFrame(runner, stride: 1.4)))
            set(chaser, Pose(sprite: now - lastTag > 0.5 ? walkFrame(chaser, stride: 1.4) : ClawdSprite.happyStand))
            if abs(runner.center - chaser.center) < 13 * px, now - lastTag > 0.8 {
                // Erwischt! Rollen tauschen.
                tags += 1
                chaser = runner
                lastTag = now
                let newRunner = other(chaser)
                runDir = newRunner.center >= chaser.center ? 1 : -1
                newRunner.say(oneOf: Voice.Sound.startled)
                log("  erwischt (\(tags))")
            }
            if tags >= 3 || t > 14 { next(now) }
        default:
            // Aus der Puste: schnaufen und schwitzen.
            let pant = Int(t / 0.3) % 2 == 0
            both(Pose(sprite: pant ? ClawdSprite.squash : ClawdSprite.stand, particles: .sweat))
            if t >= 1.6 { end(now, walkAway: false) }
        }
    }

    // MARK: - Bocksprung

    private func leapfrog(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        switch phase {
        case 0:
            if approach(spacing: 20 * px, dt: dt) {
                // In die Richtung mit mehr Platz springen.
                if let r = a.centerRange {
                    leapDir = (r.upperBound - b.center) >= (a.center - r.lowerBound) ? 1 : -1
                }
                front = leapDir > 0 ? b : a
                a.face(leapDir)
                b.face(leapDir)
                next(now)
            }
        case 1:
            // Vorderer duckt sich, hinterer macht sich bereit.
            set(front, Pose(sprite: ClawdSprite.duck))
            set(other(front), Pose(sprite: ClawdSprite.squash))
            if t >= 0.35 {
                let jumper = other(front)
                jumpFrom = jumper.center
                jumpTo = front.center + leapDir * 18 * px
                if let r = jumper.centerRange, !r.contains(jumpTo) {
                    end(now, walkAway: false)
                    return
                }
                jumper.say(.hop)
                next(now)
            }
        case 2:
            let jumper = other(front)
            let p = CGFloat(min(t / 0.7, 1))
            jumper.moveCenter(to: jumpFrom + (jumpTo - jumpFrom) * p)
            set(jumper, Pose(sprite: ClawdSprite.flail, lift: 9 * sin(.pi * p)))
            set(front, Pose(sprite: ClawdSprite.duck))
            if t >= 0.7 { next(now) }
        default:
            let jumper = other(front)
            set(jumper, Pose(sprite: ClawdSprite.squash))
            set(front, Pose(sprite: ClawdSprite.stand))
            if t >= 0.25 {
                jumps += 1
                front = jumper
                if jumps >= 4 {
                    end(now, walkAway: false)
                } else {
                    script.go(to: 1, now: now)
                }
            }
        }
    }

    // MARK: - Ball zuspielen

    private func hitPoint(_ c: PetController) -> CGPoint {
        CGPoint(x: c.center + c.facing * ClawdSprite.racketHitOffset.x * c.px,
                y: c.groundY + ClawdSprite.racketHitOffset.y * c.px)
    }

    private func hit(by c: PetController, now: CFTimeInterval) {
        c.say(.pock)
        swingUntil[ObjectIdentifier(c)] = now + 0.18
        anticipated = false
        let receiver = other(c)
        let from = hitPoint(c)
        let miss = Double.random(in: 0..<1) < 0.1
        let to = miss
            ? CGPoint(x: receiver.center + receiver.facing * -30 * receiver.px / 4 - receiver.facing * 40,
                      y: receiver.groundY + receiver.px)
            : hitPoint(receiver)
        let lob = Double.random(in: 0..<1) < 0.3
        let distance = abs(to.x - from.x)
        let path = BallArc(from: from, to: to, start: now,
                           duration: lob ? .random(in: 0.9...1.3) : min(max(Double(distance) / .random(in: 250...450), 0.4), 1.0),
                           arc: lob ? .random(in: 40...80) : .random(in: 4...14))
        flight = Flight(path: path, receiver: receiver, miss: miss)
    }

    private func ballPass(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        switch phase {
        case 0:
            if approach(spacing: passDistance, dt: dt) {
                server = a
                serveAt = now + 0.6
                rallyEnd = now + .random(in: 10...16)
                next(now)
            }
        case 1:
            for c in [a, b] {
                let id = ObjectIdentifier(c)
                let lookBack = now < (lookBackUntil[id] ?? 0)
                set(c, Pose(sprite: lookBack ? ClawdSprite.lookCycle[3] : ClawdSprite.stand,
                            prop: ClawdSprite.racket(now < (swingUntil[id] ?? 0) ? .swing : .ready),
                            sporty: true))
            }
            if var b = bounce {
                // Daneben: Ball hüpft weg.
                b.step(dt: dt, floor: a.groundY)
                bounce = now >= b.until ? nil : b
            } else if let f = flight {
                let p = f.path.progress(now)
                if !f.miss, !anticipated, f.path.duration * (1 - p) < 0.1 {
                    swingUntil[ObjectIdentifier(f.receiver)] = now + 0.2
                    anticipated = true
                }
                if p >= 1 {
                    flight = nil
                    if f.miss {
                        let r = f.receiver
                        lookBackUntil[ObjectIdentifier(r)] = now + 1.3
                        if r.isChatty { r.say(.murmur) }
                        bounce = BouncingBall(pos: f.path.to, vel: CGVector(dx: -r.facing * 90, dy: 120), until: now + 1.4)
                        server = r
                        serveAt = now + 1.8
                    } else if now > rallyEnd {
                        next(now)
                    } else {
                        hit(by: f.receiver, now: now)
                    }
                }
            } else if now >= serveAt {
                if now > rallyEnd { next(now) } else { hit(by: server, now: now) }
            }
        default:
            both(Pose(sprite: ClawdSprite.happyStand))
            if t >= 0.6 { end(now, walkAway: false) }
        }
    }

    // MARK: - Zusammenstoß

    private func bump(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        switch phase {
        case 0:
            if approach(spacing: 14 * px, dt: dt, lookingBack: true) {
                marks[ObjectIdentifier(a)] = a.center
                marks[ObjectIdentifier(b)] = b.center
                next(now)
            }
        case 1:
            // Bums! Beide prallen zurück.
            let p = CGFloat(min(t / 0.4, 1))
            a.moveCenter(to: (marks[ObjectIdentifier(a)] ?? a.center) - 8 * px * p)
            b.moveCenter(to: (marks[ObjectIdentifier(b)] ?? b.center) + 8 * px * p)
            both(Pose(sprite: ClawdSprite.flail, lift: 3 * sin(.pi * p)))
            if once("eep-a") { a.say(oneOf: Voice.Sound.startled) }
            if t >= 0.08, once("eep-b") { b.say(oneOf: Voice.Sound.startled) }
            if t >= 0.4 { next(now) }
        case 2:
            both(Pose(sprite: t > 0.4 && t < 0.55 ? ClawdSprite.blink : ClawdSprite.stand))
            if t >= 0.8 { next(now) }
        default:
            // Kichern: glücklich und ein bisschen wackelnd.
            let giggle: CGFloat = Int(t / 0.12) % 2 == 0 ? 0 : 0.5
            both(Pose(sprite: ClawdSprite.happyStand, lift: giggle))
            if once("giggle-a"), a.isChatty { a.say(.murmur) }
            if t >= 0.9, once("giggle-b"), b.isChatty { b.say(.murmur) }
            if t >= 1.4 { end(now, walkAway: true) }
        }
    }

    // MARK: - Post

    private func mail(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        let giver = courier ?? a
        let receiver = other(giver)
        switch phase {
        case 0:
            if approach(spacing: 16 * px, dt: dt) { next(now) }
        case 1:
            // Überreichen
            set(giver, Pose(sprite: ClawdSprite.wave[1]))
            set(receiver, Pose(sprite: ClawdSprite.stand))
            showLetter(ClawdSprite.envelope, x: (a.center + b.center) / 2, y: a.groundY + 4 * px)
            if t >= 0.8 { next(now) }
        case 2:
            // Lesen
            set(giver, Pose(sprite: ClawdSprite.stand))
            set(receiver, Pose(sprite: ClawdSprite.lookCycle[1]))
            showLetter(ClawdSprite.openLetter, x: receiver.center + receiver.facing * 6 * px, y: receiver.groundY + 3 * px)
            if t >= 1.6 { next(now) }
        default:
            effects.hide("letter")
            set(receiver, Pose(sprite: ClawdSprite.happyStand, particles: .hearts))
            set(giver, Pose(sprite: ClawdSprite.wave[Int(t / 0.18) % 2]))
            if once("yay") { receiver.say(.happy) }
            if t >= 1.4 { end(now, walkAway: true) }
        }
    }

    private func showLetter(_ frame: ClawdSprite.Frame, x: CGFloat, y: CGFloat) {
        effects.show("letter", frame, centerX: x, bottom: y, scale: a.px * 0.7)
    }

    // MARK: - Effekte (Stern, Ball)

    private func updateEffects(_ now: CFTimeInterval) {
        let px = a.px
        if now < starUntil {
            effects.show("star", ClawdSprite.star, centerX: starPoint.x, bottom: starPoint.y, scale: px * 0.75)
        } else {
            effects.hide("star")
        }

        let ballPos = flight.map { $0.path.position(now) } ?? bounce?.pos
        if let ballPos {
            let size = CGFloat(ClawdSprite.ball.count) * px * 0.6
            effects.show("ball", ClawdSprite.ball, origin: CGPoint(x: ballPos.x - size / 2, y: ballPos.y - size / 2),
                         scale: px * 0.6)
        } else {
            effects.hide("ball")
        }
    }

    private func showEffect(_ key: String, _ frame: ClawdSprite.Frame, origin: CGPoint, scale: CGFloat) {
        effects.show(key, frame, origin: origin, scale: scale)
    }

    private func hideEffect(_ key: String) { effects.hide(key) }

    private func showAboveHead(_ key: String, _ c: PetController, _ glyph: ClawdSprite.Frame) {
        effects.show(key, glyph, centerX: c.center, bottom: c.groundY + 9.5 * c.px, scale: c.px * 0.8)
    }

    // MARK: - Präsentation

    private func presentation(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        let chart = { (p: CGFloat) in
            let f = ClawdSprite.flipchart(progress: p)
            self.showEffect("chart", f, origin: CGPoint(x: self.a.center + 7 * px, y: self.a.groundY), scale: px * 0.9)
        }
        switch phase {
        case 0:
            if approach(spacing: 28 * px, dt: dt) { next(now) }
        case 1:
            // a präsentiert und zeigt aufs Diagramm, b hört zu und nickt
            chart(CGFloat(t / 5))
            let turn = Int(t / 1.2)
            if once("talk\(turn)"), a.isChatty { a.say(.murmur) }
            set(a, Pose(sprite: Int(t / 0.6) % 2 == 0 ? ClawdSprite.wave[1] : ClawdSprite.stand, bubble: true))
            set(b, Pose(sprite: t.truncatingRemainder(dividingBy: 1.5) < 0.25 ? ClawdSprite.sitNod : ClawdSprite.lookCycle[1]))
            if t >= 5 { next(now) }
        case 2:
            // Applaus! a verbeugt sich
            chart(1)
            if once("clap") { b.say(.clap) }
            set(b, Pose(sprite: Int(t / 0.14) % 2 == 0 ? ClawdSprite.flail : ClawdSprite.happyStand))
            set(a, Pose(sprite: t < 0.8 ? ClawdSprite.squash : ClawdSprite.happyStand))
            if t >= 1.6 { next(now) }
        default:
            hideEffect("chart")
            end(now, walkAway: true)
        }
    }

    // MARK: - Pair Programming

    private func pairProgramming(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        switch phase {
        case 0:
            if approach(spacing: 18 * px, dt: dt) { next(now) }
        case 1, 2:
            // Einer tippt am Laptop, der andere zeigt und gibt Tipps – dann Tausch
            let driver = phase == 1 ? a : b
            let navigator = other(driver)
            set(driver, Pose(sprite: ClawdSprite.codeType[Int(t / 0.12) % 2], particles: .code, laptop: true))
            set(navigator, Pose(sprite: Int(t / 0.5) % 2 == 0 ? ClawdSprite.wave[1] : ClawdSprite.stand, bubble: true))
            if once("tip\(phase)\(Int(t / 1.2))"), navigator.isChatty { navigator.say(.murmur) }
            if t >= 3.2 { next(now) }
        default:
            both(Pose(sprite: ClawdSprite.happyStand))
            if once("done") { a.say(.happy) }
            if t >= 0.8 { end(now, walkAway: true) }
        }
    }

    // MARK: - Merge-Konflikt-Tauziehen

    private func tugOfWar(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        let s = px * 0.8
        let mid = (a.center + b.center) / 2
        switch phase {
        case 0:
            if approach(spacing: 24 * px, dt: dt) {
                marks[ObjectIdentifier(a)] = a.center
                marks[ObjectIdentifier(b)] = b.center
                next(now)
            }
        case 1:
            // Ziehen und zerren
            let jitter: CGFloat = Int(t / 0.1) % 2 == 0 ? 0.5 : -0.5
            a.moveCenter(to: (marks[ObjectIdentifier(a)] ?? a.center) + jitter * px)
            b.moveCenter(to: (marks[ObjectIdentifier(b)] ?? b.center) + jitter * px)
            showEffect("paper", ClawdSprite.tugPaper, origin: CGPoint(x: mid - 5 * s + jitter * px, y: a.groundY + 3 * px), scale: s)
            both(Pose(sprite: ClawdSprite.scold[1], lift: Int(t / 0.2) % 2 == 0 ? 0 : 0.5))
            if once("grr"), a.isChatty { a.say(oneOf: [.scold, .grrr]) }
            if t >= 0.9, once("grr2"), b.isChatty { b.say(oneOf: [.scold, .grrr]) }
            if t >= 2.6 { next(now) }
        case 2:
            // Ratsch! Beide fallen nach hinten auf den Hintern
            hideEffect("paper")
            let p = CGFloat(min(t / 0.4, 1))
            a.moveCenter(to: (marks[ObjectIdentifier(a)] ?? a.center) - 7 * px * p)
            b.moveCenter(to: (marks[ObjectIdentifier(b)] ?? b.center) + 7 * px * p)
            showEffect("left", ClawdSprite.tugPaperLeft, origin: CGPoint(x: a.center + 6 * px, y: a.groundY + 3 * px * (1 - p) + px), scale: s)
            showEffect("right", ClawdSprite.tugPaperRight, origin: CGPoint(x: b.center - 6 * px - 5 * s, y: b.groundY + 3 * px * (1 - p) + px), scale: s)
            both(Pose(sprite: p < 1 ? ClawdSprite.flail : ClawdSprite.sit, lift: 2 * sin(.pi * p)))
            if once("rip") { a.say(oneOf: Voice.Sound.whine) }
            if t >= 0.1, once("rip2") { b.say(oneOf: Voice.Sound.whine) }
            if t >= 0.6 { next(now) }
        case 3:
            // Erschrocken anschauen
            both(Pose(sprite: ClawdSprite.sit))
            showAboveHead("exA", a, ClawdSprite.exclamationGlyph)
            showAboveHead("exB", b, ClawdSprite.exclamationGlyph)
            if t >= 1.4 { next(now) }
        default:
            hideEffect("exA"); hideEffect("exB"); hideEffect("left"); hideEffect("right")
            end(now, walkAway: true)
        }
    }

    // MARK: - Zauberpanne

    /// Wie der Verzauberte gerade aussieht (nil = wieder Clawd).
    private var spell: ClawdSprite.Frame?

    private func showPuff(on c: PetController, _ t: TimeInterval) {
        let px = a.px, scale = px * 0.8
        let frame = ClawdSprite.puff[t < 0.12 ? 0 : 1]
        let w = CGFloat(frame[0].count) * scale
        showEffect("puff", frame, origin: CGPoint(x: c.center - w / 2, y: c.groundY + px), scale: scale)
    }

    /// a zaubert, b wird zum Frosch oder Kaninchen; a erschrickt und schwingt dreimal hektisch den
    /// Stab – erst beim dritten Mal ist b wieder Clawd.
    private func magicMishap(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        let hat = ClawdSprite.wizardHat
        func victim(lift: CGFloat = 0) -> Pose {
            if let spell { return Pose(sprite: spell, lift: lift) }
            return Pose(sprite: ClawdSprite.stand)
        }
        switch phase {
        case 0:
            if approach(spacing: 26 * px, dt: dt) { next(now) }
        case 1:
            // Hokuspokus
            set(a, Pose(sprite: ClawdSprite.wave[Int(t / 0.25) % 2], prop: ClawdSprite.wand(.up), particles: .sparks, hat: hat))
            set(b, Pose(sprite: ClawdSprite.lookCycle[1]))
            if once("spell"), a.isChatty { a.say(.murmur) }
            if t >= 1.2 { next(now) }
        case 2:
            // Funken fliegen zu b
            set(a, Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.wand(.forward), hat: hat))
            set(b, Pose(sprite: ClawdSprite.stand))
            let p = CGFloat(min(t / 0.5, 1))
            let x = a.center + (b.center - a.center) * p
            showEffect("spark", ClawdSprite.sparkleGlyph, origin: CGPoint(x: x - px, y: a.groundY + 5 * px), scale: px * 0.7)
            if t >= 0.5 {
                hideEffect("spark")
                a.say(.pickup)
                next(now)
            }
        case 3:
            // Puff – b ist ein Tier!
            showPuff(on: b, t)
            if t >= 0.15, spell == nil { spell = Bool.random() ? ClawdSprite.frog : ClawdSprite.rabbit }
            set(a, Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.wand(.forward), hat: hat))
            set(b, victim())
            if t >= 0.4 {
                hideEffect("puff")
                next(now)
            }
        case 4:
            // a erschrickt, b hüpft verwirrt
            set(a, Pose(sprite: ClawdSprite.flail, prop: ClawdSprite.wand(.up), particles: .sweat, hat: hat))
            set(b, victim(lift: Int(t / 0.25) % 2 == 0 ? 0 : 1))
            if once("eep") { a.say(oneOf: [.eep, .oiWorried]) }
            if t >= 1.6 { next(now) }
        case 5, 6, 7:
            // Drei hektische Versuche; erst der dritte klappt.
            let attempt = phase - 4
            set(a, Pose(sprite: ClawdSprite.wave[Int(t / 0.12) % 2], prop: ClawdSprite.wand(Int(t / 0.12) % 2 == 0 ? .up : .forward),
                        particles: .sparks, hat: hat))
            if t >= 0.55 {
                showPuff(on: b, t - 0.55)
                if once("try\(attempt)") {
                    a.say(.pickup)
                    switch attempt {
                    case 1: break                                                     // nichts passiert
                    case 2: spell = spell == ClawdSprite.frog ? ClawdSprite.rabbit : ClawdSprite.frog // anderes Tier!
                    default: spell = nil                                              // geschafft
                    }
                }
            } else {
                hideEffect("puff")
            }
            set(b, victim(lift: Int(t / 0.25) % 2 == 0 ? 0 : 1))
            if t >= 0.9 {
                hideEffect("puff")
                next(now)
            }
        default:
            // Erleichterung: a wischt sich den Schweiß, b schüttelt sich
            set(a, Pose(sprite: ClawdSprite.happyStand, prop: ClawdSprite.wand(.up), particles: .sweat, hat: hat))
            set(b, Pose(sprite: ClawdSprite.lookCycle[Int(t / 0.12) % 2 == 0 ? 1 : 3]))
            if once("phew") { a.say(.happy) }
            if t >= 0.8, once("grumble"), b.isChatty { b.say(oneOf: [.scold, .hmpf]) }
            if t >= 1.6 { end(now, walkAway: true) }
        }
    }

    // MARK: - Kaffeepause

    private func coffeeBreak(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px
        switch phase {
        case 0:
            if approach(spacing: 19 * px, dt: dt) {
                marks[ObjectIdentifier(a)] = a.center
                marks[ObjectIdentifier(b)] = b.center
                next(now)
            }
        case 1:
            // Anstoßen
            let p = CGFloat(sin(.pi * min(t / 0.6, 1)))
            a.moveCenter(to: (marks[ObjectIdentifier(a)] ?? a.center) + 2 * px * p)
            b.moveCenter(to: (marks[ObjectIdentifier(b)] ?? b.center) - 2 * px * p)
            both(Pose(sprite: ClawdSprite.happyStand, prop: ClawdSprite.cupHold))
            if t >= 0.3, once("clink") {
                a.say(.clink)
                starPoint = CGPoint(x: (a.center + b.center) / 2, y: a.groundY + 6 * px)
                starUntil = now + 0.35
            }
            if t >= 0.8 { next(now) }
        case 2:
            // Schlürfen
            both(Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.coffeeCupDrinking, particles: .steam))
            if once("sip") { b.say(.slurp) }
            if t >= 1.3 { next(now) }
        case 3:
            // Plaudern mit Tasse in der Hand
            let turn = Int(t / 1.2)
            let speaker = turn % 2 == 0 ? a : b
            set(speaker, Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.cupHold, bubble: true))
            set(other(speaker), Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.cupHold, particles: .steam))
            if once("talk\(turn)"), speaker.isChatty { speaker.say(.murmur) }
            if t >= 3.6 { next(now) }
        default:
            end(now, walkAway: true)
        }
    }

    private func removeEffects() { effects.removeAll() }

    // MARK: - Rollenspielabend

    private func rpgNight(_ now: CFTimeInterval, _ t: TimeInterval, _ dt: TimeInterval) {
        let px = a.px, s = px / 2
        let hat = ClawdSprite.rpgWizardHat
        guard phase > 0 else {
            if approach(spacing: 39 * px, dt: dt) { next(now) }
            return
        }
        let mid = (a.center + b.center) / 2
        let top = a.groundY + CGFloat(ClawdSprite.gameTable.count) * s
        func at(_ cells: CGFloat, _ bottom: CGFloat) -> CGPoint { CGPoint(x: mid + cells * s, y: bottom) }
        let rolled = phase >= 5
        let dragonHop: CGFloat = rolled && rpgRoll == 1 && t < 1.4 ? CGFloat(abs(sin(t * .pi / 0.25))) * 2 * px : 0

        // Tisch mit Schirm, Spielplan, Miniaturen, Charakterbogen und Chips
        showEffect("table", ClawdSprite.gameTable, origin: at(-32, a.groundY), scale: s)
        showEffect("map", ClawdSprite.battleMap, origin: at(-9, top - 2 * s), scale: s)
        showEffect("screen", ClawdSprite.gmScreen, origin: at(-27, top), scale: s)
        showEffect("snacks", ClawdSprite.snackBowl, origin: at(-8, top), scale: s)
        showEffect("knight", ClawdSprite.miniKnight, origin: at(10, top), scale: s)
        showEffect("wizard", ClawdSprite.miniWizard, origin: at(15, top), scale: s)
        if rolled, rpgRoll == 20 {
            showEffect("dragon", ClawdSprite.miniDragonFallen, origin: at(20, top), scale: s)
        } else {
            showEffect("dragon", ClawdSprite.miniDragon, origin: at(20, top + dragonHop), scale: s)
        }
        showEffect("sheet", ClawdSprite.characterSheet, origin: at(24, top - s), scale: s)
        showEffect("pencil", ClawdSprite.pencil, origin: at(25, top + s), scale: s)

        switch phase {
        case 1:
            // Platz nehmen, der Spieler setzt seinen Zauberhut auf
            set(a, Pose(sprite: ClawdSprite.stand))
            set(b, Pose(sprite: ClawdSprite.happyStand, hat: hat))
            if t >= 0.6 { next(now) }
        case 2:
            // Der Spielleiter erzählt hinter seinem Schirm, der Spieler lauscht gespannt
            let turn = Int(t / 1.0)
            set(a, Pose(sprite: Int(t / 0.5) % 2 == 0 ? ClawdSprite.wave[1] : ClawdSprite.stand, bubble: true))
            set(b, Pose(sprite: t.truncatingRemainder(dividingBy: 1.5) < 0.25 ? ClawdSprite.blink : ClawdSprite.stand, hat: hat))
            if once("tell\(turn)"), a.isChatty { a.say(.murmur) }
            if t >= 3.0 { next(now) }
        case 3:
            // Ausholen
            set(a, Pose(sprite: ClawdSprite.stand))
            set(b, Pose(sprite: ClawdSprite.wave[1], hat: hat))
            if t >= 0.5 { next(now) }
        case 4:
            // Der Würfel kullert über den Tisch: Bogen, dann zwei kleine Hüpfer
            let p = CGFloat(min(t / 1.2, 1))
            let from = CGPoint(x: b.center - 7 * px, y: a.groundY + 7 * px)
            let land = at(5, top)
            let x = from.x + (land.x - from.x) * min(p / 0.8, 1)
            let y: CGFloat
            if p < 0.55 {
                let q = p / 0.55
                y = from.y + (land.y - from.y) * q + 8 * px * sin(.pi * q)
            } else {
                let q = (p - 0.55) / 0.45
                y = land.y + 2.5 * px * abs(sin(.pi * 2 * q)) * (1 - q)
            }
            let die = Int(t / 0.08) % 2 == 0 ? ClawdSprite.d20(tumble: true) : ClawdSprite.d20()
            showEffect("die", die, origin: CGPoint(x: x - 3.5 * s, y: y), scale: s)
            for (i, at) in [0.55, 0.78, 0.92].enumerated() where p >= CGFloat(at) {
                if once("bounce\(i)") { b.say(.pock) }
            }
            set(a, Pose(sprite: ClawdSprite.stand))
            set(b, Pose(sprite: ClawdSprite.stand, hat: hat))
            if t >= 1.3 { next(now) }
        case 5:
            showEffect("die", ClawdSprite.d20(face: rpgRoll), origin: at(1.5, top), scale: s)
            if rpgRoll == 20 {
                // Volltreffer! Glitzer, beide jubeln, der Drache kippt um
                if Int(t / 0.15) % 2 == 0, t < 1.2 {
                    showEffect("sparkle", ClawdSprite.sparkleGlyph, origin: at(1, top + 8 * s), scale: s)
                } else {
                    hideEffect("sparkle")
                }
                if once("cheer") { b.say(oneOf: Voice.Sound.cheer); a.say(.happy) }
                let hop = t < 1.2 ? CGFloat(abs(sin(t * .pi / 0.3))) * 1.5 : 0
                set(a, Pose(sprite: ClawdSprite.happyStand))
                set(b, Pose(sprite: ClawdSprite.happyStand, lift: hop, hat: hat))
            } else {
                // Patzer: Der Drache hüpft bedrohlich, der Spieler erschrickt, der Spielleiter kichert
                if once("oops") { b.say(oneOf: Voice.Sound.fluster) }
                if t >= 0.6, once("giggle") { a.say(.giggle) }
                set(a, Pose(sprite: ClawdSprite.happyStand))
                set(b, Pose(sprite: ClawdSprite.flail, particles: .sweat, hat: hat))
            }
            if t >= 1.8 { next(now) }
        case 6:
            // Zur Stärkung in die Chipsschale greifen
            hideEffect("sparkle")
            showEffect("die", ClawdSprite.d20(face: rpgRoll), origin: at(1.5, top), scale: s)
            if once("munch") { a.say(.munch) }
            set(a, Pose(sprite: Int(t / 0.3) % 2 == 0 ? ClawdSprite.wave[1] : ClawdSprite.happyStand))
            set(b, Pose(sprite: ClawdSprite.happyStand, hat: hat))
            if t >= 1.6 { next(now) }
        default:
            end(now, walkAway: true)
        }
    }
}
