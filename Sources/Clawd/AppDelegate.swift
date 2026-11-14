import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controllers: [PetController] = []
    /// Gewünschte Anzahl Clawds in dieser Sitzung (wird nicht gespeichert, Start immer mit 1).
    private var targetCount = 1
    private var stage: Stage!
    private var world: World!
    private var voice: Voice!
    private var uiVoice: Voice.Channel?
    private var statusItem: NSStatusItem?
    private var appearanceObservation: NSKeyValueObservation?
    private var playground: Playground?
    private let mediaWatcher = MediaWatcher()
    private let tiltSensor = TiltSensor()

    func applicationWillTerminate(_ notification: Notification) {
        tiltSensor.stop() // Sensor wieder ausschalten
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockLocator.requestAccessibility(prompt: true)

        applyAppearance()
        // Wechselt macOS zwischen hell und dunkel, zieht Clawd mit.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyAppearance() }
        }
        stage = Stage()
        stage.tiltSource = { [weak self] in self?.tiltSensor.lateral ?? 0 }
        if Settings.reactToTilt { tiltSensor.start() }
        world = World()
        world.includeWindows = Settings.walkOnWindows
        Settings.migrate()
        voice = Voice()
        voice.volume = Float(Settings.volume)
        uiVoice = voice.makeChannel()
        // Video läuft → stumm; App im Vollbild → stumm, Clawds dort pausiert und ausgeblendet.
        mediaWatcher.onChange = { [weak self] state in
            guard let self else { return }
            self.voice.muted = state.videoPlaying || !state.fullscreenScreens.isEmpty
            self.stage.setPausedScreens(state.fullscreenScreens)
            DebugLog.log(String(format: "%.2f ", CACurrentMediaTime()) + "Medien: Video \(state.videoPlaying), Vollbild auf \(state.fullscreenScreens.count) Bildschirm(en)")
        }
        setupStatusItem()

        let options = LaunchOptions()
        DebugLog.enabled = options.isDebugging
        Jobs.weekendOverride = options.weekend
        mediaWatcher.poll()
        if options.record != nil {
            startRecording(options)
            return
        }
        start(options)
        if options.playground {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.openPlayground() }
        }
    }

    /// Clawds landen lassen – normal oder in einem der Entwickler-Abläufe aus den Startargumenten.
    private func start(_ options: LaunchOptions) {
        let x = options.drop?.x ?? 700

        if case .encounter(let kind) = options.scenario {
            stage.forcedEncounter = kind
            for (k, dx) in [0.0, 70.0].enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 0.2) { [weak self] in
                    guard let c = self?.spawn() else { return }
                    c.allowEncountersNow()
                    c.debugDrop(at: CGPoint(x: x + dx, y: 300))
                }
            }
            return
        }

        if let demo = options.demo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.run(demo)
                DebugLog.log("Demo gestartet: \(demo.name), Clawds: \(self.controllers.count)")
            }
        }

        switch options.scenario {
        case .pair:
            guard let first = spawn() else { return }
            first.debugDrop(at: CGPoint(x: x, y: 300))
            first.debugForce = options.force
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.spawn()?.debugDrop(at: CGPoint(x: x + 160, y: 300))
            }
        case .dropTest:
            guard let first = spawn() else { return }
            first.debugDrop(at: CGPoint(x: x, y: 300))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let second = self?.spawn() else { return }
                second.debugDrop(at: CGPoint(x: first.center - second.spriteWidth / 2 + 10, y: 400), asUserDrop: true)
            }
        case .normal, .encounter:
            // Beim Start fällt immer genau ein Clawd vom Himmel; weitere kommen über das Menü.
            guard let c = spawn() else { return }
            if let drop = options.drop { c.debugDrop(at: drop) }
            if let vx = options.throwVX { c.debugThrow(vx: vx) }
            if let force = options.force { c.debugForce = force }
        }
    }

    // MARK: - Clawds

    @discardableResult
    private func spawn() -> PetController? {
        guard controllers.count < Settings.maxClawds else { return nil }
        // Jeder Clawd klingt etwas anders (der erste klingt "normal").
        let controller = makeController(pitch: controllers.isEmpty ? 1 : Double.random(in: 0.82...1.25))
        controllers.append(controller)
        return controller
    }

    private func makeController(pitch: Double) -> PetController {
        let controller = PetController(world: world, voice: voice.makeChannel(pitch: pitch),
                                       pixel: CGFloat(Settings.pixelSize), speed: CGFloat(Settings.speed))
        controller.talkativeness = Settings.talkativeness
        controller.activity = Settings.activity
        controller.magneticShoes = Settings.magneticShoes
        stage.add(controller)
        return controller
    }

    // MARK: - Demo (Option-Taste beim Öffnen des Menüs)

    /// Eintrag im Demo-Menü: Titel-Schlüssel (L10n) und Aktion.
    struct DemoEntry {
        let title: String
        let action: DemoAction
        init(_ title: String, _ action: DemoAction) { self.title = title; self.action = action }
    }

    struct DemoGroup {
        let title: String
        let items: [DemoEntry]
        init(_ title: String, _ items: [DemoEntry]) { self.title = title; self.items = items }
    }

    /// Gruppen des Demo-Menüs (Titel-Schlüssel und Einträge). Jeder Eintrag hat genau einen Platz.
    static let demoGroups: [DemoGroup] = [
        DemoGroup("demo.gestures", [
            DemoEntry("demo.wave", .behavior(.wave)), DemoEntry("demo.look", .behavior(.look)),
            DemoEntry("demo.sit", .behavior(.sit)), DemoEntry("demo.sleep", .behavior(.sleep)),
            DemoEntry("demo.yawn", .behavior(.yawn)), DemoEntry("demo.sneeze", .behavior(.sneeze)),
            DemoEntry("demo.dizzy", .behavior(.dizzy)), DemoEntry("demo.hide", .behavior(.hide)),
            DemoEntry("demo.hopOff", .behavior(.hopOff)), DemoEntry("demo.slide", .behavior(.slide)),
        ]),
        DemoGroup("demo.leisure", [
            DemoEntry("demo.music", .behavior(.music)), DemoEntry("demo.plane", .job(PaperPlaneJob.self)),
            DemoEntry("demo.kite", .job(KiteJob.self)), DemoEntry("demo.tennis", .job(TennisJob.self)),
            DemoEntry("demo.barbell", .behavior(.barbell)), DemoEntry("demo.rope", .behavior(.rope)),
            DemoEntry("demo.wallJump", .behavior(.wallJump)), DemoEntry("demo.archery", .job(ArcheryJob.self)),
            DemoEntry("demo.magic", .job(MagicJob.self)),
            DemoEntry("demo.console", .job(ConsoleGamingJob.self)), DemoEntry("demo.pcgame", .job(PCGamingJob.self)),
        ]),
        DemoGroup("demo.everyday", [
            DemoEntry("demo.eat", .job(EatingJob.self)), DemoEntry("demo.cook", .job(CookingJob.self)),
            DemoEntry("demo.coffee", .job(CoffeeJob.self)),
            DemoEntry("demo.laundry", .job(LaundryJob.self)), DemoEntry("demo.sweep", .job(SweepingJob.self)),
            DemoEntry("demo.windows", .job(WindowCleaningJob.self)), DemoEntry("demo.polish", .job(IconPolishJob.self)),
            DemoEntry("demo.trash", .job(TrashOutJob.self)), DemoEntry("demo.water", .job(WaterPlantJob.self)),
        ]),
        DemoGroup("demo.crafts", [
            DemoEntry("demo.hammer", .job(HammerJob.self)), DemoEntry("demo.paint", .job(PaintJob.self)),
            DemoEntry("demo.box", .job(BoxJob.self)), DemoEntry("demo.screw", .job(ScrewJob.self)),
            DemoEntry("demo.cables", .job(CablesJob.self)),
        ]),
        DemoGroup("demo.code", [
            DemoEntry("demo.coding", .behavior(.coding)), DemoEntry("demo.flow", .job(FlowCodingJob.self)),
            DemoEntry("demo.review", .job(CodeReviewJob.self)), DemoEntry("demo.plan", .job(PlanJob.self)),
            DemoEntry("demo.search", .job(SearchJob.self)), DemoEntry("demo.subagents", .job(SubagentsJob.self)),
            DemoEntry("demo.bug", .job(BugHuntJob.self)), DemoEntry("demo.duck", .job(RubberDuckJob.self)),
            DemoEntry("demo.whiteboard", .job(WhiteboardJob.self)),
            DemoEntry("demo.dashboard", .job(DashboardJob.self)), DemoEntry("demo.prototype", .job(PrototypeJob.self)),
        ]),
        DemoGroup("demo.release", [
            DemoEntry("demo.terminal", .job(TerminalJob.self)), DemoEntry("demo.tests", .job(TestsGreenJob.self)), DemoEntry("demo.deploy", .job(DeployRocketJob.self)),
            DemoEntry("demo.shipit", .job(ShipItJob.self)), DemoEntry("demo.server", .job(ServerJob.self)),
            DemoEntry("demo.fire", .job(FireJob.self)),
            DemoEntry("demo.security", .job(SecurityCheckJob.self)), DemoEntry("demo.migration", .job(DatabaseMigrationJob.self)),
        ]),
        DemoGroup("demo.office", [
            DemoEntry("demo.files", .job(FilesJob.self)), DemoEntry("demo.printer", .job(PrinterJob.self)),
            DemoEntry("demo.postits", .job(PostitJob.self)), DemoEntry("demo.stamp", .job(StampJob.self)),
            DemoEntry("demo.call", .job(CallJob.self)),
        ]),
        DemoGroup("demo.focus", [
            DemoEntry("demo.pomodoro", .job(PomodoroJob.self)), DemoEntry("demo.deadline", .job(DeadlinePanicJob.self)),
            DemoEntry("demo.night", .job(NightShiftJob.self)), DemoEntry("demo.hats", .job(ThinkingHatsJob.self)),
        ]),
        DemoGroup("demo.encounters", [
            DemoEntry("demo.greeting", .encounter(.greeting)), DemoEntry("demo.highFive", .encounter(.highFive)),
            DemoEntry("demo.hug", .encounter(.hug)), DemoEntry("demo.dance", .encounter(.dance)),
            DemoEntry("demo.tag", .encounter(.tag)), DemoEntry("demo.leapfrog", .encounter(.leapfrog)),
            DemoEntry("demo.ballPass", .encounter(.ballPass)), DemoEntry("demo.bump", .encounter(.bump)),
            DemoEntry("demo.mail", .encounter(.mail)),
        ]),
        DemoGroup("demo.team", [
            DemoEntry("demo.presentation", .encounter(.presentation)),
            DemoEntry("demo.pairProgramming", .encounter(.pairProgramming)),
            DemoEntry("demo.tugOfWar", .encounter(.tugOfWar)), DemoEntry("demo.coffeeBreak", .encounter(.coffeeBreak)),
            DemoEntry("demo.rpgNight", .encounter(.rpgNight)),
            DemoEntry("demo.magicMishap", .encounter(.magicMishap)),
        ]),
    ]

    private func makeDemoMenu() -> NSMenu {
        let demo = NSMenu()
        demo.autoenablesItems = false
        let playgroundItem = demo.addItem(withTitle: L10n.t("demo.playground"), action: #selector(togglePlayground),
                                          keyEquivalent: "")
        playgroundItem.target = self
        playgroundItem.state = playground == nil ? .off : .on
        demo.addItem(.separator())
        for group in Self.demoGroups {
            let sub = NSMenu()
            sub.autoenablesItems = false
            for entry in group.items {
                let item = sub.addItem(withTitle: L10n.t(entry.title), action: #selector(runDemo(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.action
            }
            demo.addItem(withTitle: L10n.t(group.title), action: nil, keyEquivalent: "").submenu = sub
        }
        return demo
    }

    @objc private func runDemo(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? DemoAction else { return }
        run(action)
    }

    private func run(_ action: DemoAction) {
        if case .encounter(let kind) = action {
            runDemoEncounter(kind)
        } else {
            controllers.forEach { $0.performDemo(action) }
        }
    }

    /// Ein vorübergehender Demo-Partner für eine Begegnung.
    private struct DemoPartner {
        let partner: PetController
        let host: PetController
        let kind: Encounter.Kind
        var started = false
        var endedAt: CFTimeInterval?
        let created = CACurrentMediaTime()
    }
    private var demoPartners: [DemoPartner] = []
    private var demoTimer: Timer?

    /// Alle Clawds spielen die Begegnung: Nachbarn auf derselben Fläche bilden Paare,
    /// wer übrig bleibt, bekommt einen vorübergehenden Partner, der danach wieder verschwindet.
    private func runDemoEncounter(_ kind: Encounter.Kind) {
        var free = controllers.filter { $0.canBeLandedOn }.sorted { $0.center < $1.center }
        while let c = free.first {
            free.removeFirst()
            if let i = free.firstIndex(where: { $0.surfaceKind == c.surfaceKind && abs($0.center - c.center) < 200 }) {
                let partner = free.remove(at: i)
                stage.startDemoEncounter(kind, c, partner)
            } else if let partner = spawnDemoPartner(next: c) {
                demoPartners.append(DemoPartner(partner: partner, host: c, kind: kind))
                DebugLog.log("Demo-Partner hinzugefügt")
            }
        }
        if !demoPartners.isEmpty, demoTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateDemoPartners() }
            RunLoop.main.add(timer, forMode: .common)
            demoTimer = timer
        }
    }

    private func spawnDemoPartner(next host: PetController) -> PetController? {
        guard let range = host.centerRange else { return nil }
        let partner = makeController(pitch: Double.random(in: 0.82...1.25))
        let offset: CGFloat = 70
        let x = host.center + offset <= range.upperBound ? host.center + offset : host.center - offset
        partner.dropIn(at: CGPoint(x: x, y: host.groundY + 40))
        return partner
    }

    private func updateDemoPartners() {
        let now = CACurrentMediaTime()
        for i in demoPartners.indices {
            var d = demoPartners[i]
            if !d.started {
                // Sobald der Partner gelandet ist: Begegnung starten (der Gastgeber beginnt, z. B. mit der Post).
                if stage.startDemoEncounter(d.kind, d.host, d.partner) {
                    d.started = true
                    DebugLog.log("Demo-Begegnung gestartet: \(d.kind.rawValue)")
                } else if now - d.created > 8 {
                    d.endedAt = now
                }
            } else if d.endedAt == nil, d.partner.encounter == nil {
                d.endedAt = now // Begegnung vorbei – Partner läuft noch kurz los, dann weg
            }
            demoPartners[i] = d
        }
        for d in demoPartners where (d.endedAt.map { now - $0 > 1.2 } ?? false) {
            d.partner.stop()
            DebugLog.log("Demo-Partner entfernt (Bühne: \(stage.controllers.count) Clawds)")
        }
        demoPartners.removeAll { $0.endedAt.map { now - $0 > 1.2 } ?? false }
        if demoPartners.isEmpty {
            demoTimer?.invalidate()
            demoTimer = nil
        }
    }

    private func despawn() {
        guard controllers.count > 1, let last = controllers.popLast() else { return }
        last.stop()
    }

    private func setCount(_ count: Int) {
        let target = min(max(count, 1), Settings.maxClawds)
        targetCount = target
        while controllers.count > target { despawn() }
        let missing = target - controllers.count
        for i in 0..<max(missing, 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.25) { [weak self] in
                guard let self, self.controllers.count < self.targetCount else { return }
                self.spawn()
            }
        }
    }

    // MARK: - Spielplatz

    @objc private func togglePlayground() {
        if let playground {
            playground.close() // windowWillClose räumt auf
        } else {
            openPlayground()
        }
    }

    /// Spielplatz öffnen: Alle Clawds fallen oben hinein und bleiben dort, bis er geschlossen wird.
    // MARK: - Szenen aufnehmen (Startoption --record)

    private var recorder: SceneRecorder?

    /// Ein Clawd fällt in einen eigenen Spielplatz; die Szene wird als GIF gespeichert, danach
    /// beendet sich die App.
    private func startRecording(_ options: LaunchOptions) {
        guard let path = options.record else { return }
        forcedTheme = .light
        applyAppearance()
        voice.volume = 0
        let p = Playground(stage: stage, world: world, size: options.playgroundSize ?? NSSize(width: 600, height: 300))
        p.onClose = { NSApp.terminate(nil) }
        playground = p
        p.refreshTheme()
        let rec = SceneRecorder(playground: p, rect: options.recordRect, scale: options.recordScale,
                                duration: options.recordSeconds, path: path) { NSApp.terminate(nil) }
        recorder = rec
        // Kurz warten, bis Fenster und Welt stehen, dann den Clawd hineinfallen lassen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let c = self.spawn() else { return }
            c.debugForce = options.force
            let drop = p.dropPoint(index: 0, of: 1)
            if case .encounter(let kind) = options.scenario, let partner = self.spawn() {
                // Begegnung: ein zweiter Clawd landet daneben, die Bühne startet die gewünschte Szene.
                self.stage.forcedEncounter = kind
                [c, partner].forEach { $0.allowEncountersNow() }
                c.dropIn(at: CGPoint(x: drop.x - 35, y: drop.y))
                partner.dropIn(at: CGPoint(x: drop.x + 35, y: drop.y))
            } else {
                c.dropIn(at: drop)
            }
            if options.recordFromStart { rec.start() }
            c.onFirstLanding = {
                if !options.recordFromStart { rec.start() }
                for (t, step) in options.script {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) { c.runScript(step) }
                }
            }
        }
    }

    private func openPlayground() {
        let p = Playground(stage: stage, world: world)
        p.onClose = { [weak self] in self?.playgroundClosed() }
        playground = p
        for (i, c) in controllers.enumerated() {
            c.dropIn(at: p.dropPoint(index: i, of: controllers.count))
        }
        DebugLog.log("Spielplatz geöffnet")
    }

    /// Fenster zu: zurück auf den Desktop, alle Clawds fallen von dort, wo sie gerade sind.
    private func playgroundClosed() {
        playground = nil
        stage.detachPlayground()
        world.playground = nil
        controllers.forEach { $0.letFall() }
        DebugLog.log("Spielplatz geschlossen")
    }

    // MARK: - Menü

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = ClawdSprite.trayIcon()
        item.button?.toolTip = "Clawd Desktop Pet"
        let menu = NSMenu()
        menu.autoenablesItems = false // isEnabled wird selbst gesetzt
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Menü bei jedem Öffnen neu aufbauen, damit Häkchen stimmen.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let n = controllers.count
        menu.addItem(withTitle: n == 1 ? L10n.t("count.one") : String(format: L10n.t("count.many"), n), action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        let add = menu.addItem(withTitle: L10n.t("add"), action: #selector(addClawd), keyEquivalent: "n")
        add.target = self
        add.isEnabled = n < Settings.maxClawds
        let remove = menu.addItem(withTitle: L10n.t("remove"), action: #selector(removeClawd), keyEquivalent: "")
        remove.target = self
        remove.isEnabled = n > 1

        addChoiceMenu(to: menu, title: L10n.t("count"), options: (1...Settings.maxClawds).map { "\($0)" },
                      selected: targetCount - 1, action: #selector(setCountItem(_:)))
        let feed = menu.addItem(withTitle: L10n.t("feed"), action: #selector(feedClawds), keyEquivalent: "")
        feed.target = self
        // Mit gedrückter Option-Taste geöffnet: Demo-Menü
        if NSEvent.modifierFlags.contains(.option) {
            menu.addItem(withTitle: L10n.t("demo"), action: nil, keyEquivalent: "").submenu = makeDemoMenu()
        }
        menu.addItem(.separator())

        addChoiceMenu(to: menu, title: L10n.t("size"), options: Settings.sizes.map { L10n.t($0.title) },
                      selected: Settings.sizes.firstIndex { $0.pixel == Settings.pixelSize },
                      action: #selector(setSize(_:)))
        addChoiceMenu(to: menu, title: L10n.t("speed"), options: Settings.speeds.map { L10n.t($0.title) },
                      selected: Settings.speeds.firstIndex { $0.speed == Settings.speed },
                      action: #selector(setSpeed(_:)))
        addChoiceMenu(to: menu, title: L10n.t("activity"), options: Settings.activityLevels.map { L10n.t($0.title) },
                      selected: Settings.activityLevels.firstIndex { $0.factor == Settings.activity },
                      action: #selector(setActivity(_:)))
        addChoiceMenu(to: menu, title: L10n.t("talk"), options: Settings.talkLevels.map { L10n.t($0.title) },
                      selected: Settings.talkLevels.firstIndex { $0.factor == Settings.talkativeness },
                      action: #selector(setTalkativeness(_:)))
        addChoiceMenu(to: menu, title: L10n.t("appearance"), options: Settings.appearances.map { L10n.t($0.title) },
                      selected: Settings.appearances.firstIndex { $0.value == Settings.appearance },
                      action: #selector(setAppearance(_:)))
        // Immer zweisprachig beschriftet, damit man auch in der "falschen" Sprache hinfindet.
        addChoiceMenu(to: menu, title: L10n.language == "de" ? "Sprache / Language" : "Language / Sprache",
                      options: Settings.languages.map { L10n.t($0.title) },
                      selected: Settings.languages.firstIndex { $0.value == Settings.language },
                      action: #selector(setLanguage(_:)))

        // Läuft ein Video (auch im Hintergrund), ist Clawd stumm – darauf über dem Regler hinweisen.
        mediaWatcher.poll()
        if mediaWatcher.state.videoPlaying {
            let hint = NSMenuItem(title: L10n.t("mutedForVideo"), action: nil, keyEquivalent: "")
            hint.image = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: nil)
            hint.isEnabled = false
            menu.addItem(hint)
        }
        let volumeItem = NSMenuItem()
        volumeItem.view = makeVolumeView()
        menu.addItem(volumeItem)
        addToggle(to: menu, L10n.t("windows"), on: Settings.walkOnWindows, #selector(toggleWindows))
        addToggle(to: menu, L10n.t("magnetic"), on: Settings.magneticShoes, #selector(toggleMagneticShoes))
        if tiltSensor.isAvailable {
            addToggle(to: menu, L10n.t("tilt"), on: Settings.reactToTilt, #selector(toggleTilt))
        }
        addToggle(to: menu, L10n.t("login"), on: SMAppService.mainApp.status == .enabled,
                  #selector(toggleLoginItem))

        menu.addItem(.separator())
        let ax = menu.addItem(withTitle: L10n.t("accessibility"),
                              action: #selector(openAccessibilitySettings), keyEquivalent: "")
        ax.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// Untermenü mit einer Auswahl; Häkchen beim gewählten Eintrag, `tag` = Index in `options`.
    private func addChoiceMenu(to menu: NSMenu, title: String, options: [String], selected: Int?, action: Selector) {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for (index, option) in options.enumerated() {
            let item = submenu.addItem(withTitle: option, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == selected ? .on : .off
        }
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
    }

    private func addToggle(to menu: NSMenu, _ title: String, on: Bool, _ action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
    }

    @objc private func feedClawds() { controllers.forEach { $0.feed() } }

    @objc private func addClawd() { setCount(targetCount + 1) }
    @objc private func removeClawd() { setCount(targetCount - 1) }
    @objc private func setCountItem(_ sender: NSMenuItem) { setCount(sender.tag + 1) }

    @objc private func setSize(_ sender: NSMenuItem) {
        let pixel = Settings.sizes[sender.tag].pixel
        Settings.pixelSize = pixel
        controllers.forEach { $0.setPixel(CGFloat(pixel)) }
    }

    @objc private func setSpeed(_ sender: NSMenuItem) {
        let speed = Settings.speeds[sender.tag].speed
        Settings.speed = speed
        controllers.forEach { $0.baseSpeed = CGFloat(speed) }
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        Settings.language = Settings.languages[sender.tag].value
    }

    @objc private func setAppearance(_ sender: NSMenuItem) {
        Settings.appearance = Settings.appearances[sender.tag].value
        applyAppearance()
    }

    /// Hell/Dunkel bestimmen und – falls geändert – an alle Clawds weitergeben.
    /// Bei Aufnahmen immer hell (passt zum hellen GitHub-Hintergrund).
    private var forcedTheme: ClawdSprite.Theme?

    private func applyAppearance() {
        let theme: ClawdSprite.Theme
        switch forcedTheme.map(\.rawValue) ?? Settings.appearance {
        case "light": theme = .light
        case "dark": theme = .dark
        default:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            theme = isDark ? .dark : .light
        }
        guard theme != ClawdSprite.theme || controllers.isEmpty else { return }
        ClawdSprite.theme = theme
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        controllers.forEach { $0.node.refreshTheme() }
        CATransaction.commit()
        playground?.refreshTheme()
    }

    @objc private func setActivity(_ sender: NSMenuItem) {
        let level = Settings.activityLevels[sender.tag]
        Settings.activity = level.factor
        controllers.forEach { $0.activity = level.factor }
    }

    @objc private func setTalkativeness(_ sender: NSMenuItem) {
        let level = Settings.talkLevels[sender.tag]
        Settings.talkativeness = level.factor
        controllers.forEach { $0.talkativeness = level.factor }
        if level.factor > 0 { controllers.first?.voice.play(.murmur) } // kleine Kostprobe
    }

    /// Menüzeile mit Lautsprecher-Symbolen und Schieberegler.
    private func makeVolumeView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))

        func icon(_ name: String, x: CGFloat) -> NSImageView {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
            let iv = NSImageView(frame: NSRect(x: x, y: 6, width: 16, height: 16))
            iv.image = image
            iv.contentTintColor = .secondaryLabelColor
            return iv
        }
        view.addSubview(icon("speaker.fill", x: 20))
        view.addSubview(icon("speaker.wave.3.fill", x: 210))

        let slider = NSSlider(value: Settings.volume, minValue: 0, maxValue: 1,
                              target: self, action: #selector(volumeChanged(_:)))
        slider.frame = NSRect(x: 42, y: 4, width: 162, height: 20)
        slider.isContinuous = true
        slider.toolTip = L10n.t("volume")
        view.addSubview(slider)
        return view
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        Settings.volume = sender.doubleValue
        voice.volume = Float(sender.doubleValue)
        // Beim Loslassen eine kleine Hörprobe.
        if NSApp.currentEvent?.type == .leftMouseUp { uiVoice?.play(.happy) }
    }

    @objc private func toggleTilt() {
        Settings.reactToTilt.toggle()
        if Settings.reactToTilt { tiltSensor.start() } else { tiltSensor.stop() }
    }

    @objc private func toggleMagneticShoes() {
        Settings.magneticShoes.toggle()
        controllers.forEach { $0.magneticShoes = Settings.magneticShoes }
    }

    @objc private func toggleWindows() {
        Settings.walkOnWindows.toggle()
        world.includeWindows = Settings.walkOnWindows
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.t("login.error")
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
