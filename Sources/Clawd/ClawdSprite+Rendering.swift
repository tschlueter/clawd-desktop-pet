import AppKit

/// Farben (hell/dunkel), Zeichnen und Bild-Cache der Pixel-Frames.
extension ClawdSprite {
    // MARK: - Farben (hell/dunkel)

    typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

    /// Hell = für helle Hintergründe (kräftigere, dunklere Akzente),
    /// Dunkel = für dunkle Hintergründe (hellere Metalle, leuchtendere Effekte).
    enum Theme: String { case light, dark }

    /// Aktuelles Theme; nach dem Ändern `ClawdNode.refreshTheme()` aufrufen.
    static var theme: Theme = .light

    /// Farben, die in beiden Themes gleich sind (Clawd selbst bleibt immer Clawd).
    private static let shared: [Character: RGB] = [
        "X": (0xD9, 0x77, 0x57), // Körper
        "x": (0xB0, 0x58, 0x3C), // Arme vor dem Körper (Hocke) – dunkler, damit sie sich abheben
        "E": (0x00, 0x00, 0x00), // Augen
        "O": (0xD9, 0x77, 0x57), // Logo auf dem Laptop
        "G": (0xAE, 0xB4, 0xBB), // Laptop-Deckel, Hantelstange
        "p": (0x5F, 0x64, 0x6B), // AirPods Max: Polster (liegt auf Clawd)
        "U": (0xF1, 0xEA, 0xDC), // Schüssel-Rand
        "u": (0xD6, 0x45, 0x45), // Schüssel
        "Q": (0xE0, 0x48, 0x48), // Schlägerrahmen
    ]

    private static let themed: [Theme: [Character: RGB]] = [
        .light: [
            "K": (0x3A, 0x3F, 0x45), // Laptop-Rand, Gewichtsscheiben
            "J": (0x5A, 0x60, 0x68), // Gewichtsscheibe, Innenrand
            "m": (0x9C, 0xA2, 0xAA), // AirPods Max: Mesh-Kopfband
            "s": (0x6A, 0x70, 0x78), // AirPods Max: Edelstahl-Bügel
            "c": (0xB4, 0xBA, 0xC1), // AirPods Max: Alu-Muschel
            "N": (0x6A, 0x5A, 0xD8), // Musiknoten
            "C": (0x2E, 0x9E, 0x3F), // Code: Zeichenketten
            "Z": (0x7D, 0x84, 0x8C), // Zzz, Code-Kommentar
            "B": (0x2F, 0x81, 0xF7), // Code: Schlüsselwort
            "M": (0xF0, 0x3A, 0x92), // 80er-Stirnband (Neonpink)
            "W": (0x14, 0xA8, 0xC0), // Schweißbänder (Türkis)
            "L": (0xF2, 0xB7, 0x05), // Stulpen (Gelb)
            "R": (0x14, 0xA8, 0xC0), // Springseil
            "S": (0x3E, 0x9C, 0xE0), // Schweiß
            "Y": (0xE6, 0xAE, 0x2E), // Nudeln
            "H": (0x8B, 0x5A, 0x2B), // Stäbchen
            "V": (0x9A, 0xA0, 0xA6), // Dampf
            "q": (0xB8, 0xBD, 0xC4), // Schlägersaiten
            "h": (0x2B, 0x2B, 0x2B), // Schlägergriff
            "T": (0x9D, 0xBA, 0x1E), // Tennisball
            "b": (0xC9, 0x9A, 0x3A), // Besenborsten
            "D": (0x8E, 0x85, 0x78), // Staub
            "o": (0x4A, 0x4F, 0x55), // Sprechblase, Rand
            "P": (0xFF, 0xFF, 0xFF), // Papierflieger (weiß; der Schatten hebt ihn vom Hintergrund ab)
            "a": (0x9A, 0xA0, 0xA6), // Papierflieger, Falzkanten
            "d": (0x23, 0x6B, 0x2E), // Frosch, Kontur
            "e": (0xA8, 0xD8, 0x6A), // Frosch, Bauch
            "w": (0xFF, 0xFF, 0xFF), // Sprechblase
            "k": (0xF2, 0xB8, 0x00), // Stern
            "r": (0xF0, 0x46, 0x7A), // Herz
            "y": (0xF2, 0xC1, 0x2E), // Schwamm
            "g": (0x3E, 0x9E, 0x4A), // Grün (Pflanze, Scheuerseite)
            "t": (0xC8, 0x69, 0x3F), // Blumentopf
            "f": (0xE8, 0x5D, 0x9A), // Blütenblätter
            "v": (0x3D, 0x8B, 0xD8), // Gießkanne
            "z": (0x4F, 0xB3, 0xD9), // Putztuch
            "n": (0xB9, 0x87, 0x4D), // Karton
            "1": (0xE8, 0x5A, 0x8E), // Farbe Pink
            "2": (0x22, 0xA6, 0x99), // Farbe Türkis
            "3": (0xE8, 0xB0, 0x10), // Farbe Gelb
            "4": (0x7E, 0x63, 0xD8), // Farbe Violett
            "5": (0xC9, 0x9A, 0x12), // Bauhelm: Rippen, Krempe
            "6": (0xFF, 0xF3, 0xB0), // Bauhelm: Glanz
            "9": (0x26, 0x29, 0x2D), // Schwarzer Denkhut
            "i": (0x23, 0x4A, 0x8E), // Zielscheibe: äußerer Ring (dunkelblau)
            "I": (0x2F, 0x63, 0xB8), // Zielscheibe: blauer Ring
            "A": (0xE2, 0xC6, 0x86), // Zielscheibe: Stroh
            "F": (0xC6, 0xA2, 0x5C), // Zielscheibe: Stroh, dunklerer Ring
            "j": (0xA8, 0x2C, 0x2C), // Zielscheibe: Zentrum
            "7": (0x5A, 0x45, 0xB0), // Sitzsack: Schatten
            "8": (0x9A, 0x7B, 0xEA), // Sitzsack: Glanz
        ],
        .dark: [
            "K": (0x8C, 0x93, 0x9B),
            "J": (0xB3, 0xB9, 0xC0),
            "m": (0xD9, 0xDD, 0xE2),
            "s": (0xAE, 0xB4, 0xBB),
            "c": (0xE8, 0xEB, 0xEE),
            "N": (0xA9, 0x9B, 0xFF),
            "C": (0x5B, 0xD4, 0x6B),
            "Z": (0xC2, 0xC8, 0xCF),
            "B": (0x79, 0xB8, 0xFF),
            "M": (0xFF, 0x5F, 0xAE),
            "W": (0x3F, 0xE0, 0xF2),
            "L": (0xFF, 0xE0, 0x4A),
            "R": (0x3F, 0xE0, 0xF2),
            "S": (0xA6, 0xDC, 0xFF),
            "Y": (0xF5, 0xC8, 0x4C),
            "H": (0xB8, 0x80, 0x4A),
            "V": (0xD0, 0xD4, 0xD9),
            "q": (0xDA, 0xDD, 0xE1),
            "h": (0x9A, 0xA0, 0xA6),
            "T": (0xD4, 0xF0, 0x4A),
            "b": (0xE8, 0xC4, 0x6A),
            "D": (0xC8, 0xBF, 0xB0),
            "o": (0x9A, 0xA0, 0xA6),
            "P": (0xF4, 0xF4, 0xF6),
            "a": (0x8A, 0x93, 0x9C),
            "d": (0x2A, 0x7A, 0x36),
            "e": (0xC4, 0xEB, 0x8A),
            "w": (0xF4, 0xF4, 0xF6),
            "k": (0xFF, 0xE0, 0x66),
            "r": (0xFF, 0x6F, 0x9A),
            "y": (0xFF, 0xD6, 0x4D),
            "g": (0x5C, 0xC8, 0x6A),
            "t": (0xD9, 0x7A, 0x4E),
            "f": (0xFF, 0x7E, 0xB6),
            "v": (0x6A, 0xAE, 0xF2),
            "z": (0x8E, 0xD6, 0xF2),
            "n": (0xD6, 0xA2, 0x66),
            "1": (0xFF, 0x7E, 0xAE),
            "2": (0x4F, 0xD6, 0xC6),
            "3": (0xFF, 0xD2, 0x4A),
            "4": (0xA6, 0x8F, 0xFF),
            "5": (0xE0, 0xB5, 0x2A),
            "6": (0xFF, 0xF8, 0xD0),
            "9": (0x3A, 0x3F, 0x45), // auf dunklem Grund dunkelgrau statt schwarz
            "i": (0x3A, 0x6C, 0xC4),
            "I": (0x52, 0x86, 0xDE),
            "A": (0xEC, 0xD3, 0x98),
            "F": (0xD2, 0xB0, 0x6A),
            "j": (0xC4, 0x3A, 0x3A),
            "7": (0x6A, 0x55, 0xC4),
            "8": (0xB0, 0x96, 0xF4),
        ],
    ]

    static func rgb(_ ch: Character, theme: Theme = theme) -> RGB? {
        shared[ch] ?? themed[theme]?[ch]
    }

    static let bodyColor = nsColor("X")

    static func nsColor(_ ch: Character, theme: Theme = theme) -> NSColor {
        let c = rgb(ch, theme: theme) ?? (0, 0, 0)
        return NSColor(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1)
    }

    static let columns = 14
    static let rows = 8

    static func size(pixel: CGFloat) -> NSSize {
        NSSize(width: CGFloat(columns) * pixel, height: CGFloat(rows) * pixel)
    }

    /// Erste Zeile, in der Clawds Körper beginnt (Oberkante des Kopfes).
    static func headRow(_ frame: Frame) -> Int {
        frame.firstIndex { $0.contains("X") || $0.contains("M") } ?? 0 // M = Stirnband
    }

    // MARK: - Zeichnen (für Menüleisten-Icon und Tests)

    /// Zeichnet einen Frame; `origin` ist unten links, `px` die Kantenlänge eines Pixels.
    static func draw(_ frame: Frame, at origin: CGPoint, px: CGFloat, mirrored: Bool) {
        let cols = frame.first?.count ?? 0
        for (rowIndex, row) in frame.enumerated() {
            for (colIndex, ch) in row.enumerated() where rgb(ch) != nil {
                let col = mirrored ? cols - 1 - colIndex : colIndex
                nsColor(ch).setFill()
                NSRect(x: origin.x + CGFloat(col) * px,
                       y: origin.y + CGFloat(frame.count - 1 - rowIndex) * px,
                       width: px, height: px).fill()
            }
        }
    }

    /// Menüleisten-Symbol: Clawd hinter seinem Laptop (wie beim Coden), einfarbig.
    /// Als Vorlagenbild färbt macOS es selbst passend zur Menüleiste ein (hell, dunkel, aktiv).
    static let trayPattern: [String] = [
        "..................",
        "..................",
        "....##########....",
        "....##########....",
        "....##.####.##....",
        "....##.####.##....",
        "..##############..",
        "..##############..",
        "..................",
        "...############...",
        "...############...",
        "...#####..#####...",
        "...#####..#####...",
        "...############...",
        "..##############..",
        "..................",
        "..................",
        "..................",
    ]

    static func trayIcon() -> NSImage {
        let rows = trayPattern
        let size = NSSize(width: CGFloat(rows[0].count), height: CGFloat(rows.count))
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clawd Desktop Pet"
        return image
    }

    static func image(pixel: CGFloat) -> NSImage {
        NSImage(size: size(pixel: pixel), flipped: false) { _ in
            draw(stand, at: .zero, px: pixel, mirrored: false)
            return true
        }
    }

    // MARK: - Bild-Cache

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let cgPalettes: [Theme: [Character: CGColor]] = [Theme.light, .dark].reduce(into: [:]) { result, t in
        var colors: [Character: CGColor] = [:]
        for ch in Set(shared.keys).union(themed[t].map { Array($0.keys) } ?? []) {
            if let c = rgb(ch, theme: t) {
                colors[ch] = CGColor(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: 1)
            }
        }
        result[t] = colors
    }
    private static var cache: [String: CGImage] = [:]

    /// Frame als winziges Bitmap (1 Bildpunkt pro Sprite-Pixel), einmal erzeugt und gecacht.
    /// Das Hochskalieren übernimmt Core Animation mit Nearest-Neighbor-Filter.
    static func cgImage(_ frame: Frame, mirrored: Bool = false) -> CGImage {
        let cacheKey = theme.rawValue + (mirrored ? "M" : "") + frame.joined(separator: "|")
        if let image = cache[cacheKey] { return image }
        let palette = cgPalettes[theme] ?? [:]

        let cols = frame.first?.count ?? 0
        let ctx = CGContext(data: nil, width: cols, height: frame.count, bitsPerComponent: 8, bytesPerRow: 0,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (rowIndex, row) in frame.enumerated() {
            for (colIndex, ch) in row.enumerated() {
                guard let color = palette[ch] else { continue }
                ctx.setFillColor(color)
                let col = mirrored ? cols - 1 - colIndex : colIndex
                ctx.fill(CGRect(x: col, y: frame.count - 1 - rowIndex, width: 1, height: 1))
            }
        }
        let image = ctx.makeImage()!
        cache[cacheKey] = image
        return image
    }
}
