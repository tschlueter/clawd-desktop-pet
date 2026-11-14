import AppKit

/// Eine waagerechte Fläche, auf der Clawd stehen kann (Cocoa-Koordinaten).
struct Platform {
    enum Kind: Equatable {
        case dock
        case floor(Int) // Index in World.screens
        case window(CGWindowID)
        /// Seitenkante eines Fensters (nur mit Magnetschuhen): side −1 = links, +1 = rechts.
        case wall(CGWindowID, Int)
    }

    let kind: Kind
    let minX: CGFloat
    let maxX: CGFloat
    let y: CGFloat

    var width: CGFloat { maxX - minX }
    func contains(x: CGFloat) -> Bool { x >= minX && x <= maxX }
}

/// Ein Bereich, in dem Clawd sich bewegt: ein echter Bildschirm oder der Spielplatz.
struct ScreenArea {
    var frame: NSRect
    /// Bereich ohne Menüleiste (beim Spielplatz gleich `frame`).
    var visibleFrame: NSRect
}

/// Kennt alles, worauf Clawd laufen kann: Dock, Bildschirm-Unterkanten und Fenster-Oberkanten –
/// auf dem echten Desktop oder, solange er offen ist, im Spielplatz-Fenster.
final class World {
    private(set) var dock: Walkway
    private(set) var screens: [ScreenArea] = []
    /// Papierkorb im Dock (zum Ausleeren des Kehrblechs).
    private(set) var trash: NSRect?
    /// App-Symbole im Dock (zum Polieren).
    private(set) var dockIcons: [NSRect] = []
    private(set) var windowPlatforms: [Platform] = []
    /// Fensterrahmen (Cocoa) nach Fenster-ID, um Bewegungen eines Fensters nachzuverfolgen.
    private(set) var windowFrames: [CGWindowID: NSRect] = [:]
    /// Stapelreihenfolge der Fenster: 0 = vorderstes.
    private(set) var windowOrder: [CGWindowID: Int] = [:]

    var includeWindows = true

    /// Spielplatz: Solange gesetzt, gibt es nur ihn – mit eigenem Mini-Dock und Kästen statt Fenstern.
    var playground: PlaygroundLayout? {
        didSet { refresh(now: CACurrentMediaTime(), force: true) }
    }

    private var lastDockCheck: CFTimeInterval = 0
    private var lastWindowCheck: CFTimeInterval = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init() {
        dock = DockLocator.fallbackWalkway() // refresh(force:) holt gleich den echten Dock
        refresh(now: CACurrentMediaTime(), force: true)
    }

    /// - Parameter windowMaxAge: Wie alt die Fensterliste höchstens sein darf. Das Abfragen ist ein
    ///   synchroner Aufruf an den WindowServer – nur schnell, wenn ein Clawd es gerade braucht.
    func refresh(now: CFTimeInterval, windowMaxAge: CFTimeInterval = 0.5, force: Bool = false) {
        if let playground {
            if force { apply(playground) }
            return
        }
        if force || now - lastDockCheck > 2 {
            lastDockCheck = now
            let snapshot = DockLocator.snapshot()
            dock = snapshot.walkway
            trash = snapshot.trash
            dockIcons = snapshot.icons
            screens = NSScreen.screens.map { ScreenArea(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        }
        if force || now - lastWindowCheck > windowMaxAge {
            lastWindowCheck = now
            scanWindows()
        }
    }

    // MARK: - Plattformen

    var dockPlatform: Platform {
        Platform(kind: .dock, minX: dock.minX, maxX: dock.maxX, y: dock.y)
    }

    var floorPlatforms: [Platform] {
        screens.enumerated().map { i, s in
            Platform(kind: .floor(i), minX: s.frame.minX, maxX: s.frame.maxX, y: s.frame.minY)
        }
    }

    /// Alle Plattformen, höchste zuerst.
    var allPlatforms: [Platform] {
        ([dockPlatform] + windowPlatforms + floorPlatforms).sorted { $0.y > $1.y }
    }

    /// Bildschirm, auf dessen Unterkante das Dock steht.
    var dockScreenIndex: Int? {
        guard dock.isDock else { return nil }
        let mid = CGPoint(x: (dock.minX + dock.maxX) / 2, y: dock.y - 1)
        return screens.firstIndex { $0.frame.contains(mid) }
    }

    func platform(_ kind: Platform.Kind, near x: CGFloat) -> Platform? {
        switch kind {
        case .dock:
            return dockPlatform
        case .floor(let i):
            return floorPlatforms.indices.contains(i) ? floorPlatforms[i] : nil
        case .wall:
            return nil
        case .window:
            let segments = windowPlatforms.filter { $0.kind == kind }
            return segments.first { $0.contains(x: x) }
                ?? segments.min { abs(($0.minX + $0.maxX) / 2 - x) < abs(($1.minX + $1.maxX) / 2 - x) }
        }
    }

    /// Spielplatz als einzige Welt übernehmen.
    private func apply(_ p: PlaygroundLayout) {
        screens = [ScreenArea(frame: p.area, visibleFrame: p.area)]
        dock = Walkway(minX: p.dock.minX, maxX: p.dock.maxX, y: p.dock.maxY, isDock: true)
        trash = p.trash
        dockIcons = p.icons
        windowFrames = Dictionary(uniqueKeysWithValues: p.boxes.map { ($0.id, $0.rect) })
        windowOrder = Dictionary(uniqueKeysWithValues: p.boxes.enumerated().map { ($0.element.id, $0.offset) })
        windowPlatforms = p.boxes.map { Platform(kind: .window($0.id), minX: $0.rect.minX, maxX: $0.rect.maxX, y: $0.rect.maxY) }
    }

    /// Ist dieser Punkt einer Fensterkante sichtbar – also nicht von einem davorliegenden Fenster verdeckt?
    /// Nur sichtbare Kanten taugen für die Magnetschuhe.
    func isEdgeVisible(_ id: CGWindowID, at point: CGPoint) -> Bool {
        Self.isEdgeVisible(id, at: point, frames: windowFrames, order: windowOrder)
    }

    static func isEdgeVisible(_ id: CGWindowID, at point: CGPoint, frames: [CGWindowID: NSRect],
                              order: [CGWindowID: Int]) -> Bool {
        guard let z = order[id] else { return false }
        return !frames.contains { other, f in
            other != id && (order[other] ?? .max) < z && f.contains(point)
        }
    }

    func screen(containingX x: CGFloat, y: CGFloat? = nil) -> ScreenArea? {
        if let y, let s = screens.first(where: { $0.frame.contains(CGPoint(x: x, y: y)) }) { return s }
        return screens.first { x >= $0.frame.minX && x < $0.frame.maxX }
    }

    /// Bildschirm, dessen waagerechter Bereich x enthält – sonst der nächstgelegene.
    func nearestScreen(toX x: CGFloat) -> ScreenArea? {
        screen(containingX: x) ?? screens.min {
            distance(x, $0.frame) < distance(x, $1.frame)
        }
    }

    private func distance(_ x: CGFloat, _ r: NSRect) -> CGFloat {
        x < r.minX ? r.minX - x : (x > r.maxX ? x - r.maxX : 0)
    }

    // MARK: - Fenster

    private func scanWindows() {
        guard includeWindows,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            windowPlatforms = []
            windowFrames = [:]
            return
        }

        // Reihenfolge der Liste: vorderstes Fenster zuerst.
        var rects: [(id: CGWindowID, rect: NSRect)] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            let rect = DockLocator.cocoaRect(fromTopLeft: cg)
            guard rect.width >= 120, rect.height >= 50 else { continue }
            rects.append((id, rect))
        }

        windowFrames = Dictionary(rects.map { ($0.id, $0.rect) }, uniquingKeysWith: { a, _ in a })
        windowOrder = Dictionary(rects.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })

        windowPlatforms = Self.windowTops(rects, screens: screens.map { ($0.frame, $0.visibleFrame.maxY) })
    }

    /// Begehbare Fenster-Oberkanten: nur die Teile, die auf einem Bildschirm liegen, nicht direkt
    /// unter der Menüleiste kleben und nicht von davorliegenden Fenstern verdeckt sind.
    /// - Parameters:
    ///   - windows: Fenster in Cocoa-Koordinaten, vorderstes zuerst.
    ///   - screens: Bildschirmrahmen und Oberkante des sichtbaren Bereichs (unter der Menüleiste).
    static func windowTops(_ windows: [(id: CGWindowID, rect: NSRect)],
                           screens: [(frame: NSRect, visibleMaxY: CGFloat)]) -> [Platform] {
        var platforms: [Platform] = []
        for (index, window) in windows.enumerated() {
            let top = window.rect.maxY
            var segments: [(CGFloat, CGFloat)] = screens.compactMap { screen in
                let f = screen.frame
                guard top > f.minY, top < screen.visibleMaxY - 4 else { return nil }
                let a = max(window.rect.minX, f.minX)
                let b = min(window.rect.maxX, f.maxX)
                return a < b ? (a, b) : nil
            }

            for front in windows[..<index] where front.rect.minY < top && front.rect.maxY > top {
                segments = segments.flatMap { seg -> [(CGFloat, CGFloat)] in
                    let (a, b) = seg
                    let (c, d) = (front.rect.minX, front.rect.maxX)
                    if d <= a || c >= b { return [seg] }
                    var out: [(CGFloat, CGFloat)] = []
                    if c > a { out.append((a, c)) }
                    if d < b { out.append((d, b)) }
                    return out
                }
            }
            for (a, b) in segments where b - a >= 60 {
                platforms.append(Platform(kind: .window(window.id), minX: a, maxX: b, y: top))
            }
        }
        return platforms
    }
}
