import AppKit

/// Die Bühne: ein durchsichtiges Overlay-Fenster pro Bildschirm, in dem alle Clawds als
/// Core-Animation-Layer leben. Statt dutzender Fensterbewegungen pro Sekunde werden nur
/// Layer-Positionen geändert.
///
/// Klicks: Das Overlay lässt Mausereignisse normalerweise durch (`ignoresMouseEvents`).
/// Steht der Mauszeiger über einem Clawd, wird das Overlay dieses Bildschirms kurz
/// klickbar, damit man Clawd packen kann.
final class Stage {
    private final class Overlay {
        let window: NSWindow
        let root: CALayer
        /// Bereich in globalen Cocoa-Koordinaten, den `root` abdeckt.
        var frame: NSRect

        init(screen: NSScreen, stage: Stage) {
            frame = screen.frame
            let window = OverlayWindow(frame: frame)
            let view = StageView(frame: NSRect(origin: .zero, size: frame.size))
            view.stage = stage
            root = view.rootLayer
            window.contentView = view
            window.orderFrontRegardless()
            self.window = window
        }

        /// Fremdes Fenster (der Spielplatz) als Zeichenfläche.
        init(window: NSWindow, root: CALayer, frame: NSRect) {
            self.window = window
            self.root = root
            self.frame = frame
        }

        func close() {
            window.orderOut(nil)
            window.close()
        }
    }

    private var overlays: [Overlay] = []
    /// Solange der Spielplatz offen ist, wird nur dort gezeichnet.
    private var playgroundOverlay: Overlay?
    /// Wird zu Beginn jedes Takts aufgerufen (der Spielplatz prüft dort, ob sein Fenster bewegt wurde).
    var beforeTick: (() -> Void)?
    /// Liefert die aktuelle Querneigung des MacBooks in g (siehe `TiltSensor`).
    var tiltSource: (() -> Double)?
    /// Reihenfolge = Zeichenreihenfolge; der letzte liegt oben.
    private(set) var controllers: [PetController] = []
    private var dragTarget: PetController?
    private var encounters: [Encounter] = []
    private var lastEncounterCheck: CFTimeInterval = 0
    /// Entwickler-Hilfe: nur diese Begegnung auswählen (und loggen).
    var forcedEncounter: Encounter.Kind?

    /// Spuren, die nach einer Arbeit liegen bleiben und langsam verblassen.
    private var leftovers: [(layer: CALayer, until: CFTimeInterval, fade: TimeInterval)] = []
    private var dragOverlay: Overlay?
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?

    init() {
        rebuildOverlays()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildOverlays() }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.safeTick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Clawds

    func add(_ controller: PetController) {
        controllers.append(controller)
        controller.stage = self
        controller.placeNow()
    }

    func remove(_ controller: PetController) {
        for e in encounters where e.a === controller || e.b === controller { e.abort() }
        encounters.removeAll { $0.finished }
        controllers.removeAll { $0 === controller }
        if dragTarget === controller { dragTarget = nil }
        controller.node.layer.removeFromSuperlayer()
    }

    /// Setzt einen Clawd an eine globale Position (Cocoa) und hängt ihn ins passende Overlay.
    func place(_ node: ClawdNode, origin: CGPoint) {
        // Von der Wand zurück: Drehung aufheben.
        if node.layer.anchorPoint != .zero || !CATransform3DIsIdentity(node.layer.transform) {
            node.layer.transform = CATransform3DIdentity
            node.layer.anchorPoint = .zero
        }
        place(layer: node.layer, origin: origin)
    }

    /// Clawd gedreht an einer Wand: `pivotInLayer` (Fußpunkt im Layer) landet auf `pivot` (global).
    func placeRotated(_ node: ClawdNode, pivot: CGPoint, pivotInLayer: CGPoint, angle: CGFloat) {
        guard let overlay = overlay(for: pivot) else { return }
        let layer = node.layer
        if layer.superlayer !== overlay.root {
            layer.removeFromSuperlayer()
            overlay.root.addSublayer(layer)
        }
        let size = layer.bounds.size
        layer.anchorPoint = CGPoint(x: pivotInLayer.x / size.width, y: pivotInLayer.y / size.height)
        layer.position = CGPoint(x: (pivot.x - overlay.frame.minX).rounded(), y: (pivot.y - overlay.frame.minY).rounded())
        layer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
    }

    private func overlay(for point: CGPoint) -> Overlay? {
        if let playgroundOverlay { return playgroundOverlay }
        return overlays.first(where: { $0.frame.contains(point) })
            ?? overlays.min(by: { distance(point, $0.frame) < distance(point, $1.frame) })
    }

    /// Beliebigen Layer (anchorPoint 0,0) global platzieren, z. B. Clawds Tennisball.
    func place(layer: CALayer, origin: CGPoint) {
        let size = layer.bounds.size
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        guard let overlay = overlay(for: center) else { return }

        if layer.superlayer !== overlay.root {
            layer.removeFromSuperlayer()
            overlay.root.addSublayer(layer)
        }
        let local = CGPoint(x: origin.x - overlay.frame.minX, y: origin.y - overlay.frame.minY)
        if layer.position != local { layer.position = local }
    }

    // MARK: - Takt

    /// Offene `CATransaction` aus `tick` – nach einer Exception muss sie trotzdem abgeschlossen werden,
    /// sonst kämen keine Änderungen mehr auf den Bildschirm.
    private var transactionOpen = false

    /// Takt mit Sicherheitsnetz: Eine Objective-C-Exception irgendwo darin würde den Timer für immer
    /// anhalten (Clawd friert ein). Sie wird abgefangen und protokolliert; der nächste Takt läuft normal.
    private func safeTick() {
        if !Safely.run("Takt", tick), transactionOpen {
            CATransaction.commit()
            transactionOpen = false
        }
    }

    private func tick() {
        beforeTick?()
        let now = CACurrentMediaTime()
        let tilt = tiltSource?() ?? 0
        for controller in controllers { controller.tilt = tilt }
        if !pausedScreens.isEmpty || !pausedControllers.isEmpty { updateCover(now: now) }
        CATransaction.begin()
        transactionOpen = true
        CATransaction.setDisableActions(true)
        // Begegnungen zuerst: sie bewegen ihre beiden Clawds, deren Tick zeichnet dann.
        for e in encounters where !isPaused(e.a) && !isPaused(e.b) { e.step(now: now) }
        encounters.removeAll { $0.finished }
        for controller in controllers where !isPaused(controller) { controller.tick(now: now) }
        CATransaction.commit()
        transactionOpen = false
        updateLeftovers(now: now)
        if now - lastEncounterCheck > 0.5 {
            lastEncounterCheck = now
            detectEncounters(now: now)
        }
        updateMouseInteractivity()
    }

    /// Overlay nur dort klickbar machen, wo der Mauszeiger gerade über einem Clawd ist.
    private func updateMouseInteractivity() {
        let mouse = NSEvent.mouseLocation
        // Im Spielplatz bekommt sein eigenes Fenster die Klicks; die Overlays bleiben durchlässig.
        let overClawd = playgroundOverlay == nil && controllers.contains { $0.hitTest(mouse) }
        for overlay in overlays {
            let visible = overlay.window.alphaValue > 0
            let interactive = visible && (dragOverlay === overlay || (overClawd && overlay.frame.contains(mouse)))
            if overlay.window.ignoresMouseEvents == interactive {
                overlay.window.ignoresMouseEvents = !interactive
            }
        }
    }

    // MARK: - Spuren

    /// Layer bleibt liegen und verblasst in den letzten `fade` Sekunden vor `lifetime`.
    func leave(_ layer: CALayer, lifetime: TimeInterval, fade: TimeInterval = 5) {
        leftovers.append((layer, CACurrentMediaTime() + lifetime, fade))
    }

    private func updateLeftovers(now: CFTimeInterval) {
        guard !leftovers.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in leftovers {
            let remaining = item.until - now
            item.layer.opacity = Float(min(max(remaining / item.fade, 0), 1))
            if remaining <= 0 { item.layer.removeFromSuperlayer() }
        }
        CATransaction.commit()
        leftovers.removeAll { $0.until <= now }
    }

    // MARK: - Begegnungen

    /// Treffen sich zwei freie Clawds auf derselben Fläche, reagieren sie (meistens) aufeinander.
    private func detectEncounters(now: CFTimeInterval) {
        let free = controllers.filter { !isPaused($0) && $0.isAvailableForEncounter(now: now) }
        guard free.count >= 2 else { return }
        for i in 0..<free.count {
            for j in (i + 1)..<free.count {
                let c1 = free[i], c2 = free[j]
                guard c1.encounter == nil, c2.encounter == nil,
                      let kind = c1.surfaceKind, kind == c2.surfaceKind,
                      abs(c1.center - c2.center) < 100,
                      let range = c1.centerRange
                else { continue }
                if forcedEncounter == nil, Double.random(in: 0..<1) >= 0.5 {
                    c1.snoozeEncounters(for: 8)
                    c2.snoozeEncounters(for: 8)
                    continue
                }
                startEncounter(c1, c2, range: range)
            }
        }
    }

    /// Zufällige Begegnung starten (lange nur, wenn die Fläche genug Platz bietet).
    private func startEncounter(_ c1: PetController, _ c2: PetController, range: ClosedRange<CGFloat>) {
        let length = range.upperBound - range.lowerBound
        let possible = Encounter.Kind.randomKinds.filter { k in
            switch k {
            case .ballPass: return length >= 260
            case .presentation, .magicMishap: return length >= 150
            case .tag, .leapfrog: return length >= 220
            default: return true
            }
        }
        let chosen = forcedEncounter.flatMap { possible.contains($0) ? $0 : nil } ?? possible.randomElement()!
        encounters.append(Encounter(kind: chosen, c1, c2, stage: self))
    }

    /// Demo: eine bestimmte Begegnung zwischen zwei Clawds starten (auf derselben Fläche).
    @discardableResult
    func startDemoEncounter(_ kind: Encounter.Kind, _ c1: PetController, _ c2: PetController) -> Bool {
        guard c1.canBeLandedOn, c2.canBeLandedOn, c1.surfaceKind == c2.surfaceKind else { return false }
        encounters.append(Encounter(kind: kind, c1, c2, stage: self,
                                    initiator: kind == .mail ? c1 : nil))
        return true
    }

    /// Für "Post austragen": ein anderer Clawd auf derselben Fläche, der gerade Zeit hat.
    func mailRecipient(for c: PetController) -> PetController? {
        guard let kind = c.surfaceKind else { return nil }
        return controllers
            .filter { $0 !== c && $0.canBeLandedOn && $0.surfaceKind == kind }
            .min { abs($0.center - c.center) < abs($1.center - c.center) }
    }

    /// Brief übergeben (Begegnung, vom Briefträger gestartet).
    func startMail(from courier: PetController, to receiver: PetController) {
        guard receiver.encounter == nil, receiver.canBeLandedOn else { return }
        encounters.append(Encounter(kind: .mail, courier, receiver, stage: self, initiator: courier))
    }

    /// Ein Clawd wurde vom Nutzer fallen gelassen und ist gelandet: Liegt er auf (oder direkt
    /// neben) einem anderen Clawd derselben Fläche, gibt es sofort eine zufällige Begegnung.
    func dropped(_ c: PetController) {
        guard c.encounter == nil, let kind = c.surfaceKind, let range = c.centerRange else { return }
        let reach = c.spriteWidth * 1.2
        let partner = controllers
            .filter { $0 !== c && $0.canBeLandedOn && $0.surfaceKind == kind && abs($0.center - c.center) < reach }
            .min { abs($0.center - c.center) < abs($1.center - c.center) }
        guard let partner else { return }
        DebugLog.log("Abwurf auf anderen Clawd → Begegnung")
        startEncounter(c, partner, range: range)
    }

    // MARK: - Maus (vom StageView)

    fileprivate func mouseDown(at p: CGPoint, in view: StageView) {
        guard let target = controllers.last(where: { $0.hitTest(p) }) else { return }
        // Gepackten Clawd nach vorn holen.
        controllers.removeAll { $0 === target }
        controllers.append(target)
        if let parent = target.node.layer.superlayer {
            target.node.layer.removeFromSuperlayer()
            parent.addSublayer(target.node.layer)
        }
        dragTarget = target
        dragOverlay = overlays.first { $0.window === view.window }
        target.mouseDown(at: p)
    }

    fileprivate func mouseDragged(to p: CGPoint) {
        dragTarget?.mouseDragged(to: p)
    }

    fileprivate func mouseUp(at p: CGPoint) {
        dragTarget?.mouseUp(at: p)
        dragTarget = nil
        dragOverlay = nil
    }

    // MARK: - Pause (Vollbild)

    /// Bildschirme, auf denen eine App im Vollbild läuft: Clawds dort halten an, die Bühne ist ausgeblendet.
    private var pausedScreens: [NSRect] = []

    /// Clawds, die gerade pausieren (und dafür in Deckung gegangen sind).
    private var pausedControllers: [ObjectIdentifier] = []

    func setPausedScreens(_ frames: [NSRect]) {
        pausedScreens = frames
        updateCover(now: CACurrentMediaTime())
        for overlay in overlays {
            overlay.window.alphaValue = frames.contains { $0.intersects(overlay.frame.insetBy(dx: 1, dy: 1)) } ? 0 : 1
        }
    }

    /// Neu pausierte Clawds gehen in Deckung, wieder freie kommen langsam hervor. Läuft auch im Takt,
    /// falls ein Clawd auf einen Vollbild-Bildschirm gerät.
    private func updateCover(now: CFTimeInterval) {
        let paused = controllers.filter(isPaused)
        let ids = paused.map(ObjectIdentifier.init)
        for c in paused where !pausedControllers.contains(ObjectIdentifier(c)) {
            DebugLog.log(String(format: "%.2f ", now) + "Deckung: Clawd bei x \(Int(c.center)) pausiert")
            c.takeCover()
        }
        for c in controllers where !ids.contains(ObjectIdentifier(c)) && pausedControllers.contains(ObjectIdentifier(c)) {
            DebugLog.log(String(format: "%.2f ", now) + "Deckung: Clawd bei x \(Int(c.center)) wieder frei")
            c.leaveCover(now: now)
        }
        pausedControllers = ids
    }

    private func isPaused(_ c: PetController) -> Bool {
        guard !pausedScreens.isEmpty else { return false }
        let p = CGPoint(x: c.center, y: c.groundY + 1)
        return pausedScreens.contains { $0.contains(p) }
    }

    // MARK: - Spielplatz

    /// Ab jetzt alle Layer im Spielplatz-Fenster zeichnen; `frame` = sein Inhalt in globalen Koordinaten.
    func attachPlayground(window: NSWindow, root: CALayer, frame: NSRect) {
        playgroundOverlay = Overlay(window: window, root: root, frame: frame)
        controllers.forEach { $0.placeNow() }
    }

    func updatePlayground(frame: NSRect) {
        playgroundOverlay?.frame = frame
    }

    /// Zurück auf die Bildschirm-Overlays; die Layer werden beim nächsten Platzieren umgehängt.
    func detachPlayground() {
        playgroundOverlay = nil
        dragOverlay = nil
        controllers.forEach { $0.placeNow() }
    }

    // MARK: - Bildschirme

    private func rebuildOverlays() {
        let old = overlays
        overlays = NSScreen.screens.map { Overlay(screen: $0, stage: self) }
        old.forEach { $0.close() }
        dragOverlay = nil
        controllers.forEach { $0.placeNow() } // Layer in die neuen Overlays umhängen
    }

    private func distance(_ p: CGPoint, _ r: NSRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }
}

/// Randloses, durchsichtiges Fenster über einem ganzen Bildschirm.
final class OverlayWindow: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Ohne .fullScreenAuxiliary: in Vollbild-Spaces anderer Apps erscheint die Bühne nicht.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Nicht von AppKit unter die Menüleiste schieben lassen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Inhalt des Overlays: hält die Layer und leitet Mausereignisse an die Bühne weiter.
final class StageView: NSView {
    weak var stage: Stage?
    let rootLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = rootLayer
        wantsLayer = true // Layer-hosting
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { stage?.mouseDown(at: NSEvent.mouseLocation, in: self) }
    override func mouseDragged(with event: NSEvent) { stage?.mouseDragged(to: NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { stage?.mouseUp(at: NSEvent.mouseLocation) }
}
