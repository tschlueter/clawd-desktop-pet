import AppKit

// Arbeiten aus Bereichen, in denen Claude Code oft eingesetzt wird: Security, Datenspeicherung,
// Data Science und Produktdesign. Die Requisiten stehen neben Clawd auf seiner Fläche.

/// Sicherheits-Check: Schloss mit der Lupe untersuchen, Lücke finden, flicken, Bügel zu – grünes Schild.
final class SecurityCheckJob: Job {
    override class var name: String { "security" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil && !c.isOnWall }

    private var dir: CGFloat = 1
    private var lockX: CGFloat = 0
    private var s: CGFloat { px / 2 }

    private func drawLock(open: Bool, cracked: Bool, shake: CGFloat = 0) {
        let f = ClawdSprite.padlock(open: open, cracked: cracked)
        showEffect("lock", f, origin: CGPoint(x: lockX - CGFloat(f[0].count) * s / 2 + shake, y: c.groundY), scale: s)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
                lockX = c.center + dir * 12 * px
            }
            drawLock(open: true, cracked: false)
            pose = Encounter.Pose(sprite: ClawdSprite.stand)
            if t >= 0.6 { next(now) }
        case 1:
            // Mit der Lupe absuchen
            drawLock(open: true, cracked: false)
            showAboveHead("glyph", ClawdSprite.questionGlyph)
            pose = Encounter.Pose(sprite: ClawdSprite.lookCycle[Int(t / 0.6) % 2 == 0 ? 0 : 1],
                                  prop: ClawdSprite.magnifier(raised: Int(t / 0.5) % 2 == 0))
            if once("hmm"), c.isChatty { c.say(.murmur) }
            if t >= 2.6 { next(now) }
        case 2:
            // Lücke gefunden!
            drawLock(open: true, cracked: Int(t / 0.15) % 2 == 0)
            showAboveHead("glyph", ClawdSprite.exclamationGlyph)
            if once("eep") { c.say(.eep) }
            pose = Encounter.Pose(sprite: ClawdSprite.flail, lift: t < 0.3 ? 1 : 0)
            if t >= 1.2 { hideEffect("glyph"); next(now) }
        case 3:
            // Flicken – dann schnappt der Bügel zu
            let fixed = t >= 1.6
            let tap = Int(t / 0.3)
            drawLock(open: t < 1.8, cracked: !fixed, shake: !fixed && tap % 2 == 0 ? 0.5 * s : 0)
            if !fixed, tap < 5, once("tap\(tap)") { c.say(.wallPock) }
            if t >= 1.8, once("click") { c.say(.plop) }
            pose = Encounter.Pose(sprite: fixed ? ClawdSprite.stand : ClawdSprite.wave[tap % 2],
                                  particles: fixed ? .none : .sparks)
            if t >= 2.2 { next(now) }
        default:
            // Sicher!
            drawLock(open: false, cracked: false)
            let g = ClawdSprite.shieldGlyph, gs = px * 0.8
            showEffect("shield", g, origin: CGPoint(x: lockX - CGFloat(g[0].count) * gs / 2, y: c.groundY + 9 * px), scale: gs)
            showAboveHead("glyph", ClawdSprite.checkGlyph)
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("yay") { c.say(.happy) }
            if t >= 1.6 { finish() }
        }
    }
}

/// Daten-Migration: alte Disketten und ein Tonband in einer Retro-Lesestation einlesen (quälend
/// langsam) und blitzschnell auf SSDs in einem Server schreiben. Kiste hinter Clawd, Lesestation vor
/// ihm, der Server weiter vorn.
final class DatabaseMigrationJob: Job {
    override class var name: String { "migration" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard c.surfaceKind != nil, !c.isOnWall, let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 42 * c.px
    }

    private var dir: CGFloat = 1
    private var startX: CGFloat = 0
    private var s: CGFloat { px / 2 }
    private var crateX: CGFloat { startX - dir * 11 * px }
    private var readerX: CGFloat { startX + dir * 13 * px }
    private var serverX: CGFloat { startX + dir * 34 * px }

    private var floppyInCrate = true
    private var reelInCrate = true
    private var tapeLoaded = false
    private var ssds = 0
    private var progress = 0.0
    private var busy = false
    private var spin = 0
    private var writing = false

    private var readerOrigin: CGPoint { CGPoint(x: readerX - 12 * s, y: c.groundY) }
    private var slot: CGPoint { CGPoint(x: readerOrigin.x + 17 * s, y: c.groundY + 6 * s) }
    private var deck: CGPoint { CGPoint(x: readerOrigin.x + 6 * s, y: c.groundY + 18 * s) }
    private var hand: CGPoint { CGPoint(x: c.center + dir * 6 * px, y: c.groundY + 3.5 * px) }

    private func drawScene(_ now: CFTimeInterval) {
        let crate = ClawdSprite.mediaCrate(floppy: floppyInCrate, reel: reelInCrate)
        showEffect("crate", crate, origin: CGPoint(x: crateX - 8 * s, y: c.groundY), scale: s)
        showEffect("reader", ClawdSprite.retroReader(tape: tapeLoaded, spin: spin, progress: progress, busy: busy),
                   origin: readerOrigin, scale: s)
        let blink = writing && Int(now / 0.08) % 2 == 0
        showEffect("server", ClawdSprite.serverRack(filled: ssds, blink: blink),
                   origin: CGPoint(x: serverX - 8 * s, y: c.groundY), scale: s)
    }

    /// Gegenstand (zentriert) an einem Punkt zeigen.
    private func showItem(_ key: String, _ frame: ClawdSprite.Frame, at p: CGPoint, scale: CGFloat) {
        showEffect(key, frame, origin: CGPoint(x: p.x - CGFloat(frame[0].count) * scale / 2,
                                               y: p.y - CGFloat(frame.count) * scale / 2), scale: scale)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
    }

    /// Drei Datenpakete fliegen zum Server; danach steckt eine SSD mehr drin.
    private func transfer(_ t: TimeInterval) {
        let from = CGPoint(x: readerX, y: c.groundY + 24 * s), to = CGPoint(x: serverX, y: c.groundY + 22 * s)
        for k in 0..<3 {
            let start = Double(k) * 0.2
            let arc = BallArc(from: from, to: to, start: start, duration: 0.5, arc: 8 * px)
            if t >= start, t < start + 0.5 {
                showItem("bit\(k)", ClawdSprite.dataBit, at: arc.position(t), scale: s)
            } else {
                hideEffect("bit\(k)")
            }
        }
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        if once("setup") {
            dir = roomierDirection()
            // Platz für Kiste hinten und Server vorn – notfalls erst ein Stück zur Mitte gehen.
            let start = c.center
            if let r = c.centerRange {
                let lo = r.lowerBound - 7 * px, hi = r.upperBound + 7 * px
                startX = dir > 0 ? min(max(start, lo + 16 * px), hi - 39 * px)
                                 : max(min(start, hi - 16 * px), lo + 39 * px)
            } else {
                startX = start
            }
        }
        if phase > 0 { drawScene(now) }
        switch phase {
        case 0:
            // Zum Startpunkt
            if walk(to: startX, dt: dt) {
                c.face(-dir)
                next(now)
            }
            pose = Encounter.Pose(sprite: walkFrame())
        case 1:
            // Diskette aus der Kiste holen
            pose = Encounter.Pose(sprite: t < 0.4 ? ClawdSprite.sit : ClawdSprite.wave[1])
            if t >= 0.4 {
                if once("grabFloppy") { floppyInCrate = false; c.face(dir); c.say(.swish) }
                showItem("item", ClawdSprite.floppy("B"), at: hand, scale: s * 0.8)
            }
            if t >= 0.8 { next(now) }
        case 2:
            // Einlegen – klick
            let p = min(t / 0.4, 1)
            showItem("item", ClawdSprite.floppy("B"), at: lerp(hand, slot, p), scale: s * 0.8)
            pose = Encounter.Pose(sprite: ClawdSprite.wave[1])
            if t >= 0.45 {
                hideEffect("item")
                c.say(.plop)
                busy = true
                next(now)
            }
        case 3:
            // Quälend langsam lesen – Clawd tippt ungeduldig mit dem Fuß
            progress = min(Double(Int(t / 0.35)) / 7, 1)
            busy = Int(t / 0.12) % 2 == 0
            let tap = Int(t / 0.3) % 2 == 0
            pose = Encounter.Pose(sprite: tap ? ClawdSprite.stand : ClawdSprite.walkCycle[1])
            if t >= 2.6 {
                busy = false
                next(now)
            }
        case 4, 8:
            // Blitzschnell auf die SSD
            transfer(t)
            writing = t < 1.0
            if t >= 0.9, once("ssd\(phase)") {
                ssds += 1
                c.say(.beep)
            }
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if t >= 1.2 {
                writing = false
                progress = 0
                next(now)
            }
        case 5:
            // Tonband aus der Kiste
            c.face(-dir)
            pose = Encounter.Pose(sprite: t < 0.4 ? ClawdSprite.sit : ClawdSprite.wave[1])
            if t >= 0.4 {
                if once("grabReel") { reelInCrate = false; c.face(dir); c.say(.swish) }
                showItem("item", ClawdSprite.tapeReel(), at: hand, scale: s)
            }
            if t >= 0.8 { next(now) }
        case 6:
            // Auf die Bandmaschine legen
            let p = min(t / 0.45, 1)
            let arc = BallArc(from: hand, to: deck, start: 0, duration: 0.45, arc: 3 * px)
            showItem("item", ClawdSprite.tapeReel(), at: arc.position(min(t, 0.45)), scale: s)
            pose = Encounter.Pose(sprite: ClawdSprite.flail)
            if p >= 1 {
                hideEffect("item")
                tapeLoaded = true
                c.say(.plop)
                next(now)
            }
        case 7:
            // Band läuft … und läuft … Gähn.
            spin = Int(t / 0.12)
            progress = min(t / 2.6, 1)
            busy = true
            let yawning = t >= 0.8 && t < 1.9
            if yawning, once("yawn") { c.say(.yawn) }
            pose = Encounter.Pose(sprite: yawning ? ClawdSprite.yawnStretch : ClawdSprite.stand)
            if t >= 2.8 {
                busy = false
                next(now)
            }
        default:
            // Alte Diskette zurück in die Kiste, Server fertig
            if t < 0.6 {
                let arc = BallArc(from: slot, to: CGPoint(x: crateX, y: c.groundY + 8 * s), start: 0, duration: 0.6, arc: 10 * px)
                showItem("item", ClawdSprite.floppy("B"), at: arc.position(t), scale: s * 0.8)
                pose = Encounter.Pose(sprite: ClawdSprite.wave[1])
            } else {
                if once("binned") { hideEffect("item"); floppyInCrate = true; c.say(.wallPock) }
                let g = ClawdSprite.checkGlyph, gs = px * 0.8
                showEffect("check", g, origin: CGPoint(x: serverX - CGFloat(g[0].count) * gs / 2, y: c.groundY + 14 * px),
                           scale: gs)
                pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
                if once("yay") { c.say(.happy) }
            }
            if t >= 2.0 { finish() }
        }
    }
}

/// Dashboard bauen: Balken wachsen nacheinander, einer spinnt, ein Klaps auf den Monitor hilft,
/// dann zieht sich eine grüne Trendlinie nach oben.
final class DashboardJob: Job {
    override class var name: String { "dashboard" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil && !c.isOnWall }

    private static let targets = [5, 8, 6, 11]
    private var dir: CGFloat = 1
    private var panelX: CGFloat = 0
    private var s: CGFloat { px / 2 }

    private func drawPanel(_ frame: ClawdSprite.Frame, shake: CGFloat = 0) {
        showEffect("panel", frame, origin: CGPoint(x: panelX - CGFloat(frame[0].count) * s / 2 + shake, y: c.groundY),
                   scale: s)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
                panelX = c.center + dir * 14 * px
            }
            drawPanel(ClawdSprite.dashboard(heights: []))
            pose = Encounter.Pose(sprite: ClawdSprite.stand)
            if t >= 0.5 { next(now) }
        case 1:
            // Balken für Balken
            let i = min(Int(t / 0.7), 3)
            let local = t - Double(i) * 0.7
            var heights = Array(Self.targets.prefix(i))
            heights.append(Int((Double(Self.targets[i]) * min(local / 0.5, 1)).rounded()))
            drawPanel(ClawdSprite.dashboard(heights: heights))
            if once("bar\(i)") { c.say(.beep) }
            pose = Encounter.Pose(sprite: local < 0.5 ? ClawdSprite.wave[1] : ClawdSprite.stand)
            if t >= 2.8 { next(now) }
        case 2:
            // Ein Balken spinnt – Klaps auf den Monitor
            let tapping = t >= 0.9
            var heights = Self.targets
            if t < 1.3 { heights[2] = Int(t / 0.1) % 2 == 0 ? 1 : 9 }
            drawPanel(ClawdSprite.dashboard(heights: heights, glitch: t < 1.3), shake: tapping && t < 1.3 ? 0.5 * s : 0)
            if t < 0.9 {
                showAboveHead("glyph", ClawdSprite.exclamationGlyph)
                pose = Encounter.Pose(sprite: ClawdSprite.flail, lift: t < 0.3 ? 1 : 0)
            } else {
                hideEffect("glyph")
                if once("tap") { c.say(.wallPock) }
                pose = Encounter.Pose(sprite: ClawdSprite.wave[Int(t / 0.15) % 2])
            }
            if t >= 1.6 { next(now) }
        case 3:
            // Trendlinie nach oben
            drawPanel(ClawdSprite.dashboard(heights: Self.targets, trend: t / 1.2))
            pose = Encounter.Pose(sprite: ClawdSprite.wave[Int(t / 0.2) % 2])
            if t >= 1.4 { next(now) }
        default:
            drawPanel(ClawdSprite.dashboard(heights: Self.targets, trend: 1))
            showAboveHead("glyph", ClawdSprite.checkGlyph)
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("yay") { c.say(.happy) }
            if t >= 1.4 { finish() }
        }
    }
}

/// Prototyp entwerfen: Kopfzeile, Bild, Text und Knopf auf die Leinwand ziehen. Der Knopf steht
/// nicht in der Flucht – Clawd schubst ihn, bis er an der Hilfslinie sitzt.
final class PrototypeJob: Job {
    override class var name: String { "prototype" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil && !c.isOnWall }

    private var dir: CGFloat = 1
    private var boardX: CGFloat = 0
    private var s: CGFloat { px / 2 }

    private func drawBoard(_ frame: ClawdSprite.Frame) {
        // Weiße Leinwand: Schatten statt Rand, damit sie auf hellem Grund erkennbar ist.
        showEffect("board", frame, origin: CGPoint(x: boardX - CGFloat(frame[0].count) * s / 2, y: c.groundY), scale: s,
                   shadow: true)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
                boardX = c.center + dir * 15 * px
            }
            drawBoard(ClawdSprite.prototype(elements: 0))
            pose = Encounter.Pose(sprite: ClawdSprite.stand)
            if t >= 0.5 { next(now) }
        case 1:
            // Vier Teile nacheinander auf die Leinwand ziehen
            let i = min(Int(t / 0.8), 3)
            let local = t - Double(i) * 0.8
            let shown = local >= 0.5 ? i + 1 : i
            drawBoard(ClawdSprite.prototype(elements: shown, buttonOffset: 2))
            if local >= 0.5, once("drop\(i)") { c.say(.swish) }
            pose = Encounter.Pose(sprite: local < 0.5 ? ClawdSprite.wave[Int(local / 0.2) % 2] : ClawdSprite.stand)
            if t >= 3.2 { next(now) }
        case 2:
            // Hm – der Knopf steht nicht in der Flucht
            drawBoard(ClawdSprite.prototype(elements: 4, buttonOffset: 2, guide: Int(t / 0.25) % 2 == 0))
            showAboveHead("glyph", ClawdSprite.questionGlyph)
            pose = Encounter.Pose(sprite: ClawdSprite.lookCycle[Int(t / 0.5) % 2 == 0 ? 0 : 1])
            if once("hmm"), c.isChatty { c.say(.murmur) }
            if t >= 1.2 { hideEffect("glyph"); next(now) }
        case 3:
            // Zweimal schubsen
            let offset = t < 0.4 ? 2 : (t < 0.9 ? 1 : 0)
            drawBoard(ClawdSprite.prototype(elements: 4, buttonOffset: offset, guide: true))
            for (k, at) in [0.4, 0.9].enumerated() where t >= at { if once("nudge\(k)") { c.say(.wallPock) } }
            let nudging = (t >= 0.3 && t < 0.5) || (t >= 0.8 && t < 1.0)
            pose = Encounter.Pose(sprite: nudging ? ClawdSprite.wave[1] : ClawdSprite.stand, lift: nudging ? 1 : 0)
            if t >= 1.4 { next(now) }
        default:
            drawBoard(ClawdSprite.prototype(elements: 4))
            showAboveHead("glyph", ClawdSprite.checkGlyph)
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, particles: .sparks)
            if once("yay") { c.say(.happy) }
            if t >= 1.4 { finish() }
        }
    }
}
