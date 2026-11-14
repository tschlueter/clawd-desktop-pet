import AppKit

// MARK: - Freizeit

/// Papierflieger: im Sitzen falten, aufstehen, werfen – der Flieger gleitet in einer sanften
/// Wellenbahn davon, landet und bleibt noch kurz liegen (oder verschwindet am Bildschirmrand).
final class PaperPlaneJob: Job {
    override class var name: String { "plane" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil && !c.isOnWall }

    private var dir: CGFloat = 1
    private var start = CGPoint.zero
    private var landing = CGPoint.zero
    private var duration: TimeInterval = 3
    private var scale: CGFloat { px * 0.7 }

    /// Flieger zentriert an einem Punkt zeigen; nach links gespiegelt.
    private func drawPlane(_ frame: ClawdSprite.Frame, at p: CGPoint) {
        let w = CGFloat(frame[0].count) * scale
        showEffect("plane", frame, origin: CGPoint(x: p.x - w / 2, y: p.y), scale: scale, mirrored: dir < 0,
                   shadow: true)
    }

    private var hand: CGPoint { CGPoint(x: c.center + dir * 6 * px, y: c.groundY + 5 * px) }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Falten: drei Stufen, bei jeder raschelt es.
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
            }
            let fold = min(Int(t / 0.7), 2)
            if once("fold\(fold)") { c.say(.swish) }
            pose = Encounter.Pose(sprite: ClawdSprite.sit)
            drawPlane(ClawdSprite.paperFolds[fold], at: CGPoint(x: c.center + dir * 5 * px, y: c.groundY + 1.5 * px))
            if t >= 2.2 { next(now) }
        case 1:
            // Aufstehen und ausholen
            pose = Encounter.Pose(sprite: ClawdSprite.wave[1])
            drawPlane(ClawdSprite.paperPlane, at: hand)
            if t >= 0.4 {
                c.say(.swish)
                start = hand
                let distance = CGFloat.random(in: 300...600)
                let endX = start.x + dir * distance
                // Auf der eigenen Fläche landen, sonst bis zum Bildschirmboden sinken.
                let onPlatform = c.centerRange.map { $0.contains(endX) } ?? false
                let floor = world.screen(containingX: endX)?.frame.minY ?? c.groundY
                landing = CGPoint(x: endX, y: onPlatform ? c.groundY : floor)
                duration = Double(distance) / .random(in: 110...150)
                next(now)
            }
        case 2:
            // Gleitflug: erst kurz steigen, dann in Wellen sinken.
            let p = CGFloat(min(t / duration, 1))
            let x = start.x + (landing.x - start.x) * p
            let y = start.y + (landing.y - start.y) * p + 45 * sin(.pi * p) * (1 - 0.4 * p)
                + 12 * sin(4 * .pi * p) * (1 - p)
            pose = Encounter.Pose(sprite: p < 0.15 ? ClawdSprite.wave[1] : ClawdSprite.stand)
            if world.screen(containingX: x) == nil {
                hideEffect("plane") // zum Bildschirm hinaus
                next(now)
                return
            }
            drawPlane(ClawdSprite.paperPlane, at: CGPoint(x: x, y: y))
            if p >= 1 {
                leaveBehind("plane", lifetime: 6)
                next(now)
            }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("yay") { c.say(.happy) }
            if t >= 1.2 { finish() }
        }
    }
}

/// Drachen steigen lassen: kurzer Anlauf, der Drache steigt über Clawd auf, schaukelt eine
/// Weile im Wind (Schnur als Punktkette, flatternder Schwanz) und wird wieder eingeholt.
final class KiteJob: Job {
    override class var name: String { "kite" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard c.surfaceKind != nil, !c.isOnWall, let r = c.centerRange, r.upperBound - r.lowerBound >= 140 else { return false }
        return headroom(c) >= 250
    }

    /// Platz nach oben bis unter die Menüleiste.
    static func headroom(_ c: PetController) -> CGFloat {
        guard let s = c.world.screen(containingX: c.center, y: c.groundY + 1) else { return 0 }
        return s.visibleFrame.maxY - c.groundY
    }

    private var dir: CGFloat = 1
    private var runTo: CGFloat = 0
    private var height: CGFloat = 200
    private var flyTime: TimeInterval = 12
    /// Kantenlänge einer Drachenzelle: ganze Bildschirmpixel (sonst wird die Pixelgrafik unscharf),
    /// abgerundet, damit der Drache (31 Zellen) nie höher als Clawd (8 × px) ist.
    private var scale: CGFloat {
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        return max(floor(px * 0.25 * backing), 1) / backing
    }

    /// Kreuzungspunkt der Stäbe relativ zu Clawds Füßen in Höhe `h`, mit Wind-Schaukeln.
    private func kitePosition(height h: CGFloat, now: CFTimeInterval, sway: CGFloat) -> CGPoint {
        CGPoint(x: c.center + dir * (30 + h * 0.3) + sway * 22 * sin(now * 1.3),
                y: c.groundY + h + sway * 8 * sin(now * 2.1))
    }

    /// Drachen mit dem Stabkreuz bei `p`; lehnt sich zum Halter hin (für links gespiegelt).
    private func drawKite(at p: CGPoint, now: CFTimeInterval) {
        let frame = ClawdSprite.kite
        let cols = CGFloat(frame[0].count), rows = CGFloat(frame.count)
        let mirrored = dir < 0
        let cross = ClawdSprite.kiteCross, tipCell = ClawdSprite.kiteTip
        let origin = CGPoint(x: p.x - (mirrored ? cols - cross.x : cross.x) * scale,
                             y: p.y - (rows - cross.y) * scale)
        showEffect("kite", frame, origin: origin, scale: scale, mirrored: mirrored)
        let tip = CGPoint(x: origin.x + (mirrored ? cols - tipCell.x : tipCell.x) * scale,
                          y: origin.y + (rows - tipCell.y) * scale)
        drawTail(from: tip, now: now)
        drawString(to: p)
    }

    /// Flatternder Schwanz von der unteren Spitze: geschwungene Punktkette mit zwei bunten Schleifen,
    /// weht vom Halter weg und wird nie länger, als Platz bis zum Boden ist.
    private func drawTail(from tip: CGPoint, now: CFTimeInterval) {
        let unit = px / 4
        let length = min(55 * unit, max(tip.y - c.groundY - 4, 0))
        let dot = max((scale * 2).rounded(), 1)
        let count = 22
        for i in 1...count {
            let t = CGFloat(i) / CGFloat(count)
            let x = tip.x + dir * (t * 30 * unit * length / (55 * unit) + 4 * unit * sin(now * 5 - Double(t) * 9))
            let y = tip.y - t * length
            showRect("tail\(i)", CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot),
                     color: ClawdSprite.nsColor("o").cgColor)
            if i == 8 || i == 15 {
                let bow = CGSize(width: max((scale * 5).rounded(), 3), height: max((scale * 2).rounded(), 1))
                showRect("bow\(i)", CGRect(x: x - bow.width / 2, y: y - bow.height / 2, width: bow.width, height: bow.height),
                         color: ClawdSprite.nsColor(i == 8 ? "1" : "2").cgColor)
            }
        }
    }

    /// Schnur von der Hand zum Drachen: Punkte entlang einer leicht durchhängenden Linie.
    private func drawString(to kite: CGPoint) {
        let hand = CGPoint(x: c.center + dir * 5 * px, y: c.groundY + 6 * px)
        let length = hypot(kite.x - hand.x, kite.y - hand.y)
        let dot = max((px * 0.5).rounded(), 1)
        let count = min(Int(length / (px * 2.2)), 60)
        for i in 0..<60 {
            let key = "string\(i)"
            guard i < count else { hideEffect(key); continue }
            let p = CGFloat(i + 1) / CGFloat(count + 1)
            let sag = length * 0.06 * sin(.pi * p)
            let point = CGPoint(x: hand.x + (kite.x - hand.x) * p, y: hand.y + (kite.y - hand.y) * p - sag)
            showRect(key, CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot),
                     color: ClawdSprite.nsColor("o").cgColor)
        }
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Anlauf mit dem Drachen
            if once("setup") {
                dir = roomierDirection()
                height = min(.random(in: 150...250), Self.headroom(c) - 50)
                flyTime = .random(in: 10...15)
                runTo = c.center + dir * 70
            }
            let arrived = walk(to: runTo, speed: 1.6, dt: dt)
            pose = Encounter.Pose(sprite: walkFrame(stride: 1.4))
            let lift = CGFloat(min(t / 1.2, 1)) * 30
            drawKite(at: CGPoint(x: c.center - dir * 8 * px, y: c.groundY + 14 * px + lift), now: now)
            if arrived || t >= 2.5 {
                c.face(dir)
                c.say(oneOf: Voice.Sound.cheer)
                next(now)
            }
        case 1:
            // Aufsteigen
            let p = CGFloat(min(t / 2.5, 1))
            let eased = p * p * (3 - 2 * p)
            pose = Encounter.Pose(sprite: ClawdSprite.wave[1])
            drawKite(at: kitePosition(height: 14 * px + (height - 14 * px) * eased, now: now, sway: eased), now: now)
            if p >= 1 {
                c.say(.happy)
                next(now)
            }
        case 2:
            // Schweben im Wind
            pose = Encounter.Pose(sprite: Int(t / 1.6) % 4 == 3 ? ClawdSprite.happyStand : ClawdSprite.wave[1])
            drawKite(at: kitePosition(height: height, now: now, sway: 1), now: now)
            if t >= flyTime { next(now) }
        case 3:
            // Einholen
            let p = CGFloat(min(t / 2.5, 1))
            let eased = p * p * (3 - 2 * p)
            pose = Encounter.Pose(sprite: ClawdSprite.wave[Int(t / 0.3) % 2])
            drawKite(at: kitePosition(height: height - (height - 14 * px) * eased, now: now, sway: 1 - eased), now: now)
            if p >= 1 { next(now) }
        default:
            cleanup()
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("yay") { c.say(.happy) }
            if t >= 1.0 { finish() }
        }
    }
}

// MARK: - Kochen

/// Kochen mit Kochmütze: Herd aufstellen, umrühren, eine Tomate hinein, weiterrühren, abschmecken.
final class CookingJob: Job {
    override class var name: String { "cook" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard c.surfaceKind != nil, !c.isOnWall, let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 120
    }

    private var dir: CGFloat = 1
    private var stoveX: CGFloat = 0
    private var scale: CGFloat { px * 0.75 }

    private func drawStove(_ now: CFTimeInterval, steam: Bool = true) {
        let frame = ClawdSprite.stove[Int(now / 0.15) % ClawdSprite.stove.count]
        let w = CGFloat(frame[0].count) * scale
        showEffect("stove", frame, origin: CGPoint(x: stoveX - w / 2, y: c.groundY), scale: scale)
        guard steam else { return }
        // Dampf steigt aus dem Topf auf: drei Fäden, versetzt, die beim Aufsteigen verblassen.
        let glyph = ClawdSprite.steamGlyph
        let s = px * 0.5
        let potTop = c.groundY + CGFloat(frame.count) * scale
        for k in 0..<3 {
            let p = CGFloat((now / 1.6 + Double(k) / 3).truncatingRemainder(dividingBy: 1))
            let x = stoveX + CGFloat(k - 1) * 1.5 * px - CGFloat(glyph[0].count) * s / 2
                + (sin(p * .pi * 2) * 0.5).rounded() * px
            showEffect("steam\(k)", glyph, origin: CGPoint(x: x, y: potTop + (p * 6).rounded() * px),
                       scale: s, opacity: Float(sin(.pi * p)))
        }
    }

    private func stir(_ t: TimeInterval) -> Encounter.Pose {
        let stroke = Int(t / 0.3)
        if once("stir\(phase)-\(stroke / 2)") { c.say(.swish) }
        return Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.ladle(left: stroke % 2 == 0),
                              hat: ClawdSprite.chefHat)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
                stoveX = c.center + dir * 13 * px
            }
            drawStove(now, steam: false) // Herd wird gerade erst angeheizt
            pose = Encounter.Pose(sprite: ClawdSprite.stand, hat: ClawdSprite.chefHat)
            if t >= 0.6 { next(now) }
        case 1, 3:
            drawStove(now)
            pose = stir(t)
            if t >= (phase == 1 ? 3.0 : 2.0) { next(now) }
        case 2:
            // Tomate in den Topf werfen
            drawStove(now)
            pose = Encounter.Pose(sprite: ClawdSprite.wave[1], hat: ClawdSprite.chefHat)
            let p = CGFloat(min(t / 0.6, 1))
            if p < 1 {
                let from = CGPoint(x: c.center + dir * 5 * px, y: c.groundY + 7 * px)
                let to = CGPoint(x: stoveX, y: c.groundY + 6 * px)
                let x = from.x + (to.x - from.x) * p, y = from.y + (to.y - from.y) * p + 14 * px * 0.25 * sin(.pi * p)
                showEffect("tomato", ClawdSprite.tomato, origin: CGPoint(x: x - 1.5 * scale, y: y), scale: scale)
            } else if once("plop") {
                hideEffect("tomato")
                c.say(.pour) // brutzelt
            }
            if t >= 1.2 { next(now) }
        case 4:
            // Abschmecken – lecker!
            drawStove(now)
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, particles: .hearts, hat: ClawdSprite.chefHat)
            if once("yum") { c.say(.happy) }
            if t >= 1.4 { finish() }
        default:
            finish()
        }
    }
}

// MARK: - Bogenschießen

/// Bogenschießen: Zielscheibe aufstellen, dreimal spannen und schießen; Treffer bleiben stecken.
final class ArcheryJob: Job {
    override class var name: String { "archery" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard c.surfaceKind != nil, !c.isOnWall, let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 200
    }

    private var dir: CGFloat = 1
    private var targetX: CGFloat = 0
    private var shots = 0
    private var hits = 0
    private var miss = false
    private var flight = BallArc(from: .zero, to: .zero, start: 0, duration: 1, arc: 0)
    private var wobbleUntil: CFTimeInterval = 0
    private var targetScale: CGFloat { px * 0.8 }
    private var targetWidth: CGFloat { CGFloat(ClawdSprite.target[0].count) * targetScale }
    /// Mitte der Scheibe (Höhe des Zentrums).
    private var bullseye: CGPoint {
        let row = ClawdSprite.target.firstIndex { $0.contains("j") } ?? 0
        return CGPoint(x: targetX, y: c.groundY + (CGFloat(ClawdSprite.target.count - row) - 0.5) * targetScale)
    }

    private func drawTarget(_ now: CFTimeInterval) {
        let wobble: CGFloat = now < wobbleUntil ? (Int(now / 0.05) % 2 == 0 ? 1 : -1) : 0
        showEffect("target", ClawdSprite.target,
                   origin: CGPoint(x: targetX - targetWidth / 2 + wobble, y: c.groundY), scale: targetScale,
                   shadow: true)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        if phase > 0 { drawTarget(now) }
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
                let wanted = c.center + dir * .random(in: 150...240)
                if let r = c.centerRange {
                    let half = c.spriteWidth / 2
                    targetX = min(max(wanted, r.lowerBound - half + targetWidth), r.upperBound + half - targetWidth)
                } else {
                    targetX = wanted
                }
            }
            drawTarget(now)
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.bow(.relaxed))
            if t >= 0.6 { next(now) }
        case 1:
            // Spannen und zielen
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.bow(.drawn))
            if t >= 0.9 {
                c.say(.plop)
                miss = Double.random(in: 0..<1) < 0.4
                let from = CGPoint(x: c.center + dir * 9 * px, y: c.groundY + 4.5 * px)
                let aim = bullseye
                let to: CGPoint
                if miss {
                    // Daneben: zu kurz, zu weit oder über die Scheibe hinweg – jeweils in den Boden.
                    switch Int.random(in: 0..<3) {
                    case 0: to = CGPoint(x: aim.x - dir * .random(in: 25...50), y: c.groundY)
                    case 1: to = CGPoint(x: aim.x + dir * .random(in: 30...70), y: c.groundY)
                    default: to = CGPoint(x: aim.x + dir * .random(in: 80...120), y: c.groundY)
                    }
                } else {
                    // Treffer irgendwo auf der Scheibe – nicht immer ins Gelbe.
                    let r = CGFloat.random(in: 0...4), a = CGFloat.random(in: 0..<(2 * .pi))
                    to = CGPoint(x: aim.x + cos(a) * r * targetScale, y: aim.y + sin(a) * r * targetScale)
                }
                // Sichtbarer Bogen, je weiter, desto höher.
                let distance = abs(to.x - from.x)
                flight = BallArc(from: from, to: to, start: now, duration: Double(distance) / 480 + 0.15,
                                 arc: distance * 0.16 + 8)
                next(now)
            }
        case 2:
            // Pfeil fliegt
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.bow(.relaxed))
            // Pfeil dreht sich mit der Flugbahn – Spitze voran.
            let p = flight.position(now)
            showRotated("arrow", ClawdSprite.arrow, center: p, scale: px * 0.6, angle: flight.heading(now))
            if flight.progress(now) >= 1 {
                hideEffect("arrow")
                shots += 1
                if miss {
                    c.say(.wallPock)
                    if c.chatty(0.7) { c.say(.murmur) }
                } else {
                    hits += 1
                    c.say(.pock)
                    wobbleUntil = now + 0.3
                    let sw = CGFloat(ClawdSprite.stuckArrow[0].count) * px * 0.6
                    showEffect("stuck\(shots)", ClawdSprite.stuckArrow,
                               origin: CGPoint(x: flight.to.x - (dir > 0 ? sw : 0), y: flight.to.y - px * 0.9),
                               scale: px * 0.6, mirrored: dir < 0)
                }
                next(now)
            }
        case 3:
            pose = Encounter.Pose(sprite: miss ? ClawdSprite.lookCycle[1] : ClawdSprite.happyStand,
                                  prop: ClawdSprite.bow(.relaxed))
            if t >= 0.7 {
                if shots < 3 { go(to: 1, now: now) } else { next(now) }
            }
        default:
            // Bilanz: mindestens zwei Treffer → Jubel
            let good = hits >= 2
            pose = Encounter.Pose(sprite: good ? ClawdSprite.happyStand : ClawdSprite.stand,
                                  prop: ClawdSprite.bow(.relaxed), particles: good ? .sparks : .none)
            if once("done") { c.say(good ? .happy : .murmur) }
            if t >= 1.3 { finish() }
        }
    }
}

// MARK: - Zaubern

/// Zaubern mit Hut und Stab: Hokuspokus, Funken fliegen, Rauchwolke – und ein Blumenstrauß erscheint.
final class MagicJob: Job {
    override class var name: String { "magic" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil && !c.isOnWall }

    private var dir: CGFloat = 1
    private var spot = CGPoint.zero
    private var scale: CGFloat { px * 0.7 }

    private var wandTip: CGPoint { CGPoint(x: c.center + dir * 9 * px, y: c.groundY + 5.5 * px) }

    private func drawCentered(_ key: String, _ frame: ClawdSprite.Frame, at p: CGPoint) {
        let w = CGFloat(frame[0].count) * scale
        showEffect(key, frame, origin: CGPoint(x: p.x - w / 2, y: p.y), scale: scale)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        let hat = ClawdSprite.wizardHat
        switch phase {
        case 0:
            // Hokuspokus
            if once("setup") {
                dir = roomierDirection()
                c.face(dir)
                spot = CGPoint(x: c.center + dir * 16 * px, y: c.groundY)
                if c.chatty(0.8) { c.say(.murmur) }
            }
            pose = Encounter.Pose(sprite: ClawdSprite.wave[Int(t / 0.25) % 2], prop: ClawdSprite.wand(.up),
                                  particles: .sparks, hat: hat)
            if t >= 1.2 { next(now) }
        case 1:
            // Funken fliegen zum Zauberplatz
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.wand(.forward), hat: hat)
            let p = CGFloat(min(t / 0.5, 1))
            let pt = CGPoint(x: wandTip.x + (spot.x - wandTip.x) * p, y: wandTip.y + (spot.y + 2 * px - wandTip.y) * p)
            drawCentered("spark", ClawdSprite.sparkleGlyph, at: pt)
            if t >= 0.5 {
                hideEffect("spark")
                c.say(.pickup)
                next(now)
            }
        case 2:
            // Puff!
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.wand(.forward), hat: hat)
            drawCentered("puff", ClawdSprite.puff[t < 0.15 ? 0 : 1], at: spot)
            if t >= 0.35 {
                hideEffect("puff")
                next(now)
            }
        case 3:
            // Tadaa – ein Blumenstrauß!
            drawCentered("bouquet", ClawdSprite.bouquet, at: spot)
            pose = Encounter.Pose(sprite: t < 0.6 ? ClawdSprite.squash : ClawdSprite.happyStand,
                                  prop: ClawdSprite.wand(.up), particles: .sparks, hat: hat)
            if once("tada") { c.say(.happy) }
            if t >= 1.8 { next(now) }
        case 4:
            // Strauß verschwindet wieder im Rauch
            hideEffect("bouquet")
            drawCentered("puff", ClawdSprite.puff[t < 0.15 ? 1 : 0], at: spot)
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, prop: ClawdSprite.wand(.forward), hat: hat)
            if t >= 0.35 { finish() }
        default:
            finish()
        }
    }
}
