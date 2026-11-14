import AppKit

// MARK: - Handwerk

/// Hämmern: Bauhelm auf, hinhocken, Nagel für Nagel einschlagen – mit Funken.
final class HammerJob: Job {
    override class var name: String { "hammer" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var hits = 0
    private var lastCycle = -1

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            pose = Encounter.Pose(sprite: ClawdSprite.stand, hat: ClawdSprite.hardHat)
            if t >= 0.5 { next(now) }
        case 1:
            let cycle = Int(t / 0.5)
            let local = t.truncatingRemainder(dividingBy: 0.5)
            let down = local >= 0.3
            if down, cycle != lastCycle {
                lastCycle = cycle
                hits += 1
                c.say(.wallPock)
            }
            let nail = max(2 - hits / 3, 0)
            pose = Encounter.Pose(sprite: ClawdSprite.sit, prop: ClawdSprite.hammer(down: down, nail: nail),
                                  particles: down ? .sparks : .none, hat: ClawdSprite.hardHat)
            if t >= 4.5 { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, hat: ClawdSprite.hardHat)
            if once("done"), c.isChatty { c.say(.happy) }
            if t >= 0.9 { finish() }
        }
    }
}

/// Streichen: mit dem Pinsel die Fensterkante bemalen, auf der Clawd steht; der Streifen
/// verblasst später wieder.
final class PaintJob: Job {
    override class var name: String { "paint" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard case .window = c.surfaceKind, let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 100
    }

    private static let paints: [Character] = ["1", "2", "3", "4"]
    private var paint: Character = "1"
    private var dir: CGFloat = 1
    private var distance: CGFloat = 0
    private var startX: CGFloat = 0

    private var paintColor: CGColor {
        let rgb = ClawdSprite.rgb(paint) ?? (200, 200, 200)
        return CGColor(srgbRed: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255, alpha: 1)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                paint = Self.paints.randomElement()!
                dir = roomierDirection()
                if let r = c.centerRange {
                    distance = min(dir > 0 ? r.upperBound - c.center : c.center - r.lowerBound, 180) - 2
                }
                c.face(dir)
                startX = c.center + dir * 8 * px
            }
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.paintBrush(dab: false, paint: paint))
            if t >= 0.4 { next(now) }
        case 1:
            let step = c.walkSpeed * 0.45 * CGFloat(dt)
            c.moveCenter(to: c.center + dir * step)
            walked += step
            let front = c.center + dir * 8 * px
            let x0 = min(startX, front), x1 = max(startX, front)
            showRect("stripe", CGRect(x: x0, y: c.groundY - px * 0.75, width: x1 - x0, height: px * 0.75), color: paintColor)
            let stroke = Int(walked / (1.5 * px))
            pose = Encounter.Pose(sprite: walkFrame(), prop: ClawdSprite.paintBrush(dab: stroke % 2 == 0, paint: paint))
            if walked >= distance { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("done"), c.isChatty { c.say(.happy) }
            if t >= 0.9 {
                leaveBehind("stripe", lifetime: 25)
                finish()
            }
        }
    }
}

/// Kisten schleppen: schwerer Karton, langsam und wankend ans andere Ende, abstellen, Stirn abwischen.
final class BoxJob: Job {
    override class var name: String { "box" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 160
    }

    private var dir: CGFloat = 1
    private var distance: CGFloat = 0
    private var boxW: CGFloat { CGFloat(ClawdSprite.box[0].count) * px }

    private func boxOrigin(height: CGFloat) -> CGPoint {
        CGPoint(x: c.center + dir * 5 * px - boxW / 2, y: c.groundY + height * px)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                if let r = c.centerRange {
                    distance = min(dir > 0 ? r.upperBound - c.center : c.center - r.lowerBound, 260) - 10
                }
                c.face(dir)
            }
            // Hinhocken und anheben
            let p = CGFloat(min(t / 0.8, 1))
            pose = Encounter.Pose(sprite: p < 0.5 ? ClawdSprite.sit : ClawdSprite.stand)
            showEffect("box", ClawdSprite.box, origin: boxOrigin(height: 2 * p), scale: px)
            if once("lift"), c.isChatty { c.say(.hop) }
            if t >= 0.8 { next(now) }
        case 1:
            // Wankend schleppen, ab und zu kurz stehen bleiben
            let pausing = Int(t / 1.6) % 3 == 2 && t.truncatingRemainder(dividingBy: 1.6) < 0.35
            if !pausing {
                let step = c.walkSpeed * 0.55 * CGFloat(dt)
                c.moveCenter(to: c.center + dir * step)
                walked += step
            }
            let wobble: CGFloat = Int(walked / (2 * px)) % 2 == 0 ? 0 : 0.5
            pose = Encounter.Pose(sprite: pausing ? ClawdSprite.squash : walkFrame(stride: 0.8), lift: wobble)
            showEffect("box", ClawdSprite.box, origin: boxOrigin(height: 2 + wobble), scale: px)
            if walked >= distance { next(now) }
        case 2:
            // Abstellen
            let p = CGFloat(min(t / 0.5, 1))
            pose = Encounter.Pose(sprite: ClawdSprite.sit)
            showEffect("box", ClawdSprite.box, origin: boxOrigin(height: 2 * (1 - p)), scale: px)
            if t >= 0.5 {
                c.say(oneOf: [.oof, .uff])
                next(now)
            }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand, particles: .sweat)
            if t >= 1.4 {
                leaveBehind("box", lifetime: 30)
                finish()
            }
        }
    }
}

/// Schraube anziehen: zur Ecke des Fensters, hinhocken, Schraubenzieher drehen.
final class ScrewJob: Job {
    override class var name: String { "screw" }
    override class func isPossible(_ c: PetController) -> Bool { ScrewJob.cornerTarget(c) != nil }

    /// Standpunkt (Mitte) und Blickrichtung an einer erreichbaren Fensterecke.
    static func cornerTarget(_ c: PetController) -> (x: CGFloat, dir: CGFloat)? {
        guard case .window(let id) = c.surfaceKind, let frame = c.world.windowFrames[id],
              let r = c.centerRange else { return nil }
        let reach = 8.5 * c.px
        let options: [(x: CGFloat, dir: CGFloat)] = [(frame.minX + reach, -1), (frame.maxX - reach, 1)]
        return options.filter { r.contains($0.x) }.min { abs($0.x - c.center) < abs($1.x - c.center) }
    }

    private var target: (x: CGFloat, dir: CGFloat) = (0, 1)

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                guard let tgt = Self.cornerTarget(c) else { finish(); return }
                target = tgt
            }
            let arrived = walk(to: target.x, dt: dt)
            pose = Encounter.Pose(sprite: arrived ? ClawdSprite.stand : walkFrame())
            if arrived {
                c.face(target.dir)
                next(now)
            }
        case 1:
            let twist = Int(t / 0.25) % 2 == 0
            if once("turn\(Int(t / 0.5))") { c.say(.wallPock) }
            pose = Encounter.Pose(sprite: ClawdSprite.sit, prop: ClawdSprite.screwdriver(twist: twist))
            if t >= 3.5 { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.wave[1])
            let p = Float(sin(.pi * min(t / 1.0, 1)))
            showEffect("shine", ClawdSprite.sparkleGlyph,
                       origin: CGPoint(x: c.center + target.dir * 8 * px - px, y: c.groundY), scale: px * 0.6, opacity: p)
            if once("done"), c.isChatty { c.say(.happy) }
            if t >= 1.0 { finish() }
        }
    }
}
