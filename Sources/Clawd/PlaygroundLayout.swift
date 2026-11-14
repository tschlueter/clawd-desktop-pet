import AppKit

/// Geometrie des Spielplatzes (globale Cocoa-Koordinaten), aus der Fenstergröße berechnet:
/// ein Mini-Dock unten in der Mitte mit Symbolen und Papierkorb und bis zu zwei schwebende
/// Kästen, die sich wie Fenster verhalten (draufspringen, putzen, streichen, Magnetschuhe).
struct PlaygroundLayout: Equatable {
    struct Box: Equatable {
        let id: CGWindowID
        let rect: NSRect
    }

    /// Fenster-IDs der Kästen – weit weg von echten Fensternummern.
    static let boxIDs: [CGWindowID] = [0xFFFF_FF01, 0xFFFF_FF02]
    static let minimumSize = NSSize(width: 420, height: 300)

    let area: NSRect
    let dock: NSRect
    let icons: [NSRect]
    let trash: NSRect
    let boxes: [Box]

    init(area: NSRect) {
        self.area = area
        // Mini-Dock: unten mittig, Symbole links, Papierkorb rechts.
        let dockWidth = min(max(area.width * 0.5, 200), 380)
        let dockHeight: CGFloat = 30
        let dock = NSRect(x: (area.midX - dockWidth / 2).rounded(), y: area.minY, width: dockWidth.rounded(), height: dockHeight)
        self.dock = dock
        let tile: CGFloat = 22, gap: CGFloat = 6
        trash = NSRect(x: dock.maxX - 8 - tile, y: dock.minY + 4, width: tile, height: tile)
        let count = min(max(Int((dockWidth - 16 - tile - gap) / (tile + gap)), 1), 6)
        icons = (0..<count).map { i in
            NSRect(x: dock.minX + 8 + CGFloat(i) * (tile + gap), y: dock.minY + 4, width: tile, height: tile)
        }

        // Kästen: links tiefer, rechts höher – vom Boden bzw. vom ersten Kasten aus erreichbar.
        let boxHeight: CGFloat = 56
        let w1 = min(max(area.width * 0.28, 130), 240)
        let top1 = area.minY + min(130, area.height * 0.42)
        var boxes = [Box(id: Self.boxIDs[0],
                         rect: NSRect(x: (area.minX + area.width * 0.06).rounded(), y: (top1 - boxHeight).rounded(),
                                      width: w1.rounded(), height: boxHeight))]
        let w2 = min(max(area.width * 0.26, 120), 220)
        let top2 = top1 + min(95, area.height * 0.28)
        if top2 <= area.maxY - 70 {
            boxes.append(Box(id: Self.boxIDs[1],
                             rect: NSRect(x: (area.maxX - area.width * 0.06 - w2).rounded(), y: (top2 - boxHeight).rounded(),
                                          width: w2.rounded(), height: boxHeight)))
        }
        self.boxes = boxes
    }
}
