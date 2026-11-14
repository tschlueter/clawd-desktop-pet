import AppKit

/// Das Spielplatz-Fenster: ein normales, größenveränderbares Fenster, in dem die Clawds leben,
/// solange es offen ist. Hintergrund schlicht passend zum Theme; Mini-Dock und Kästen werden
/// als Layer unter den Clawds gezeichnet. Schließen lässt alle Clawds auf den Desktop fallen.
final class Playground: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let view: StageView
    private let furniture = PlaygroundFurniture()
    private unowned let stage: Stage
    private let world: World
    private var area: NSRect
    /// Wird nach dem Schließen aufgerufen.
    var onClose: (() -> Void)?

    init(stage: Stage, world: World, size: NSSize = NSSize(width: 720, height: 460)) {
        self.stage = stage
        self.world = world
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = L10n.t("demo.playground")
        window.isReleasedWhenClosed = false
        window.contentMinSize = PlaygroundLayout.minimumSize
        window.collectionBehavior = [.fullScreenNone]
        view = StageView(frame: NSRect(origin: .zero, size: size))
        view.stage = stage
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        area = rect
        super.init()
        window.delegate = self
        view.rootLayer.addSublayer(furniture.layer)
        area = currentArea
        refreshTheme()
        world.playground = PlaygroundLayout(area: area)
        furniture.layout(world.playground!, in: area)
        stage.attachPlayground(window: window, root: view.rootLayer, frame: area)
        stage.beforeTick = { [weak self] in self?.followWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Fensterinhalt in globalen Cocoa-Koordinaten.
    private var currentArea: NSRect { window.convertToScreen(view.frame) }

    /// Pro Takt: Fenster verschoben oder in der Größe geändert? Dann Welt und Clawds nachführen.
    private func followWindow() {
        let now = currentArea
        guard now != area else { return }
        let moved = now.size == area.size
        let delta = CGVector(dx: now.minX - area.minX, dy: now.minY - area.minY)
        area = now
        stage.updatePlayground(frame: now)
        let layout = PlaygroundLayout(area: now)
        world.playground = layout
        furniture.layout(layout, in: now)
        if moved { stage.controllers.forEach { $0.shift(by: delta) } }
    }

    /// Ein Punkt oben im Spielplatz, um einen Clawd hineinfallen zu lassen.
    func dropPoint(index: Int, of count: Int) -> CGPoint {
        let step = area.width / CGFloat(count + 1)
        return CGPoint(x: area.minX + step * CGFloat(index + 1), y: area.maxY - 50)
    }

    func refreshTheme() {
        let dark = ClawdSprite.theme == .dark
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.rootLayer.backgroundColor = dark
            ? CGColor(srgbRed: 0x23 / 255, green: 0x24 / 255, blue: 0x27 / 255, alpha: 1)
            : CGColor(srgbRed: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF5 / 255, alpha: 1)
        furniture.dark = dark
        if let layout = world.playground { furniture.layout(layout, in: area) }
        CATransaction.commit()
    }

    func close() { window.close() }

    /// Inhalt als Bild (für `SceneRecorder`): `rect` in Punkten relativ zur unteren linken Ecke,
    /// ohne Angabe der ganze Spielplatz.
    func snapshot(rect: CGRect?, scale: CGFloat) -> CGImage? {
        let root = view.rootLayer
        let r = (rect ?? root.bounds).integral
        guard let ctx = CGContext(data: nil, width: Int(r.width * scale), height: Int(r.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -r.minX, y: -r.minY)
        root.render(in: ctx)
        return ctx.makeImage()
    }

    func windowWillClose(_ notification: Notification) {
        stage.beforeTick = nil
        onClose?()
    }

    /// Minimiert wie geschlossen behandeln – sonst lebten die Clawds unsichtbar im Dock.
    func windowWillMiniaturize(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.window.close() }
    }
}

/// Mini-Dock, Symbole, Papierkorb und Kästen als einfache Layer.
final class PlaygroundFurniture {
    let layer = CALayer()
    var dark = false
    private var parts: [String: CALayer] = [:]

    init() {
        layer.anchorPoint = .zero
        layer.actions = ["sublayers": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    private func part(_ key: String) -> CALayer {
        if let l = parts[key] { return l }
        let l = CALayer()
        l.actions = ["position": NSNull(), "bounds": NSNull(), "backgroundColor": NSNull(), "hidden": NSNull(),
                     "borderColor": NSNull(), "frame": NSNull()]
        layer.addSublayer(l)
        parts[key] = l
        return l
    }

    private func color(_ light: UInt32, _ darkValue: UInt32, alpha: CGFloat = 1) -> CGColor {
        let v = dark ? darkValue : light
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    /// Alles neu anordnen; `area` ist der Fensterinhalt in globalen Koordinaten.
    func layout(_ p: PlaygroundLayout, in area: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        func local(_ r: NSRect) -> CGRect { r.offsetBy(dx: -area.minX, dy: -area.minY) }

        let dock = part("dock")
        dock.frame = local(p.dock)
        dock.cornerRadius = 8
        dock.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
        dock.backgroundColor = color(0xE3E4E6, 0x3A3B3F)
        dock.borderWidth = 1
        dock.borderColor = color(0xCFD1D4, 0x4A4B50)

        let iconColors: [(UInt32, UInt32)] = [(0x2F81F7, 0x79B8FF), (0xE85A8E, 0xFF7EAE), (0x22A699, 0x4FD6C6),
                                               (0xE8B010, 0xFFD24A), (0x7E63D8, 0xA68FFF), (0xD97757, 0xE89070)]
        for i in 0..<6 {
            let icon = part("icon\(i)")
            icon.isHidden = i >= p.icons.count
            guard i < p.icons.count else { continue }
            icon.frame = local(p.icons[i])
            icon.cornerRadius = 5
            icon.backgroundColor = color(iconColors[i].0, iconColors[i].1)
        }

        let trash = part("trash")
        trash.frame = local(p.trash).insetBy(dx: 3, dy: 0).offsetBy(dx: 0, dy: -1)
        trash.cornerRadius = 3
        trash.backgroundColor = color(0x9AA0A6, 0x8A9097)
        let lid = part("trashLid")
        lid.frame = CGRect(x: trash.frame.minX - 2, y: trash.frame.maxY - 3, width: trash.frame.width + 4, height: 3)
        lid.cornerRadius = 1.5
        lid.backgroundColor = color(0x6A7078, 0xB0B6BC)

        for i in 0..<PlaygroundLayout.boxIDs.count {
            let box = part("box\(i)"), bar = part("boxBar\(i)")
            let visible = i < p.boxes.count
            box.isHidden = !visible
            bar.isHidden = !visible
            for d in 0..<3 { part("boxDot\(i)-\(d)").isHidden = !visible }
            guard visible else { continue }
            let r = local(p.boxes[i].rect)
            box.frame = r
            box.cornerRadius = 6
            box.backgroundColor = color(0xFFFFFF, 0x2E2F33)
            box.borderWidth = 1
            box.borderColor = color(0xD0D2D5, 0x47484D)
            // Titelleiste mit drei Punkten – ein kleines "Fenster".
            bar.frame = CGRect(x: r.minX + 1, y: r.maxY - 11, width: r.width - 2, height: 10)
            bar.backgroundColor = color(0xECEDEF, 0x393A3E)
            bar.cornerRadius = 5
            bar.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
            let dots: [(UInt32, UInt32)] = [(0xFF5F57, 0xFF6B63), (0xFEBC2E, 0xFFC94A), (0x28C840, 0x3DDC5A)]
            for d in 0..<3 {
                let dot = part("boxDot\(i)-\(d)")
                dot.frame = CGRect(x: r.minX + 6 + CGFloat(d) * 7, y: r.maxY - 8, width: 4, height: 4)
                dot.cornerRadius = 2
                dot.backgroundColor = color(dots[d].0, dots[d].1)
            }
        }
        CATransaction.commit()
    }
}
