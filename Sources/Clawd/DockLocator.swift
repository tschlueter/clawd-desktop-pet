import AppKit
import ApplicationServices

/// Bereich, auf dem Clawd laufen kann: von minX bis maxX auf Höhe y (Cocoa-Koordinaten).
struct Walkway: Equatable {
    var minX: CGFloat
    var maxX: CGFloat
    var y: CGFloat
    var isDock: Bool
}

enum DockLocator {
    /// Fragt (einmalig mit Dialog) nach der Bedienungshilfen-Freigabe.
    @discardableResult
    static func requestAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Was die Accessibility-API über den Dock verrät (Cocoa-Koordinaten).
    struct Snapshot {
        var walkway: Walkway
        /// Papierkorb im Dock (zum Ausleeren des Kehrblechs).
        var trash: NSRect?
        /// App-, Ordner- und Dokument-Symbole (zum Polieren).
        var icons: [NSRect] = []
    }

    /// Ein einziger AX-Durchlauf durch den Dock: Laufweg, Papierkorb und Symbole.
    static func snapshot() -> Snapshot {
        guard let list = dockList(), let frame = frame(of: list),
              frame.width > frame.height, // Dock unten (horizontal)
              NSScreen.screens.contains(where: { $0.frame.intersects(frame.insetBy(dx: 1, dy: 1)) }) // nicht versteckt
        else { return Snapshot(walkway: fallbackWalkway()) }

        var snapshot = Snapshot(walkway: Walkway(minX: frame.minX, maxX: frame.maxX, y: frame.maxY, isDock: true))
        let iconSubroles: Set<String> = ["AXApplicationDockItem", "AXFolderDockItem", "AXDocumentDockItem"]
        for item in children(of: list) {
            guard let subrole = string(item, kAXSubroleAttribute), let itemFrame = self.frame(of: item) else { continue }
            if subrole == "AXTrashDockItem" {
                snapshot.trash = itemFrame
            } else if iconSubroles.contains(subrole) {
                snapshot.icons.append(itemFrame)
            }
        }
        // Der Rahmen der Symbolleiste ragt ein paar Punkte über den sichtbaren Dock hinaus.
        // Clawd soll auf dem Dock stehen, nicht darüber schweben: Oberkante der Symbole + 1 pt
        // (so schließen die Füße optisch mit dem Dock ab).
        if let iconTop = (snapshot.icons + [snapshot.trash].compactMap { $0 }).map(\.maxY).max() {
            snapshot.walkway.y = min(iconTop + 1, frame.maxY)
        }
        return snapshot
    }

    /// Ohne Freigabe oder bei seitlichem/verstecktem Dock: volle Breite auf Höhe des Dock-Bereichs.
    static func fallbackWalkway() -> Walkway {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return Walkway(minX: 0, maxX: 800, y: 0, isDock: false)
        }
        return Walkway(
            minX: screen.frame.minX,
            maxX: screen.frame.maxX,
            y: screen.visibleFrame.minY,
            isDock: false
        )
    }

    /// AX/CoreGraphics (Ursprung oben links des Hauptbildschirms) → Cocoa (unten links).
    static func cocoaRect(fromTopLeft r: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    // MARK: - Accessibility

    /// Die Symbol-Liste des Docks (erstes Kind mit Rolle AXList).
    private static func dockList() -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let appElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        return children(of: appElement).first { string($0, kAXRoleAttribute) == (kAXListRole as String) }
    }

    private static func frame(of element: AXUIElement) -> NSRect? {
        guard let origin = pointValue(element, kAXPositionAttribute),
              let size = sizeValue(element, kAXSizeAttribute),
              size.width > 0, size.height > 0
        else { return nil }
        return cocoaRect(fromTopLeft: CGRect(origin: origin, size: size))
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return ref as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success else { return [] }
        return ref as? [AXUIElement] ?? []
    }

    private static func pointValue(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeValue(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
