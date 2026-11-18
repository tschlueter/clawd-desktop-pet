import AppKit

/// Geometrie des Spielplatzes (globale Cocoa-Koordinaten), aus der Fenstergröße berechnet.
///
/// Ab der Mindestgröße ist alles da, was Clawd für seine Aktivitäten braucht:
/// - ein Mini-Dock unten in der Mitte (Symbole, Papierkorb, lange Fläche) mit Boden links und rechts,
/// - Kasten A, niedrig links: mit einem Sprung vom Boden oder Dock erreichbar (Fenster-Jobs),
/// - Kasten C, hoch und schwebend: linke Kante über A (Enterhaken oder Jetpack von A aus),
/// - Kasten B, ein Turm bis zum Boden: zum Hochklettern mit Magnetschuhen, Haken oder Jetpack vom
///   Boden; B und C stehen sich für den Wandsprung gegenüber.
///
/// Kleinere Flächen (nur für README-Aufnahmen) bekommen das kompakte Layout mit zwei Kästen.
struct PlaygroundLayout: Equatable {
    struct Box: Equatable {
        let id: CGWindowID
        let rect: NSRect
    }

    /// Fenster-IDs der Kästen – weit weg von echten Fensternummern.
    static let boxIDs: [CGWindowID] = [0xFFFF_FF01, 0xFFFF_FF02, 0xFFFF_FF03]
    static let minimumSize = NSSize(width: 760, height: 480)
    static let defaultSize = NSSize(width: 900, height: 560)

    let area: NSRect
    let dock: NSRect
    let icons: [NSRect]
    let trash: NSRect
    let boxes: [Box]

    init(area: NSRect) {
        self.area = area
        let compact = area.width < Self.minimumSize.width || area.height < Self.minimumSize.height
        // Mini-Dock: unten mittig, Symbole links, Papierkorb rechts.
        let dockWidth = compact ? min(max(area.width * 0.5, 200), 380) : min(max(area.width * 0.4, 320), 420)
        let dockHeight: CGFloat = 30
        let dock = NSRect(x: (area.midX - dockWidth / 2).rounded(), y: area.minY, width: dockWidth.rounded(), height: dockHeight)
        self.dock = dock
        let tile: CGFloat = 22, gap: CGFloat = 6
        trash = NSRect(x: dock.maxX - 8 - tile, y: dock.minY + 4, width: tile, height: tile)
        let count = min(max(Int((dockWidth - 16 - tile - gap) / (tile + gap)), 1), 6)
        icons = (0..<count).map { i in
            NSRect(x: dock.minX + 8 + CGFloat(i) * (tile + gap), y: dock.minY + 4, width: tile, height: tile)
        }
        boxes = compact ? Self.compactBoxes(area) : Self.fullBoxes(area)
    }

    /// A niedrig links, C hoch schwebend (linke Kante über A), B als Turm rechts bis zum Boden.
    private static func fullBoxes(_ area: NSRect) -> [Box] {
        let w = area.width, h = area.height
        // A: Oberkante 120 pt über dem Boden – vom Boden (120) und vom Dock (90) aus ein Sprung.
        let aWidth = min(max(w * 0.28, 200), 300)
        let a = NSRect(x: (area.minX + w * 0.045).rounded(), y: area.minY + 64, width: aWidth.rounded(), height: 56)
        // B: Turm rechts; die Seiten reichen bis zum Boden.
        let bWidth = min(max(w * 0.19, 140), 200)
        let bTop = min(max(h * 0.6, 280), 360)
        let b = NSRect(x: (area.maxX - w * 0.02 - bWidth).rounded(), y: area.minY, width: bWidth.rounded(), height: bTop.rounded())
        // C: 20 pt höher als B, 120 pt hoch – überlappt B in der Höhe, damit der Wandsprung klappt.
        // Linke Kante 30 pt vor dem Ende von A, rechte Kante 150 pt vor B.
        let cTop = bTop + 20, cHeight: CGFloat = 120
        let cMinX = a.maxX - 30
        let cMaxX = max(b.minX - 150, cMinX + 180)
        let c = NSRect(x: cMinX, y: (area.minY + cTop - cHeight).rounded(), width: (cMaxX - cMinX).rounded(), height: cHeight)
        return [Box(id: boxIDs[0], rect: a), Box(id: boxIDs[1], rect: c), Box(id: boxIDs[2], rect: b)]
    }

    /// Kompakt (kleine Flächen): links tiefer, rechts höher – vom Boden bzw. vom ersten Kasten aus erreichbar.
    private static func compactBoxes(_ area: NSRect) -> [Box] {
        let boxHeight: CGFloat = 56
        let w1 = min(max(area.width * 0.28, 130), 240)
        let top1 = area.minY + min(130, area.height * 0.42)
        var boxes = [Box(id: boxIDs[0],
                         rect: NSRect(x: (area.minX + area.width * 0.06).rounded(), y: (top1 - boxHeight).rounded(),
                                      width: w1.rounded(), height: boxHeight))]
        let w2 = min(max(area.width * 0.26, 120), 220)
        let top2 = top1 + min(95, area.height * 0.28)
        if top2 <= area.maxY - 70 {
            boxes.append(Box(id: boxIDs[1],
                             rect: NSRect(x: (area.maxX - area.width * 0.06 - w2).rounded(), y: (top2 - boxHeight).rounded(),
                                          width: w2.rounded(), height: boxHeight)))
        }
        return boxes
    }
}
