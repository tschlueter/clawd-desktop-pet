import AppKit

// MARK: - Putzen & Pflege

/// Fenster putzen: mit dem Schwamm an der Fensteroberkante entlang, dahinter funkelt es.
final class WindowCleaningJob: Job {
    override class var name: String { "windows" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard case .window = c.surfaceKind, let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 100
    }

    private var dir: CGFloat = 1
    private var distance: CGFloat = 0
    private var lastSparkleAt: CGFloat = 0
    private var lastStroke = -1
    private var sparkles: [(x: CGFloat, y: CGFloat, born: CFTimeInterval)] = []

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                if let r = c.centerRange {
                    distance = min(dir > 0 ? r.upperBound - c.center : c.center - r.lowerBound, 180) - 2
                }
                c.face(dir)
            }
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.sponge(forward: true))
            if t(now) >= 0.5 { next(now) }
        case 1:
            let step = c.walkSpeed * 0.5 * CGFloat(dt)
            c.moveCenter(to: c.center + dir * step)
            walked += step
            let stroke = Int(walked / px)
            if stroke != lastStroke, stroke % 4 == 0 { c.say(.swish) }
            lastStroke = stroke
            if walked - lastSparkleAt > 26 {
                lastSparkleAt = walked
                sparkles.append((c.center - dir * 10 * px, c.groundY + px, now))
            }
            pose = Encounter.Pose(sprite: walkFrame(), prop: ClawdSprite.sponge(forward: (stroke / 2) % 2 == 0))
            if walked >= distance { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("done"), c.isChatty { c.say(.happy) }
            if t(now) >= 1.0 { finish() }
        }
        drawSparkles(now)
    }

    private func drawSparkles(_ now: CFTimeInterval) {
        sparkles.removeAll { now - $0.born > 1.6 }
        for i in 0..<8 {
            guard i < sparkles.count else { hideEffect("s\(i)"); continue }
            let s = sparkles[i]
            let age = (now - s.born) / 1.6
            showEffect("s\(i)", ClawdSprite.sparkleGlyph, origin: CGPoint(x: s.x, y: s.y + CGFloat(age) * 3 * px),
                       scale: px * 0.6, opacity: Float(sin(.pi * age)))
        }
    }
}

/// Dock-Symbol polieren: hinhocken, mit dem Tuch reiben, das Symbol glänzt.
final class IconPolishJob: Job {
    override class var name: String { "polish" }
    override class func isPossible(_ c: PetController) -> Bool {
        c.surfaceKind == .dock && !c.world.dockIcons.isEmpty
    }

    private var icon = NSRect.zero
    private var dir: CGFloat = 1

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        switch phase {
        case 0:
            if once("pick") {
                // Eines der nächstgelegenen Symbole
                let near = world.dockIcons.sorted { abs($0.midX - c.center) < abs($1.midX - c.center) }.prefix(4)
                icon = near.randomElement() ?? world.dockIcons[0]
                dir = icon.midX >= c.center ? 1 : -1
            }
            let target = icon.midX - dir * 8 * px
            let arrived = walk(to: target, dt: dt)
            pose = Encounter.Pose(sprite: arrived ? ClawdSprite.stand : walkFrame())
            if arrived {
                c.face(dir)
                next(now)
            }
        case 1:
            let t = t(now)
            let stroke = Int(t / 0.18)
            if once("rub\(stroke / 2)") { c.say(.swish) }
            pose = Encounter.Pose(sprite: ClawdSprite.sit, prop: ClawdSprite.cloth(forward: stroke % 2 == 0))
            if t >= 2.8 { next(now) }
        default:
            let t = t(now)
            // Glanz auf dem Symbol
            let pulse = Float(sin(.pi * min(t / 1.0, 1)))
            showEffect("shine", ClawdSprite.star, origin: CGPoint(x: icon.midX - 2.5 * px * 0.9, y: icon.midY - 2.5 * px * 0.9),
                       scale: px * 0.9, opacity: pulse)
            showEffect("twinkle", ClawdSprite.sparkleGlyph, origin: CGPoint(x: icon.minX + icon.width * 0.25, y: icon.maxY - 3 * px),
                       scale: px * 0.5, opacity: pulse)
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("done"), c.isChatty { c.say(.happy) }
            if t >= 1.1 { finish() }
        }
    }
}

/// Papierkorb rausbringen: Sack herausziehen, zuknoten, zum Dock-Ende tragen und wegwerfen.
final class TrashOutJob: Job {
    override class var name: String { "trash" }
    override class func isPossible(_ c: PetController) -> Bool {
        c.surfaceKind == .dock && c.world.trash != nil
    }

    private var trash = NSRect.zero
    private var throwDir: CGFloat = 1
    private var throwFrom = CGPoint.zero
    private var bagWidth: CGFloat { CGFloat(ClawdSprite.trashBag[0].count) * px }

    private func bagAboveHead(lift: CGFloat = 0) -> CGPoint {
        CGPoint(x: c.center - bagWidth / 2, y: c.groundY + (8.5 + lift) * px)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup"), let tr = world.trash { trash = tr }
            let arrived = walk(to: trash.midX, dt: dt)
            pose = Encounter.Pose(sprite: arrived ? ClawdSprite.stand : walkFrame())
            if arrived { next(now) }
        case 1:
            // In die Hocke, Sack aus dem Papierkorb ziehen
            pose = Encounter.Pose(sprite: ClawdSprite.sit)
            let p = CGFloat(min(t / 1.0, 1))
            let y = trash.midY + (c.groundY + 2 * px - trash.midY) * p
            showEffect("bag", ClawdSprite.trashBag, origin: CGPoint(x: trash.midX - bagWidth / 2, y: y), scale: px)
            if t >= 1.0 { next(now) }
        case 2:
            // Hochstemmen
            pose = Encounter.Pose(sprite: ClawdSprite.yawnStretch)
            showEffect("bag", ClawdSprite.trashBag, origin: bagAboveHead(), scale: px)
            if once("lift") { c.say(.hop) }
            if t >= 0.5 {
                // Zum näheren Dock-Ende
                if let r = c.centerRange {
                    throwDir = (r.upperBound - c.center) < (c.center - r.lowerBound) ? 1 : -1
                }
                next(now)
            }
        case 3:
            guard let r = c.centerRange else { finish(); return }
            let target = throwDir > 0 ? r.upperBound : r.lowerBound
            let arrived = walk(to: target, speed: 0.8, dt: dt)
            let wobble = CGFloat(Int(walked / (3 * px)) % 2) * 0.5
            pose = Encounter.Pose(sprite: ClawdSprite.yawnStretch, lift: wobble)
            showEffect("bag", ClawdSprite.trashBag, origin: bagAboveHead(lift: wobble), scale: px)
            if arrived {
                c.face(throwDir)
                throwFrom = bagAboveHead()
                next(now)
            }
        case 4:
            // Schwung – und weg!
            pose = Encounter.Pose(sprite: t < 0.25 ? ClawdSprite.flail : ClawdSprite.stand)
            if once("throw") { c.say(.whee) }
            let p = CGFloat(min(t / 1.0, 1))
            let x = throwFrom.x + throwDir * 140 * p
            let y = throwFrom.y + 40 * sin(.pi * p * 0.6) - 260 * p * p
            showEffect("bag", ClawdSprite.trashBag, origin: CGPoint(x: x, y: y), scale: px,
                       opacity: Float(p < 0.7 ? 1 : (1 - p) / 0.3))
            if t >= 1.0 {
                hideEffect("bag")
                next(now)
            }
        default:
            // Stirn abwischen
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, particles: .sweat)
            if t >= 1.4 { finish() }
        }
    }
}

/// Blume gießen: Topf vor sich abstellen, gießen – einmal am Tag wächst die Pflanze.
/// Danach bleibt sie noch kurz stehen und verblasst (wie die Wäscheleine).
final class WaterPlantJob: Job {
    override class var name: String { "water" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard c.surfaceKind != nil else { return false }
        // Durstig? Dann gern; sonst nur selten.
        return Settings.plantLastWatered != WaterPlantJob.today || Double.random(in: 0..<1) < 0.2
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var today: String { dayFormatter.string(from: Date()) }

    private var plantX: CGFloat = 0
    private var grew = false

    private func drawPlant() {
        let frame = ClawdSprite.plantStages[Settings.plantStage]
        showEffect("plant", frame, origin: CGPoint(x: plantX - CGFloat(frame[0].count) * px / 2, y: c.groundY), scale: px)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Topf abstellen
            if once("setup") {
                c.face(roomierDirection())
                plantX = c.center + c.facing * 9.5 * px
            }
            pose = Encounter.Pose(sprite: ClawdSprite.sit)
            if t >= 0.4 { drawPlant() }
            if t >= 0.7 { next(now) }
        case 1:
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.wateringCan(tilted: false))
            if t >= 0.4 { next(now) }
        case 2:
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.wateringCan(tilted: true), particles: .water)
            if once("pour") { c.say(.pour) }
            if t >= 2.2 {
                if Settings.plantLastWatered != Self.today {
                    Settings.plantLastWatered = Self.today
                    if Settings.plantStage < 4 {
                        Settings.plantStage += 1
                        grew = true
                    }
                    drawPlant()
                }
                next(now)
            }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if grew {
                let p = Float(sin(.pi * min(t / 1.0, 1)))
                showEffect("grow", ClawdSprite.sparkleGlyph, origin: CGPoint(x: plantX - 1.5 * px, y: c.groundY + 9 * px),
                           scale: px * 0.7, opacity: p)
            }
            if once("done"), c.isChatty { c.say(.happy) }
            if t >= 1.1 {
                leaveBehind("plant", lifetime: 8)
                finish()
            }
        }
    }
}
