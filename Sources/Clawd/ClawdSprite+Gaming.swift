import Foundation

/// Gaming-Requisiten. Clawd wird dabei von hinten gezeigt – man schaut ihm über die Schulter auf
/// den Bildschirm. Requisiten in doppelter Auflösung (mit `px / 2` zeichnen), Clawd-Frames normal.
extension ClawdSprite {
    // MARK: - Clawd von hinten

    /// Sitzend von hinten: Kopf, Schultern, angewinkelte Arme (nur die Ellbogen sind zu sehen).
    static let backSit: Frame = [
        "..............",
        "..............",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        ".XXXXXXXXXXXX.",
        "XXXXXXXXXXXXXX",
        "..XXXXXXXXXX..",
    ]

    /// Mitgehen: ganzer Körper eine Spalte nach links (−1) oder rechts (+1).
    static func backLean(_ dir: Int, _ frame: Frame = backSit) -> Frame {
        frame.map { row in
            dir < 0 ? String(row.dropFirst()) + "." : "." + String(row.dropLast())
        }
    }

    /// Enttäuscht zusammengesackt: eine Zeile tiefer, Arme hängen.
    static let backSag: Frame = [
        "..............",
        "..............",
        "..............",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "XXXXXXXXXXXXXX",
        "X.XXXXXXXXXX.X",
    ]

    /// Jubel von hinten: beide Arme hoch.
    static let backCheer: Frame = [
        "X............X",
        "X............X",
        "XXXXXXXXXXXXXX",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
    ]

    /// Headset von hinten dazu: Bügel über dem Kopf, Ohrmuscheln links und rechts.
    static func withHeadset(_ frame: Frame) -> Frame {
        var rows = frame.map(Array.init)
        // Oberste Kopfzeile: die erste Zeile, in der Spalte 5 zum Körper gehört.
        guard let top = rows.firstIndex(where: { $0[5] == "X" }) else { return frame }
        if top > 0 { for x in 3...10 { rows[top - 1][x] = "K" } }
        for y in top...min(top + 1, rows.count - 1) {
            let left = rows[y].firstIndex(of: "X") ?? 2, right = rows[y].lastIndex(of: "X") ?? 11
            if left > 0 { rows[y][left - 1] = "K" }
            if right < rows[y].count - 1 { rows[y][right + 1] = "K" }
        }
        return rows.map { String($0) }
    }

    // MARK: - Konsole

    /// Sideboard für den Fernseher (52 × 6).
    static let tvBench: Frame = ["n" + String(repeating: "n", count: 51), String(repeating: "H", count: 52)]
        + Array(repeating: ".H" + String(repeating: ".", count: 48) + "H.", count: 4)

    /// Vordere Kante des Sitzsacks (32 × 8) – liegt vor Clawd, er versinkt darin.
    static let beanbagFront: Frame = [
        "....444444444444444444444444....",
        "..4444444444444444444444444444..",
        ".444444444444444444444444444444.",
        "44444844444444444444444444484444",
        "44444444444444444444444444444444",
        "44444444444444444444444444444444",
        "77777777777777777777777777777777",
        ".777777777777777777777777777777.",
    ]

    /// Was gerade auf dem Fernseher passiert.
    enum TVScene {
        /// Die Figur läuft (`x` 0…1 über das Bild) und springt (`lift` in Zellen).
        case run(x: Double, lift: Int)
        /// In die Grube gefallen: Bild blinkt rot.
        case fail(blink: Bool)
        /// Ziel erreicht: Fahne, Sterne.
        case clear(stars: Int)
    }

    /// Großer Fernseher (48 × 32) mit Jump-'n'-Run: Wiese mit Grube, zwei Plattformen, Münzen.
    static func gamingTV(_ scene: TVScene) -> Frame {
        var p = GamingPixels(48, 32)
        p.fill(0, 0, 47, 27, "K")
        let flash: Bool = { if case .fail(let b) = scene { return b }; return false }()
        p.fill(1, 1, 46, 26, flash ? "u" : "z")
        p.fill(1, 21, 46, 26, "g")
        p.fill(22, 21, 25, 26, flash ? "u" : "z")                 // Grube
        p.fill(6, 15, 15, 16, "g"); p.fill(28, 11, 38, 12, "g")   // Plattformen
        p.fill(18, 4, 23, 5, "w"); p.fill(19, 3, 21, 3, "w"); p.fill(38, 5, 42, 5, "w") // Wolken
        p.set(45, 25, "C")                                        // Power-LED
        var heroX = 4
        var heroBottom = 20
        switch scene {
        case .run(let x, let lift):
            heroX = 3 + Int((x * 39).rounded())
            heroBottom = 20 - lift
        case .fail:
            heroX = 22
            heroBottom = 25
        case .clear(let stars):
            heroX = 40
            p.fill(43, 6, 43, 20, "o"); p.fill(44, 6, 46, 9, "u")  // Zielfahne
            for (i, (x, y)) in [(10, 6), (24, 9), (33, 4)].enumerated() where i < stars {
                p.set(x, y, "k"); p.set(x - 1, y + 1, "k"); p.set(x + 1, y + 1, "k"); p.set(x, y + 2, "k")
            }
        }
        // Münzen: verschwinden, sobald die Figur daran vorbei ist.
        for coin in [30, 33, 36] {
            let visible: Bool
            switch scene {
            case .run: visible = heroX + 2 < coin
            case .fail: visible = true
            case .clear: visible = false
            }
            if visible { p.fill(coin, 8, coin, 9, "k") }
        }
        // Spielfigur (4 × 5)
        p.paste([".uu.", "uuuu", "uuuu", ".uu.", "u..u"], at: heroX, heroBottom - 4)
        p.fill(20, 28, 27, 29, "J"); p.fill(12, 30, 35, 31, "K")  // Fuß
        return p.frame
    }

    // MARK: - PC

    /// Breiter Schreibtisch (48 × 14).
    static let gamingDesk: Frame = [String(repeating: "H", count: 48), String(repeating: "n", count: 48)]
        + Array(repeating: ".n" + String(repeating: ".", count: 44) + "n.", count: 12)

    /// Ausgang eines Gefechts auf dem Monitor.
    enum PCResult { case victory, defeat }

    /// Großer Monitor (44 × 30) mit Action-Szene: eigene Figur schießt auf einen Gegner.
    /// `shot` 0…1 = Flugweg des Schusses (nil = keiner), `health` 0…15 = eigener Lebensbalken.
    static func gamingMonitor(shot: Double?, enemyHit: Bool, health: Int, result: PCResult? = nil) -> Frame {
        var p = GamingPixels(44, 30)
        p.fill(0, 0, 43, 25, "o"); p.fill(1, 1, 42, 24, "K")
        p.fill(1, 18, 42, 24, "J"); p.fill(1, 17, 42, 17, "Z")
        for (x, y) in [(6, 6), (7, 5), (8, 6), (7, 7), (30, 4), (31, 5), (29, 5), (36, 9)] { p.set(x, y, "N") } // Sterne
        p.fill(3, 3, 3 + max(0, min(health, 15)), 3, health > 4 ? "C" : "u")
        p.fill(34, 2, 40, 2, "w")
        switch result {
        case .victory:
            // Pokal
            p.fill(17, 6, 26, 7, "k"); p.fill(18, 8, 25, 11, "k"); p.fill(16, 7, 16, 9, "k"); p.fill(27, 7, 27, 9, "k")
            p.fill(20, 12, 23, 13, "k"); p.fill(18, 14, 25, 15, "3")
        case .defeat:
            for i in 0..<8 { p.set(18 + i, 7 + i, "u"); p.set(19 + i, 7 + i, "u"); p.set(25 - i, 7 + i, "u"); p.set(26 - i, 7 + i, "u") }
        case nil:
            p.fill(10, 12, 12, 16, "B"); p.set(11, 11, "B")                        // eigene Figur
            if !enemyHit { p.fill(30, 13, 32, 16, "u"); p.set(31, 12, "u") }       // Gegner
            else { for (x, y) in [(30, 12), (32, 12), (31, 14), (29, 15), (33, 15)] { p.set(x, y, "k") } }
            if let s = shot {
                let x = 14 + Int((s * 14).rounded())
                p.fill(x, 14, x + 2, 14, "W"); p.set(x + 3, 14, "w")
            }
        }
        p.fill(19, 26, 24, 27, "o"); p.fill(13, 28, 30, 29, "o")
        return p.frame
    }

    /// PC-Tower (10 × 22); der RGB-Streifen wechselt mit `phase` die Farben.
    static func gamingTower(phase: Int) -> Frame {
        var p = GamingPixels(10, 22)
        p.fill(0, 0, 9, 20, "o"); p.fill(1, 1, 8, 19, "K"); p.fill(2, 2, 7, 2, "q")
        let colors: [Character] = ["M", "W", "C", "k", "B", "u"]
        for i in 0..<8 { p.set(2, 4 + i, colors[(i / 2 + phase) % colors.count]) }
        p.fill(4, 13, 5, 15, "J"); p.fill(3, 14, 6, 14, "J"); p.set(7, 18, "C")
        p.set(1, 21, "o"); p.set(8, 21, "o")
        return p.frame
    }

    /// Tastatur (24 × 3) mit umlaufender RGB-Beleuchtung.
    static func gamingKeyboard(phase: Int) -> Frame {
        let colors: [Character] = ["u", "k", "C", "B", "4", "M"]
        let keys = String((0..<22).map { colors[($0 / 4 + phase) % colors.count] })
        return [String(repeating: "K", count: 24), "K" + keys + "K", String(repeating: "K", count: 24)]
    }

    /// Vorderteil des Gaming-Stuhls (32 × 10): Sitzfläche, Säule, Fuß mit Rollen – liegt vor Clawd.
    static let chairFront: Frame = [
        "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK",
        "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK",
        ".JJJJJJJJJJJJJJJJJJJJJJJJJJJJJJ.",
        "..............JJJJ..............",
        "..............JJJJ..............",
        "..............JJJJ..............",
        "..............JJJJ..............",
        "....JJJJJJJJJJJJJJJJJJJJJJJJ....",
        "...J..........JJJJ..........J...",
        "...K........................K...",
    ]
}

/// Raster mit kleinen Zeichenhilfen für die Gaming-Requisiten.
private struct GamingPixels {
    var g: [[Character]]
    init(_ w: Int, _ h: Int) { g = Array(repeating: Array(repeating: Character("."), count: w), count: h) }
    mutating func set(_ x: Int, _ y: Int, _ ch: Character) {
        if g.indices.contains(y), g[y].indices.contains(x) { g[y][x] = ch }
    }
    mutating func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ ch: Character) {
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 { for x in x0...x1 { set(x, y, ch) } }
    }
    mutating func paste(_ f: ClawdSprite.Frame, at ox: Int, _ oy: Int) {
        for (y, row) in f.enumerated() { for (x, ch) in row.enumerated() where ch != "." { set(ox + x, oy + y, ch) } }
    }
    var frame: ClawdSprite.Frame { g.map { String($0) } }
}
