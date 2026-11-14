import Foundation

/// Requisiten für Arbeiten aus den Bereichen, in denen Claude Code oft eingesetzt wird:
/// Security, Datenspeicherung, Data Science und Produktdesign. Alle in doppelter Auflösung
/// (mit `px / 2` zeichnen), nach rechts gerichtet.
extension ClawdSprite {
    // MARK: - Sicherheits-Check

    /// Vorhängeschloss (12 × 16): goldener Körper mit Schlüsselloch, Bügel offen oder zu.
    /// `cracked` = rotes Loch im Körper (die gefundene Lücke).
    static func padlock(open: Bool, cracked: Bool) -> Frame {
        let shackleClosed = [
            "............",
            "............",
            "...oooooo...",
            "..oqqqqqqo..",
            ".oqo....oqo.",
            ".oqo....oqo.",
            ".oqo....oqo.",
        ]
        let shackleOpen = [
            "...oooooo...",
            "..oqqqqqqo..",
            ".oqo....oqo.",
            ".oqo....oqo.",
            ".oqo....ooo.",
            ".oqo........",
            ".oqo........",
        ]
        var body = [
            "oooooooooooo",
            "okkkkkkkkkko",
            "okkkkkkkkkko",
            "okkkkEEkkkko",
            "okkkkEEkkkko",
            "okkkkkEkkkko",
            "okkkkkEkkkko",
            "okkkkkkkkkko",
            "oooooooooooo",
        ].map(Array.init)
        if cracked {
            for (x, y) in [(2, 2), (3, 3), (2, 4), (3, 5), (2, 6)] { body[y][x] = "u" }
            body[3][1] = "u"; body[5][1] = "u"
        }
        return (open ? shackleOpen : shackleClosed) + body.map { String($0) }
    }

    /// Grünes Schild mit weißem Häkchen: Lücke geschlossen.
    static let shieldGlyph: Frame = [
        "ggggggg",
        "gggggwg",
        "ggggwgg",
        "gwgwggg",
        ".gwggg.",
        "..ggg..",
        "...g...",
    ]

    // MARK: - Daten-Migration (Disketten und Band → SSDs im Server)

    /// Raster in doppelter Auflösung mit kleinen Zeichenhilfen.
    private struct Pixels {
        var g: [[Character]]
        init(_ w: Int, _ h: Int) { g = Array(repeating: Array(repeating: Character("."), count: w), count: h) }
        mutating func fill(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ ch: Character) {
            for y in y0...y1 { for x in x0...x1 where g.indices.contains(y) && g[y].indices.contains(x) { g[y][x] = ch } }
        }
        mutating func disc(_ cx: Double, _ cy: Double, _ r: Double, _ ch: Character) {
            for y in g.indices { for x in g[y].indices {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                if dx * dx + dy * dy <= r * r { g[y][x] = ch }
            } }
        }
        mutating func paste(_ f: Frame, at ox: Int, _ oy: Int) {
            for (y, row) in f.enumerated() { for (x, ch) in row.enumerated() where ch != "." {
                if g.indices.contains(oy + y), g[oy + y].indices.contains(ox + x) { g[oy + y][ox + x] = ch }
            } }
        }
        var frame: Frame { g.map { String($0) } }
    }

    /// 3,5"-Diskette (10 × 10): Gehäuse in `body`, Metallschieber, Kerbe, beschriftetes Etikett.
    static func floppy(_ body: Character = "K") -> Frame {
        var p = Pixels(10, 10)
        p.fill(0, 9, 0, 9, body); p.g[0][9] = "."
        p.fill(2, 6, 0, 3, "q"); p.fill(4, 5, 1, 2, body)
        p.fill(1, 8, 5, 8, "w"); p.fill(2, 6, 6, 6, "Z"); p.fill(2, 4, 8, 8, "Z")
        return p.frame
    }

    /// Bandspule (10 × 10); `spin` wechselt die Stellung der Speichen.
    static func tapeReel(spin: Int = 0) -> Frame {
        var p = Pixels(10, 10)
        p.disc(5, 5, 5, "o"); p.disc(5, 5, 4.2, "n"); p.disc(5, 5, 2.2, "q"); p.disc(5, 5, 0.8, "o")
        let spokes = spin % 2 == 0 ? [(5, 2), (5, 7), (2, 5), (7, 5)] : [(3, 3), (6, 6), (3, 6), (6, 3)]
        for (x, y) in spokes { p.g[y][x] = "o" }
        return p.frame
    }

    /// Lesestation (24 × 24): oben eine Bandmaschine, unten ein Retro-PC mit Bildschirm,
    /// Fortschrittsbalken (`progress` 0…1), Diskettenschlitz und Lese-LED (`busy`).
    /// Ohne eingelegtes Band (`tape`) dreht sich nur die leere rechte Spule.
    static func retroReader(tape: Bool, spin: Int = 0, progress: Double = 0, busy: Bool = false) -> Frame {
        var p = Pixels(24, 24)
        p.fill(0, 23, 0, 11, "o"); p.fill(1, 22, 1, 10, "U")
        if tape {
            p.paste(tapeReel(spin: spin), at: 1, 1)
            p.fill(6, 17, 10, 10, "n")
        } else {
            p.disc(6, 6, 1.5, "q")
        }
        var right = Pixels(10, 10)
        right.disc(5, 5, 5, "o"); right.disc(5, 5, 4.2, "U"); right.disc(5, 5, 2.2, "q"); right.disc(5, 5, 0.8, "o")
        for (x, y) in (spin % 2 == 0 ? [(5, 2), (5, 7), (2, 5), (7, 5)] : [(3, 3), (6, 6), (3, 6), (6, 3)]) { right.g[y][x] = "o" }
        p.paste(right.frame, at: 12, 1)
        p.fill(1, 22, 12, 23, "o"); p.fill(2, 21, 13, 22, "U")
        p.fill(3, 12, 14, 20, "K")
        p.fill(4, 11, 15, 15, "C")
        let bar = Int(8 * min(max(progress, 0), 1))
        if bar > 0 { p.fill(4, 3 + bar, 17, 18, "C") }
        p.fill(14, 20, 17, 17, "o")
        p.g[15][20] = busy ? "k" : "J"
        p.fill(14, 16, 20, 20, "Z")
        return p.frame
    }

    /// SSD (10 × 4): silbern mit blauem Etikett und grüner LED.
    static let ssd: Frame = ["oooooooooo", "oqqqBBBqqo", "oqqqBBBqgo", "oooooooooo"]

    /// Server-Rack (16 × 26) mit vier Einschüben; `filled` SSDs stecken. `blink` lässt die LED
    /// der zuletzt eingesteckten SSD aus (Schreibzugriff).
    static func serverRack(filled: Int, blink: Bool = false) -> Frame {
        var p = Pixels(16, 26)
        p.fill(0, 15, 0, 25, "o"); p.fill(1, 14, 1, 24, "K")
        for x in stride(from: 3, through: 12, by: 3) { p.fill(x, x, 2, 3, "J") }
        for i in 0..<4 {
            let y = 6 + i * 5
            if i < filled {
                p.paste(ssd, at: 3, y)
                p.g[y + 1][13] = blink && i == filled - 1 ? "J" : "g"
            } else {
                p.fill(3, 12, y, y + 3, "J"); p.fill(4, 11, y + 1, y + 2, "o")
                p.g[y + 1][13] = "J"
            }
        }
        return p.frame
    }

    /// Holzkiste mit alten Medien (16 × 14): hinten immer eine schwarze Diskette, davor optional
    /// eine blaue Diskette und eine Bandspule.
    static func mediaCrate(floppy front: Bool, reel: Bool) -> Frame {
        var p = Pixels(16, 14)
        p.paste(floppy("K"), at: 1, 0)
        if front { p.paste(floppy("B"), at: 5, 1) }
        if reel { p.paste(tapeReel(), at: 6, 2) }
        p.fill(0, 15, 8, 13, "H"); p.fill(1, 14, 9, 12, "n"); p.fill(1, 14, 10, 10, "H")
        return p.frame
    }

    /// Kleines grünes Datenpaket, das zum Server fliegt.
    static let dataBit: Frame = ["CC", "CC"]

    // MARK: - Dashboard

    /// Monitor mit Balkendiagramm (24 × 20). `heights` = Balkenhöhen (0…12) für bis zu vier Balken,
    /// `glitch` = Balken 3 flackert rot, `trend` = 0…1, wie weit die grüne Trendlinie gezeichnet ist.
    static func dashboard(heights: [Int], glitch: Bool = false, trend: Double = 0) -> Frame {
        var c = Array(repeating: Array(repeating: Character("."), count: 24), count: 20)
        func set(_ x: Int, _ y: Int, _ ch: Character) {
            if c.indices.contains(y), c[y].indices.contains(x) { c[y][x] = ch }
        }
        // Rahmen und dunkle Fläche
        for y in 0...16 { for x in 0...23 { set(x, y, (y == 0 || y == 16 || x == 0 || x == 23) ? "o" : "K") } }
        // Fuß
        for y in 17...18 { set(11, y, "o"); set(12, y, "o") }
        for x in 7...16 { set(x, 19, "o") }
        // Grundlinie
        for x in 2...21 { set(x, 14, "Z") }
        let colors: [Character] = ["B", "g", "3", "1"]
        for (i, h) in heights.prefix(4).enumerated() {
            let x0 = 3 + i * 5
            let color: Character = (i == 2 && glitch) ? "r" : colors[i]
            for y in stride(from: 13, to: 13 - min(h, 12), by: -1) { for x in x0...(x0 + 2) { set(x, y, color) } }
        }
        // Trendlinie von links unten nach rechts oben
        if trend > 0 {
            let points = [(2, 12), (7, 10), (12, 8), (17, 5), (21, 2)]
            let last = Int((Double(points.count - 1) * min(trend, 1)).rounded(.down))
            for i in 0..<max(last, 1) where i + 1 < points.count {
                let (x0, y0) = points[i], (x1, y1) = points[i + 1]
                let steps = max(abs(x1 - x0), abs(y1 - y0))
                for s in 0...steps {
                    set(x0 + (x1 - x0) * s / steps, y0 + (y1 - y0) * s / steps, "C")
                }
            }
        }
        return c.map { String($0) }
    }

    // MARK: - Prototyp

    /// Entwurf auf einer Staffelei (26 × 20): Kopfzeile, Bild, Textzeilen und ein Knopf.
    /// `elements` = wie viele Teile schon gezogen sind (0…4), `buttonOffset` = wie weit der Knopf
    /// noch aus der Flucht steht, `guide` = rosa Hilfslinie an der Fluchtkante.
    static func prototype(elements: Int, buttonOffset: Int = 0, guide: Bool = false) -> Frame {
        var c = Array(repeating: Array(repeating: Character("."), count: 26), count: 20)
        func fill(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ ch: Character) {
            for y in y0...y1 { for x in x0...x1 where c.indices.contains(y) && c[y].indices.contains(x) { c[y][x] = ch } }
        }
        // Weiße Leinwand mit hellgrauer Kante und Staffelei-Beinen
        fill(0, 25, 0, 16, "q")
        fill(1, 24, 1, 15, "w")
        fill(4, 5, 17, 19, "H"); fill(20, 21, 17, 19, "H")
        if elements >= 1 { fill(2, 23, 2, 3, "B") }                 // Kopfzeile
        if elements >= 2 { fill(3, 10, 6, 11, "4") }                // Bild
        if elements >= 3 { for y in [6, 8, 10] { fill(13, y == 10 ? 18 : 22, y, y, "Z") } } // Text
        if elements >= 4 { fill(15 + buttonOffset, 22 + buttonOffset, 13, 14, "g") }      // Knopf
        if guide { for y in stride(from: 5, through: 15, by: 2) { c[y][22] = "1" } }
        return c.map { String($0) }
    }
}
