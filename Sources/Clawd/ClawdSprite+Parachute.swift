import Foundation

/// Sanft landen: Regenschirm oder Ballon bremsen einen ungewollten Sturz. Requisiten in doppelter
/// Auflösung (mit `px / 2` zeichnen), Clawd-Frames normal (14 × 8, Blick nach rechts).
extension ClawdSprite {
    /// Am Griff hängen: vorderer Arm hoch (Spalte 12–13), Beine baumeln.
    static let hangFrames: [Frame] = [
        [
            "..XXXXXXXXXXXX",
            "..XXXEXXXXEXXX",
            "..XXXEXXXXEX..",
            "XXXXXXXXXXXX..",
            "XXXXXXXXXXXX..",
            "..XXXXXXXXXX..",
            "..X.X....X.X..",
            "...X.X....X.X.",
        ],
        [
            "..XXXXXXXXXXXX",
            "..XXXEXXXXEXXX",
            "..XXXEXXXXEX..",
            "XXXXXXXXXXXX..",
            "XXXXXXXXXXXX..",
            "..XXXXXXXXXX..",
            "..X.X....X.X..",
            "..X.X....X.X..",
        ],
    ]

    /// Erleichtert: Augen zu, steht wieder sicher.
    static let relieved: Frame = [
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..XEEXXXXEEX..",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        "..XXXXXXXXXX..",
        "..X.X....X.X..",
        "..X.X....X.X..",
    ]

    /// Erhobener Arm über dem Kopf (Halbraster, 4 breit), pro Zeile ½ px.
    static func raisedArm(rows: Int) -> Frame { Array(repeating: "XXXX", count: max(rows, 1)) }

    /// Regenschirm offen (32 × 23): rot-weiße Segmente mit dunkelroter Kontur und Rippen;
    /// Stock in Spalte 15–16, Griff-Haken unten (Zeile 21–22).
    static let umbrellaOpen: Frame = {
        var p = ParachutePixels(32, 23)
        let rows = [(14, 17), (10, 21), (7, 24), (5, 26), (3, 28), (2, 29), (1, 30)]
        p.fill(15, 0, 16, 0, "K") // Spitze
        for (i, r) in rows.enumerated() {
            let y = i + 1
            for x in r.0...r.1 { p.set(x, y, (x / 8) % 2 == 0 ? "u" : "w") }
            p.set(r.0, y, "j"); p.set(r.1, y, "j")
            if i == 0 { p.fill(r.0, y, r.1, y, "j") }
        }
        for x in [8, 16, 24] { p.fill(x, 3, x, 7, "j") } // Rippen
        for seg in 0..<4 {                                 // Saum: Bögen zwischen den Rippen
            for dx in 1...6 { p.set(seg * 8 + dx, 8, dx == 1 || dx == 6 ? "j" : (seg % 2 == 0 ? "u" : "w")) }
            p.fill(seg * 8 + 2, 9, seg * 8 + 5, 9, "j")
        }
        p.fill(15, 8, 16, 20, "K")
        p.handle()
        return p.frame
    }()

    /// Regenschirm halb geöffnet (beim Aufspannen und Zuklappen).
    static let umbrellaHalf: Frame = {
        var p = ParachutePixels(32, 23)
        let rows = [(14, 17), (12, 19), (11, 20), (11, 20), (10, 21), (10, 21), (11, 20), (12, 19)]
        p.fill(15, 0, 16, 0, "K")
        for (i, r) in rows.enumerated() {
            for x in r.0...r.1 { p.set(x, i + 1, (x / 3) % 2 == 0 ? "u" : "w") }
            p.set(r.0, i + 1, "j"); p.set(r.1, i + 1, "j")
        }
        p.fill(15, 9, 16, 20, "K")
        p.handle()
        return p.frame
    }()

    /// Ballon (14 × 30) in drei Größen beim Aufpusten (0 klein … 2 voll), Knoten in Zeile 13–14,
    /// Schnur bis Zeile 29 (Spalte 6–7).
    static func balloon(size: Int) -> Frame {
        var p = ParachutePixels(14, 30)
        let shapes: [[(Int, Int)]] = [
            [(5, 8), (4, 9), (4, 9), (5, 8)],
            [(4, 9), (2, 11), (1, 12), (1, 12), (1, 12), (2, 11), (3, 10), (5, 8)],
            [(4, 9), (2, 11), (1, 12), (0, 13), (0, 13), (0, 13), (0, 13), (1, 12), (1, 12), (2, 11), (3, 10), (4, 9), (5, 8)],
        ]
        let rows = shapes[min(max(size, 0), 2)]
        let top = 13 - rows.count
        for (i, r) in rows.enumerated() { p.fill(r.0, top + i, r.1, top + i, "u") }
        if size >= 2 { p.set(3, top + 2, "w"); p.set(4, top + 2, "w"); p.set(3, top + 3, "w"); p.set(2, top + 4, "w") } // Glanz
        p.set(6, 13, "j"); p.set(7, 13, "j"); p.set(6, 14, "j")                                                         // Knoten
        for y in 15..<30 { p.set(6 + (y / 4) % 2, y, "Z") }                                                             // Schnur
        return p.frame
    }

    /// Erleichterter Atemzug: Wölkchen vor dem Mund (5 × 4).
    static let sighPuff: Frame = ["..ZZ.", ".ZVVZ", "ZVVVZ", ".ZZZ."]
}

/// Raster mit kleinen Zeichenhilfen für Schirm und Ballon.
private struct ParachutePixels {
    var g: [[Character]]
    init(_ w: Int, _ h: Int) { g = Array(repeating: Array(repeating: Character("."), count: w), count: h) }
    mutating func set(_ x: Int, _ y: Int, _ ch: Character) {
        if g.indices.contains(y), g[y].indices.contains(x) { g[y][x] = ch }
    }
    mutating func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ ch: Character) {
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 { for x in x0...x1 { set(x, y, ch) } }
    }
    /// Brauner Griff-Haken unter dem Stock.
    mutating func handle() {
        fill(15, 21, 16, 22, "H"); fill(13, 22, 14, 22, "H"); fill(11, 21, 12, 21, "H")
    }
    var frame: ClawdSprite.Frame { g.map { String($0) } }
}
