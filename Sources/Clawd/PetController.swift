import AppKit

/// Clawds Gehirn: Verhalten, Physik und Maus-Interaktion.
///
/// Clawd steht immer auf einer `Platform` (Dock, Fenster-Oberkante oder Bildschirm-Unterkante)
/// oder ist in der Luft. Das Dock ist ein fester Block; Fenster sind nur von oben begehbar.
final class PetController {
    enum Emote { case sneeze, yawn, dizzy }

    enum SportKind: String, CaseIterable {
        case barbell, rope
    }

    private enum State {
        case walking(remaining: TimeInterval)
        case idle(remaining: TimeInterval)
        case looking(remaining: TimeInterval)
        case sitting(remaining: TimeInterval)
        case sleeping(remaining: TimeInterval)
        case waving(remaining: TimeInterval)
        case coding(remaining: TimeInterval)
        case music(remaining: TimeInterval)
        case sport(SportKind, remaining: TimeInterval)
        case encounter
        case emote(Emote)
        case job
        case dragged
        case airborne
        case landing(remaining: TimeInterval)
        /// In Deckung, solange eine Vollbild-App läuft – und kurz danach (siehe `takeCover`).
        case sheltering
        /// Das MacBook ist geneigt: Clawd rutscht hangabwärts (siehe `reactToTilt`).
        case sliding

        /// Der Fall ohne seine Werte – zum Erkennen von Zustandswechseln.
        var kind: StateKind {
            switch self {
            case .walking: .walking
            case .idle: .idle
            case .looking: .looking
            case .sitting: .sitting
            case .sleeping: .sleeping
            case .waving: .waving
            case .coding: .coding
            case .music: .music
            case .sport: .sport
            case .encounter: .encounter
            case .emote: .emote
            case .job: .job
            case .dragged: .dragged
            case .airborne: .airborne
            case .landing: .landing
            case .sheltering: .sheltering
            case .sliding: .sliding
            }
        }
    }

    private enum StateKind {
        case walking, idle, looking, sitting, sleeping, waving, coding, music, sport
        case encounter, emote, job, dragged, airborne, landing, sheltering, sliding
    }

    let node: ClawdNode
    weak var stage: Stage?
    let world: World
    let voice: Voice.Channel

    private(set) var pixel: CGFloat
    /// Grundtempo aus den Einstellungen; jeder Clawd ist individuell etwas schneller/langsamer.
    var baseSpeed: CGFloat
    private let speedFactor = CGFloat.random(in: 0.85...1.15)
    private var speed: CGFloat { baseSpeed * speedFactor * (isCaffeinated ? 1.25 : 1) }

    /// Nach dem Kaffee eine Weile munterer.
    var caffeinatedUntil: CFTimeInterval = 0
    private var isCaffeinated: Bool { CACurrentMediaTime() < caffeinatedUntil }
    private var spriteSize: NSSize { ClawdSprite.size(pixel: pixel) }

    /// Unten links des Sprites (= Füße), Cocoa-Koordinaten.
    private var pos: CGPoint
    private var velocity = CGVector.zero
    private var direction: CGFloat = 1
    private var surface: Platform.Kind?
    private var walkingOff = false
    /// Freiwillig vom Dock gehüpft: bis zu diesem Zeitpunkt darf Clawd auf dem Boden daneben bleiben.
    private var floorVisitUntil: CFTimeInterval?
    /// Unterwegs zum Dock-Ende, um hinunterzuhüpfen: −1 = links, +1 = rechts.
    private var hopOffSide: CGFloat?
    /// Aus dem Schlaf geklickt – nach der Landung gibt es manchmal ein beleidigtes "Hmpf".
    private var grumpyWake = false
    private var lastBonk: CFTimeInterval = -100

    /// Beim Werfen gegen Decke oder Bildschirmrand geprallt.
    private func bonk() {
        let now = CACurrentMediaTime()
        guard now - lastBonk > 0.4 else { return }
        lastBonk = now
        say(.bonk)
    }
    private var fallStartY: CGFloat = 0
    private var fallSoundPlayed = false
    /// Entwickler-Hilfe: diesen Clawd ausführlich loggen (nach `debugDrop`).
    private var debugLog = false
    private var lastDebugLine = ""

    private var state: State = .airborne
    /// Bis wann die ruhige Phase läuft (nur Grundverhalten, keine Aktivitäten).
    private var calmUntil = CACurrentMediaTime() + .random(in: 20...50)
    /// Eine Aktivität läuft oder lief gerade; beim nächsten Auswählen beginnt die ruhige Phase.
    private var activityPending = false
    private var stateKind: StateKind?
    private var stateStart: CFTimeInterval = 0

    // Laufen
    private var distanceWalked: CGFloat = 0

    // Physik
    private let gravity: CGFloat = 2600
    private let maxThrow: CGFloat = 1400
    private let wallBounce: CGFloat = 0.4

    // Maus
    private var grabOffset = CGVector.zero
    private var mouseDownPoint = CGPoint.zero
    private var isDragging = false
    private var dragSamples: [(t: CFTimeInterval, p: CGPoint)] = []
    private let dragThreshold: CGFloat = 3
    private var lastMouse = CGPoint.zero
    private var lastMouseMove: CFTimeInterval = 0
    private var lastWave: CFTimeInterval = -100

    // Kleinkram
    private var blinkUntil: CFTimeInterval = 0
    private var nextBlink = CACurrentMediaTime() + .random(in: 2...5)
    private var nextSnore: CFTimeInterval = 0
    /// Coden: tippt gerade (sonst kurze Denkpause). Musik: wippt gerade mit (sonst nur zuhören).
    private var activityActive = false
    private var activityPhaseUntil: CFTimeInterval = 0

    // Bedürfnisse: Hunger (→ Nudeln essen) und Langeweile (→ Tennis, Sport oder Fegen)
    /// Schwellen (s): Hunger etwa alle 25–35 min, Langeweile nach 9–15 min ruhiger Zeit –
    /// so bleibt neben den Bedürfnissen genug Raum für Jobs und andere Aktivitäten.
    static let hungerRange: ClosedRange<TimeInterval> = 1500...2100
    static let boredomRange: ClosedRange<TimeInterval> = 540...900

    private var hunger = TimeInterval.random(in: 0...600)
    private var hungerThreshold = TimeInterval.random(in: PetController.hungerRange)
    private var boredom: TimeInterval = 0
    private var boredomThreshold = TimeInterval.random(in: PetController.boredomRange)

    // Niesen & Gähnen
    private var emoteStart: CFTimeInterval = 0
    private var emoteThenSleep = false
    private var emoteCues: Set<String> = []

    /// 0 = still, 1 = normal, >1 = Plappermaul (aus den Einstellungen).
    var talkativeness: Double = 1 {
        didSet { beginEvent() } // laufendes Ereignis mit der neuen Stufe neu auswürfeln
    }
    /// Aktivität: <1 = gemütlich (mehr Pausen, Sitzen, Schlafen), >1 = quirlig (mehr Laufen,
    /// Springen, Sport, Putzen, schneller gelangweilt).
    var activity: Double = 1
    /// Entwickler-Hilfe: nach der nächsten Landung dieses Verhalten starten.
    var debugForce: DemoAction?
    /// Einmalig nach der ersten Landung aufgerufen (Szenen-Aufnahmen).
    var onFirstLanding: (() -> Void)?
    private var lastTick = CACurrentMediaTime()

    init(world: World, voice: Voice.Channel, pixel: CGFloat, speed: CGFloat) {
        self.node = ClawdNode(pixel: pixel)
        self.world = world
        self.voice = voice
        self.pixel = pixel
        self.baseSpeed = speed

        // Start: von oben aufs Dock fallen.
        let dock = world.dockPlatform
        let w = ClawdSprite.size(pixel: pixel).width
        let x = CGFloat.random(in: dock.minX...max(dock.minX, dock.maxX - w))
        let top = world.screen(containingX: x + w / 2)?.visibleFrame.maxY ?? dock.y + 400
        pos = CGPoint(x: x, y: top - ClawdSprite.size(pixel: pixel).height)
        fallStartY = pos.y
        direction = Bool.random() ? 1 : -1

    }

    /// Sofort an die aktuelle Position setzen (z. B. nach dem Hinzufügen oder Bildschirmwechsel).
    func placeNow() {
        lastTick = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateSprite(now: lastTick)
        place()
        CATransaction.commit()
    }

    /// Clawd entfernen: Loop anhalten, Fenster schließen, Stimme lösen.
    func stop() {
        if isDragging { NSCursor.pop() }
        // Laufende Arbeit beenden, sonst blieben ihre Effekt-Layer verwaist auf der Bühne.
        job?.cleanup()
        job = nil
        fx.removeAll()
        stage?.remove(self)
        voice.close()
    }

    /// Größe ändern; die Füße bleiben, wo sie sind.
    func setPixel(_ newPixel: CGFloat) {
        let oldWidth = spriteSize.width
        pixel = newPixel
        pos.x += (oldWidth - spriteSize.width) / 2
        node.pixel = newPixel
        place()
    }

    // MARK: - Demo

    /// Animation aus dem Demo-Menü sofort hier ausführen. Fällt Clawd gerade, kommt sie nach
    /// der Landung. Gibt false zurück, wenn sie hier nicht geht (z. B. Tennis ohne Wand).
    @discardableResult
    func performDemo(_ action: DemoAction) -> Bool {
        guard encounter == nil else { return false }
        switch state {
        case .airborne, .landing, .dragged:
            debugForce = action // nach der Landung
            return true
        default:
            break
        }
        var behavior: DemoAction.Behavior?
        if case .behavior(let b) = action { behavior = b }
        // An der Wand geht nur Winken, Umschauen und der Wandsprung – und der nur dort.
        if isOnWall, behavior != .wave, behavior != .look, behavior != .wallJump { return false }
        if behavior == .wallJump, !isOnWall { return false }
        if behavior == .hopOff, hopOffSides.isEmpty { return false }
        // Diese Verhalten starten auch dann, wenn Clawd schon so dasteht.
        let restartsInPlace = behavior == .wave || behavior == .look || behavior == .sit
        let before = state.kind
        debugForce = action
        applyDebugForce()
        debugForce = nil // im Demo-Menü nicht später nachholen
        return state.kind != before || restartsInPlace
    }

    /// Mitsamt der Welt verschieben (Spielplatz-Fenster bewegt); am Boden kommt er dabei ins Hüpfen.
    func shift(by delta: CGVector) {
        pos.x += delta.dx
        pos.y += delta.dy
        if isGroundedState { startFalling(vx: 0) }
    }

    /// Ein Schritt aus `--script` (Szenen-Aufnahmen): "jump"/"jumpHigh" springt auf eine höhere
    /// Fläche, "walkLeft"/"walkRight" läuft los, sonst eine Demo-Aktion wie "wave" oder "job:coffee".
    func runScript(_ step: String) {
        trace("Skript: \(step)")
        switch step {
        case "jump", "jumpHigh":
            // "jump": auf die nächsthöhere Fläche, "jumpHigh": auf die höchste in Reichweite.
            let w = spriteSize.width
            let candidates = (world.windowPlatforms + [world.dockPlatform])
                .filter { $0.kind != surface && $0.y - pos.y > 20 && $0.y - pos.y < 200 && $0.width > w + 8 }
            let target = step == "jump" ? candidates.min { $0.y < $1.y } : candidates.max { $0.y < $1.y }
            if let p = target {
                jump(to: p, centerX: min(max(centerX, p.minX + w), p.maxX - w))
            }
        case "walkLeft", "walkRight":
            direction = step == "walkLeft" ? -1 : 1
            state = .walking(remaining: 30)
        default:
            if let action = DemoAction(argument: step) { _ = performDemo(action) }
        }
    }

    /// Von der aktuellen Stelle aus fallen lassen (z. B. wenn der Spielplatz geschlossen wird).
    func letFall() {
        if isDragging { NSCursor.pop(); isDragging = false }
        startFalling(vx: 0)
    }

    /// Clawd an einem Punkt fallen lassen (z. B. ein Demo-Partner).
    func dropIn(at p: CGPoint) {
        pos = CGPoint(x: p.x - spriteSize.width / 2, y: p.y)
        startFalling(vx: 0)
    }

    /// Entwickler-Hilfe: seitlich wegwerfen.
    func debugThrow(vx: CGFloat) { velocity.dx = vx }

    /// Entwickler-Hilfe: Clawd an einem Punkt (Cocoa-Koordinaten) fallen lassen.
    func debugDrop(at p: CGPoint, asUserDrop: Bool = false) {
        DebugLog.write("dock: \(world.dock) trash: \(String(describing: world.trash)) screens: \(world.screens.map(\.frame)) drop: \(p)")
        DebugLog.write("dock-symbole: " + world.dockIcons.map { "\(Int($0.minX))…\(Int($0.maxX)) y \(Int($0.minY))…\(Int($0.maxY))" }.joined(separator: ", "))
        for w in world.windowPlatforms {
            DebugLog.write("window \(w.kind) x: \(Int(w.minX)) - \(Int(w.maxX)) y: \(Int(w.y))")
        }
        debugLog = true
        pos = p
        startFalling(vx: 0)
        droppedByUser = asUserDrop
    }

    // MARK: - Hilfen

    func trace(_ text: @autoclosure () -> String) {
        if debugLog { DebugLog.write(text()) }
    }

    private var centerX: CGFloat { pos.x + spriteSize.width / 2 }
    private var centerPoint: CGPoint { CGPoint(x: centerX, y: pos.y + spriteSize.height / 2) }

    private func overlapsDock(_ x: CGFloat) -> Bool {
        let d = world.dock
        return x + spriteSize.width > d.minX && x < d.maxX
    }

    /// Zufall, skaliert mit der Gesprächigkeit.
    func chatty(_ probability: Double) -> Bool {
        Double.random(in: 0..<1) < probability * talkativeness
    }

    /// Aktivitäten ziehen Aufmerksamkeit auf sich; danach folgt eine ruhige Phase.
    /// Schlafen (samt Gähnen davor) gehört zur ruhigen Phase.
    private var isActivityState: Bool {
        switch state {
        case .sport, .coding, .music, .job, .encounter: return true
        case .emote(let e): return !(e == .yawn && emoteThenSleep)
        default: return false
        }
    }

    private var isGroundedState: Bool {
        switch state {
        case .walking, .idle, .looking, .sitting, .sleeping, .waving, .coding, .music, .sport, .encounter, .emote, .job,
             .sheltering, .sliding: true
        default: false
        }
    }

    // MARK: - Loop

    /// Wird von der Bühne 60× pro Sekunde aufgerufen.
    func tick(now: CFTimeInterval) {
        let dt = min(now - lastTick, 0.05)
        lastTick = now
        world.refresh(now: now, windowMaxAge: needsFreshWindows ? 1.0 / 30 : 0.5)

        hunger += dt * (0.5 + 0.5 * activity) // wer viel macht, hat schneller Hunger
        switch state {
        case .walking, .idle, .looking, .sitting: boredom += dt * activity
        default: break
        }

        reactToTilt(now: now)

        switch state {
        case .dragged:
            break // Position kommt aus mouseDragged
        case .sliding:
            stepSliding(dt: dt, now: now)
        case .airborne:
            stepPhysics(dt: dt)
        case .sheltering:
            stepShelter(now: now)
        case .landing(let remaining):
            let r = remaining - dt
            if r <= 0 {
                state = .idle(remaining: .random(in: 0.4...1.2))
                if let landed = onFirstLanding {
                    onFirstLanding = nil
                    landed()
                }
                if coverMissed {
                    // Während des Vollbilds in der Luft gewesen: das Verstecken jetzt nachholen.
                    knockedOut = false
                    wallJumpsLeft = 0
                    droppedByUser = false
                    takeCover()
                    shelterReleased = now
                } else {
                    if knockedOut {
                        knockedOut = false
                        droppedByUser = false // erst mal benommen – keine Begegnung
                        startEmote(.dizzy)
                    }
                    applyDebugForce()
                    // Wandsprung-Serie: drüben angedockt – gleich weiter, etwas höher.
                    if wallJumpsLeft > 0 { continueWallJumps() }
                    // Vom Nutzer auf einen anderen Clawd fallen gelassen? → Begegnung.
                    if droppedByUser {
                        droppedByUser = false
                        stage?.dropped(self)
                    }
                }
            } else {
                state = .landing(remaining: r)
            }
        default:
            stepGrounded(dt: dt, now: now)
        }

        // Arbeit unterbrochen (hochgehoben, angeklickt …)? Aufräumen.
        if let job, state.kind != .job {
            job.cleanup()
            self.job = nil
        }

        if state.kind != stateKind {
            stateKind = state.kind
            if isActivityState { activityPending = true }
            stateStart = now
        }
        updateSprite(now: now)
        if debugLog {
            let line = "\(state.kind) \(String(describing: surface)) laptop:\(node.showLaptop) kopfhörer:\(node.showHeadphones) partikel:\(node.particles) kopf:\(ClawdSprite.headRow(node.sprite))"
            if line != lastDebugLine {
                lastDebugLine = line
                DebugLog.write(String(format: "%.2f ", now) + "\(state) pos: \(Int(pos.x)) \(Int(pos.y)) "
                    + "surface: \(String(describing: surface)) laptop: \(node.showLaptop) kopfhörer: \(node.showHeadphones) "
                    + "partikel: \(node.particles) kopfzeile: \(ClawdSprite.headRow(node.sprite))")
            }
        }
        place()
    }

    /// Auf einem Fenster oder in der Luft muss Clawd schnell merken, wenn sich Fenster bewegen.
    private var needsFreshWindows: Bool {
        if case .window = surface { return true }
        if isOnWall { return true }
        switch state {
        case .airborne, .dragged: return true
        default: return false
        }
    }

    // MARK: - Am Boden

    private func stepGrounded(dt: TimeInterval, now: CFTimeInterval) {
        guard let kind = surface else { startFalling(vx: 0); return }
        if isOnWall {
            stepWall(dt: dt, now: now)
            return
        }

        // Clawd fährt nicht mit: Wird das Fenster unter ihm weggezogen (zur Seite oder
        // nach unten), verliert er den Boden und fällt. Nach oben wird er mitgehoben.
        guard let platform = world.platform(kind, near: centerX),
              walkingOff || platform.contains(x: centerX) || kind == .dock,
              platform.y >= pos.y - 1
        else {
            // Fenster unter ihm weggezogen (nicht selbst runtergelaufen)? Dann ist es ein Absturz.
            if case .window(let id) = kind, !walkingOff, world.windowFrames[id] != nil {
                yankedFall = true
                startFalling(vx: 0)
                say(oneOf: Voice.Sound.startled)
                return
            }
            startFalling(vx: 0)
            return
        }
        pos.y = platform.y
        if kind == .dock {
            // Dock kann schrumpfen/wachsen – im Bereich bleiben.
            pos.x = min(max(pos.x, platform.minX), max(platform.minX, platform.maxX - spriteSize.width))
        }

        let homing = isHomingFloor(kind)
        checkCursor(now: now)

        switch state {
        case .walking(let remaining):
            if homing {
                direction = centerX < (world.dock.minX + world.dock.maxX) / 2 ? 1 : -1
            }
            let step = speed * CGFloat(dt)
            let oldFront = direction > 0 ? pos.x + spriteSize.width : pos.x
            pos.x += direction * step
            distanceWalked += step
            // Mit Magnetschuhen an einer Fensterkante, die bis zum Boden reicht, manchmal hochklettern.
            if magneticShoes, !homing, !walkingOff, let wall = climbableWall(from: oldFront),
               Double.random(in: 0..<1) < 0.5 {
                enterWall(id: wall.id, side: wall.side, y: pos.y + spriteSize.width / 2, goingDown: false)
                trace(World.isScreenEdge(wall.id) ? "klettert hoch am Bildschirmrand" : "klettert hoch an Fenster \(wall.id)")
                return
            }
            let r = remaining - dt
            if r <= 0, !homing, !walkingOff {
                state = .idle(remaining: .random(in: 1...4) / activity)
                if chatty(0.2) { voice.play(.murmur) }
            } else {
                state = .walking(remaining: r)
            }
            handleEdges(platform, homing: homing)
            if chatty(0.025 * dt) { voice.play(.murmur) }

        case .idle(let r): countdown(r, dt) { .idle(remaining: $0) }
        case .looking(let r): countdown(r, dt) { .looking(remaining: $0) }
        case .sitting(let r): countdown(r, dt) { .sitting(remaining: $0) }
        case .waving(let r): countdown(r, dt) { .waving(remaining: $0) }
        case .sleeping(let r):
            if now >= nextSnore {
                // Abwechselnd normales Schnarchen und Cartoon-"we we we".
                if Bool.random() {
                    say(.snore)
                    nextSnore = now + .random(in: 3...4.5)
                } else {
                    say(.sleepyWe)
                    nextSnore = now + .random(in: 4...5.5)
                }
            }
            countdown(r, dt) { .sleeping(remaining: $0) }
        case .coding(let r):
            if now >= activityPhaseUntil {
                activityActive.toggle()
                activityPhaseUntil = now + (activityActive ? .random(in: 1.5...4) : .random(in: 0.6...1.8))
                if !activityActive, chatty(0.15) { voice.play(.murmur) } // "hmm…"
            }
            countdown(r, dt) { .coding(remaining: $0) }
        case .music(let r):
            if now >= activityPhaseUntil {
                activityActive = Double.random(in: 0..<1) < 0.6
                activityPhaseUntil = now + (activityActive ? .random(in: 3...6) : .random(in: 2...5))
                if activityActive, chatty(0.6) { voice.play(.hum) }
            }
            countdown(r, dt) { .music(remaining: $0) }
        case .sport(let kind, let r):
            if r - dt <= 0, chatty(0.7) { voice.play(.happy) } // "Puh, geschafft!"
            countdown(r, dt) { .sport(kind, remaining: $0) }
        case .emote(let e):
            stepEmote(e, now: now)
        case .job:
            if let job, now - job.startedAt > Job.maxDuration {
                job.finish() // Sicherheitsnetz: hängt eine Arbeit, wird sie beendet
            } else {
                job?.step(now: now, dt: dt)
            }
        default:
            break
        }

        // Auf dem Boden neben dem Dock gibt es nur eins: zurücklaufen – sobald Clawd nichts
        // anderes vorhat (benommen sein, niesen usw. lässt er sich nicht nehmen).
        if homing {
            switch state {
            case .idle, .looking, .sitting, .waving: state = .walking(remaining: .infinity)
            default: break
            }
        }
    }

    private func countdown(_ remaining: TimeInterval, _ dt: TimeInterval, _ make: (TimeInterval) -> State) {
        let r = remaining - dt
        if r <= 0 { chooseNext() } else { state = make(r) }
    }

    /// Auf dem Boden des Dock-Bildschirms will Clawd zurück aufs Dock – außer er ist gerade
    /// freiwillig hinuntergehüpft und hat noch Lust, sich dort umzusehen.
    private func isHomingFloor(_ kind: Platform.Kind) -> Bool {
        guard case .floor(let i) = kind, i == world.dockScreenIndex else { return false }
        if let until = floorVisitUntil, CACurrentMediaTime() < until { return false }
        return true
    }

    /// Bodenstück direkt neben dem Dock (−1 = links, +1 = rechts), auf das Clawd hinunterhüpfen kann.
    private func floorBesideDock(_ side: CGFloat) -> Platform? {
        guard let i = world.dockScreenIndex else { return nil }
        let d = world.dock
        return world.floorPlatforms.first {
            $0.kind == .floor(i) && (side < 0 ? abs($0.maxX - d.minX) < 2 : abs($0.minX - d.maxX) < 2)
        }
    }

    /// Seiten, auf denen neben dem Dock genug Platz zum Herumlaufen ist.
    private var hopOffSides: [CGFloat] {
        guard surface == .dock, world.dock.isDock else { return [] }
        return [-1, 1].filter { (floorBesideDock($0)?.width ?? 0) >= 2 * spriteSize.width }
    }

    /// Zum Dock-Ende laufen; dort hüpft er hinunter (siehe `handleEdges`).
    private func startHopOff() -> Bool {
        // Zum näheren Ende – quer über das ganze Dock wäre ein langer Marsch.
        let d = world.dock
        guard let side = hopOffSides.min(by: { abs(($0 < 0 ? d.minX : d.maxX) - centerX) < abs(($1 < 0 ? d.minX : d.maxX) - centerX) })
        else { return false }
        hopOffSide = side
        direction = side
        let end = side < 0 ? world.dock.minX : world.dock.maxX
        state = .walking(remaining: Double(abs(end - centerX) / max(speed, 1)) + 3)
        trace("will vom Dock hüpfen (\(side < 0 ? "links" : "rechts"))")
        return true
    }

    /// Vom Dock-Ende in einem kleinen Bogen auf den Boden daneben – nie vor die Symbole.
    private func hopOffDock(side: CGFloat) {
        hopOffSide = nil
        guard let floor = floorBesideDock(side) else { return }
        let w = spriteSize.width
        let edge = side < 0 ? floor.maxX : floor.minX
        let tx = min(max(edge + side * w * .random(in: 1.5...3), floor.minX + w / 2), floor.maxX - w / 2)
        let vy: CGFloat = 320
        let drop = max(pos.y - floor.y, 0)
        let flight = (vy + sqrt(vy * vy + 2 * gravity * drop)) / gravity
        // Bis er wieder auf Dock-Höhe ist, muss der Körper ganz am Dock vorbei sein.
        let clear = w * 1.2 / (2 * vy / gravity)
        let vx = side * max(abs(tx - centerX) / flight, clear)
        floorVisitUntil = CACurrentMediaTime() + .random(in: 25...75)
        trace(String(format: "hüpft vom Dock, bleibt %.0f s unten", floorVisitUntil! - CACurrentMediaTime()))
        startFalling(vx: vx)
        fallSoundPlayed = true // gewollter Hüpfer: nur "Hop", kein Juchzer im Fallen
        velocity.dy = vy
        say(.hop)
    }

    private func handleEdges(_ platform: Platform, homing: Bool) {
        let lo = platform.minX
        let hi = platform.maxX - spriteSize.width

        if homing {
            let d = world.dock
            let touchingLeft = direction > 0 && pos.x + spriteSize.width >= d.minX - 4
            let touchingRight = direction < 0 && pos.x <= d.maxX + 4
            if touchingLeft || touchingRight {
                let target = touchingLeft ? d.minX + spriteSize.width : d.maxX - spriteSize.width
                jump(to: world.dockPlatform, centerX: target)
                return
            }
        }

        if walkingOff {
            if !platform.contains(x: centerX) { startFalling(vx: direction * speed) }
            return
        }

        let atLeft = pos.x <= lo && direction < 0
        let atRight = pos.x >= hi && direction > 0
        guard atLeft || atRight else { return }

        // Am gewünschten Dock-Ende angekommen: hinunterhüpfen.
        if platform.kind == .dock, let side = hopOffSide, side == direction {
            hopOffDock(side: side)
            return
        }
        // Beim Herumlaufen unten am Dock angestoßen: manchmal schon wieder hinauf.
        if case .floor(let i) = platform.kind, i == world.dockScreenIndex, world.dock.isDock,
           (atRight && abs(platform.maxX - world.dock.minX) < 2) || (atLeft && abs(platform.minX - world.dock.maxX) < 2),
           Double.random(in: 0..<1) < 0.3 {
            floorVisitUntil = nil
            let d = world.dock
            jump(to: world.dockPlatform, centerX: atRight ? d.minX + spriteSize.width : d.maxX - spriteSize.width)
            return
        }

        // Mit Magnetschuhen um die Ecke auf die Seitenkante des Fensters.
        if magneticShoes, case .window(let id) = platform.kind, let f = world.windowFrames[id],
           world.isEdgeVisible(id, at: CGPoint(x: atLeft ? f.minX : f.maxX, y: f.maxY - spriteSize.width)) {
            if atLeft, abs(platform.minX - f.minX) < 2 { enterWall(id: id, side: -1, y: f.maxY - spriteSize.width / 2 - 1, goingDown: true); return }
            if atRight, abs(platform.maxX - f.maxX) < 2 { enterWall(id: id, side: 1, y: f.maxY - spriteSize.width / 2 - 1, goingDown: true); return }
        }

        if case .window = platform.kind, Double.random(in: 0...1) < 0.55 {
            walkingOff = true // einfach weiterlaufen und herunterfallen
            return
        }
        pos.x = min(max(pos.x, lo), max(lo, hi))
        direction *= -1
    }

    private func chooseNext() {
        hopOffSide = nil
        if debugForce != nil {
            let before = state.kind
            applyDebugForce()
            if state.kind != before { return } // erzwungenes Verhalten hat begonnen
        }
        if isOnWall {
            // Gegenüber ein Fenster in Sprungweite? Dann manchmal hinüberspringen.
            if wallJumpTarget() != nil, Double.random(in: 0..<1) < 0.15, startWallJumps() {
                return
            }
            // Genug geklettert? Je länger er schon an Fenstern hängt, desto eher springt er ab.
            if let since = climbingSince,
               Double.random(in: 0..<1) < Self.jumpDownChance(climbing: CACurrentMediaTime() - since) {
                jumpDown()
                return
            }
            // An der Wand: nur laufen, stehen, umschauen.
            let r = Double.random(in: 0..<1)
            if r < 0.6 {
                if Double.random(in: 0..<1) < 0.4 { wallDir *= -1 }
                state = .walking(remaining: .random(in: 3...9))
            } else if r < 0.8 {
                state = .idle(remaining: .random(in: 1...3))
            } else {
                state = .looking(remaining: 2.4)
            }
            return
        }
        let a = activity * (isCaffeinated ? 1.6 : 1)
        let now = CACurrentMediaTime()
        // Gerade eine Aktivität beendet? Dann beginnt jetzt die ruhige Phase.
        if activityPending {
            activityPending = false
            calmUntil = now + .random(in: Self.calmPhase(activity: a))
            trace(String(format: "ruhige Phase: %.0f s", calmUntil - now))
        }
        if now < calmUntil || !chooseActivity(a) {
            chooseCalm(a)
        }
    }

    /// Länge der ruhigen Phase zwischen zwei Aktivitäten (s): bei Normal 60–120 s,
    /// kürzer bei hoher, länger bei niedriger Aktivität.
    static func calmPhase(activity: Double) -> ClosedRange<Double> {
        let a = max(activity, 0.1)
        return (60 / a)...(120 / a)
    }

    /// Ruhige Phase: nur unauffälliges Grundverhalten – laufen, stehen, umschauen, sitzen, schlafen.
    private func chooseCalm(_ a: Double) {
        let jump = jumpCandidate()
        pickWeighted([
            (0.45 * a, { [unowned self] in
                if Double.random(in: 0...1) < 0.35 { self.direction *= -1 }
                self.state = .walking(remaining: .random(in: 6...20))
            }),
            (jump == nil ? 0 : 0.08 * a, { [unowned self] in
                if let (platform, x) = jump { self.jump(to: platform, centerX: x) }
            }),
            // Gelegentlich vom Dock hinunter, um sich unten umzusehen.
            (hopOffSides.isEmpty ? 0 : 0.04 * a, { [unowned self] in _ = self.startHopOff() }),
            (0.15 / a, { [unowned self] in
                self.state = .idle(remaining: .random(in: 2...6) / a)
                if self.chatty(0.3) { self.voice.play(.murmur) }
            }),
            (0.1, { [unowned self] in self.state = .looking(remaining: 2.4) }),
            (0.1 / a, { [unowned self] in self.state = .sitting(remaining: .random(in: 6...15) / a) }),
            (0.05 / a, { [unowned self] in
                if Double.random(in: 0..<1) < 0.7 {
                    self.startEmote(.yawn, thenSleep: true) // erst gähnen, dann einschlafen
                } else {
                    self.startSleeping()
                }
            }),
        ])
    }

    /// Nach der ruhigen Phase: eine Aktivität. Bedürfnisse (Hunger, Langeweile) gehen vor.
    /// - Returns: false, wenn hier gerade keine Aktivität möglich ist.
    private func chooseActivity(_ a: Double) -> Bool {
        if hunger >= hungerThreshold, EatingJob.isPossible(self) {
            startJob(EatingJob(self))
            return true
        }
        // Langeweile: irgendetwas mit Bewegung – meist Tennis, sonst Sport oder Fegen.
        if boredom >= boredomThreshold, pickWeighted([
            (TennisJob.isPossible(self) ? 0.4 : 0, { [unowned self] in self.startJob(TennisJob(self)) }),
            (0.2, { [unowned self] in self.startSport(.barbell) }),
            (0.2, { [unowned self] in self.startSport(.rope) }),
            (SweepingJob.isPossible(self) ? 0.2 : 0, { [unowned self] in self.startJob(SweepingJob(self)) }),
        ]) {
            satisfy(.boredom)
            return true
        }
        let canSweep = SweepingJob.isPossible(self)
        let jobs = Jobs.possible(for: self)
        // Wochenende: weniger Coden, mehr Musik und Sport (die Jobs gewichtet `Jobs.weight`).
        let weekend = Jobs.isWeekend
        let work = weekend ? Jobs.weekendWorkFactor : 1
        let fun = weekend ? 2.0 : 1
        return pickWeighted([
            // Jobs gewichtet und ohne Wiederholung der letzten drei
            (jobs.isEmpty ? 0 : 0.4, { [unowned self] in
                guard let type = Jobs.pick(from: jobs, avoiding: self.recentJobs) else { return }
                self.recentJobs = Array((self.recentJobs + [type.name]).suffix(3))
                self.startJob(type.init(self))
            }),
            (canSweep ? 0.05 : 0, { [unowned self] in self.startJob(SweepingJob(self)) }),
            (0.09 * fun, { [unowned self] in self.startSport(SportKind.allCases.randomElement() ?? .barbell) }),
            (0.08 * work, { [unowned self] in
                self.state = .coding(remaining: .random(in: 12...35))
                self.startActivity(active: true)
            }),
            (0.08 * work, { [unowned self] in self.startJob(FlowCodingJob(self)) }),
            (0.08 * fun, { [unowned self] in
                self.state = .music(remaining: .random(in: 15...40))
                self.startActivity(active: false)
            }),
            (0.03, { [unowned self] in self.startEmote(.yawn) }),
            (0.025, { [unowned self] in self.startEmote(.sneeze) }),
        ])
    }

    /// Eine Option nach Gewicht auswählen und starten; false, wenn alle Gewichte 0 sind.
    @discardableResult
    private func pickWeighted(_ options: [(weight: Double, start: () -> Void)]) -> Bool {
        let total = options.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return false }
        var r = Double.random(in: 0..<total)
        for option in options {
            if r < option.weight {
                option.start()
                return true
            }
            r -= option.weight
        }
        options.last { $0.weight > 0 }?.start()
        return true
    }

    private func startSleeping() {
        beginEvent()
        state = .sleeping(remaining: .random(in: 15...40) / activity)
        nextSnore = CACurrentMediaTime() + 1.5
    }

    private func startSport(_ kind: SportKind) {
        if Double.random(in: 0...1) < 0.35 { direction *= -1 }
        state = .sport(kind, remaining: .random(in: 10...22))
    }

    private func applyDebugForce() {
        guard let force = debugForce else { return }
        debugForce = nil
        switch force {
        case .behavior(let behavior):
            start(behavior)
        case .job(let type):
            if type.isPossible(self) {
                let job = type.init(self)
                job.isDemo = true
                startJob(job)
            } else {
                debugForce = force // später nochmal versuchen (z. B. bis ein zweiter Clawd gelandet ist)
                let others = stage?.controllers.filter { $0 !== self }
                    .map { "\(String(describing: $0.surfaceKind)) frei:\($0.canBeLandedOn)" } ?? []
                trace("job noch nicht möglich: \(force.name) andere: \(others)")
            }
        case .encounter:
            break // Begegnungen startet die Bühne
        }
    }

    private func start(_ behavior: DemoAction.Behavior) {
        switch behavior {
        case .wave: beginEvent(); state = .waving(remaining: 1.6); say(.happy)
        case .look: state = .looking(remaining: 2.4)
        case .sit: state = .sitting(remaining: 6)
        case .coding: state = .coding(remaining: 30); startActivity(active: true)
        case .music: state = .music(remaining: 30); startActivity(active: false)
        case .sleep: beginEvent(); state = .sleeping(remaining: 30); nextSnore = CACurrentMediaTime() + 1
        case .sneeze: startEmote(.sneeze)
        case .yawn: startEmote(.yawn, thenSleep: true)
        case .dizzy: startEmote(.dizzy)
        case .hide:
            // Wie bei einer Vollbild-App, nur ohne Ausblenden: 1 s in Deckung, dann der gewohnte Ablauf.
            takeCover()
            shelterReleased = CACurrentMediaTime() + 1
        case .barbell: startSport(.barbell)
        case .rope: startSport(.rope)
        case .wallJump:
            if !startWallJumps() { trace("Wandsprung: kein Fenster in Sprungweite") }
        case .hopOff:
            if !startHopOff() { trace("Vom Dock hüpfen: nicht auf dem Dock oder kein Platz daneben") }
        case .slide:
            // Neigung vorspielen: 2,5 s lang, als würde das MacBook zur Seite gekippt.
            demoTilt = Bool.random() ? 0.4 : -0.4
            demoTiltUntil = CACurrentMediaTime() + 2.5
        }
    }

    private func startActivity(active: Bool) {
        activityActive = active
        activityPhaseUntil = CACurrentMediaTime() + .random(in: 1.5...3)
    }

    /// Ein höher gelegenes Fenster (oder das Dock) in Sprungweite.
    private func jumpCandidate() -> (Platform, CGFloat)? {
        let w = spriteSize.width
        let candidates = (world.windowPlatforms + [world.dockPlatform]).compactMap { p -> (Platform, CGFloat)? in
            guard p.kind != surface else { return nil }
            let dy = p.y - pos.y
            guard dy > 30, dy < 170, p.width > w + 8 else { return nil }
            let tx = min(max(centerX + .random(in: -200...200), p.minX + w / 2 + 4), p.maxX - w / 2 - 4)
            guard abs(tx - centerX) < 260 else { return nil }
            return (p, tx)
        }
        return candidates.randomElement()
    }

    private func checkCursor(now: CFTimeInterval) {
        let m = NSEvent.mouseLocation
        if m != lastMouse {
            lastMouse = m
            lastMouseMove = now
        }
        switch state {
        case .walking, .idle, .looking, .sitting: break
        default: return
        }
        guard now - lastWave > 8, now - lastMouseMove < 0.5,
              hypot(m.x - centerPoint.x, m.y - centerPoint.y) < 140,
              !isHomingFloor(surface ?? .dock)
        else { return }
        direction = m.x < centerX ? -1 : 1
        lastWave = now
        beginEvent()
        state = .waving(remaining: 1.6)
        say(.happy)
    }

    // MARK: - Luft

    /// Ein Fall ist ein Ereignis: Erschrecken, "Wiiieee", "Oof" und "Klonk" gehören zusammen.
    private func startFalling(vx: CGFloat) {
        beginEvent()
        if isOnWall {
            undockEffect(sound: false)
            wallToUpright()
        }
        surface = nil
        walkingOff = false
        hopOffSide = nil
        fallSoundPlayed = false
        velocity = CGVector(dx: vx, dy: 0)
        fallStartY = pos.y
        state = .airborne
    }

    private func jump(to target: Platform, centerX tx: CGFloat) {
        let overshoot: CGFloat = 18
        let h = max(target.y - pos.y, 0) + overshoot
        let vy = sqrt(2 * gravity * h)
        let flightTime = vy / gravity + sqrt(2 * overshoot / gravity)
        let vx = (tx - centerX) / flightTime
        startFalling(vx: vx)
        velocity.dy = vy
        say(.hop)
    }

    private func stepPhysics(dt: TimeInterval) {
        let t = CGFloat(dt)
        velocity.dy -= gravity * t
        // Geneigtes MacBook: die Schwerkraft zieht auch ein Stück zur Seite.
        if abs(effectiveTilt) > 0.05 { velocity.dx += CGFloat(effectiveTilt) * gravity * t }
        let prev = pos
        var next = CGPoint(x: pos.x + velocity.dx * t, y: pos.y + velocity.dy * t)
        let w = spriteSize.width
        let h = spriteSize.height

        // Seitlich nur innerhalb der Bildschirme: Mitte zurück auf den nächsten Bildschirm holen.
        if world.screen(containingX: next.x + w / 2) == nil, let s = world.nearestScreen(toX: next.x + w / 2) {
            next.x = min(max(next.x, s.frame.minX), s.frame.maxX - w)
            if abs(velocity.dx) > 300 { bonk() }
            velocity.dx = -velocity.dx * wallBounce
        }
        // Decke
        if let s = world.screen(containingX: next.x + w / 2), next.y > s.frame.maxY - h {
            next.y = s.frame.maxY - h
            if velocity.dy > 200 { bonk() }
            velocity.dy = min(velocity.dy, 0)
        }
        // Seitlich gegen den Dock-Block (beim Hochspringen hochrutschen, sonst abprallen)
        if world.dock.isDock, next.y < world.dock.y, overlapsDock(next.x), !overlapsDock(prev.x) {
            next.x = prev.x
            if velocity.dy <= 0 { velocity.dx = -velocity.dx * wallBounce }
        }

        // Magnetschuhe: seitlich gegen ein Fenster geflogen? Festhaften!
        if magneticShoes, !knockedOut, CACurrentMediaTime() >= magnetPauseUntil {
            let cy = next.y + h / 2
            let half = h / 2 // Körper ragt quer zur Wand eine halbe Sprite-Höhe heraus
            let pcx = prev.x + w / 2, ncx = next.x + w / 2
            let screens = world.screens.map(\.frame)
            for (id, f) in world.wallFrames where cy > f.minY + w / 2 && cy < f.maxY - w / 2 {
                if pcx + half <= f.minX, ncx + half > f.minX, world.isEdgeVisible(id, at: CGPoint(x: f.minX, y: cy)),
                   Self.wallHasRoom(x: f.minX, side: -1, depth: h, y: cy, screens: screens) {
                    stickToWall(id: id, side: -1, y: cy); return
                }
                if pcx - half >= f.maxX, ncx - half < f.maxX, world.isEdgeVisible(id, at: CGPoint(x: f.maxX, y: cy)),
                   Self.wallHasRoom(x: f.maxX, side: 1, depth: h, y: cy, screens: screens) {
                    stickToWall(id: id, side: 1, y: cy); return
                }
            }
        }

        // Landung: die höchste Plattform, die in diesem Schritt von oben durchquert wird.
        if velocity.dy <= 0 {
            let cx = next.x + w / 2
            for p in world.allPlatforms where prev.y >= p.y - 0.5 && next.y <= p.y {
                let hit = p.kind == .dock ? overlapsDock(next.x) : p.contains(x: cx)
                if hit {
                    land(on: p, x: next.x)
                    return
                }
            }
        }
        pos = next

        if !fallSoundPlayed, velocity.dy < -250, fallStartY - pos.y > 30 {
            fallSoundPlayed = true
            say(oneOf: Voice.Sound.cheer)
        }

        // Sicherheitsnetz: nie unter den Bildschirm fallen
        if let floor = world.nearestScreen(toX: centerX)?.frame.minY, pos.y < floor - 1 {
            pos.y = floor
            // Unter dem Dock gibt es keinen Boden (z. B. weil das Dock gewachsen ist): obendrauf.
            if world.dock.isDock, overlapsDock(pos.x), !world.floorPlatforms.contains(where: { $0.y == floor && $0.contains(x: centerX) }) {
                land(on: world.dockPlatform, x: pos.x)
            }
        }
    }

    private func land(on p: Platform, x: CGFloat) {
        wallJumpsLeft = 0 // Serie verpasst: auf einer Fläche gelandet
        climbingSince = nil
        if yankedFall {
            yankedFall = false
            if fallStartY - p.y > 50 { knockedOut = true } // kleine Hopser zählen nicht
        }
        surface = p.kind
        if case .floor = p.kind {} else { floorVisitUntil = nil }
        walkingOff = false
        velocity = .zero
        let w = spriteSize.width
        // Dock und Boden: ganz auf der Fläche (am Bildschirmrand nicht halb hinausragen).
        switch p.kind {
        case .dock, .floor: pos.x = min(max(x, p.minX), max(p.minX, p.maxX - w))
        default: pos.x = x
        }
        pos.y = p.y
        distanceWalked = 0
        // Aufprall: nach einem Sturz "Autsch", aus großer Höhe ein Stöhnen, sonst "Oof".
        let height = fallStartY - p.y
        if knockedOut, height > 30 {
            say(.autsch)
        } else if height > 400 {
            say(.ohOuh)
        } else if height > 120 {
            say(.oof)
        }
        if grumpyWake {
            grumpyWake = false
            if Double.random(in: 0..<1) < 0.6 { say(.hmpf) } // aus dem Schlaf geklickt
        }
        state = .landing(remaining: 0.25)
    }

    // MARK: - Maus

    /// Liegt der Punkt (global, Cocoa) auf einem sichtbaren Pixel von Clawd?
    func hitTest(_ p: CGPoint) -> Bool {
        let size = spriteSize
        if isOnWall {
            let c = wallBodyCenter
            return abs(p.x - c.x) <= size.height / 2 && abs(p.y - c.y) <= size.width / 2
        }
        guard p.x >= pos.x, p.x < pos.x + size.width, p.y >= pos.y, p.y < pos.y + size.height else { return false }
        let frame = node.sprite
        // Frames in doppelter Auflösung (z. B. das Kaninchen) haben mehr Zellen pro Clawd-Pixel.
        let cols = frame.first?.count ?? ClawdSprite.columns
        let cellsX = CGFloat(cols) / CGFloat(ClawdSprite.columns)
        let cellsY = CGFloat(frame.count) / CGFloat(ClawdSprite.rows)
        var col = Int((p.x - pos.x) / pixel * cellsX)
        let row = frame.count - 1 - Int((p.y - pos.y) / pixel * cellsY)
        if node.facingLeft { col = cols - 1 - col }
        guard frame.indices.contains(row) else { return false }
        let line = Array(frame[row])
        guard line.indices.contains(col) else { return false }
        // Ein Pixel Toleranz, damit man die dünnen Beinchen auch erwischt.
        let neighbours = [col - 1, col, col + 1].filter { line.indices.contains($0) }
        return neighbours.contains { line[$0] != "." }
    }

    func mouseDown(at p: CGPoint) {
        mouseDownPoint = p
        isDragging = false
        grabOffset = CGVector(dx: p.x - pos.x, dy: p.y - pos.y)
        dragSamples = [(CACurrentMediaTime(), p)]
        dragShake.reset()
        shakenWhileDragged = false
    }

    func mouseDragged(to p: CGPoint) {
        if !isDragging {
            guard hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) >= dragThreshold else { return }
            isDragging = true
            if isOnWall {
                undockEffect(sound: true)
                // Aufrecht unter den Mauszeiger holen.
                pos = CGPoint(x: p.x - spriteSize.width / 2, y: p.y - spriteSize.height / 2)
                grabOffset = CGVector(dx: spriteSize.width / 2, dy: spriteSize.height / 2)
            }
            surface = nil
            floorVisitUntil = nil
            velocity = .zero
            state = .dragged
            wallJumpsLeft = 0
            NSCursor.closedHand.push()
            beginEvent()
            say(oneOf: Voice.Sound.startled)
        }

        let s = world.screen(containingX: p.x, y: p.y)?.frame ?? NSRect(x: p.x - 1000, y: p.y - 1000, width: 2000, height: 2000)
        pos.x = min(max(p.x - grabOffset.dx, s.minX), s.maxX - spriteSize.width)
        pos.y = min(max(p.y - grabOffset.dy, s.minY), s.maxY - spriteSize.height)

        let now = CACurrentMediaTime()
        dragSamples.append((now, p))
        dragSamples.removeAll { now - $0.t > Self.throwWindow }
        if !shakenWhileDragged, dragShake.add(p, now: now).isVigorous {
            // Heftig durchgeschüttelt: ab jetzt benommen, nach dem Absetzen wird geschimpft.
            shakenWhileDragged = true
            trace("am Mauszeiger durchgeschüttelt")
            say(.oiExcited)
        }
        updateMagnet()
        place()
    }

    func mouseUp(at p: CGPoint) {
        guard isDragging else {
            clicked()
            return
        }
        isDragging = false
        NSCursor.pop()

        // Durchgeschüttelt: zu benommen zum Festhalten – er fällt, und nach der Landung wird geschimpft.
        if shakenWhileDragged {
            shakenWhileDragged = false
            knockedOut = true
            magnet = nil
            hideMagnetWaves()
        }

        // Nah genug an einer Fensterkante? Dann dockt er dort an, statt zu fallen.
        if let m = magnet {
            magnet = nil
            hideMagnetWaves()
            stickToWall(id: m.id, side: m.side, y: pos.y + spriteSize.height / 2)
            return
        }

        let v = Self.throwVelocity(samples: dragSamples, release: (CACurrentMediaTime(), p), limit: maxThrow)

        // Losgelassen "im" Dock-Block → obendrauf setzen.
        if world.dock.isDock, pos.y < world.dock.y, overlapsDock(pos.x) {
            pos.y = world.dock.y
        }
        startFalling(vx: v.dx)
        droppedByUser = true
        velocity.dy = v.dy
    }

    /// Zeitfenster vor dem Loslassen, aus dem die Wurfgeschwindigkeit stammt.
    static let throwWindow: TimeInterval = 0.1

    /// Wurfgeschwindigkeit: Strecke der letzten `throwWindow` s **bis zum Loslassen**, geteilt durch die Zeit.
    /// Ein stillstehender Cursor schickt keine Bewegungen mehr – die Ruhezeit zählt trotzdem mit, sonst
    /// würde nach einer Pause noch die letzte Bewegung davor geworfen. Nach `throwWindow` s Stillstand: 0.
    static func throwVelocity(samples: [(t: CFTimeInterval, p: CGPoint)], release: (t: CFTimeInterval, p: CGPoint),
                              limit: CGFloat) -> CGVector {
        guard let first = samples.first(where: { release.t - $0.t <= throwWindow }) else { return .zero }
        let dt = CGFloat(release.t - first.t)
        guard dt > 0.01 else { return .zero }
        func clamp(_ v: CGFloat) -> CGFloat { min(max(v, -limit), limit) }
        return CGVector(dx: clamp((release.p.x - first.p.x) / dt), dy: clamp((release.p.y - first.p.y) / dt))
    }

    /// Kurzer Klick: weckt Clawd bzw. lässt ihn hüpfen.
    private func clicked() {
        if case .sleeping = state {
            startFalling(vx: 0)
            velocity.dy = 600
            say(oneOf: Voice.Sound.startled)
            grumpyWake = true
        } else if isGroundedState {
            startFalling(vx: 0)
            velocity.dy = 520
            if chatty(0.5) { voice.play(.murmur) } else { say(.hop) }
        }
    }

    // MARK: - Darstellung

    private func updateSprite(now: CFTimeInterval) {
        if now >= nextBlink {
            blinkUntil = now + 0.15
            nextBlink = now + (Double.random(in: 0...1) < 0.2 ? 0.35 : .random(in: 2...6))
        }
        let blinking = now < blinkUntil
        let t = now - stateStart

        node.particles = .none
        if case .dragged = state {} else if node.bootsGlow || magnet != nil {
            node.bootsGlow = false
            magnet = nil
            hideMagnetWaves()
        }
        node.showLaptop = false
        node.showHeadphones = false
        node.sportProp = nil
        node.liftPixels = 0
        node.dustPile = 0
        node.showBubble = false
        node.bubbleFrame = ClawdSprite.speechBubble
        node.hat = nil
        switch state {
        case .walking:
            node.sprite = blinking ? ClawdSprite.blink : ClawdSprite.walkFrame(walked: distanceWalked, px: pixel)
        case .idle:
            distanceWalked = 0
            node.sprite = blinking ? ClawdSprite.blink : ClawdSprite.stand
        case .looking:
            let i = Int(t / 0.6) % ClawdSprite.lookCycle.count
            node.sprite = ClawdSprite.lookCycle[i]
        case .sitting:
            node.sprite = blinking ? ClawdSprite.sitBlink : ClawdSprite.sit
        case .sleeping:
            node.sprite = ClawdSprite.sleep
            node.particles = .zzz
        case .coding:
            node.showLaptop = true
            if activityActive {
                let i = Int(t / 0.12) % ClawdSprite.codeType.count
                node.sprite = ClawdSprite.codeType[i]
                node.particles = .code
            } else {
                node.sprite = blinking ? ClawdSprite.sitBlink : ClawdSprite.codeIdle
            }
        case .music:
            node.showHeadphones = true
            if activityActive {
                // Mitwippen im Takt (~100 bpm), Noten steigen auf.
                let i = Int(t / 0.3) % ClawdSprite.musicGroove.count
                node.sprite = ClawdSprite.musicGroove[i]
                node.particles = .notes
            } else {
                node.sprite = blinking ? ClawdSprite.sitBlink : ClawdSprite.musicListen
            }
        case .waving:
            let i = Int(t / 0.18) % ClawdSprite.wave.count
            node.sprite = ClawdSprite.wave[i]
        case .dragged:
            if shakenWhileDragged {
                node.sprite = ClawdSprite.dizzy
                node.sportProp = ClawdSprite.dizzyEyes
            } else {
                let i = Int(now / 0.1) % ClawdSprite.wriggle.count
                node.sprite = ClawdSprite.wriggle[i]
            }
            node.bootsGlow = magnet != nil && Int(now / 0.12) % 2 == 0
            drawMagnetWaves(now: now)
        case .airborne:
            node.sprite = velocity.dy < -250 ? ClawdSprite.flail : ClawdSprite.stand
        case .landing:
            node.sprite = ClawdSprite.squash
        case .sliding:
            // Rudert mit den Armen, schaut bergauf und wackelt beim Rutschen.
            node.sprite = ClawdSprite.flail
            node.liftPixels = slideSpeed != 0 && Int(now / 0.1) % 2 == 0 ? 0.5 : 0
        case .sheltering:
            node.sprite = ClawdSprite.coverFrame(sinceRelease: shelterReleased.map { now - $0 })
        case .sport(let kind, _):
            updateSportSprite(kind, t: t)
        case .encounter:
            encounter?.applyVisuals(to: self, blinking: blinking)
        case .emote(let e):
            updateEmoteSprite(e, now: now, blinking: blinking)
        case .job:
            if let job { applyPose(job.pose, blinking: blinking) }
        }
        node.animateParticles()
    }

    /// Sport im 80er-Outfit; nach ein paar Sekunden perlt ab und zu Schweiß ab.
    private func updateSportSprite(_ kind: SportKind, t: TimeInterval) {
        var frame: ClawdSprite.Frame
        switch kind {
        case .barbell:
            // Curl: unten → Mitte → oben (kurz halten) → Mitte → unten (kurz Pause).
            let sequence = [(0, 0.45), (1, 0.3), (2, 0.55), (1, 0.3)]
            let cycle = sequence.reduce(0) { $0 + $1.1 }
            var rest = t.truncatingRemainder(dividingBy: cycle)
            var position = 0
            for (pos, duration) in sequence {
                if rest < duration { position = pos; break }
                rest -= duration
            }
            frame = ClawdSprite.curlFrames[position]
            node.sportProp = ClawdSprite.barbell(spriteRow: ClawdSprite.curlBarRow[position])
        case .rope:
            let phases = ClawdSprite.RopePhase.allCases
            let phase = phases[Int(t / 0.14) % phases.count]
            let lift: Int
            switch phase {
            case .over: lift = 0
            case .front, .behind: lift = 1
            case .under: lift = 2
            }
            frame = phase == .under ? ClawdSprite.ropeJump : ClawdSprite.stand
            node.liftPixels = CGFloat(lift)
            node.sportProp = ClawdSprite.rope(phase, lift: lift)
        }
        node.sprite = ClawdSprite.sporty(frame)
        if t > 4 { node.particles = .sweat }
    }

    // MARK: - Bedürfnisse

    enum Need { case hunger, boredom }

    /// Bedürfnis gestillt (nach dem Essen bzw. bei Beginn einer Bewegungs-Aktivität gegen die Langeweile).
    func satisfy(_ need: Need) {
        switch need {
        case .hunger:
            hunger = 0
            hungerThreshold = .random(in: Self.hungerRange)
        case .boredom:
            boredom = 0
            boredomThreshold = .random(in: Self.boredomRange)
        }
    }

    /// Von außen (Menü "Clawd füttern"): sofort hungrig, und wenn möglich gleich essen.
    func feed() {
        hunger = hungerThreshold
        switch state {
        case .walking, .idle, .looking, .sitting, .waving, .coding, .music, .sport:
            if !isHomingFloor(surface ?? .dock), EatingJob.isPossible(self) { startJob(EatingJob(self)) }
        default:
            break
        }
    }

    // MARK: - Niesen & Gähnen

    func startEmote(_ e: Emote, thenSleep: Bool = false) {
        beginEvent()
        emoteStart = CACurrentMediaTime()
        emoteThenSleep = thenSleep
        emoteCues = []
        state = .emote(e)
    }

    private func cue(_ key: String) -> Bool { emoteCues.insert(key).inserted }

    private func stepEmote(_ e: Emote, now: CFTimeInterval) {
        let t = now - emoteStart
        switch e {
        case .sneeze:
            // "ha… ha…" – "TSCHIII!" – "huhuhuhu"
            if cue("haa") { say(.haa) }
            if t >= 1.2, cue("achoo") { say(.achoo) }
            if t >= 1.85, cue("giggle") { say(.giggle) }
            if t >= 3.0 { state = .idle(remaining: .random(in: 0.6...1.2)) }
        case .dizzy:
            // Benommen (Vögelchen) → aufrappeln → den Nutzer beschimpfen
            if t < 3.2 {
                let chirp = Int(t / 0.9)
                if cue("tweet\(chirp)") { say(.tweet) }
            } else if t < 4.3 {
                // Beim Aufrappeln manchmal erst jammern …
                if cue("whine"), Bool.random() { say(oneOf: Voice.Sound.whine) }
            } else {
                if cue("face") {
                    // Zum Mauszeiger drehen – da ist der Schuldige!
                    direction = NSEvent.mouseLocation.x < centerX ? -1 : 1
                }
                if cue("scold1") { say(.scold) }
                if t >= 5.6, cue("scold2") { say(oneOf: [.scold, .naWarte]) }
            }
            if t >= 7.0 { state = .idle(remaining: .random(in: 0.8...1.5)) }
        case .yawn:
            if t >= 0.3, cue("yawn") { say(.yawn) }
            if t >= 2.4 {
                if emoteThenSleep { startSleeping() } else { state = .idle(remaining: .random(in: 0.6...1.2)) }
            }
        }
    }

    private func updateEmoteSprite(_ e: Emote, now: CFTimeInterval, blinking: Bool) {
        let t = now - emoteStart
        switch e {
        case .sneeze:
            switch t {
            case ..<1.2:
                // Kopf geht mit jedem Einatmen ein Stück nach hinten/oben.
                node.sprite = ClawdSprite.sneezeBuild
                node.liftPixels = t < 0.55 ? 0.5 : 1
            case ..<1.6:
                // Ruckartig zusammengestaucht, Tröpfchen fliegen nach vorn.
                node.sprite = ClawdSprite.sneezeBlast
                node.particles = t < 1.5 ? .sneeze : .none
            default:
                // Verlegenes Kichern mit leichtem Wackeln
                node.sprite = ClawdSprite.happyStand
                node.liftPixels = Int(t / 0.12) % 2 == 0 ? 0 : 0.5
            }
        case .dizzy:
            switch t {
            case ..<3.5:
                node.sprite = ClawdSprite.dizzy
                node.sportProp = ClawdSprite.dizzyEyes
                node.particles = .birds
            case ..<4.3:
                // Aufrappeln, Kopf schütteln
                node.sprite = ClawdSprite.lookCycle[Int(t / 0.12) % 2 == 0 ? 1 : 3]
            default:
                node.sprite = ClawdSprite.scold[Int(t / 0.12) % 2]
                node.liftPixels = Int(t / 0.24) % 2 == 0 ? 0 : 0.5 // stampfen
                node.bubbleFrame = ClawdSprite.curseBubble
                node.showBubble = true
            }
        case .yawn:
            switch t {
            case ..<0.5:
                // Auf die Zehenspitzen, Arme nach oben
                node.sprite = ClawdSprite.yawnStretch
                node.liftPixels = 1.5 * CGFloat(t / 0.5)
            case ..<1.8:
                node.sprite = ClawdSprite.yawnMouth
                node.liftPixels = 1.5
            default:
                node.sprite = blinking || t < 2.0 ? ClawdSprite.blink : ClawdSprite.stand
            }
        }
    }

    // MARK: - Neigung (Beschleunigungssensor)

    /// Querneigung des MacBooks in g, von der Bühne gesetzt: > 0 = rechte Seite tiefer.
    var tilt: Double = 0
    /// Vorgespielte Neigung aus dem Demo-Menü.
    private var demoTilt: Double = 0
    private var demoTiltUntil: CFTimeInterval = 0
    private var effectiveTilt: Double { CACurrentMediaTime() < demoTiltUntil ? demoTilt : tilt }

    /// Ab dieser Neigung (≈ 10°) rutscht Clawd los, ab ≈ 20° auch mitten aus einer Beschäftigung.
    static let slideStart = 0.17
    static let slideBusy = 0.35
    /// Haftreibung (pt/s²): Unterhalb von etwa 7° Neigung bleibt er stehen.
    static let slideFriction: CGFloat = 300

    private var slideSpeed: CGFloat = 0
    private var slideDistance: CGFloat = 0
    private var lastSlideSound: CFTimeInterval = -100

    /// Ist das MacBook genug geneigt, verliert Clawd den Halt. Magnetschuhe an der Wand halten.
    private func reactToTilt(now: CFTimeInterval) {
        let tilt = effectiveTilt
        guard abs(tilt) >= Self.slideStart, surface != nil, !isOnWall else { return }
        switch state {
        case .walking, .idle, .looking, .sitting, .sleeping, .waving:
            break
        case .coding, .music, .sport, .emote, .job, .encounter:
            guard abs(tilt) >= Self.slideBusy else { return }
            encounter?.abort()
            job?.cleanup()
            job = nil
        default:
            return
        }
        beginEvent()
        hopOffSide = nil
        slideSpeed = 0
        slideDistance = 0
        state = .sliding
        trace(String(format: "rutscht los (Neigung %.2f g)", tilt))
        if now - lastSlideSound > 4 {
            lastSlideSound = now
            say(oneOf: [.uiiiSlide, .uiii])
        }
    }

    /// Hangabtrieb gegen Haftreibung. Am Ende eines Fensters oder des Docks rutscht er hinunter,
    /// am Bildschirmrand und am Dock-Block bleibt er hängen.
    private func stepSliding(dt: TimeInterval, now: CFTimeInterval) {
        guard let kind = surface, let platform = world.platform(kind, near: centerX) else {
            startFalling(vx: slideSpeed)
            return
        }
        let t = CGFloat(dt)
        let drive = CGFloat(effectiveTilt) * gravity
        slideSpeed += drive * t
        let friction = Self.slideFriction * t
        slideSpeed = abs(slideSpeed) <= friction ? 0 : slideSpeed - friction * (slideSpeed > 0 ? 1 : -1)
        slideSpeed = min(max(slideSpeed, -900), 900)
        pos.x += slideSpeed * t
        pos.y = platform.y
        slideDistance += abs(slideSpeed * t)
        if slideSpeed != 0 { direction = slideSpeed > 0 ? -1 : 1 } // rutscht rückwärts, Blick bergauf

        if !platform.contains(x: centerX) {
            switch kind {
            case .window, .dock:
                trace("rutscht über die Kante")
                startFalling(vx: slideSpeed)
                return
            default:
                break
            }
        }
        let lo = platform.minX, hi = max(platform.minX, platform.maxX - spriteSize.width)
        if pos.x < lo || pos.x > hi {
            pos.x = min(max(pos.x, lo), hi)
            slideSpeed = 0
        }
        // Wieder gerade genug, um stehen zu bleiben? Dann verdutzt umschauen.
        if slideSpeed == 0, abs(drive) < Self.slideFriction {
            trace(String(format: "rutscht nicht mehr (%.0f pt gerutscht)", slideDistance))
            state = slideDistance > 30 ? .looking(remaining: 2.4) : .idle(remaining: .random(in: 0.5...1.5))
        }
    }

    // MARK: - Magnetschuhe (an Fensterseiten laufen)

    var magneticShoes = false {
        didSet {
            node.boots = magneticShoes
            if !magneticShoes, isOnWall { startFalling(vx: 0) }
        }
    }

    /// Abgeschüttelt und im Fallen – nach der Landung erst mal benommen.
    private var knockedOut = false
    /// Bis dahin greifen die Magnetschuhe im Flug nicht (nach dem Abrutschen von einer Kante).
    private var magnetPauseUntil: CFTimeInterval = 0
    /// Fenster wurde unter ihm weggezogen – bei einem richtigen Sturz danach benommen.
    private var yankedFall = false
    private var shake = ShakeDetector()
    /// Schütteln am Mauszeiger (beim Ziehen) – getrennt von dem des Fensters, mit doppelt so
    /// langem Zeitfenster, damit die acht Richtungswechsel von `isVigorous` machbar sind.
    private var dragShake = ShakeDetector(window: 1.6)
    private var shakenWhileDragged = false

    /// Wird das Fenster gerade geschüttelt?
    private func isBeingShaken(_ origin: CGPoint, now: CFTimeInterval) -> Bool {
        let reading = shake.add(origin, now: now)
        if reading.path > 20 {
            trace(String(format: "schütteln? proben=%d wechsel=%d weg=%.0f", reading.samples, reading.reversals, reading.path))
        }
        return reading.isShaking
    }

    /// An der Wand: +1 = hoch, −1 = runter.
    private var wallDir: CGFloat = -1

    var isOnWall: Bool {
        if case .wall = surface { return true }
        return false
    }

    private struct WallGeometry {
        let id: CGWindowID
        let side: Int
        let frame: NSRect
        let x: CGFloat
        let minY: CGFloat
        let maxY: CGFloat
    }

    /// Aktuelle Wand (live aus dem Fensterrahmen); Fußpunkt bewegt sich zwischen minY und maxY.
    private var wall: WallGeometry? {
        guard case .wall(let id, let side) = surface, let f = world.wallFrames[id] else { return nil }
        let half = spriteSize.width / 2
        let x = side < 0 ? f.minX : f.maxX
        var bottom: CGFloat
        let top: CGFloat
        if World.isScreenEdge(id) {
            // Bildschirmrand: unten bis zum Boden – außer das Dock reicht bis hierher, dann nur bis
            // zur Dock-Oberkante (nie vor den Symbolen); oben bis unter die Menüleiste.
            let screen = world.screen(containingX: x + CGFloat(side), y: f.midY)
            bottom = f.minY
            let d = world.dock
            let bodyMin = side > 0 ? x : x - spriteSize.height, bodyMax = bodyMin + spriteSize.height
            if d.isDock, d.minX < bodyMax, d.maxX > bodyMin, d.y > f.minY, d.y < f.maxY { bottom = d.y }
            top = min(f.maxY, screen?.visibleFrame.maxY ?? f.maxY)
        } else {
            let screen = world.screen(containingX: f.midX, y: f.midY)
            bottom = max(f.minY, screen?.visibleFrame.minY ?? f.minY)
            top = min(f.maxY, screen?.visibleFrame.maxY ?? f.maxY)
        }
        return WallGeometry(id: id, side: side, frame: f, x: x,
                            minY: bottom + half, maxY: max(bottom + half, top - half))
    }

    /// Mitte des (gedrehten) Körpers, wenn Clawd an der Wand steht.
    private var wallBodyCenter: CGPoint {
        guard case .wall(_, let side) = surface else { return centerPoint }
        return CGPoint(x: pos.x + CGFloat(side) * spriteSize.height / 2, y: pos.y)
    }

    /// Von der Wand in die normale Lage (Position = unten links), z. B. vor dem Fallen.
    private func wallToUpright() {
        let c = wallBodyCenter
        pos = CGPoint(x: c.x - spriteSize.width / 2, y: c.y - spriteSize.height / 2)
    }

    /// Reine Geometrie: Liegt der Körper (ragt `depth` von der Kante in Richtung `side` ab) noch auf
    /// einem Bildschirm?
    static func wallHasRoom(x: CGFloat, side: Int, depth: CGFloat, y: CGFloat, screens: [NSRect]) -> Bool {
        let cx = x + CGFloat(side) * depth / 2
        return screens.contains { cx >= $0.minX && cx < $0.maxX && y >= $0.minY && y <= $0.maxY }
    }

    /// Fensterkante, die Clawd beim Laufen auf Boden oder Dock gerade erreicht hat: Das Fenster muss
    /// bis zum Boden reichen und hoch genug sein. `oldFront` = Vorderkante vor diesem Schritt.
    private func climbableWall(from oldFront: CGFloat) -> (id: CGWindowID, side: Int)? {
        switch surface {
        case .dock, .floor: break
        default: return nil
        }
        let newFront = direction > 0 ? pos.x + spriteSize.width : pos.x
        let half = spriteSize.width / 2
        return Self.climbableWall(in: world.wallFrames, groundY: pos.y, from: oldFront, to: newFront, direction: direction,
                                  visible: { [world] id, p in world.isEdgeVisible(id, at: CGPoint(x: p.x, y: p.y + half)) })
    }

    /// Reine Geometrie: welche Fensterseite überquert die Vorderkante von `oldFront` nach `newFront`?
    /// side −1 = linke Fensterseite (von links kommend), +1 = rechte (von rechts kommend).
    static func climbableWall(in windows: [CGWindowID: NSRect], groundY: CGFloat, from oldFront: CGFloat,
                              to newFront: CGFloat, direction: CGFloat,
                              visible: (CGWindowID, CGPoint) -> Bool = { _, _ in true }) -> (id: CGWindowID, side: Int)? {
        for (id, f) in windows where f.minY <= groundY + 12 && f.maxY >= groundY + 80 {
            if direction > 0, oldFront < f.minX, newFront >= f.minX, visible(id, CGPoint(x: f.minX, y: groundY)) { return (id, -1) }
            if direction < 0, oldFront > f.maxX, newFront <= f.maxX, visible(id, CGPoint(x: f.maxX, y: groundY)) { return (id, 1) }
        }
        return nil
    }

    /// Seit wann Clawd am Stück klettert (auch über Wandsprünge hinweg); nil auf festem Boden.
    private var climbingSince: CFTimeInterval?

    /// Wahrscheinlichkeit pro Entscheidung, freiwillig abzuspringen: die ersten 15 s nie,
    /// dann steigend bis höchstens 50 % (nach etwa 75 s).
    static func jumpDownChance(climbing seconds: TimeInterval) -> Double {
        min(max((seconds - 15) / 120, 0), 0.5)
    }

    /// Von der Wand abstoßen und nach unten springen.
    private func jumpDown() {
        guard case .wall(_, let side) = surface else { return }
        climbingSince = nil
        wallJumpsLeft = 0
        say(.hop)
        trace("hat genug vom Klettern und springt ab")
        startFalling(vx: CGFloat(side) * 140)
        velocity.dy = 180
    }

    private func enterWall(id: CGWindowID, side: Int, y: CGFloat, goingDown: Bool) {
        guard let f = world.wallFrames[id] else { return }
        if climbingSince == nil { climbingSince = CACurrentMediaTime() }
        surface = .wall(id, side)
        pos = CGPoint(x: side < 0 ? f.minX : f.maxX, y: y)
        wallDir = goingDown ? -1 : 1
        walkingOff = false
        if case .walking = state {} else { state = .walking(remaining: .random(in: 3...8)) }
    }

    /// Schmalste und breiteste Lücke, über die Clawd von Fensterkante zu Fensterkante springt.
    static let wallJumpGap: ClosedRange<CGFloat> = 40...320

    /// Fenster gegenüber der aktuellen Wand, dessen zugewandte Seite in Sprungweite liegt.
    private func wallJumpTarget(rise: CGFloat = 0) -> (id: CGWindowID, gap: CGFloat)? {
        guard let g = wall else { return nil }
        return Self.wallJumpTarget(from: g.x, side: g.side, footY: pos.y + rise, selfID: g.id,
                                   windows: world.wallFrames, margin: spriteSize.width / 2,
                                   visible: { [world] id, p in world.isEdgeVisible(id, at: p) })
    }

    /// Reine Geometrie: side +1 = rechte Fensterseite (springt nach rechts), −1 = linke.
    /// Die Zielseite muss in Höhe `footY` (mit Rand `margin`) Halt bieten.
    static func wallJumpTarget(from x: CGFloat, side: Int, footY: CGFloat, selfID: CGWindowID,
                               windows: [CGWindowID: NSRect], margin: CGFloat,
                               visible: (CGWindowID, CGPoint) -> Bool = { _, _ in true }) -> (id: CGWindowID, gap: CGFloat)? {
        windows
            .filter { $0.key != selfID && footY > $0.value.minY + margin && footY < $0.value.maxY - margin }
            .compactMap { id, f -> (id: CGWindowID, gap: CGFloat)? in
                let gap = side > 0 ? f.minX - x : x - f.maxX
                let edge = CGPoint(x: side > 0 ? f.minX : f.maxX, y: footY)
                return wallJumpGap.contains(gap) && visible(id, edge) ? (id, gap) : nil
            }
            .min { $0.gap < $1.gap }
    }

    /// Von der Wand abstoßen und quer über die Lücke springen; die Magnetschuhe greifen drüben
    /// wieder (siehe Haften im Flug in `stepPhysics`).
    /// Noch ausstehende Sprünge der laufenden Serie und wie viele schon gesprungen wurden.
    private var wallJumpsLeft = 0
    private var wallJumpIndex = 0

    /// Serie von 1–3 Wandsprüngen hin und her; jeder landet etwas höher als der vorige.
    @discardableResult
    private func startWallJumps() -> Bool {
        wallJumpsLeft = Int.random(in: 1...3)
        wallJumpIndex = 0
        return continueWallJumps()
    }

    /// Nächsten Sprung der Serie starten (nach dem Andocken an der Gegenseite).
    @discardableResult
    private func continueWallJumps() -> Bool {
        let rise = 16 + 22 * CGFloat(wallJumpIndex)
        guard wallJumpsLeft > 0, isOnWall, let target = wallJumpTarget(rise: rise) else {
            wallJumpsLeft = 0
            return false
        }
        wallJumpsLeft -= 1
        wallJumpIndex += 1
        jumpAcross(gap: target.gap, rise: rise)
        return true
    }

    private func jumpAcross(gap: CGFloat, rise: CGFloat) {
        guard case .wall(_, let side) = surface else { return }
        say(.hop)
        trace("springt über \(Int(gap)) pt zum nächsten Fenster, \(Int(rise)) pt höher")
        // Gut sichtbarer Bogen: 0,3–0,6 s Flug (je nach Lücke), drüben `rise` pt höher ankommen.
        let t = 0.3 + 0.3 * Double((gap - Self.wallJumpGap.lowerBound) / (Self.wallJumpGap.upperBound - Self.wallJumpGap.lowerBound))
        let distance = max(gap - spriteSize.height, 4) // Körper ragt eine Sprite-Höhe von der Wand ab
        startFalling(vx: CGFloat(side) * distance / CGFloat(t))
        velocity.dy = CGFloat((Double(rise) + Double(gravity) / 2 * t * t) / t)
    }

    private func stickToWall(id: CGWindowID, side: Int, y: CGFloat) {
        yankedFall = false // mit den Magnetschuhen gerettet
        enterWall(id: id, side: side, y: y, goingDown: Bool.random())
        velocity = .zero
        say(.wallPock) // "klonk"
        dockEffect()
        state = .landing(remaining: 0.2)
    }

    // MARK: - Magnetschuhe: Anziehen, Andocken, Abdocken

    /// Effekt-Layer des Clawds selbst (Magnetwellen, Funken); erst bei Bedarf angelegt.
    private lazy var fx = EffectLayers(stage: stage)
    /// Fensterkante in Reichweite, während Clawd gezogen wird.
    private var magnet: (id: CGWindowID, side: Int, distance: CGFloat)?
    /// Wie nah (pt) eine Kante sein muss, damit die Schuhe sie anziehen.
    static let magnetReach: CGFloat = 40

    private func updateMagnet() {
        guard magneticShoes, isDragging else { magnet = nil; return }
        let body = NSRect(x: pos.x, y: pos.y, width: spriteSize.width, height: spriteSize.height)
        magnet = Self.magnetTarget(body: body, windows: world.wallFrames, reach: Self.magnetReach,
                                   margin: spriteSize.width / 2,
                                   visible: { [world] id, p in world.isEdgeVisible(id, at: p) })
    }

    /// Reine Geometrie: nächste sichtbare Fensterkante neben dem Körper (Abstand −12…reach pt),
    /// auf deren Höhe Clawd Halt fände. side −1 = linke Fensterseite, +1 = rechte.
    static func magnetTarget(body: NSRect, windows: [CGWindowID: NSRect], reach: CGFloat, margin: CGFloat,
                             visible: (CGWindowID, CGPoint) -> Bool = { _, _ in true })
        -> (id: CGWindowID, side: Int, distance: CGFloat)? {
        let cy = body.midY
        var best: (id: CGWindowID, side: Int, distance: CGFloat)?
        for (id, f) in windows where cy > f.minY + margin && cy < f.maxY - margin {
            let candidates: [(side: Int, distance: CGFloat, edge: CGFloat)] = [
                body.midX < f.minX ? (-1, f.minX - body.maxX, f.minX) : nil,
                body.midX > f.maxX ? (1, body.minX - f.maxX, f.maxX) : nil,
            ].compactMap { $0 }
            for c in candidates where c.distance >= -12 && c.distance <= reach && visible(id, CGPoint(x: c.edge, y: cy)) {
                if best == nil || c.distance < best!.distance { best = (id, c.side, c.distance) }
            }
        }
        return best
    }

    /// Magnetwellen laufen von den Schuhen zur Kante – mehr, je näher sie ist.
    private func drawMagnetWaves(now: CFTimeInterval) {
        guard let m = magnet, let f = world.wallFrames[m.id] else { hideMagnetWaves(); return }
        let edgeX = m.side < 0 ? f.minX : f.maxX
        let from = m.side < 0 ? pos.x + spriteSize.width - 2 * pixel : pos.x + 2 * pixel
        let scale = pixel * 0.6
        let arcWidth = CGFloat(ClawdSprite.magnetArc[0].count) * scale
        let count = min(max(1 + Int((Self.magnetReach - m.distance) / 15), 1), 3)
        for i in 0..<3 {
            let key = "magnet\(i)"
            guard i < count else { fx.hide(key); continue }
            let progress = CGFloat((now * 2.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1))
            let x = from + (edgeX - from) * progress - (m.side < 0 ? 0 : arcWidth)
            fx.show(key, ClawdSprite.magnetArc, origin: CGPoint(x: x, y: pos.y + pixel), scale: scale,
                    opacity: Float(1 - progress * 0.6), mirrored: m.side > 0)
        }
    }

    private func hideMagnetWaves() {
        for i in 0..<3 { fx.hide("magnet\(i)") }
    }

    /// Andocken: kurzer Funkenregen an der Stelle, an der die Schuhe greifen.
    private func dockEffect() {
        let scale = pixel * 0.6
        for (i, dy) in [CGFloat(-3), 3].enumerated() {
            let key = "dock\(i)"
            let w = CGFloat(ClawdSprite.sparkleGlyph[0].count) * scale
            fx.show(key, ClawdSprite.sparkleGlyph, origin: CGPoint(x: pos.x - w / 2, y: pos.y + dy * pixel), scale: scale)
            if let layer = fx.detach(key) { stage?.leave(layer, lifetime: 0.35, fade: 0.3) }
        }
    }

    /// Abdocken: ein kleiner Ring bleibt kurz an der Kante zurück.
    private func undockEffect(sound: Bool) {
        let scale = pixel * 0.6
        let w = CGFloat(ClawdSprite.undockPuff[0].count) * scale
        fx.show("undock", ClawdSprite.undockPuff, origin: CGPoint(x: pos.x - w / 2, y: pos.y - w / 2), scale: scale)
        if let layer = fx.detach("undock") { stage?.leave(layer, lifetime: 0.4, fade: 0.35) }
        if sound { say(.pickup) }
    }

    /// Oben um die Ecke zurück auf die Fensteroberkante.
    private func leaveWallToTop(_ g: WallGeometry) -> Bool {
        let w = spriteSize.width
        let cx = g.side < 0 ? g.frame.minX + w / 2 + 1 : g.frame.maxX - w / 2 - 1
        let kind = Platform.Kind.window(g.id)
        guard let p = world.platform(kind, near: cx), p.contains(x: cx), abs(p.y - g.frame.maxY) < 2 else { return false }
        surface = kind
        pos = CGPoint(x: cx - w / 2, y: p.y)
        direction = g.side < 0 ? 1 : -1
        climbingSince = nil
        return true
    }

    private func stepWall(dt: TimeInterval, now: CFTimeInterval) {
        guard let g = wall else { startFalling(vx: 0); return }
        if isBeingShaken(g.frame.origin, now: now) {
            // Abgeschüttelt! Weg vom Fenster, hinfallen.
            knockedOut = true
            shake.reset()
            startFalling(vx: CGFloat(g.side) * 160)
            velocity.dy = 220
            say(oneOf: [.eep, .weehEeh])
            return
        }
        pos.x = g.x // fährt mit, wenn das Fenster verschoben wird
        pos.y = min(max(pos.y, g.minY), g.maxY)
        // Fenster bis an den Bildschirmrand gezogen (z. B. maximiert)? Dann ist neben der Kante kein
        // Platz mehr für den Körper – loslassen und herunterfallen.
        guard Self.wallHasRoom(x: g.x, side: g.side, depth: spriteSize.height, y: pos.y,
                               screens: world.screens.map(\.frame)) else {
            trace("kein Platz mehr neben der Fensterkante")
            magnetPauseUntil = now + 1.2 // erst mal richtig herunterfallen, nicht gleich wieder andocken
            startFalling(vx: CGFloat(-g.side) * 60)
            return
        }
        // Ein anderes Fenster hat sich davorgeschoben? Dann hält nichts mehr – herunterfallen.
        guard world.isEdgeVisible(g.id, at: CGPoint(x: g.x, y: pos.y)) else {
            startFalling(vx: CGFloat(g.side) * 60)
            return
        }
        checkCursor(now: now)
        switch state {
        case .walking(let remaining):
            let step = speed * CGFloat(dt)
            // Nur auf sichtbaren Teilen der Kante laufen: vor einem verdeckten Stück umdrehen.
            let lead = pos.y + wallDir * (step + spriteSize.width / 2)
            if !world.isEdgeVisible(g.id, at: CGPoint(x: g.x, y: lead)) {
                wallDir = -wallDir
            } else {
                pos.y += wallDir * step
            }
            distanceWalked += step
            if pos.y >= g.maxY, wallDir > 0 {
                if leaveWallToTop(g) { return }
                pos.y = g.maxY
                wallDir = -1
            } else if pos.y <= g.minY, wallDir < 0 {
                pos.y = g.minY
                wallDir = 1
            }
            let r = remaining - dt
            state = r <= 0 ? .idle(remaining: .random(in: 1...3) / activity) : .walking(remaining: r)
        case .idle(let r): countdown(r, dt) { .idle(remaining: $0) }
        case .looking(let r): countdown(r, dt) { .looking(remaining: $0) }
        case .waving(let r): countdown(r, dt) { .waving(remaining: $0) }
        default: state = .idle(remaining: 1)
        }
        // Blickrichtung im (gedrehten) Sprite: an der linken Kante heißt "nach rechts" = hoch.
        direction = (g.side < 0) == (wallDir > 0) ? 1 : -1
    }

    // MARK: - Begegnungen (Schnittstelle für Encounter)

    /// Laufende Begegnung, die diesen Clawd gerade steuert.
    var encounter: Encounter?
    private var nextEncounterAllowed = CACurrentMediaTime() + .random(in: 10...30)

    var surfaceKind: Platform.Kind? { surface }
    var center: CGFloat { centerX }
    var groundY: CGFloat { pos.y }
    var px: CGFloat { pixel }
    var walkSpeed: CGFloat { speed }
    var facing: CGFloat { direction }
    var isChatty: Bool { talkativeness > 0 }
    var inEncounterState: Bool {
        if case .encounter = state { return true }
        return false
    }

    /// Erlaubter Bereich für die Mitte auf der aktuellen Fläche.
    var centerRange: ClosedRange<CGFloat>? {
        guard let kind = surface, let p = world.platform(kind, near: centerX) else { return nil }
        let half = spriteSize.width / 2
        return (p.minX + half)...max(p.minX + half, p.maxX - half)
    }

    func isAvailableForEncounter(now: CFTimeInterval) -> Bool {
        guard encounter == nil, now >= nextEncounterAllowed, now >= calmUntil, !activityPending,
              let kind = surface, !isHomingFloor(kind), !isOnWall else { return false }
        switch state {
        case .walking, .idle, .looking, .sitting: return true
        default: return false
        }
    }

    /// Wurde gerade vom Nutzer losgelassen (bis zur nächsten Landung).
    private var droppedByUser = false

    /// Kann ein anderer Clawd auf diesen fallen und eine Begegnung starten? (Unterbricht fast alles.)
    var canBeLandedOn: Bool {
        guard encounter == nil, let kind = surface, !isHomingFloor(kind), !isOnWall else { return false }
        return isGroundedState
    }

    var spriteWidth: CGFloat { spriteSize.width }

    /// Entwickler-Hilfe: Begegnungen sofort erlauben.
    /// Sofort für Begegnungen bereit – auch ohne die ruhige Phase nach dem Start abzuwarten.
    func allowEncountersNow() {
        nextEncounterAllowed = 0
        calmUntil = 0
    }

    /// Kurz nicht für Begegnungen in Frage kommen (z. B. wenn der Zufall "nein" sagte).
    func snoozeEncounters(for seconds: TimeInterval) {
        nextEncounterAllowed = max(nextEncounterAllowed, CACurrentMediaTime() + seconds)
    }

    func beginEncounter(_ e: Encounter) {
        encounter = e
        beginEvent(audible: e.audible) // beide Clawds teilen sich die Entscheidung
        walkingOff = false
        state = .encounter
    }

    func finishEncounter(walkAway: Bool) {
        encounter = nil
        nextEncounterAllowed = CACurrentMediaTime() + .random(in: 40...90)
        guard inEncounterState else { return }
        state = walkAway ? .walking(remaining: .random(in: 2...5)) : .idle(remaining: .random(in: 0.6...1.5))
    }

    func face(_ dir: CGFloat) { direction = dir < 0 ? -1 : 1 }

    func moveCenter(to x: CGFloat) {
        var x = x
        if let r = centerRange { x = min(max(x, r.lowerBound), r.upperBound) }
        pos.x = x - spriteSize.width / 2
    }

    /// Einen Schritt Richtung Mitte x gehen (Begegnungen, Arbeiten).
    /// - Returns: ob Clawd angekommen ist und welche Strecke er dabei gegangen ist.
    func step(toward x: CGFloat, speed factor: CGFloat, dt: TimeInterval) -> (arrived: Bool, distance: CGFloat) {
        // Ziele jenseits der Fläche (z. B. der Papierkorb ganz am Dock-Rand) gelten am Rand als erreicht –
        // sonst liefe Clawd endlos gegen die Kante.
        let x = centerRange.map { min(max(x, $0.lowerBound), $0.upperBound) } ?? x
        let step = speed * factor * CGFloat(dt)
        let dx = x - center
        if abs(dx) <= step {
            moveCenter(to: x)
            return (true, 0)
        }
        face(dx)
        moveCenter(to: center + (dx < 0 ? -step : step))
        return (false, step)
    }

    // MARK: - Laute

    /// Darf das laufende Ereignis (Fall, Emote, Arbeit, Begegnung, Schlaf …) Laute machen?
    /// Wird einmal pro Ereignis ausgewürfelt: Still nie, Wortkarg zu 40 %, ab Normal immer.
    /// So bleiben zusammenhängende Laute (z. B. "ha… ha… TSCHIII!") vollständig oder ganz stumm.
    private(set) var eventAudible = true

    /// Wahrscheinlichkeit, dass ein Ereignis hörbar ist: Plappermaul (> 1) zählt wie Normal.
    static func eventProbability(talkativeness: Double) -> Double { min(max(talkativeness, 0), 1) }

    /// Neues Ereignis beginnt: hörbar oder nicht neu entscheiden.
    func beginEvent(audible: Bool? = nil) {
        eventAudible = audible ?? rollEventAudible()
    }

    func rollEventAudible() -> Bool {
        Double.random(in: 0..<1) < Self.eventProbability(talkativeness: talkativeness)
    }

    /// Laut des laufenden Ereignisses – nur wenn es hörbar ist. Spontanes Plappern läuft
    /// stattdessen über `chatty(_:)` und wird dort mit der vollen Gesprächigkeit skaliert.
    /// Einer von mehreren passenden Lauten, zufällig gewählt (siehe `Voice.Sound.startled` usw.).
    func say(oneOf sounds: [Voice.Sound]) {
        if let sound = sounds.randomElement() { say(sound) }
    }

    func say(_ sound: Voice.Sound) {
        trace("laut: \(sound)" + (eventAudible ? "" : " (stumm)"))
        guard eventAudible else { return }
        voice.play(sound)
    }

    // MARK: - In Deckung (Vollbild)

    /// Seit wann der Bildschirm wieder frei ist; nil = Vollbild läuft noch.
    private var shelterReleased: CFTimeInterval?
    /// Vollbild begann, während Clawd nicht am Boden war (z. B. vom Fenster gefallen, das ins Vollbild
    /// ging) – dann holt er das Verstecken nach der nächsten Landung nach.
    private var coverMissed = false

    /// Eine App geht auf diesem Bildschirm ins Vollbild: stehen bleiben, ducken, Arme über den Kopf.
    /// Laufende Arbeiten und Begegnungen werden abgebrochen. In der Luft oder in der Hand geht das nicht.
    func takeCover() {
        guard isGroundedState else {
            coverMissed = true
            return
        }
        coverMissed = false
        encounter?.abort()
        job?.cleanup()
        job = nil
        wallJumpsLeft = 0
        shelterReleased = nil
        state = .sheltering
        placeNow()
    }

    /// Vollbild beendet: erst regungslos, dann umschauen, Arme runter – und weiterlaufen.
    func leaveCover(now: CFTimeInterval) {
        guard case .sheltering = state, shelterReleased == nil else { return }
        shelterReleased = now
        lastTick = now
    }

    private func stepShelter(now: CFTimeInterval) {
        // Fenster unter ihm weggezogen? Dann fällt er trotzdem.
        if !isOnWall, let kind = surface {
            guard let p = world.platform(kind, near: centerX), p.y >= pos.y - 1 else {
                shelterReleased = nil
                startFalling(vx: 0)
                return
            }
            pos.y = p.y
        }
        guard let released = shelterReleased, now - released >= ClawdSprite.coverDuration else { return }
        shelterReleased = nil
        state = .walking(remaining: .random(in: 2...5)) // die Luft ist rein
    }

    // MARK: - Arbeiten (Schnittstelle für Job)

    var job: Job?
    /// Die letzten drei Jobs – werden bei der nächsten Auswahl ausgelassen.
    private var recentJobs: [String] = []

    func startJob(_ j: Job) {
        // Läuft schon eine Arbeit (z. B. Demo-Menü mitten im Job), deren Effekte erst aufräumen.
        job?.cleanup()
        beginEvent()
        job = j
        walkingOff = false
        state = .job
    }

    func finishJob(walkAway: Bool) {
        job = nil
        guard case .job = state else { return }
        state = walkAway ? .walking(remaining: .random(in: 2...5)) : .idle(remaining: .random(in: 0.6...1.4))
    }

    /// Pose einer Begegnung oder Arbeit anzeigen.
    func applyPose(_ p: Encounter.Pose, blinking: Bool = false) {
        let sprite = blinking ? p.blinkSprite ?? p.sprite : p.sprite
        node.sprite = p.sporty ? ClawdSprite.sporty(sprite) : sprite
        node.dustPile = p.dustPile
        node.sportProp = p.prop
        node.particles = p.particles
        node.liftPixels = p.lift
        node.showBubble = p.bubble
        node.hat = p.hat
        node.showLaptop = p.laptop
        node.showHeadphones = p.headphones
    }

    private func place() {
        if case .airborne = state, velocity.dx != 0 {
            direction = velocity.dx < 0 ? -1 : 1
        }
        node.facingLeft = direction < 0
        if case .wall(_, let side) = surface {
            // Füße an der Fensterkante, Körper zeigt vom Fenster weg.
            stage?.placeRotated(node, pivot: pos,
                                pivotInLayer: CGPoint(x: (CGFloat(ClawdNode.marginX) + 7) * pixel, y: 0),
                                angle: side < 0 ? .pi / 2 : -.pi / 2)
            return
        }
        let origin = CGPoint(x: (pos.x - CGFloat(ClawdNode.marginX) * pixel).rounded(), y: pos.y.rounded())
        stage?.place(node, origin: origin)
    }
}
