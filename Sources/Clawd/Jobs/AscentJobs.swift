import AppKit

/// Fenster, die zu hoch zum Hinaufspringen sind: Clawd kommt mit dem Enterhaken oder dem Jetpack
/// hinauf. Reine Geometrie, damit sie sich testen lässt.
enum Ascent {
    /// Ab dieser Höhe (pt) springt Clawd nicht mehr (siehe `jumpCandidate`), sondern holt Werkzeug.
    static let minRise: CGFloat = 170
    static let maxRise: CGFloat = 1400
    /// So weit läuft (bzw. fliegt) er höchstens zur Seite.
    static let maxDistance: CGFloat = 420

    /// Platz über der Oberkante bis zum oberen Bildschirmrand (Menüleiste mitgerechnet), den Clawd
    /// braucht: beim Aufschwingen kommt sein Kopf gut 14 px über die Kante, das Jetpack fliegt mit den
    /// Füßen 9 px darüber ein. 18 px = 72 pt bei normaler Größe.
    static func minHeadroom(px: CGFloat) -> CGFloat { 18 * px }

    /// Genug Luft über dieser Stelle einer Oberkante?
    static func hasHeadroom(x: CGFloat, top: CGFloat, px: CGFloat, screens: [NSRect]) -> Bool {
        guard let screen = screens.first(where: { x >= $0.minX && x < $0.maxX && top >= $0.minY && top <= $0.maxY })
        else { return false }
        return screen.maxY - top >= minHeadroom(px: px)
    }

    /// Sichtbares Stück einer Fensteroberkante mit dem ganzen Fensterrahmen.
    struct Ledge: Equatable {
        let id: CGWindowID
        let minX: CGFloat
        let maxX: CGFloat
        let y: CGFloat
        let frame: NSRect
    }

    /// Eine Kante, an der Clawd den Haken hochschießen kann.
    struct GrappleSpot: Equatable {
        let id: CGWindowID
        /// Seite des Rahmens: −1 = linke Kante (Clawd steht links davon), +1 = rechte.
        let side: Int
        let edgeX: CGFloat
        /// Oberkante, an der der Haken greift.
        let top: CGFloat
        /// Wo Clawd zum Zielen steht (Mitte): die Hand mit der Pistole genau an der Kante.
        let spotX: CGFloat
        /// Wo er oben landet (Mitte).
        let landX: CGFloat
        /// Mit Magnetschuhen an der Kante hochlaufen statt frei am Seil zu hängen.
        let alongWall: Bool
        /// Bildschirmrand: Der Haken greift unter der Menüleiste, oben bleibt Clawd an der Kante.
        let screenEdge: Bool

        /// Blickrichtung beim Zielen und Klettern: zur Kante hin.
        var facing: CGFloat { CGFloat(-side) }
    }

    /// Ein Fenster, auf das Clawd mit dem Jetpack fliegt.
    struct JetTarget: Equatable {
        let id: CGWindowID
        let top: CGFloat
        let landX: CGFloat
    }

    /// Seitenkanten hoher Fenster, neben denen Clawd auf seiner Fläche stehen kann.
    /// `range` = erlaubter Bereich für seine Mitte, `px` = Clawd-Pixelgröße.
    static func grappleSpots(ledges: [Ledge], groundY: CGFloat, range: ClosedRange<CGFloat>, center: CGFloat,
                             px: CGFloat, magnetic: Bool, screens: [NSRect],
                             visible: (CGWindowID, CGPoint) -> Bool = { _, _ in true }) -> [GrappleSpot] {
        let half = 7 * px, hand = 6 * px
        var spots: [GrappleSpot] = []
        for l in ledges where (minRise...maxRise).contains(l.y - groundY) && l.maxX - l.minX >= 2 * half + 8 {
            for side in [-1, 1] {
                let edgeX = side < 0 ? l.frame.minX : l.frame.maxX
                // Die sichtbare Oberkante muss bis zur Ecke reichen, sonst greift der Haken ins Leere.
                guard abs((side < 0 ? l.minX : l.maxX) - edgeX) < 2 else { continue }
                let spotX = edgeX + CGFloat(side) * hand
                guard range.contains(spotX), abs(spotX - center) <= maxDistance,
                      visible(l.id, CGPoint(x: edgeX, y: l.y - 4)),
                      hasHeadroom(x: edgeX - CGFloat(side), top: l.y, px: px, screens: screens) else { continue }
                let landX = inward(edgeX - CGFloat(side) * 2.2 * half, l, half: half)
                // Reicht die Kante bis zu ihm herunter, läuft er mit Magnetschuhen daran hoch.
                let alongWall = magnetic && l.frame.minY <= groundY + 12
                    && visible(l.id, CGPoint(x: edgeX, y: groundY + half))
                    && PetController.wallHasRoom(x: edgeX, side: side, depth: 8 * px, y: groundY + half, screens: screens)
                spots.append(GrappleSpot(id: l.id, side: side, edgeX: edgeX, top: l.y, spotX: spotX, landX: landX,
                                         alongWall: alongWall, screenEdge: false))
            }
        }
        return spots
    }

    /// Bildschirmränder (nur mit Magnetschuhen, vom Boden aus): Haken unter die Menüleiste,
    /// dann an der Kante hochlaufen. `edges` = die virtuellen Randfenster aus `World.wallFrames`.
    static func screenEdgeSpots(edges: [CGWindowID: NSRect], screens: [ScreenArea], groundY: CGFloat,
                                range: ClosedRange<CGFloat>, center: CGFloat, px: CGFloat,
                                visible: (CGWindowID, CGPoint) -> Bool = { _, _ in true }) -> [GrappleSpot] {
        let half = 7 * px, hand = 6 * px
        var spots: [GrappleSpot] = []
        for (id, f) in edges.sorted(by: { $0.key < $1.key }) {
            for side in [-1, 1] {
                let edgeX = side < 0 ? f.minX : f.maxX
                guard PetController.wallHasRoom(x: edgeX, side: side, depth: 8 * px, y: groundY + half,
                                                screens: screens.map(\.frame)) else { continue }
                // Ganz am Rand darf die Hand ein Stück vor der Kante bleiben.
                let wanted = edgeX + CGFloat(side) * hand
                let spotX = min(max(wanted, range.lowerBound), range.upperBound)
                guard abs(spotX - wanted) <= 1.5 * px, abs(spotX - center) <= maxDistance,
                      let screen = screens.first(where: { $0.frame.contains(CGPoint(x: spotX, y: groundY + 1)) })
                else { continue }
                let top = min(screen.visibleFrame.maxY, f.maxY)
                guard top - groundY >= minRise, visible(id, CGPoint(x: edgeX, y: groundY + half)),
                      visible(id, CGPoint(x: edgeX, y: top - half)) else { continue }
                spots.append(GrappleSpot(id: id, side: side, edgeX: edgeX, top: top, spotX: spotX, landX: spotX,
                                         alongWall: true, screenEdge: true))
            }
        }
        return spots
    }

    /// Hohe Fenster in Flugweite; gelandet wird möglichst nah über der eigenen Position.
    static func jetTargets(ledges: [Ledge], groundY: CGFloat, center: CGFloat, px: CGFloat,
                           screens: [NSRect]) -> [JetTarget] {
        let half = 7 * px
        return ledges.compactMap { l in
            guard (minRise...maxRise).contains(l.y - groundY), l.maxX - l.minX >= 2 * half + 8 else { return nil }
            let landX = inward(center, l, half: half)
            guard abs(landX - center) <= maxDistance,
                  hasHeadroom(x: landX, top: l.y, px: px, screens: screens) else { return nil }
            return JetTarget(id: l.id, top: l.y, landX: landX)
        }
    }

    /// Landepunkt mindestens eine Körperbreite von den Enden der Kante entfernt (schmale Kante: Mitte),
    /// damit Clawd nach der Mühe nicht gleich wieder hinunterläuft.
    static func inward(_ x: CGFloat, _ l: Ledge, half: CGFloat) -> CGFloat {
        let lo = l.minX + 2 * half + 4, hi = l.maxX - 2 * half - 4
        return lo <= hi ? min(max(x, lo), hi) : (l.minX + l.maxX) / 2
    }

    /// Fensteroberkanten der aktuellen Welt.
    static func ledges(in world: World) -> [Ledge] {
        world.windowPlatforms.compactMap { p in
            guard case .window(let id) = p.kind, let f = world.windowFrames[id] else { return nil }
            return Ledge(id: id, minX: p.minX, maxX: p.maxX, y: p.y, frame: f)
        }
    }
}

// MARK: - Enterhaken

/// Enterhaken: Clawd stellt sich neben die Kante eines hohen Fensters, schießt den Haken hoch,
/// zieht sich am Seil hinauf und schwingt sich auf die Oberkante. Mit Magnetschuhen läuft er
/// dabei an der Kante hoch – auch an Bildschirmrändern, dann bleibt er oben an der Kante.
final class GrappleJob: Job {
    override class var name: String { "grapple" }
    override class func isPossible(_ c: PetController) -> Bool { !spots(for: c).isEmpty }

    static func spots(for c: PetController) -> [Ascent.GrappleSpot] {
        guard let kind = c.surfaceKind, !c.isOnWall, let range = c.centerRange else { return [] }
        let world = c.world
        let visible = { (id: CGWindowID, p: CGPoint) in world.isEdgeVisible(id, at: p) }
        var spots = Ascent.grappleSpots(ledges: Ascent.ledges(in: world), groundY: c.groundY, range: range,
                                        center: c.center, px: c.px, magnetic: c.magneticShoes,
                                        screens: world.screens.map(\.frame), visible: visible)
        if c.magneticShoes, case .floor = kind {
            let edges = world.wallFrames.filter { World.isScreenEdge($0.key) }
            spots += Ascent.screenEdgeSpots(edges: edges, screens: world.screens, groundY: c.groundY, range: range,
                                            center: c.center, px: c.px, visible: visible)
        }
        return spots
    }

    private var spot: Ascent.GrappleSpot?
    /// Unterkante des fliegenden Hakens.
    private var hookY: CGFloat = 0
    /// Fußhöhe beim freien Klettern am Seil.
    private var footY: CGFloat = 0
    private var s: CGFloat { px / 2 }
    /// Wie weit (in Clawd-Pixeln) der erhobene Arm über den Kopf hinausragt.
    private var reach: CGFloat = 0

    /// Oberseite der erhobenen Hand (dort sitzt die Pistole, dort hält er das Seil).
    private var hand: CGPoint { CGPoint(x: c.center + c.facing * 6 * px, y: c.groundY + (8 + reach) * px) }

    /// Den vorderen Arm über den Kopf strecken (`pixels` = 0 → Arm wieder unten).
    private func raiseArm(_ pixels: CGFloat) {
        reach = pixels
        guard pixels > 0 else { hideEffect("arm"); return }
        let rows = Int((pixels * 2).rounded())
        showEffect("arm", Array(repeating: "XXXX", count: rows),
                   origin: CGPoint(x: c.center + (c.facing > 0 ? 5 : -7) * px, y: c.groundY + 8 * px), scale: s)
    }
    /// Wo Haken und Seil hängen: an der Kante; am Bildschirmrand ein Stück nach innen, damit der
    /// Haken nicht halb außerhalb des Bildschirms sitzt.
    private func anchorX(_ sp: Ascent.GrappleSpot) -> CGFloat { sp.screenEdge ? sp.edgeX + CGFloat(sp.side) * 5 * s : sp.edgeX }
    /// Öse des eingerasteten Hakens: hier hängt das Seil.
    private func eye(_ sp: Ascent.GrappleSpot) -> CGPoint { CGPoint(x: anchorX(sp), y: sp.top - 4 * s) }

    /// Sitzt die Kante noch da, wo der Haken greift? (Fenster verschoben oder geschlossen → loslassen.)
    private func edgeStillThere(_ sp: Ascent.GrappleSpot) -> Bool {
        guard let f = sp.screenEdge ? world.wallFrames[sp.id] : world.windowFrames[sp.id] else { return false }
        let x = sp.side < 0 ? f.minX : f.maxX
        return abs(x - sp.edgeX) < 3 && (sp.screenEdge || abs(f.maxY - sp.top) < 3)
    }

    private func showLauncher() {
        let frame = ClawdSprite.grappleLauncher
        // Griff (Spalte 4–5) auf der Hand; gespiegelt liegt er in Spalte 1–2.
        let gripX = c.facing > 0 ? 5 * s : 2 * s
        showEffect("launcher", frame, origin: CGPoint(x: hand.x - gripX, y: hand.y - s), scale: s, mirrored: c.facing < 0)
    }

    private func showRope(from a: CGPoint, to b: CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = Int((hypot(dx, dy) / s).rounded())
        showRotated("rope", ClawdSprite.tautRope(length: length), center: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2),
                    scale: s, angle: atan2(-dx, dy))
    }

    private func showCaughtHook(_ sp: Ascent.GrappleSpot) {
        showEffect("hook", ClawdSprite.grappleHookCaught, origin: CGPoint(x: anchorX(sp) - 4.5 * s, y: sp.top - 4 * s), scale: s)
    }

    /// Haken löst sich (Fenster weg): Seil und Haken verschwinden, Clawd fällt, falls er hing.
    private func letGo() {
        hideEffect("hook"); hideEffect("rope"); hideEffect("ropeFly"); hideEffect("arm")
        if phase >= 4 { c.say(oneOf: Voice.Sound.startled) }
        finish()
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        if spot == nil, once("pick") {
            let spots = Self.spots(for: c)
            // Im Demo-Menü bevorzugt die ausführlichste Form (mit Magnetschuhen an der Kante hoch).
            spot = isDemo ? spots.first(where: \.alongWall) ?? spots.randomElement() : spots.randomElement()
        }
        guard let sp = spot else { finish(); return }
        if phase >= 2, !edgeStillThere(sp) { letGo(); return }
        let t = t(now)
        switch phase {
        case 0:
            // Hin zur Kante, dann zu ihr umdrehen.
            if walk(to: sp.spotX, dt: dt) {
                c.face(sp.facing)
                next(now)
            } else {
                pose = Encounter.Pose(sprite: walkFrame())
            }
        case 1:
            // Zielen
            c.face(sp.facing)
            raiseArm(2)
            showLauncher()
            pose = Encounter.Pose(sprite: ClawdSprite.aimUp)
            if t >= 0.5 { next(now) }
        case 2:
            // Schuss: Der Haken fliegt an der Kante hoch, das Seil schlängelt hinterher.
            if once("shot") {
                c.playNoise(.grappleShot)
                hookY = hand.y + 10 * s
            }
            raiseArm(2)
            showLauncher()
            pose = Encounter.Pose(sprite: ClawdSprite.aimUp)
            hookY = min(hookY + 1100 * CGFloat(dt), sp.top - 4 * s)
            let ropeBottom = hand.y + 10 * s
            let ropeLength = Int(((hookY - ropeBottom) / s).rounded())
            if ropeLength > 0 {
                showEffect("ropeFly", ClawdSprite.wavyRope(length: ropeLength),
                           origin: CGPoint(x: anchorX(sp) - 1.5 * s, y: ropeBottom), scale: s)
            }
            showEffect("hookFly", ClawdSprite.grappleHook, origin: CGPoint(x: anchorX(sp) - 3.5 * s, y: hookY), scale: s)
            if hookY >= sp.top - 4 * s {
                c.playNoise(.grappleCatch) // eingerastet
                hideEffect("hookFly"); hideEffect("ropeFly")
                next(now)
            }
        case 3:
            // Festziehen: zweimal kräftig am Seil rucken, Pistole wegstecken.
            showCaughtHook(sp)
            if t < 0.3 { showLauncher() } else { hideEffect("launcher") }
            let tug = Int(t / 0.2) % 2 == 1
            raiseArm(tug ? 1 : 2)
            pose = Encounter.Pose(sprite: ClawdSprite.aimUp)
            showRope(from: eye(sp), to: hand)
            if t >= 0.8 { next(now) }
        case 4:
            showCaughtHook(sp)
            if sp.alongWall { climbAlongWall(sp, dt: dt) } else { climbRope(sp, t: t, dt: dt) }
        default:
            finish()
        }
    }

    /// Frei am Seil hangeln, Hand über Hand; oben mit Schwung auf das Fenster.
    private func climbRope(_ sp: Ascent.GrappleSpot, t: TimeInterval, dt: TimeInterval) {
        if once("takeOff") {
            footY = c.groundY
            c.takeOff()
        }
        let topFeet = sp.top - 8 * px
        footY = min(footY + 210 * CGFloat(dt), topFeet)
        c.hover(centerX: sp.spotX, footY: footY)
        c.face(sp.facing)
        let frame = Int(t / 0.13) % 2
        pose = Encounter.Pose(sprite: ClawdSprite.ropeClimb[frame])
        raiseArm(frame == 0 ? 2 : 0) // Hand über Hand: Arm ganz hoch ↔ auf Kopfhöhe
        showRope(from: eye(sp), to: CGPoint(x: hand.x, y: hand.y - (frame == 1 ? px : 0)))
        if frame == 0, once("pull\(Int(t / 0.26))"), Int(t / 0.26) % 3 == 0 { c.say(.hop) }
        if footY >= topFeet { swingUp(sp) }
    }

    /// Mit Magnetschuhen an der Kante hochlaufen, das Seil in der Hand.
    private func climbAlongWall(_ sp: Ascent.GrappleSpot, dt: TimeInterval) {
        if once("grip") {
            raiseArm(0)
            guard c.gripWall(id: sp.id, side: sp.side) else { letGo(); return }
        }
        guard c.isOnWall, let range = c.wallFootRange else { letGo(); return }
        let step = 170 * CGFloat(dt)
        c.climbWall(to: c.groundY + step)
        walked += step
        // An der linken Kante heißt "nach rechts schauen" im gedrehten Sprite: hoch.
        c.face(sp.side < 0 ? 1 : -1)
        pose = Encounter.Pose(sprite: walkFrame(stride: 1.3))
        // Hand am vorderen Arm: 4 px von der Kante weg, 6,5 px über dem Fußpunkt.
        showRope(from: eye(sp), to: CGPoint(x: sp.edgeX + CGFloat(sp.side) * 4 * px, y: c.groundY + 6.5 * px))
        guard c.groundY >= range.upperBound - 0.5 else { return }
        if sp.screenEdge {
            // Oben am Bildschirmrand: Haken lösen, an der Kante bleiben.
            hideEffect("rope"); hideEffect("hook"); hideEffect("arm")
            c.say(.happy)
            finish()
        } else {
            swingUp(sp)
        }
    }

    private func swingUp(_ sp: Ascent.GrappleSpot) {
        hideEffect("arm")
        retire()
        c.swing(onto: .window(sp.id), centerX: sp.landX)
    }
}

// MARK: - Jetpack

/// Jetpack: Clawd schnallt es um, setzt die Fliegerbrille auf, wirft das Triebwerk an (es stottert,
/// dann wächst die Flamme, alles zittert) und fliegt hinauf auf das Fenster.
final class JetpackJob: Job {
    override class var name: String { "jetpack" }
    override class func isPossible(_ c: PetController) -> Bool { !targets(for: c).isEmpty }

    static func targets(for c: PetController) -> [Ascent.JetTarget] {
        guard c.surfaceKind != nil, !c.isOnWall else { return [] }
        return Ascent.jetTargets(ledges: Ascent.ledges(in: c.world), groundY: c.groundY, center: c.center, px: c.px,
                                 screens: c.world.screens.map(\.frame))
    }

    private var target: Ascent.JetTarget?
    /// Boden beim Abheben (dort bleibt der Rauch).
    private var ground = CGPoint.zero
    private var flyX: CGFloat = 0
    private var flyY: CGFloat = 0
    private var climbSpeed: CGFloat = 0
    private var s: CGFloat { px / 2 }

    /// Jetpack auf dem Rücken (hinter Clawd), optional mit Flamme; `jitter` = Zittern in pt.
    @discardableResult
    private func showPack(flame: ClawdSprite.Frame?, jitter: CGFloat = 0) -> CGFloat {
        let back = c.facing > 0 ? c.center - 9.5 * px : c.center + 5.5 * px
        let origin = CGPoint(x: back + jitter, y: c.groundY + 1.5 * px)
        showEffect("pack", ClawdSprite.jetpackSide, origin: origin, scale: s, mirrored: c.facing < 0, behind: true)
        let nozzle = origin.x + 4 * s
        if let flame {
            showEffect("flame", flame, origin: CGPoint(x: nozzle - CGFloat(flame[0].count) * s / 2,
                                                       y: origin.y - CGFloat(flame.count) * s), scale: s, behind: true)
        } else {
            hideEffect("flame")
        }
        return nozzle
    }

    private func pose(_ sprite: ClawdSprite.Frame, lift: CGFloat = 0) -> Encounter.Pose {
        Encounter.Pose(sprite: sprite, lift: lift, hat: ClawdSprite.flightGoggles)
    }

    /// Ziel live nachführen (Fenster verschoben); nil, wenn es weg ist.
    private func liveTarget(_ t: Ascent.JetTarget) -> Ascent.JetTarget? {
        guard let p = world.platform(.window(t.id), near: t.landX), p.width >= 14 * px + 8 else { return nil }
        let ledge = Ascent.Ledge(id: t.id, minX: p.minX, maxX: p.maxX, y: p.y, frame: .zero)
        return Ascent.JetTarget(id: t.id, top: p.y, landX: Ascent.inward(t.landX, ledge, half: 7 * px))
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        if target == nil, once("pick") { target = Self.targets(for: c).randomElement() }
        guard let picked = target else { finish(); return }
        let t = t(now)
        switch phase {
        case 0:
            // Jetpack steht vor ihm
            if once("unpack") {
                c.face(picked.landX >= c.center ? 1 : -1)
                c.say(.hop)
            }
            let front = ClawdSprite.jetpackFront
            showEffect("front", front, origin: CGPoint(x: c.center + c.facing * 10 * px - CGFloat(front[0].count) * s / 2,
                                                       y: c.groundY), scale: s)
            if t < 0.3 {
                showEffect("puff", ClawdSprite.smokePuffSmall, origin: CGPoint(x: c.center + c.facing * 10 * px - 2 * s,
                                                                                y: c.groundY), scale: s)
            } else {
                hideEffect("puff")
            }
            pose = Encounter.Pose(sprite: ClawdSprite.jetStand)
            if t >= 0.8 { next(now) }
        case 1:
            // Umgeschnallt, Brille auf
            if once("strap") {
                hideEffect("front")
                c.say(.pock)
            }
            showPack(flame: nil)
            pose = pose(ClawdSprite.jetStand)
            if t >= 0.5 { next(now) }
        case 2:
            // Triebwerk stottert
            let beat = Int(t / 0.12)
            let nozzle = showPack(flame: beat % 3 == 2 ? nil : ClawdSprite.jetSputter(beat))
            for (i, at) in [0.15, 0.55, 0.95].enumerated() where t >= at && once("cough\(i)") { c.playNoise(.jetCough) }
            if beat % 4 == 1 {
                showEffect("puffL", ClawdSprite.smokePuffSmall, origin: CGPoint(x: nozzle - 6 * s, y: c.groundY), scale: s)
            } else {
                hideEffect("puffL")
            }
            pose = pose(ClawdSprite.jetStand)
            if t >= 1.3 { next(now) }
        case 3:
            // Druck baut sich auf: Flamme wächst, alles zittert, Rauch quillt
            let shake = Int(t / 0.05) % 2 == 0
            let flame = t < 0.6 ? ClawdSprite.jetFlameShort : ClawdSprite.jetFlameFull(Int(t / 0.06))
            let nozzle = showPack(flame: flame, jitter: shake ? 0.5 * s : -0.5 * s)
            showEffect("puffL", ClawdSprite.smokePuff, origin: CGPoint(x: nozzle - 10 * s, y: c.groundY), scale: s)
            showEffect("puffR", ClawdSprite.smokePuff, origin: CGPoint(x: nozzle + 4 * s, y: c.groundY), scale: s)
            pose = pose(ClawdSprite.jetStand, lift: shake ? 0.25 : 0)
            if t >= 1.2 { next(now) }
        case 4:
            // Abheben und hinauf, dann hinüber
            guard let live = liveTarget(picked) else { finish(); return }
            target = live
            if once("liftoff") {
                c.playNoise(.jetThrust)
                ground = CGPoint(x: c.center, y: c.groundY)
                flyX = c.center
                flyY = c.groundY
                c.takeOff()
            }
            if t > 0.9 { hideEffect("puffL"); hideEffect("puffR") }
            let screenTop = world.nearestScreen(toX: flyX)?.frame.maxY ?? .greatestFiniteMagnitude
            let cruise = min(live.top + 9 * px, screenTop - 9 * px) // Freiraum prüft `Ascent.hasHeadroom`
            climbSpeed = min(climbSpeed + 900 * CGFloat(dt), 320)
            flyY = min(flyY + climbSpeed * CGFloat(dt), cruise)
            if flyY > ground.y + 30 {
                let dx = live.landX - flyX, step = 180 * CGFloat(dt)
                flyX = abs(dx) <= step ? live.landX : flyX + (dx < 0 ? -step : step)
            }
            c.hover(centerX: flyX, footY: flyY)
            showPack(flame: ClawdSprite.jetFlameFull(Int(now / 0.06)), jitter: Int(now / 0.05) % 2 == 0 ? 0.5 * s : 0)
            pose = pose(ClawdSprite.jetFly)
            if flyY >= cruise - 0.5, flyX == live.landX { next(now) }
        case 5:
            // Sanft hinunter auf das Fenster
            guard let live = liveTarget(picked) else { finish(); return }
            target = live
            flyY = max(flyY - 110 * CGFloat(dt), live.top)
            let dx = live.landX - flyX
            flyX += max(min(dx, 120 * CGFloat(dt)), -120 * CGFloat(dt))
            c.hover(centerX: flyX, footY: flyY)
            showPack(flame: ClawdSprite.jetFlameShort)
            pose = pose(ClawdSprite.jetFly)
            if flyY <= live.top {
                guard c.touchDown(on: .window(live.id)) else { finish(); return }
                c.playLanding()
                next(now)
            }
        case 6:
            // Gelandet: Triebwerk aus, ein letztes Wölkchen
            showPack(flame: nil)
            if t < 0.5 {
                showEffect("puff", ClawdSprite.smokePuffSmall, origin: CGPoint(x: c.center - c.facing * 8 * px, y: c.groundY),
                           scale: s)
            } else {
                hideEffect("puff")
            }
            pose = pose(ClawdSprite.jetStand)
            if t >= 1.0 { finish() }
        default:
            finish()
        }
    }
}
