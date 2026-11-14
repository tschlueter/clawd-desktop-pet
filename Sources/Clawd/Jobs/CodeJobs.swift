import AppKit

// MARK: - Programmierer-Jobs

/// Bug-Jagd: ein Käfer flitzt über die Fläche, Clawd jagt ihn mit dem Kescher.
/// Die ersten Versuche gehen meist daneben, dann hat er ihn.
final class BugHuntJob: Job {
    override class var name: String { "bug" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 160
    }

    private var bugX: CGFloat = 0
    private var bugDir: CGFloat = 1
    private var bugSpeed: CGFloat = 70
    private var nextTurn: CFTimeInterval = 0
    private var attempts = 0
    private var swingUntil: CFTimeInterval = 0
    private var dashUntil: CFTimeInterval = 0
    private var caught = false

    private var bugRange: ClosedRange<CGFloat> {
        guard let r = c.centerRange else { return c.center...c.center }
        let half = 7 * px
        return (r.lowerBound - half + 2)...(r.upperBound + half - 2)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                let dir = roomierDirection()
                bugX = min(max(c.center + dir * 70, bugRange.lowerBound), bugRange.upperBound)
                bugDir = dir
                nextTurn = now + .random(in: 0.6...1.4)
                c.face(dir)
            }
            // Clawd entdeckt den Käfer: "?" und Kescher holen
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.net(swing: false, caught: false))
            showAboveHead("q", ClawdSprite.questionGlyph)
            moveBug(now: now, dt: dt, speedFactor: 0.4)
            if t >= 0.9 {
                hideEffect("q")
                next(now)
            }
        case 1:
            moveBug(now: now, dt: dt, speedFactor: now < dashUntil ? 1.8 : 1)
            let swinging = now < swingUntil
            if !swinging { walk(to: bugX - (bugX >= c.center ? 1 : -1) * 8 * px, speed: 1.9, dt: dt) }
            c.face(bugX - c.center)
            pose = Encounter.Pose(sprite: swinging ? ClawdSprite.squash : walkFrame(stride: 1.4),
                                  prop: ClawdSprite.net(swing: swinging, caught: false))
            // Nah genug? Zuschlagen!
            if !swinging, abs(bugX - (c.center + c.facing * 8 * px)) < 5 * px {
                attempts += 1
                swingUntil = now + 0.3
                c.say(.pock)
                if attempts >= 3 || Double.random(in: 0..<1) < 0.25 {
                    caught = true
                    next(now)
                } else {
                    // Daneben – der Käfer flitzt davon
                    dashUntil = now + 0.8
                    bugDir = Bool.random() ? 1 : -1
                    if c.isChatty { c.say(.eep) }
                }
            }
            if t > 15 { caught = true; next(now) }
        default:
            hideEffect("bug")
            pose = Encounter.Pose(sprite: t < 0.6 ? ClawdSprite.flail : ClawdSprite.happyStand,
                                  prop: ClawdSprite.net(swing: false, caught: true))
            if once("caught") { c.say(.happy) }
            if t >= 1.6 { finish() }
        }
        if !caught { drawBug(now) }
    }

    private func moveBug(now: CFTimeInterval, dt: TimeInterval, speedFactor: CGFloat) {
        if now >= nextTurn {
            nextTurn = now + .random(in: 0.5...1.5)
            if Double.random(in: 0..<1) < 0.45 { bugDir *= -1 }
            bugSpeed = .random(in: 55...95)
        }
        bugX += bugDir * bugSpeed * speedFactor * CGFloat(dt)
        let r = bugRange
        if bugX <= r.lowerBound { bugX = r.lowerBound; bugDir = 1 }
        if bugX >= r.upperBound { bugX = r.upperBound; bugDir = -1 }
    }

    private func drawBug(_ now: CFTimeInterval) {
        let frame = ClawdSprite.bugFrames[Int(now / 0.08) % 2]
        let scale = px * 0.6
        showEffect("bug", frame, origin: CGPoint(x: bugX - CGFloat(frame[0].count) * scale / 2, y: c.groundY), scale: scale)
    }
}

/// Code-Review: im Sitzen eine lange Papierrolle lesen, nicken, rote Striche, zum Schluss ein Häkchen.
final class CodeReviewJob: Job {
    override class var name: String { "review" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var marks: Set<Int> = []
    private var lastScroll = -1

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            let scroll = Int(t / 0.45)
            if scroll != lastScroll {
                lastScroll = scroll
                // Zeilen wandern nach oben; Korrekturen wandern mit, ab und zu kommt eine neue dazu.
                marks = Set(marks.compactMap { $0 > 0 ? $0 - 1 : nil })
                if Double.random(in: 0..<1) < 0.25 { marks.insert(4) }
            }
            let nod = Int(t / 0.9) % 3 == 1 && t.truncatingRemainder(dividingBy: 0.9) < 0.25
            pose = Encounter.Pose(sprite: nod ? ClawdSprite.sitNod : ClawdSprite.sitRead,
                                  prop: ClawdSprite.codeScroll(scroll: scroll, marks: marks))
            if once("hmm"), c.isChatty { c.say(.murmur) }
            if t >= 6 { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.musicGroove[0], prop: ClawdSprite.codeScroll(scroll: lastScroll, marks: marks))
            showAboveHead("check", ClawdSprite.checkGlyph, opacity: Float(sin(.pi * min(t / 1.2, 1))))
            if once("ok") { c.say(.happy) }
            if t >= 1.2 { finish() }
        }
    }
}

/// Server-Wartung: Kabel umstecken, bis alle LEDs grün leuchten.
final class ServerJob: Job {
    override class var name: String { "server" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            let green = min(Int(t / 0.9), 6)
            let plugging = t.truncatingRemainder(dividingBy: 0.9) > 0.45
            if plugging, once("plug\(green)") { c.say(.wallPock) }
            pose = Encounter.Pose(sprite: plugging ? ClawdSprite.wave[1] : ClawdSprite.stand,
                                  prop: ClawdSprite.serverRack(green: green, blinkOn: Int(t / 0.25) % 2 == 0, plugging: plugging))
            if green >= 6 { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand,
                                  prop: ClawdSprite.serverRack(green: 6, blinkOn: false, plugging: false))
            if once("ok") { c.say(.happy) }
            if t >= 1.2 { finish() }
        }
    }
}

/// Whiteboard: Kästen und Pfeile zeichnen, grübeln ("?") – bis die Idee kommt (Glühbirne).
final class WhiteboardJob: Job {
    override class var name: String { "whiteboard" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Zeichnen: alle 0,6 s ein Strich
            let strokes = min(Int(t / 0.6) + 1, 4)
            let drawing = t.truncatingRemainder(dividingBy: 0.6) < 0.4
            pose = Encounter.Pose(sprite: drawing ? ClawdSprite.wave[1] : ClawdSprite.stand,
                                  prop: ClawdSprite.whiteboard(strokes: strokes))
            if t >= 2.4 { next(now) }
        case 1:
            // Grübeln
            pose = Encounter.Pose(sprite: ClawdSprite.lookCycle[Int(t / 0.5) % 4], prop: ClawdSprite.whiteboard(strokes: 4))
            showAboveHead("idea", ClawdSprite.questionGlyph)
            if once("hmm"), c.isChatty { c.say(.murmur) }
            if t >= 1.8 { next(now) }
        case 2:
            // Idee! Rest der Skizze schnell fertig
            let strokes = min(4 + Int(t / 0.35) + 1, 7)
            pose = Encounter.Pose(sprite: ClawdSprite.wave[Int(t / 0.18) % 2], prop: ClawdSprite.whiteboard(strokes: strokes))
            showAboveHead("idea", ClawdSprite.lightbulbGlyph)
            if once("aha") { c.say(.happy) }
            if t >= 1.3 { next(now) }
        default:
            hideEffect("idea")
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, prop: ClawdSprite.whiteboard(strokes: 7))
            if t >= 0.8 { finish() }
        }
    }
}

/// Flow Coden: mit Laptop und Kopfhörern im Takt der Musik tippen, zwischendurch zurücklehnen,
/// mitwippen und mitsummen. Kommt so oft wie normales Coden (eigene Option in der Aktivitätsauswahl).
final class FlowCodingJob: Job {
    override class var name: String { "flow" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil && !c.isOnWall }

    /// Ein Takt bei etwa 100 bpm.
    private let beat: TimeInterval = 0.6
    private var endAt: CFTimeInterval = 0
    private var typing = true
    private var phaseUntil: CFTimeInterval = 0

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                endAt = now + .random(in: 20...45)
                phaseUntil = now + .random(in: 4...8)
            }
            if now >= phaseUntil {
                typing.toggle()
                phaseUntil = now + (typing ? .random(in: 4...8) : .random(in: 2...4))
                if !typing, c.chatty(0.6) { c.say(.hum) }
            }
            if typing {
                // Im Takt tippen (etwas schneller als beim normalen Coden), Code und Noten steigen auf.
                pose = Encounter.Pose(sprite: ClawdSprite.codeType[Int(t / 0.1) % ClawdSprite.codeType.count],
                                      particles: .flow, laptop: true, headphones: true)
            } else {
                // Zurücklehnen und mitwippen
                pose = Encounter.Pose(sprite: ClawdSprite.musicGroove[Int(t / (beat / 2)) % ClawdSprite.musicGroove.count],
                                      particles: .notes, laptop: true, headphones: true)
            }
            if now >= endAt { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.musicGroove[0], laptop: true, headphones: true)
            if once("done") { c.say(.happy) }
            if t >= 1.0 { finish() }
        }
    }
}

// MARK: - Claude-Code-Aufgaben

/// Plan machen: Klemmbrett mit drei Aufgaben, eine nach der anderen abhaken – zum Schluss Konfetti.
final class PlanJob: Job {
    override class var name: String { "plan" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil && !c.isOnWall }

    private var dir: CGFloat = 1

    private func drawClipboard(checked: Int) {
        let frame = ClawdSprite.clipboard(checked: checked)
        let s = px * 0.6
        let w = CGFloat(frame[0].count) * s
        showEffect("clipboard", frame, origin: CGPoint(x: c.center + dir * 7 * px - w / 2, y: c.groundY + 2 * px), scale: s)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") { dir = roomierDirection(); c.face(dir) }
            drawClipboard(checked: 0)
            pose = Encounter.Pose(sprite: ClawdSprite.stand)
            if t >= 0.5 { next(now) }
        case 1, 2, 3:
            // Kurz überlegen, dann abhaken
            let done = t >= 0.8
            drawClipboard(checked: phase - (done ? 0 : 1))
            pose = Encounter.Pose(sprite: done ? ClawdSprite.wave[1] : ClawdSprite.lookCycle[1])
            if done, once("check\(phase)") { c.say(.pock) }
            if t >= 1.1 { next(now) }
        default:
            drawClipboard(checked: 3)
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, particles: .confetti)
            if once("done") { c.say(.happy) }
            if t >= 1.3 { finish() }
        }
    }
}

/// Terminal: Befehle tippen, ausführen lassen, Fortschrittsbalken – manchmal schlägt es fehl,
/// dann seufzt Clawd und versucht es noch einmal.
final class TerminalJob: Job {
    override class var name: String { "terminal" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard c.surfaceKind != nil, !c.isOnWall, let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 110
    }

    private var dir: CGFloat = 1
    private var termX: CGFloat = 0
    private var failNext = false
    private var lines = 0
    private var progress: CGFloat = 0
    private var state = ClawdSprite.TerminalState.running

    private func drawTerminal() {
        let frame = ClawdSprite.terminal(lines: lines, progress: progress, state: state)
        let s = px * 0.6
        let w = CGFloat(frame[0].count) * s
        showEffect("terminal", frame, origin: CGPoint(x: termX - w / 2, y: c.groundY), scale: s)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
                termX = c.center + dir * 14 * px
                failNext = Double.random(in: 0..<1) < 0.35
            }
            drawTerminal()
            pose = Encounter.Pose(sprite: ClawdSprite.stand)
            if t >= 0.4 { next(now) }
        case 1:
            // Befehle tippen
            lines = min(Int(t / 0.8) + 1, 3)
            progress = 0
            state = .running
            drawTerminal()
            pose = Encounter.Pose(sprite: ClawdSprite.codeType[Int(t / 0.1) % ClawdSprite.codeType.count])
            if t >= 2.4 { next(now) }
        case 2:
            // Läuft …
            progress = CGFloat(min(t / 1.8, 1))
            drawTerminal()
            pose = Encounter.Pose(sprite: ClawdSprite.lookCycle[1])
            if t >= 1.8 {
                state = failNext ? .failed : .ok
                c.say(failNext ? .alarm : .beep)
                next(now)
            }
        case 3:
            drawTerminal()
            if state == .failed {
                pose = Encounter.Pose(sprite: ClawdSprite.stand, particles: .sweat)
                if once("sigh"), c.chatty(0.8) { c.say(.murmur) }
                if t >= 1.2 {
                    failNext = false // zweiter Versuch klappt
                    go(to: 1, now: now)
                }
            } else {
                pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
                if once("yay") { c.say(.happy) }
                if t >= 1.2 { finish() }
            }
        default:
            finish()
        }
    }
}

/// Codebase durchsuchen: mit der Lupe einen Aktenstapel durchblättern, bis die Stelle gefunden ist.
final class SearchJob: Job {
    override class var name: String { "search" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard c.surfaceKind != nil, !c.isOnWall, let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 100
    }

    private var dir: CGFloat = 1
    private var pileX: CGFloat = 0
    private var scale: CGFloat { px * 0.8 }

    private func drawPile() {
        let frame = ClawdSprite.folderPile(count: 4, wobble: 0)
        let w = CGFloat(frame[0].count) * scale
        showEffect("pile", frame, origin: CGPoint(x: pileX - w / 2, y: c.groundY), scale: scale)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
                pileX = c.center + dir * 11 * px
            }
            drawPile()
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.magnifier(raised: false))
            if t >= 0.5 { next(now) }
        case 1:
            // Durchblättern: alle 0,4 s fliegt ein Blatt zur Seite
            drawPile()
            pose = Encounter.Pose(sprite: ClawdSprite.sit, prop: ClawdSprite.magnifier(raised: false))
            showAboveHead("hmm", ClawdSprite.questionGlyph)
            let k = Int(t / 0.4), p = CGFloat((t / 0.4).truncatingRemainder(dividingBy: 1))
            if once("flip\(k)") { c.say(.swish) }
            let s = px * 0.6
            showEffect("sheet", ClawdSprite.paperSheet,
                       origin: CGPoint(x: pileX + dir * p * 6 * px - 2 * s, y: c.groundY + (4 + 3 * sin(.pi * p)) * px),
                       scale: s, opacity: Float(1 - p * 0.7))
            if t >= 2.6 {
                hideEffect("sheet")
                hideEffect("hmm")
                next(now)
            }
        case 2:
            // Gefunden!
            drawPile()
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, prop: ClawdSprite.magnifier(raised: true))
            showAboveHead("idea", ClawdSprite.lightbulbGlyph)
            let s = px * 0.6
            showEffect("found", ClawdSprite.sparkleGlyph,
                       origin: CGPoint(x: pileX - 1.5 * s, y: c.groundY + 5 * px), scale: s,
                       opacity: Float(0.6 + 0.4 * sin(t * 12)))
            if once("found") { c.say(.happy) }
            if t >= 1.4 { finish() }
        default:
            finish()
        }
    }
}

/// Subagenten: Clawd pfeift, zwei Mini-Clawds flitzen in beide Richtungen davon, arbeiten kurz
/// und kommen mit Zetteln zurück; Clawd sammelt sie ein und nickt zufrieden.
final class SubagentsJob: Job {
    override class var name: String { "subagents" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard c.surfaceKind != nil, !c.isOnWall, let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 200
    }

    private var targets: [CGFloat] = []
    private var scale: CGFloat { px * 0.5 }

    /// Mini-Clawd bei x; `moving` −1/+1 läuft, 0 steht (tippt), `note` trägt einen Zettel.
    private func drawMini(_ i: Int, x: CGFloat, moving: CGFloat, note: Bool, now: CFTimeInterval, opacity: Float = 1) {
        let frame = moving == 0 ? ClawdSprite.codeType[Int(now / 0.12 + Double(i)) % ClawdSprite.codeType.count]
                                : ClawdSprite.walkCycle[Int(now / 0.08) % ClawdSprite.walkCycle.count]
        let w = CGFloat(frame[0].count) * scale
        let facingLeft = moving < 0 || (moving == 0 && x < c.center)
        showEffect("mini\(i)", frame, origin: CGPoint(x: x - w / 2, y: c.groundY), scale: scale, opacity: opacity,
                   mirrored: facingLeft)
        if note {
            let s = px * 0.5
            showEffect("note\(i)", ClawdSprite.paperSheet, origin: CGPoint(x: x - 2 * s, y: c.groundY + 4.5 * px),
                       scale: s, opacity: opacity)
        } else {
            hideEffect("note\(i)")
        }
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Pfeifen
            if once("setup"), let r = c.centerRange {
                targets = [max(r.lowerBound, c.center - 120), min(r.upperBound, c.center + 120)]
                c.say(.tweet)
            }
            pose = Encounter.Pose(sprite: ClawdSprite.wave[1])
            if t >= 0.8 { next(now) }
        case 1, 3:
            // Hin (1) bzw. zurück mit Zettel (3)
            let p = CGFloat(min(t / 1.2, 1))
            for (i, target) in targets.enumerated() {
                let from = phase == 1 ? c.center : target, to = phase == 1 ? target : c.center
                drawMini(i, x: from + (to - from) * p, moving: to < from ? -1 : 1, note: phase == 3, now: now)
            }
            pose = Encounter.Pose(sprite: phase == 1 ? ClawdSprite.wave[1] : ClawdSprite.lookCycle[1])
            if t >= 1.2 { next(now) }
        case 2:
            // Die Minis arbeiten
            for (i, target) in targets.enumerated() { drawMini(i, x: target, moving: 0, note: false, now: now) }
            pose = Encounter.Pose(sprite: ClawdSprite.lookCycle[Int(t / 0.7) % 2 == 0 ? 1 : 3])
            if t >= 1.6 { next(now) }
        default:
            // Einsammeln: Minis verblassen, Clawd nickt
            let fade = Float(max(1 - t / 0.5, 0))
            for i in targets.indices { drawMini(i, x: c.center, moving: 0, note: true, now: now, opacity: fade) }
            pose = Encounter.Pose(sprite: ClawdSprite.sitNod)
            if once("thanks") { c.say(.happy) }
            if t >= 1.2 { finish() }
        }
    }
}
