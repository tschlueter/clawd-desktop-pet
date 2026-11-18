import AppKit

/// Clawd als Pixel-Raster. Zeichen → Farbe siehe `palette`, "." = transparent.
/// Alle Clawd-Frames sind 14×8 und schauen nach rechts (für links wird gespiegelt).
enum ClawdSprite {
    typealias Frame = [String]

    private static let empty: Frame = [".............."]
    private static let head: Frame = ["..XXXXXXXXXX.."]

    private static let eyesOpen: Frame = [
        "..XXEXXXXEXX..",
        "..XXEXXXXEXX..",
    ]
    private static let eyesClosed: Frame = [
        "..XXXXXXXXXX..",
        "..XXEXXXXEXX..",
    ]
    private static let eyesSleep: Frame = [
        "..XXXXXXXXXX..",
        "..XEEXXXXEEX..",
    ]
    /// Glücklich zugekniffen: ^ ^
    private static let eyesHappy: Frame = [
        "..XXEXXXXEXX..",
        "..XEXEXXEXEX..",
    ]
    private static let eyesForward: Frame = [
        "..XXXEXXXXEX..",
        "..XXXEXXXXEX..",
    ]
    private static let eyesBack: Frame = [
        "..XEXXXXEXXX..",
        "..XEXXXXEXXX..",
    ]

    private static let torso: Frame = [
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        "..XXXXXXXXXX..",
    ]
    private static let torsoNoFrontArm: Frame = [
        "XXXXXXXXXXXX..",
        "XXXXXXXXXXXX..",
        "..XXXXXXXXXX..",
    ]
    private static let torsoNoArms: Frame = [
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
    ]
    /// Tippen: ein Arm unten auf der Tastatur, der andere oben.
    private static let torsoTypeA: Frame = [
        "XXXXXXXXXXXX..",
        "XXXXXXXXXXXXXX",
        "..XXXXXXXXXXXX",
    ]
    private static let torsoTypeB: Frame = [
        "..XXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXX..",
    ]

    private static let legsStand: Frame = [
        "..X.X....X.X..",
        "..X.X....X.X..",
    ]
    /// Beine 1 und 3 angehoben.
    private static let legsStepA: Frame = [
        "..X.X....X.X..",
        "....X......X..",
    ]
    /// Beine 2 und 4 angehoben.
    private static let legsStepB: Frame = [
        "..X.X....X.X..",
        "..X......X....",
    ]

    // MARK: - Frames

    /// Pixel Laufweg pro Animationsbild bei Pixelgröße 4.
    static let stepLength: CGFloat = 6

    /// Laufbild nach zurückgelegter Strecke; `stride` > 1 = längere Schritte.
    static func walkFrame(walked: CGFloat, px: CGFloat, stride: CGFloat = 1, lookingBack: Bool = false) -> Frame {
        let cycle = lookingBack ? walkLookingBack : walkCycle
        let step = stepLength * stride * px / 4
        return cycle[Int(walked / step) % cycle.count]
    }

    static let stand: Frame = head + eyesOpen + torso + legsStand
    static let blink: Frame = head + eyesClosed + torso + legsStand

    /// Laufzyklus: Stand → Schritt A → Stand → Schritt B.
    static let walkCycle: [Frame] = [
        stand,
        head + eyesOpen + torso + legsStepA,
        stand,
        head + eyesOpen + torso + legsStepB,
    ]

    /// Umschauen: geradeaus → nach vorn → geradeaus → zurück.
    static let lookCycle: [Frame] = [
        stand,
        head + eyesForward + torso + legsStand,
        stand,
        head + eyesBack + torso + legsStand,
    ]

    /// Beim Aufprall zusammengestaucht: Körper eine Reihe tiefer, Beine kurz.
    static let squash: Frame = empty + head + eyesClosed + torso + ["..X.X....X.X.."]

    /// Sitzen: Beine eingezogen.
    static let sit: Frame = empty + empty + head + eyesOpen + torso
    static let sitBlink: Frame = empty + empty + head + eyesClosed + torso
    static let sleep: Frame = empty + empty + head + eyesSleep + torso

    /// Coden: sitzt hinter dem Laptop und tippt abwechselnd mit beiden Armen.
    static let codeIdle: Frame = sit
    static let codeType: [Frame] = [
        empty + empty + head + eyesOpen + torsoTypeA,
        empty + empty + head + eyesOpen + torsoTypeB,
    ]

    /// Musik hören: sitzen; beim Mitwippen glücklich und im Takt eine Reihe tiefer.
    static let musicListen: Frame = sit
    static let musicGroove: [Frame] = [
        empty + empty + head + eyesHappy + torso,
        empty + empty + empty + head + eyesHappy + ["XXXXXXXXXXXXXX", "..XXXXXXXXXX.."],
    ]

    /// Winken mit dem vorderen Arm (ganz hoch ↔ halb hoch).
    static let wave: [Frame] = [
        ["..XXXXXXXXXXXX", "..XXEXXXXEXXXX", "..XXEXXXXEXX.."] + torsoNoFrontArm + legsStand,
        head + ["..XXEXXXXEXXXX", "..XXEXXXXEXXXX"] + torsoNoFrontArm + legsStand,
    ]

    /// Fallen: beide Arme hochgerissen.
    static let flail: Frame = ["XXXXXXXXXXXXXX", "XXXXEXXXXEXXXX", "..XXEXXXXEXX.."] + torsoNoArms + legsStand

    // MARK: - In Deckung (Vollbild)

    /// Ganz klein gemacht: in der Hocke, die Arme (dunkler) um die Beine geschlungen.
    private static func cover(eyes: Frame) -> Frame {
        empty + empty + empty + head + eyes + [".xXXXXXXXXXXx.", "..xxxxxxxxxx.."]
    }
    /// Augen fest zugekniffen.
    static let coverHide: Frame = cover(eyes: ["..XEXXXXXXEX..", "..XXEEXXEEXX.."])
    /// Vorsichtig umschauen, die Beine noch umklammert: geradeaus → nach vorn → geradeaus → zurück.
    static let coverPeek: [Frame] = [
        cover(eyes: eyesOpen),
        cover(eyes: eyesForward),
        cover(eyes: eyesOpen),
        cover(eyes: eyesBack),
    ]

    /// Ablauf nach einem Vollbild: `sinceRelease` = Sekunden, seit der Bildschirm wieder frei ist
    /// (nil = noch in Deckung). Erst regungslos, dann umschauen, Beine loslassen, aufstehen.
    static let coverFreeze: TimeInterval = 2
    static let coverLookStep: TimeInterval = 0.6
    static let coverArmsDown: TimeInterval = 0.4
    static let coverStandUp: TimeInterval = 0.35
    static var coverDuration: TimeInterval {
        coverFreeze + coverLookStep * Double(coverPeek.count) + coverArmsDown + coverStandUp
    }

    static func coverFrame(sinceRelease t: TimeInterval?) -> Frame {
        guard var t else { return coverHide }
        if t < coverFreeze { return coverHide }
        t -= coverFreeze
        let look = coverLookStep * Double(coverPeek.count)
        if t < look { return coverPeek[Int(t / coverLookStep)] }
        t -= look
        return t < coverArmsDown ? sit : stand
    }

    // MARK: - Begegnungen

    /// Glücklich stehen (^ ^).
    static let happyStand: Frame = head + eyesHappy + torso + legsStand
    /// Umarmen: zusammengekuschelt, Augen glücklich zu.
    static let hugFrame: Frame = empty + head + eyesHappy + torso + ["..X.X....X.X.."]
    /// Laufen und dabei nach hinten schauen (zum Zusammenstoßen).
    static let walkLookingBack: [Frame] = [
        head + eyesBack + torso + legsStand,
        head + eyesBack + torso + legsStepA,
        head + eyesBack + torso + legsStand,
        head + eyesBack + torso + legsStepB,
    ]
    /// Ducken (Bocksprung): Beine eingezogen.
    static let duck: Frame = sit

    static let speechBubble: Frame = [
        ".ooooo.",
        "owwwwwo",
        "owowowo",
        "owwwwwo",
        ".ooooo.",
        ".o.....",
    ]
    static let star: Frame = [
        "..k..",
        "..k..",
        "kk.kk",
        "..k..",
        "..k..",
    ]
    static let heartGlyph: Frame = [
        ".r.r.",
        "rrrrr",
        ".rrr.",
        "..r..",
    ]

    // MARK: - Abgestürzt & wütend

    /// Benommen hingefallen: zusammengesackt; die (kleinen) X-Augen kommen als feine
    /// Requisite in doppelter Auflösung dazu (`dizzyEyes`).
    static let dizzy: Frame = [
        "..............",
        "..............",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "XXXXXXXXXXXXXX",
        "..XXXXXXXXXX..",
    ]

    /// Kleine X-Augen (je 3×3 Halbpixel) passend zu `dizzy`.
    static let dizzyEyes: Frame = {
        var c = HiResCanvas()
        for x0 in [12, 22] {
            c.set(x0, 14, "E"); c.set(x0 + 2, 14, "E")
            c.set(x0 + 1, 15, "E")
            c.set(x0, 16, "E"); c.set(x0 + 2, 16, "E")
        }
        return c.frame
    }()

    /// Wütend: schräge Brauen (innen tief).
    private static let eyesAngry: Frame = [
        "..XEXXXXXXEX..",
        "..XXEXXXXEXX..",
    ]
    static let angryStand: Frame = head + eyesAngry + torso + legsStand
    /// Faust schütteln: vorderer Arm oben bzw. halb oben, böser Blick.
    static let scold: [Frame] = [
        ["..XXXXXXXXXXXX", "..XEXXXXXXEXXX", "..XXEXXXXEXX.."] + torsoNoFrontArm + legsStand,
        head + ["..XEXXXXXXEX..", "..XXEXXXXEXXXX"] + torsoNoFrontArm + legsStand,
    ]

    /// Sprechblase mit Comic-Flüchen (Grawlix): ohne Rand, wird mit Schatten gezeigt (`bubbleHasShadow`).
    static let curseBubble: Frame = [
        ".wwwwwwwww.",
        "wwwwwwwwwww",
        "wwrwrwkwrww",
        "wwwrwkkwrww",
        "wwrwrwkwwww",
        "wwwwwwwwrww",
        ".wwwwwwwww.",
        ".w.........",
    ]

    /// Sprechblasen ohne Rand heben sich nur durch einen Schatten vom Hintergrund ab.
    static func bubbleHasShadow(_ bubble: Frame) -> Bool { bubble == curseBubble }

    /// Vögelchen (zwei Flügelstellungen), kreisen über dem Kopf.
    static let birdFrames: [Frame] = [
        ["y.y", ".y."],
        [".y.", "y.y"],
    ]

    // MARK: - Niesen & Gähnen

    /// Niesen, Anlauf: Augen zusammengekniffen.
    static let sneezeBuild: Frame = head + eyesSleep + torso + legsStand
    /// "TSCHIII!": nach vorn zusammengestaucht, Augen fest zu.
    static let sneezeBlast: Frame = empty + head + eyesSleep + torso + ["..X.X....X.X.."]

    /// Gähnen: beide Arme senkrecht nach oben gestreckt (Hände über dem Kopf), Augen zu –
    /// erst Mund zu, dann offen.
    private static let armsStraightUpEyesClosed: Frame = [".X..........X.", ".XXXXXXXXXXXX.", "..XEEXXXXEEX.."]
    static let yawnStretch: Frame = armsStraightUpEyesClosed + torsoNoArms + legsStand
    static let yawnMouth: Frame = armsStraightUpEyesClosed + [
        "..XXXXEEXXXX..",
        "..XXXXEEXXXX..",
        "..XXXXXXXXXX..",
    ] + legsStand

    /// Zappeln, während Clawd gehalten wird.
    static let wriggle: [Frame] = [
        head + eyesOpen + torso + legsStepA,
        head + eyesOpen + torso + legsStepB,
    ]

    // MARK: - Sport (80er-Jahre)

    /// Bizeps-Curls mit der Langhantel: Arme unten (Hüfte) → Mitte → oben (Brust).
    static let curlDown: Frame = head + eyesOpen + [
        "..XXXXXXXXXX..",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
    ] + legsStand
    static let curlMid: Frame = stand
    static let curlUp: Frame = head + [
        "..XXEXXXXEXX..",
        "XXXEXEXXEXEXXX", // ^ ^ vor Anstrengung, Arme hochgezogen
        "XXXXXXXXXXXXXX",
        "..XXXXXXXXXX..",
        "..XXXXXXXXXX..",
    ] + legsStand
    /// Zeile (im Sprite) der Hantelstange für Curl-Stellung 0 (unten) … 2 (oben).
    static let curlBarRow = [5, 4, 3]
    static let curlFrames = [curlDown, curlMid, curlUp]

    /// Seilspringen: Beine beim Sprung leicht angezogen.
    static let ropeJump: Frame = head + eyesOpen + torso + ["..X.X....X.X..", ".............."]

    private static var sportyCache: [String: Frame] = [:]

    /// Zieht Clawd das 80er-Outfit an: Stirnband (oberste Kopfzeile), Schweißbänder an den
    /// Armenden, Stulpen an den Beinen.
    static func sporty(_ frame: Frame) -> Frame {
        let key = frame.joined(separator: "|")
        if let cached = sportyCache[key] { return cached }
        let head = headRow(frame)
        var rows = frame.map { Array($0) }
        for r in rows.indices {
            for c in rows[r].indices where rows[r][c] == "X" {
                if r == head, (2...11).contains(c) {
                    rows[r][c] = "M"
                } else if c == 0 || c == columns - 1 {
                    rows[r][c] = "W"
                }
            }
        }
        // Unterste Zeile mit Lücken = Beine → Stulpen.
        if let last = rows.indices.last, rows[last].filter({ $0 == "X" }).count <= 6 {
            rows[last] = rows[last].map { $0 == "X" ? "L" : $0 }
        }
        let result = rows.map { String($0) }
        sportyCache[key] = result
        return result
    }

    private static var bootsCache: [String: Frame] = [:]

    /// Magnetschuhe: unterste Beinzeile rot.
    /// `color`: Farbzeichen der Schuhe ("u" rot; beim Anziehen eines Fensters blinkend heller).
    static func withBoots(_ frame: Frame, color: Character = "u") -> Frame {
        let key = String(color) + frame.joined(separator: "|")
        if let cached = bootsCache[key] { return cached }
        var rows = frame
        if let last = rows.indices.last {
            let count = rows[last].filter { $0 != "." }.count
            if count > 0, count <= 6 {
                rows[last] = String(rows[last].map { $0 == "." ? "." : color })
            }
        }
        bootsCache[key] = rows
        return rows
    }

    /// Requisiten-Raster für Sport: 18×11, Clawd steht darin bei Spalten 2…15, Zeilen 3…10.
    static let propColumns = 18
    static let propRows = 11

    private static func propGrid(_ draw: (inout [[Character]]) -> Void) -> Frame {
        var g = Array(repeating: Array(repeating: Character("."), count: propColumns), count: propRows)
        draw(&g)
        return g.map { String($0) }
    }

    /// Langhantel vor dem Körper: Stange quer, große Gewichtsscheiben außen neben den Händen.
    /// `spriteRow` = Zeile im Clawd-Sprite, auf der die Stange liegt.
    static func barbell(spriteRow: Int) -> Frame {
        propGrid { g in
            let r = spriteRow + 3 // Sprite-Zeile → Rasterzeile
            for c in 2...15 { g[r][c] = "G" }
            // Schwere Scheiben: 5 hoch, mit hellerem Rand innen (Tiefe).
            for dr in -2...2 where g.indices.contains(r + dr) {
                g[r + dr][0] = "K"; g[r + dr][17] = "K"
                g[r + dr][1] = abs(dr) == 2 ? "K" : "J"
                g[r + dr][16] = abs(dr) == 2 ? "K" : "J"
            }
        }
    }

    /// Springseil in vier Phasen. `lift` = wie viele Pixel Clawd gerade hochgesprungen ist.
    /// Doppelte Auflösung (36×22), damit das Seil nur einen halben Pixel dick ist.
    enum RopePhase: CaseIterable { case over, front, under, behind }

    static func rope(_ phase: RopePhase, lift: Int) -> Frame {
        let cols = propColumns * 2, rows = propRows * 2
        var g = Array(repeating: Array(repeating: Character("."), count: cols), count: rows)
        func line(_ a: (Int, Int), _ b: (Int, Int)) { // Bresenham, (Spalte, Zeile)
            var (x0, y0) = a
            let (x1, y1) = b
            let dx = abs(x1 - x0), dy = -abs(y1 - y0)
            let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
            var err = dx + dy
            while true {
                if g.indices.contains(y0), g[y0].indices.contains(x0) { g[y0][x0] = "R" }
                if x0 == x1 && y0 == y1 { break }
                let e2 = 2 * err
                if e2 >= dy { err += dy; x0 += sx }
                if e2 <= dx { err += dx; y0 += sy }
            }
        }
        func path(_ points: [(Int, Int)]) {
            for (a, b) in zip(points, points.dropFirst()) { line(a, b) }
        }
        let hand = 2 * (6 - lift) + 1 // Halbpixel-Zeile der Hände
        let (l, r) = (3, cols - 4)    // direkt außen neben den Händen
        switch phase {
        case .over:
            path([(l, hand), (l, 6), (6, 2), (10, 1), (cols - 11, 1), (cols - 7, 2), (r, 6), (r, hand)])
        case .under:
            path([(l, hand), (l, rows - 5), (6, rows - 2), (10, rows - 1), (cols - 11, rows - 1),
                  (cols - 7, rows - 2), (r, rows - 5), (r, hand)])
        case .front:
            path([(l, hand), (6, hand + 4), (cols - 7, hand + 4), (r, hand)])
        case .behind:
            path([(l, hand - 1), (l, hand + 2)])
            path([(r, hand - 1), (r, hand + 2)])
        }
        return g.map { String($0) }
    }

    /// Zeichenfläche in doppelter Auflösung (36×22) für feine Requisiten.
    struct HiResCanvas {
        static let cols = 36, rows = 22
        var g = Array(repeating: Array(repeating: Character("."), count: cols), count: rows)

        mutating func set(_ x: Int, _ y: Int, _ ch: Character) {
            if g.indices.contains(y), g[y].indices.contains(x) { g[y][x] = ch }
        }

        mutating func hline(_ x0: Int, _ x1: Int, _ y: Int, _ ch: Character) {
            for x in x0...x1 { set(x, y, ch) }
        }

        /// Bresenham-Linie von a nach b (Spalte, Zeile).
        mutating func line(_ a: (Int, Int), _ b: (Int, Int), _ ch: Character) {
            var (x0, y0) = a
            let (x1, y1) = b
            let dx = abs(x1 - x0), dy = -abs(y1 - y0)
            let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
            var err = dx + dy
            while true {
                set(x0, y0, ch)
                if x0 == x1 && y0 == y1 { break }
                let e2 = 2 * err
                if e2 >= dy { err += dy; x0 += sx }
                if e2 <= dx { err += dx; y0 += sy }
            }
        }

        /// Ellipse mit Rand `edge` und Füllung `fill`.
        mutating func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, edge: Character, fill: Character) {
            for y in 0..<Self.rows {
                for x in 0..<Self.cols {
                    let d = pow((Double(x) - cx) / rx, 2) + pow((Double(y) - cy) / ry, 2)
                    if d <= 1 {
                        let inner = pow((Double(x) - cx) / max(rx - 1, 0.5), 2) + pow((Double(y) - cy) / max(ry - 1, 0.5), 2)
                        set(x, y, inner <= 1 ? fill : edge)
                    }
                }
            }
        }

        var frame: Frame { g.map { String($0) } }
    }

    // MARK: - Essen (Nudelschüssel, Stäbchen)

    enum EatPose { case dip, lift, slurp, chew }

    /// Schüssel vor dem Bauch (sitzend), Nudelstand 0…4, Stäbchen in der vorderen Hand.
    /// Schaut nach rechts; für links spiegelt der Node das ganze Bild.
    static func noodleBowl(level: Int, pose: EatPose, slurpStep: Int = 0) -> Frame {
        var c = HiResCanvas()
        // Nudeln (zwischen den Augen frei lassen)
        if level >= 1 { c.hline(9, 26, 17, "Y") }
        if level >= 2 { c.hline(10, 25, 16, "Y") }
        if level >= 3 { for x in stride(from: 14, through: 21, by: 1) where x % 2 == 0 { c.set(x, 15, "Y") } }
        if level >= 4 { for x in [15, 17, 19] { c.set(x, 14, "Y") } }
        // Schüssel: cremefarbener Rand, roter Körper, Fuß
        c.hline(7, 28, 18, "U")
        c.hline(8, 27, 19, "u")
        c.hline(9, 26, 20, "u")
        c.hline(11, 24, 21, "u")
        // Stäbchen aus der Hand (rechts, ca. Spalte 30, Zeile 16)
        switch pose {
        case .dip:
            c.line((30, 16), (21, 17), "H"); c.line((31, 17), (22, 18), "H")
        case .lift:
            c.line((30, 16), (20, 8), "H"); c.line((31, 16), (21, 8), "H")
            // Nudelstrang hängt von den Stäbchen herab
            c.line((18, 9), (17, 12), "Y"); c.line((17, 12), (18, 15), "Y")
            c.line((20, 9), (21, 12), "Y"); c.line((21, 12), (20, 15), "Y")
        case .slurp:
            c.line((30, 16), (21, 15), "H"); c.line((30, 17), (22, 16), "H")
            let length = max(2 - slurpStep, 0)
            if length > 0 {
                c.line((18, 16), (18, 16 + length), "Y")
                c.line((19, 16), (19, 15 + length), "Y")
            }
        case .chew:
            c.line((30, 17), (24, 19), "H"); c.line((30, 18), (25, 20), "H")
        }
        return c.frame
    }

    static let steamGlyph: Frame = [
        "V.",
        ".V",
        "V.",
        ".V",
    ]

    // MARK: - Putzen (Besen, Kehrblech, Staub)

    /// Besen in der vorderen Hand (stehend), Borsten vorne bzw. hinten am Boden.
    static func broom(forward: Bool) -> Frame {
        var c = HiResCanvas()
        if forward {
            c.line((30, 12), (33, 18), "H")
            c.hline(32, 34, 19, "b"); c.hline(31, 35, 20, "b"); c.hline(31, 35, 21, "b")
        } else {
            c.line((30, 12), (29, 18), "H")
            c.hline(28, 30, 19, "b"); c.hline(27, 31, 20, "b"); c.hline(27, 31, 21, "b")
        }
        return c.frame
    }

    enum DustpanPose { case ground, carry, tilt }

    /// Kehrblech: am Boden (zum Aufschaufeln), getragen (evtl. mit Staub) oder gekippt.
    static func dustpan(_ pose: DustpanPose, full: Bool) -> Frame {
        var c = HiResCanvas()
        switch pose {
        case .ground:
            c.line((31, 13), (32, 18), "h")
            c.hline(29, 35, 21, "u"); c.set(35, 20, "u"); c.set(35, 19, "u"); c.set(34, 20, "u")
            if full { c.hline(31, 34, 20, "D") }
        case .carry:
            c.line((30, 13), (31, 14), "h")
            c.hline(31, 35, 15, "u"); c.set(35, 14, "u"); c.set(35, 13, "u")
            if full { c.hline(32, 34, 14, "D"); c.set(33, 13, "D") }
        case .tilt:
            c.line((30, 13), (31, 14), "h")
            c.line((31, 15), (35, 19), "u"); c.line((32, 15), (35, 18), "u")
            if full { c.set(34, 17, "D"); c.set(35, 20, "D") }
        }
        return c.frame
    }

    /// Staubhaufen in drei Größen (vor dem Besen am Boden).
    static let dustPiles: [Frame] = [
        ["DD"],
        [".DD.", "DDDD"],
        ["..DD..", ".DDDD.", "DDDDDD"],
    ]

    static let dustGlyph: Frame = ["DD", "DD"]

    // MARK: - Arbeiten: Putzen & Pflege

    /// Schwamm vorne am Boden (gelb mit grüner Scheuerseite), vor- bzw. zurückgewischt.
    static func sponge(forward: Bool) -> Frame {
        var c = HiResCanvas()
        let x0 = forward ? 31 : 27
        c.hline(x0, x0 + 4, 18, "g")
        c.hline(x0, x0 + 4, 19, "y"); c.hline(x0, x0 + 4, 20, "y"); c.hline(x0, x0 + 4, 21, "y")
        return c.frame
    }

    /// Putztuch vorne am Boden (sitzend), hin und her gerieben.
    static func cloth(forward: Bool) -> Frame {
        var c = HiResCanvas()
        let x0 = forward ? 30 : 26
        c.hline(x0 + 1, x0 + 4, 20, "z"); c.hline(x0, x0 + 5, 21, "z")
        c.set(x0 + 2, 19, "z")
        return c.frame
    }

    /// Voller Müllsack mit Knoten.
    static let trashBag: Frame = [
        "..K..",
        ".KJK.",
        "KKKKK",
        "KKKKK",
        ".KKK.",
    ]

    /// Gießkanne in der vorderen Hand; gekippt = Wasser läuft.
    static func wateringCan(tilted: Bool) -> Frame {
        var c = HiResCanvas()
        c.line((30, 13), (31, 13), "h")
        if tilted {
            c.hline(31, 34, 12, "v"); c.hline(31, 34, 13, "v"); c.hline(32, 35, 14, "v"); c.hline(32, 35, 15, "v")
            c.line((35, 15), (35, 18), "v")
        } else {
            c.hline(31, 34, 12, "v"); c.hline(31, 34, 13, "v"); c.hline(31, 34, 14, "v"); c.hline(31, 34, 15, "v")
            c.line((34, 13), (35, 11), "v")
        }
        return c.frame
    }

    /// Topfpflanze in fünf Wachstumsstufen (Keimling → Blüte).
    static let plantStages: [Frame] = [
        ["..g..", "ttttt", ".ttt."],
        [".g.g.", "..g..", "ttttt", ".ttt."],
        ["g.g.g", ".ggg.", "..g..", "..g..", "ttttt", ".ttt."],
        ["..f..", "g.g.g", ".ggg.", "..g..", "..g..", "ttttt", ".ttt."],
        [".fff.", "ffYff", ".fff.", "g.g.g", ".ggg.", "..g..", "ttttt", ".ttt."],
    ]

    static let sparkleGlyph: Frame = [
        ".k.",
        "kkk",
        ".k.",
    ]

    // MARK: - Arbeiten: Handwerk

    /// Gelber Bauhelm (Variante D): halbrunde Kuppel mit drei Rippen, Krempe und Glanzpunkt.
    /// Doppelte Auflösung (28 breit, 10 hoch); die Krempe liegt auf der obersten Kopfzeile.
    static let hardHat: Frame = {
        var rows: [[Character]] = Array(repeating: Array(repeating: ".", count: 28), count: 10)
        func inDome(_ x: Int, _ y: Int) -> Bool {
            let dx = Double(x) + 0.5 - 14, dy = Double(y) + 0.5 - 1
            return dx * dx + dy * dy <= 81
        }
        for y in -8...0 {
            for x in 0..<28 where inDome(x, y) { rows[y + 8][x] = "y" }
            for rib in [9, 14, 19] where inDome(rib, y) { rows[y + 8][rib] = "5" }
        }
        for x in 3..<25 { rows[9][x] = "5" }                      // Krempe
        for (x, y) in [(8, -5), (9, -6), (8, -4)] { rows[y + 8][x] = "6" } // Glanzpunkt
        return rows.map { String($0) }
    }()

    /// Hammer in der vorderen Hand (sitzend), oben ausgeholt oder unten aufgeschlagen,
    /// davor ein Nagel, der mit jedem Schlag tiefer sitzt (Höhe 0…2).
    static func hammer(down: Bool, nail: Int) -> Frame {
        var c = HiResCanvas()
        for y in stride(from: 21, to: 21 - nail, by: -1) { c.set(34, y, "G") }
        if down {
            c.line((31, 17), (33, 19), "H")
            c.hline(33, 35, 19 - max(nail, 0), "K"); c.hline(33, 35, 20 - max(nail, 0), "K")
        } else {
            c.line((31, 17), (32, 12), "H")
            c.hline(31, 34, 10, "K"); c.hline(31, 34, 11, "K")
        }
        return c.frame
    }

    /// Pinsel in der vorderen Hand (stehend), Borsten in Farbe `paint` ("1"…"4") tupfen
    /// abwechselnd vor und zurück auf die Kante.
    static func paintBrush(dab: Bool, paint: Character) -> Frame {
        var c = HiResCanvas()
        let tip = dab ? 34 : 32
        c.line((31, 13), (tip - 1, 17), "H")
        c.hline(tip - 1, tip, 18, "G")
        c.hline(tip - 1, tip, 19, paint); c.hline(tip - 1, tip, 20, paint); c.set(tip, 21, paint)
        return c.frame
    }

    /// Umzugskarton mit Klebeband.
    static let box: Frame = [
        "nnUUnn",
        "nnUUnn",
        "nnnnnn",
        "nnnnnn",
        "nnnnnn",
    ]

    /// Schraubenzieher (hockend), Griff verdreht sich; Schraubenkopf am Boden.
    static func screwdriver(twist: Bool) -> Frame {
        var c = HiResCanvas()
        c.line((31, 16), (33, 18), "u"); c.line((31, 17), (33, 19), "u")
        if twist { c.set(32, 16, "u") } else { c.set(30, 18, "u") }
        c.line((34, 19), (34, 20), "G")
        c.hline(33, 35, 21, "K")
        c.set(twist ? 33 : 35, 20, "K")
        return c.frame
    }

    // MARK: - Arbeiten: Programmierer-Jobs

    /// Käfer (Bug) mit zappelnden Beinchen.
    static let bugFrames: [Frame] = [
        [".uu.", "uKKu", "K..K"],
        [".uu.", "uKKu", ".KK."],
    ]

    /// Kescher: ausgeholt (oben hinten) oder zugeschlagen (vorne am Boden), evtl. mit Käfer drin.
    static func net(swing: Bool, caught: Bool) -> Frame {
        var c = HiResCanvas()
        if swing {
            c.line((31, 13), (33, 17), "h")
            c.ellipse(cx: 34, cy: 19.5, rx: 1.6, ry: 2.2, edge: "o", fill: caught ? "u" : ".")
        } else {
            c.line((30, 13), (28, 7), "h")
            c.ellipse(cx: 27, cy: 4, rx: 2.6, ry: 2.2, edge: "o", fill: caught ? "u" : ".")
        }
        return c.frame
    }

    /// Lesen im Sitzen (Blick nach vorn) und Nicken (Kopf eine Reihe tiefer).
    static let sitRead: Frame = empty + empty + head + eyesForward + torso
    static let sitNod: Frame = empty + empty + empty + head + eyesForward + ["XXXXXXXXXXXXXX", "..XXXXXXXXXX.."]

    /// Papierrolle mit Code, der nach oben scrollt (`scroll` verschiebt die Zeilen);
    /// `marks` = Zeilen (0…4) mit rotem Korrekturstrich.
    static func codeScroll(scroll: Int, marks: Set<Int>) -> Frame {
        var c = HiResCanvas()
        for y in 8...19 { c.hline(24, 33, y, "w") }
        c.line((24, 8), (24, 19), "o"); c.line((33, 8), (33, 19), "o")
        c.hline(23, 34, 7, "U"); c.hline(23, 34, 20, "U")
        // Dunkle Kontur um die Rollen, damit sie auch auf weißem Hintergrund erkennbar sind.
        c.hline(23, 34, 6, "o"); c.hline(23, 34, 21, "o")
        for y in [7, 20] { c.set(22, y, "o"); c.set(35, y, "o") }
        let lines: [(Int, Int, Character)] = [(26, 31, "B"), (27, 32, "C"), (26, 29, "Z"), (28, 32, "N"), (26, 30, "C"), (27, 31, "Z")]
        for i in 0..<5 {
            let (x0, x1, color) = lines[(i + scroll) % lines.count]
            let y = 9 + i * 2
            c.hline(x0, x1, y, color)
            if marks.contains(i) { c.set(32, y, "r"); c.set(25, y, "r") }
        }
        return c.frame
    }

    /// Server-Rack vor Clawd: `green` von 6 LEDs leuchten grün, die übrigen blinken rot;
    /// beim Einstecken führt ein Kabel von der Hand zum Rack.
    static func serverRack(green: Int, blinkOn: Bool, plugging: Bool) -> Frame {
        var c = HiResCanvas()
        for y in 2...21 { c.hline(28, 35, y, "K") }
        for slot in 0..<3 {
            let y0 = 4 + slot * 6
            for y in y0...(y0 + 3) { c.hline(29, 34, y, "J") }
            for led in 0..<2 {
                let index = slot * 2 + led
                let color: Character = index < green ? "g" : (blinkOn ? "r" : "J")
                c.set(30 + led * 2, y0 + 1, color)
            }
            c.set(33, y0 + 2, "o")
        }
        if plugging { c.line((27, 13), (31, 12), "v") }
        return c.frame
    }

    /// Whiteboard mit Skizze, die Strich für Strich entsteht (`strokes` 0…7).
    static func whiteboard(strokes: Int) -> Frame {
        var c = HiResCanvas()
        for y in 3...15 { c.hline(25, 35, y, "w") }
        c.hline(25, 35, 3, "o"); c.hline(25, 35, 15, "o"); c.line((25, 3), (25, 15), "o"); c.line((35, 3), (35, 15), "o")
        c.line((27, 16), (26, 21), "K"); c.line((33, 16), (34, 21), "K")
        let steps: [(inout HiResCanvas) -> Void] = [
            { $0.hline(27, 29, 5, "B"); $0.hline(27, 29, 7, "B"); $0.set(27, 6, "B"); $0.set(29, 6, "B") },
            { $0.hline(30, 31, 6, "Z"); $0.set(31, 5, "Z"); $0.set(31, 7, "Z") },
            { $0.hline(32, 34, 5, "C"); $0.hline(32, 34, 7, "C"); $0.set(32, 6, "C"); $0.set(34, 6, "C") },
            { $0.line((33, 8), (33, 10), "Z") },
            { $0.hline(32, 34, 11, "N"); $0.hline(32, 34, 13, "N"); $0.set(32, 12, "N"); $0.set(34, 12, "N") },
            { $0.hline(29, 31, 12, "Z"); $0.set(29, 11, "Z"); $0.set(29, 13, "Z") },
            { $0.hline(27, 28, 11, "r"); $0.hline(27, 28, 13, "r"); $0.set(27, 12, "r"); $0.set(28, 12, "r") },
        ]
        for step in steps.prefix(strokes) { step(&c) }
        return c.frame
    }

    static let questionGlyph: Frame = ["ooo", "..o", ".o.", "...", ".o."]
    static let lightbulbGlyph: Frame = [".y.", "yyy", "yyy", ".G.", ".G."]
    static let checkGlyph: Frame = ["....g", "...g.", "g.g..", ".g..."]

    // MARK: - Arbeiten: Alltag

    /// Kaffeemaschine vor Clawd; beim Brühen tropft Kaffee in die Tasse.
    static func coffeeMachine(brewing: Bool, drip: Int, cupFull: Bool) -> Frame {
        var c = HiResCanvas()
        for y in 6...21 { c.hline(29, 35, y, "K") }
        for y in 6...8 { c.hline(26, 35, y, "K") }
        c.set(33, 10, brewing ? "r" : "g")
        c.set(27, 9, "J"); c.set(27, 10, "J")
        // Tasse
        c.hline(25, 28, 18, "o"); c.set(25, 19, "o"); c.set(28, 19, "o"); c.set(25, 20, "o"); c.set(28, 20, "o")
        c.hline(25, 28, 21, "o"); c.hline(26, 27, 19, cupFull ? "n" : "w"); c.hline(26, 27, 20, "w")
        if brewing { for y in stride(from: 11 + drip % 2, through: 17, by: 2) { c.set(27, y, "n") } }
        return c.frame
    }

    /// Tasse an den Mund gehoben.
    static let coffeeCupDrinking: Frame = {
        var c = HiResCanvas()
        c.hline(25, 28, 10, "o"); c.set(25, 11, "o"); c.set(28, 11, "o"); c.set(25, 12, "o"); c.set(28, 12, "o")
        c.hline(25, 28, 13, "o"); c.hline(26, 27, 11, "n"); c.hline(26, 27, 12, "w"); c.set(29, 11, "o")
        return c.frame
    }()

    static let envelope: Frame = [
        "ooooooo",
        "oowwwoo",
        "owwowwo",
        "ooooooo",
    ]
    static let openLetter: Frame = [
        "ooooo",
        "owwwo",
        "oZZwo",
        "owZZo",
        "oZZwo",
        "ooooo",
    ]

    /// Wäschestück (`color` = Farbzeichen): Hemd, Socke oder Hose.
    static func laundryItem(_ kind: Int, color: Character) -> Frame {
        let shapes: [[String]] = [
            ["cc.cc", "ccccc", ".ccc.", ".ccc."],
            ["cc", "cc", ".c", "cc"],
            ["ccc", "c.c", "c.c"],
        ]
        return shapes[kind % shapes.count].map { String($0.map { $0 == "c" ? color : $0 }) }
    }

    /// Aktenstapel: `count` Ordner übereinander; die oberen wackeln um `wobble` (−1…1).
    static func folderPile(count: Int, wobble: Int) -> Frame {
        let colors: [Character] = ["3", "2", "1", "4", "v", "g", "n", "u"]
        var rows: [String] = []
        for i in 0..<count {
            let shift = (i >= count - 3 && count >= 4) ? wobble : 0
            var row = Array(repeating: Character("."), count: 8)
            for x in 0..<6 { row[1 + shift + x] = colors[i % colors.count] }
            rows.append(String(row))
        }
        return rows.reversed()
    }

    // MARK: - Videocall

    /// Headset (stehend): Kopfbügel, zwei Ohrmuscheln, Mikrofonarm zum Mund mit roter Spitze.
    static let headset: Frame = {
        var c = HiResCanvas()
        for y in 0..<HiResCanvas.rows {
            for x in 0..<HiResCanvas.cols where y <= 7 {
                let dx = (Double(x) + 0.5 - 17.5) / 10.5, dy = (Double(y) + 0.5 - 8) / 5.5
                let d = dx * dx + dy * dy
                if d <= 1, d >= 0.6 { c.set(x, y, "K") }
            }
        }
        for y in 7...10 { c.hline(6, 7, y, "K"); c.hline(28, 29, y, "K") }
        c.line((29, 10), (26, 13), "K")
        c.hline(24, 25, 13, "u")
        return c.frame
    }()

    enum CallScreen {
        case ringing(dots: Int)
        case talking(mouthOpen: Bool, waving: Bool)
    }

    /// Kleines Videocall-Fenster (12 × 10): Titelleiste mit Ampel-Punkten, darunter
    /// "Verbinde …" oder der violette Freund.
    static func callWindow(_ screen: CallScreen) -> Frame {
        var rows = ["JrJyJgJJJJJJ"]
        switch screen {
        case .ringing(let dots):
            let bg = String(repeating: "K", count: 12)
            for r in 1...9 {
                if r == 5 {
                    var row = Array(bg)
                    for (i, x) in [4, 6, 8].enumerated() { row[x] = i < dots ? "w" : "J" }
                    rows.append(String(row))
                } else {
                    rows.append(bg)
                }
            }
        case .talking(let mouthOpen, let waving):
            let mouth = mouthOpen ? "EE" : "44"
            rows += [
                "UUUUUUUUUUUU",
                "UUUUUUUUUUUU",
                "UU44444444UU",
                waving ? "UU4E4444E4U4" : "UU4E4444E4UU",
                waving ? "UU4E4444E444" : "UU4E4444E4UU",
                "U4444" + mouth + "4444U",
                waving ? "U444444444UU" : "U4444444444U",
                "UU44444444UU",
                "UU4U4UU4U4UU",
            ]
        }
        return rows
    }

    // MARK: - Entwickler-Jobs 2

    /// Quietscheente vorne am Boden; `bob` = hüpft beim Quietschen.
    static func rubberDuck(bob: Bool) -> Frame {
        var c = HiResCanvas()
        let o = bob ? -1 : 0
        c.hline(31, 35, 19 + o, "y"); c.hline(30, 35, 20 + o, "y"); c.hline(31, 34, 21 + o, "y")
        c.hline(32, 34, 16 + o, "y"); c.hline(32, 34, 17 + o, "y"); c.set(33, 18 + o, "y")
        c.set(33, 16 + o, "E"); c.hline(35, 35, 17 + o, "O"); c.set(35, 16 + o, "O")
        return c.frame
    }

    static let rocket: Frame = [
        "..u..",
        ".uwu.",
        ".wvw.",
        ".www.",
        ".wvw.",
        ".www.",
        "uwwwu",
        "u.w.u",
    ]
    static let rocketFlames: [Frame] = [
        [".3.", "3u3", ".3."],
        ["3u3", ".u.", "..."],
    ]
    static let commitBox: Frame = ["nn", "nn"]
    static let digits: [Frame] = [
        [".o.", "oo.", ".o.", ".o.", "ooo"],   // 1
        ["ooo", "..o", "ooo", "o..", "ooo"],   // 2
        ["ooo", "..o", "ooo", "..o", "ooo"],   // 3
    ]

    /// Test-Anzeige: 2 × 3 Kästchen, die ersten `green` sind grün, der Rest rot (blinkend).
    static func testPanel(green: Int, blinkOn: Bool) -> Frame {
        var rows: [String] = []
        for r in 0..<2 {
            var line = ""
            for col in 0..<3 {
                let i = r * 3 + col
                let ch: Character = i < green ? "g" : (blinkOn ? "r" : "J")
                line += String(repeating: String(ch), count: 2) + (col < 2 ? "." : "")
            }
            rows += [line, line]
            if r == 0 { rows.append(String(repeating: ".", count: 8)) }
        }
        return rows
    }

    static let confettiGlyphs: [Frame] = [["1"], ["2"], ["3"], ["4"], ["g"]]

    /// Kleines Server-Rack als Effekt (4 × 9), LEDs rot oder grün.
    static func miniRack(ok: Bool, blinkOn: Bool) -> Frame {
        let led: Character = ok ? "g" : (blinkOn ? "r" : "J")
        return ["KKKK", "KJJK", "K\(led)JK", "KKKK", "KJJK", "KJ\(led)K", "KKKK", "KJJK", "K\(led)JK"]
    }

    static let flameFrames: [Frame] = [
        [".3..3.", "3u33u3", "uu3uuu"],
        ["3..3..", "u33u3.", "uuu3uu"],
    ]

    /// Feuerlöscher in der vorderen Hand, Düse nach vorn.
    static let extinguisher: Frame = {
        var c = HiResCanvas()
        for y in 13...20 { c.hline(29, 32, y, "u") }
        c.hline(30, 31, 12, "K")
        c.line((31, 12), (34, 11), "K"); c.set(35, 11, "K")
        return c.frame
    }()

    // MARK: - Büro

    /// Drucker (Statuslicht grün oder rot).
    static func printer(lightOn: Bool, jammed: Bool) -> Frame {
        let light: Character = jammed ? (lightOn ? "r" : "J") : "g"
        return [".oooo...", "JJJJJJJJ", "JJJJJJ\(light)J", "JKKKKKKJ", "JJJJJJJJ", "J......J"]
    }
    static let paperSheet: Frame = ["oooo", "owwo", "oZwo", "oooo"]

    /// Haftnotiz in Farbe `color` mit umgeknickter Ecke.
    static func postit(_ color: Character) -> Frame {
        let c = String(color)
        return [c + c + c, c + c + c, c + c + "."]
    }

    /// Papierstapel; `stamped` = oberstes Blatt hat einen roten Stempelabdruck.
    static func paperStack(stamped: Bool) -> Frame {
        ["ooooo", stamped ? "owrwo" : "owwwo", "ooooo", "owwwo", "ooooo"]
    }

    /// Stempel in der vorderen Hand: oben ausgeholt oder unten aufs Papier gedrückt.
    static func rubberStamp(down: Bool) -> Frame {
        var c = HiResCanvas()
        if down {
            c.line((33, 13), (33, 17), "H"); c.hline(32, 34, 12, "H")
            c.hline(31, 35, 18, "u")
        } else {
            c.line((31, 8), (31, 12), "H"); c.hline(30, 32, 7, "H")
            c.hline(29, 33, 13, "u")
        }
        return c.frame
    }

    static let tomatoTimer: Frame = ["..g..", ".uuu.", "uuwuu", "uuuuu", ".uuu."]

    // MARK: - Team-Szenen

    /// Flipchart mit wachsendem Balkendiagramm (`progress` 0…1).
    static func flipchart(progress: CGFloat) -> Frame {
        var rows = Array(repeating: Array("owwwwwwo"), count: 9)
        rows[0] = Array("oooooooo"); rows[8] = Array("oooooooo")
        let bars: [(col: Int, height: Int, color: Character)] = [(2, 3, "2"), (4, 5, "1"), (6, 7, "3")]
        for bar in bars {
            let h = Int((CGFloat(bar.height) * min(progress * 1.4, 1)).rounded())
            for i in 0..<h where 7 - i >= 1 { rows[7 - i][bar.col] = bar.color }
        }
        return rows.map { String($0) } + [".K....K.", ".K....K."]
    }

    /// Blatt Papier zum Tauziehen; zerrissen = zwei Hälften mit gezackter Kante.
    static let tugPaper: Frame = ["oooooooooo", "owwwZwwwwo", "owwwwwwZwo", "oooooooooo"]
    static let tugPaperLeft: Frame = ["ooooo", "owwwZ", "owww.", "oooo."]
    static let tugPaperRight: Frame = [".oooo", "wwwwo", "wwwZo", "ooooo"]

    /// Tasse in der vorderen Hand auf Brusthöhe.
    static let cupHold: Frame = {
        var c = HiResCanvas()
        c.hline(31, 34, 11, "o"); c.set(31, 12, "o"); c.set(34, 12, "o"); c.set(31, 13, "o"); c.set(34, 13, "o")
        c.hline(31, 34, 14, "o"); c.hline(32, 33, 12, "n"); c.hline(32, 33, 13, "w"); c.set(35, 12, "o")
        return c.frame
    }()

    static let exclamationGlyph: Frame = ["r", "r", "r", ".", "r"]

    // MARK: - Arbeits-Stimmungen

    /// Kalenderblatt mit rot eingekreistem Tag.
    static let calendar: Frame = ["rrrrrrr", "owwwwwo", "owwwwwo", "owwrrwo", "owwrrwo", "ooooooo"]
    /// Tickende Uhr (Zeiger in zwei Stellungen).
    static let clockFrames: [Frame] = [
        [".ooo.", "owKwo", "owKwo", "owwwo", ".ooo."],
        [".ooo.", "owwwo", "owKKo", "owwwo", ".ooo."],
    ]
    /// Schreibtischlampe (Schirm rechts oben, Licht fällt nach unten).
    static let deskLamp: Frame = [
        "...yyy",
        "..K.y.",
        ".K....",
        ".K....",
        ".K....",
        "KKK...",
    ]
    static let mugSmall: Frame = ["ooo.", "onoo", "owo.", "ooo."]

    /// Wegfliegende lange Kabel mit Steckern an den Enden (leicht gewellt).
    static let cableBits: [Frame] = [
        ["KK..........vvvvvv....",
         "..vvvvvvvvvv......vvKK"],
        ["....uuuuuu..........KK",
         "KKuu......uuuuuuuuuu.."],
        ["KKvvvvvvvvvvvvvvvvKK"],
        ["..uuuuuuu.......",
         "KK.......uuuuuuuKK"].map { $0.padding(toLength: 18, withPad: ".", startingAt: 0) },
        ["vvvv........vvvvvvKK",
         "....vvvvvvvv........",
         "KK.................."].map { $0.padding(toLength: 20, withPad: ".", startingAt: 0) },
    ]


    /// Kabelberg (Variante D) in doppelter Auflösung: viele verschlungene Kabel, Stecker oben,
    /// dazu Steckdosenleiste und Router. `stage` 0 = ganzer Berg … 3 = kleiner Rest.
    static func cableMountain(stage: Int) -> Frame {
        let key = "cableMountain\(stage)"
        if let cached = mountainCache[key] { return cached }
        let scales: [(cables: Int, h: Int, w: Int, plugs: Int, devices: Bool)] = [
            (18, 32, 60, 5, true), (13, 24, 50, 4, true), (8, 16, 40, 3, false), (4, 9, 28, 2, false),
        ]
        let cfg = scales[min(max(stage, 0), 3)]
        let width = 60, height = 42
        var rows = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        let offset = (width - cfg.w) / 2
        func put(_ x: Int, _ y: Int, _ c: Character) {
            let gx = x + offset
            if gx >= 0, gx < width, y >= 0, y < height { rows[height - 1 - y][gx] = c }
        }
        let shape = 0.6
        let w = Double(cfg.w), h = Double(cfg.h)
        func inside(_ x: Int, _ y: Int) -> Bool {
            let nx = (Double(x) - w / 2) / (w / 2)
            guard abs(nx) <= 1 else { return false }
            return y >= 0 && Double(y) < h * pow(1 - nx * nx, shape)
        }
        // Deterministischer Zufall (mulberry32), damit der Berg immer gleich aussieht
        var seed: UInt32 = 5
        func rnd() -> Double {
            seed = seed &+ 0x6D2B79F5
            var t = (seed ^ (seed >> 15)) &* (1 | seed)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296
        }
        let colors: [Character] = ["v", "u", "3", "p", "2"]
        for k in 0..<cfg.cables {
            let col = colors[k % colors.count]
            var x = Int(rnd() * w), y = Int(rnd() * h * 0.8), dx = rnd() < 0.5 ? 1 : -1, dy = 0
            for _ in 0..<130 {
                if inside(x, y) { put(x, y, col) }
                if rnd() < 0.35 { dy = Int(rnd() * 3) - 1 }
                if rnd() < 0.12 { dx = -dx }
                x += dx; y += dy
                if !inside(x, y) { dx = -dx; dy = -dy; x += dx * 2; y += dy * 2 }
            }
        }
        if cfg.devices {
            // Steckdosenleiste
            let sx = Int(w * 0.25)
            for x in sx..<(sx + 14) { for y in 4..<7 { put(x, y, "U") } }
            for i in 0..<4 { put(sx + 2 + i * 3, 5, "K") }
            // Router mit grünen Lämpchen und zwei Antennen
            let rx = Int(w * 0.6), ry = Int(h * 0.45)
            for x in rx..<(rx + 9) { for y in ry..<(ry + 4) { put(x, y, "K") } }
            put(rx + 2, ry + 2, "g"); put(rx + 4, ry + 2, "g")
            for y in (ry + 4)...(ry + 5) { put(rx + 2, y, "K"); put(rx + 7, y, "K") }
        }
        // Stecker, die oben herausragen
        for p in 0..<cfg.plugs {
            let nx = -0.8 + rnd() * 1.6
            let x = Int((w / 2 + nx * w / 2).rounded())
            let top = Int(h * pow(1 - nx * nx, shape))
            let up = 1 + Int(rnd() * 4)
            for s in 0..<up { put(x, top + s, colors[p % colors.count]) }
            for dx in -1...1 { for dy in 0..<2 { put(x + dx, top + up + dy, "K") } }
            put(x - 1, top + up + 2, "G"); put(x + 1, top + up + 2, "G")
        }
        let frame = rows.map { String($0) }
        mountainCache[key] = frame
        return frame
    }
    private static var mountainCache: [String: Frame] = [:]

    // MARK: - Freizeit: Papierflieger & Drachen

    /// Papierflieger falten: Blatt → halb gefaltet → fertiger Flieger (zeigt nach rechts).
    /// Farben: "P" Papier, "a" Kanten – je Theme so gewählt, dass er auf hellen wie dunklen Fenstern auffällt.
    static let paperFolds: [Frame] = [
        ["aaaaa", "aPPPa", "aPPPa", "aaaaa"],
        ["..a..", ".aPa.", "aPPPa", "aaaaa"],
        paperPlane,
    ]

    /// Fliegender Papierflieger (Seitenansicht, Spitze rechts).
    static let paperPlane: Frame = ["PP......", "aPPPP...", ".aaPPPPa", "...aa..."]

    /// Drachen: lange, leicht gekippte Raute in vier bunten Feldern mit Stabkreuz und kleinen
    /// Wimpeln an den Seitenecken. Alle Kanten haben gleichmäßige Stufen (1:1, 1:2, 1:7, 5:1),
    /// damit er sauber wirkt. Lehnt sich nach links oben (zum Halter hin); der Schwanz hängt an
    /// der unteren Spitze. 31 Zeilen – bei 1 pt pro Zelle knapp so hoch wie Clawd.
    static let kite: Frame = [
        ".......o............",
        ".......o1...........",
        "......33o1..........",
        "......33o11.........",
        ".....3333o11........",
        ".....3333o111.......",
        "....33333o1111......",
        "....333333o1111.....",
        "...3333333o11111....",
        "...33333333o11oooo..",
        "..3333333ooooo222.o.",
        "..33ooooo44o22222.o.",
        ".ooo44444444o2222..o",
        "o.4444444444o22222..",
        "o..4444444444o2222..",
        ".o..444444444o2222..",
        ".o...44444444o2222..",
        "o.....44444444o222..",
        ".......4444444o222..",
        "........4444444o22..",
        ".........444444o222.",
        "..........44444o222.",
        "...........44444o22.",
        "............4444o22.",
        ".............4444o2.",
        "..............444o2.",
        "...............44o2.",
        "................44o2",
        ".................4o2",
        "..................4o",
        "...................o",
    ]
    /// Kreuzungspunkt der Stäbe (Schnur) und Unterkante der Spitze (Schwanz), in Zellen von oben links.
    static let kiteCross = CGPoint(x: 11.5, y: 10.5)
    static let kiteTip = CGPoint(x: 19.5, y: 31)

    // MARK: - Kochen, Bogenschießen, Zaubern

    /// Umriss: jede leere Zelle neben `fill` wird zu `edge` (damit Weißes auf Weiß sichtbar bleibt).
    private static func outlined(_ rows: [[Character]], fill: Set<Character>, edge: Character) -> Frame {
        var out = rows
        for y in rows.indices {
            for x in rows[y].indices where rows[y][x] == "." {
                // 8er-Nachbarschaft: geschlossene Kontur auch an schrägen Kanten
                let near = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1),
                            (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1), (x + 1, y + 1)].contains { nx, ny in
                    rows.indices.contains(ny) && rows[ny].indices.contains(nx) && fill.contains(rows[ny][nx])
                }
                if near { out[y][x] = edge }
            }
        }
        return out.map { String($0) }
    }

    /// Kochmütze (28 breit wie der Bauhelm): drei Bauschen über einem Band. Ohne Rand – auf hellem
    /// Hintergrund hebt sie ein Schatten ab (siehe `hasShadow`).
    static let chefHat: Frame = {
        var r = Array(repeating: Array(repeating: Character("."), count: 28), count: 14)
        for y in 0..<14 {
            for x in 0..<28 {
                // Eine Zeile Luft oben (Platz für den Schatten); das Band sitzt in der untersten Zeile auf dem Kopf.
                let puffs = [(10.0, 7.5, 4.2), (14.0, 6.5, 4.5), (18.0, 7.5, 4.2)]
                let inPuff = puffs.contains { cx, cy, rad in
                    let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                    return dx * dx + dy * dy <= rad * rad
                }
                if (inPuff && y <= 10) || (y >= 10 && x >= 7 && x <= 20) { r[y][x] = "w" }
            }
        }
        for x in 8...19 { r[12][x] = "Z" } // Falte im Band
        return r.map { String($0) }
    }()

    /// Denkhut (28 breit): Zylinder mit Band, gerader Krempe und Glanzstreifen.
    private static func topHat(_ color: Character, band: Character, shine: Character?) -> Frame {
        var r = Array(repeating: Array(repeating: Character("."), count: 28), count: 12)
        for y in 0...8 { for x in 8...19 { r[y][x] = color } }
        for x in 7...20 { r[0][x] = color }
        for y in 6...7 { for x in 8...19 { r[y][x] = band } }
        for x in 3...24 { r[9][x] = color }
        for x in 4...23 { r[10][x] = color }
        if let shine { for y in 1...4 { r[y][10] = shine } }
        return r.map { String($0) }
    }

    /// Die sechs Denkhüte: Blau, Weiß, Rot, Schwarz, Gelb, Grün.
    static let thinkingHats: [Frame] = [
        topHat("B", band: "K", shine: "w"),
        topHat("w", band: "q", shine: nil),
        topHat("u", band: "K", shine: "w"),
        topHat("9", band: "q", shine: "Z"),
        topHat("3", band: "K", shine: "w"),
        topHat("g", band: "K", shine: "w"),
    ]

    /// Warndreieck mit Ausrufezeichen (schwarzer Denkhut: Risiken).
    static let warningGlyph: Frame = ["..k..", ".kEk.", ".kkk.", "kkEkk", "kkkkk"]

    /// Kopfbedeckungen ohne dunklen Rand, die einen Schatten brauchen.
    static func hasShadow(_ hat: Frame) -> Bool { hat == chefHat || hat == thinkingHats[1] }

    /// Zauberhut (28 breit): schiefer violetter Kegel mit Sternen und goldenem Band, breite Krempe.
    static let wizardHat: Frame = {
        var r = Array(repeating: Array(repeating: Character("."), count: 28), count: 15)
        for y in 0..<13 {
            // Kegel wird nach unten breiter, Spitze leicht nach rechts geneigt
            let half = Double(y) * 0.62 + 0.5
            let cx = 17.0 - Double(y) * 0.3
            for x in 0..<28 where abs(Double(x) + 0.5 - cx) <= half { r[y][x] = "4" }
        }
        for x in 0..<28 where r[11][x] == "4" { r[11][x] = "k" } // Band
        for x in 2...25 { r[13][x] = "4"; r[14][x] = "4" }       // Krempe
        for (x, y) in [(16, 3), (13, 7), (18, 8), (15, 9)] { r[y][x] = "k" } // Sterne
        return outlined(r, fill: ["4", "k"], edge: "o")
    }()

    enum WandPose { case up, forward }

    /// Zauberstab in der vorderen Hand; Spitze funkelt.
    static func wand(_ pose: WandPose) -> Frame {
        var c = HiResCanvas()
        switch pose {
        case .up:
            c.line((31, 13), (34, 6), "K")
            c.set(34, 5, "k"); c.set(33, 5, "k"); c.set(35, 5, "k"); c.set(34, 4, "k"); c.set(34, 6, "w")
        case .forward:
            c.line((31, 13), (35, 11), "K")
            c.set(35, 10, "k"); c.set(34, 10, "k"); c.set(35, 9, "k"); c.set(35, 11, "w")
        }
        return c.frame
    }

    enum BowPose { case relaxed, drawn }

    /// Bogen senkrecht in der vorderen Hand; gespannt mit eingelegtem Pfeil.
    static func bow(_ pose: BowPose) -> Frame {
        var c = HiResCanvas()
        c.line((32, 6), (34, 8), "H"); c.line((34, 8), (35, 11), "H"); c.line((35, 11), (35, 15), "H")
        c.line((35, 15), (34, 18), "H"); c.line((34, 18), (32, 20), "H")
        switch pose {
        case .relaxed:
            c.line((32, 7), (32, 19), "Z")
        case .drawn:
            c.line((32, 7), (27, 13), "Z"); c.line((27, 13), (32, 19), "Z")
            c.hline(27, 35, 13, "o")
            c.set(27, 12, "u"); c.set(27, 14, "u"); c.set(28, 12, "u"); c.set(28, 14, "u")
        }
        return c.frame
    }

    /// Fliegender Pfeil (Spitze rechts) und Pfeil in der Scheibe.
    static let arrow: Frame = ["u.....", "uooooK", "u....."]
    static let stuckArrow: Frame = ["u..", "uoo", "u.."]

    /// Zielscheibe aus Stroh auf einem Ständer: außen blau, in der Mitte strohgelb, rotes Zentrum.
    static let target: Frame = [
        "...iiiii...",
        "..iIIIIIi..",
        ".iIAAAAAIi.",
        "iIAFFFFFAIi",
        "iIAFuuuFAIi",
        "iIAFujuFAIi",
        "iIAFuuuFAIi",
        "iIAFFFFFAIi",
        ".iIAAAAAIi.",
        "..iIIIIIi..",
        "...iiiii...",
        ".....H.....",
        "....H.H....",
        "...H...H...",
    ]

    /// Herd mit Topf; die Flammen flackern (zwei Bilder).
    static let stove: [Frame] = [
        [".KKKKKKKK.", ".KJJJJJJK.", ".KJJJJJJK.", "..KKKKKK..", "...u3u3...", "oooooooooo", "o........o"],
        [".KKKKKKKK.", ".KJJJJJJK.", ".KJJJJJJK.", "..KKKKKK..", "...3u3u...", "oooooooooo", "o........o"],
    ]

    /// Kochlöffel in der Hand, mal links, mal rechts im Topf.
    static func ladle(left: Bool) -> Frame {
        var c = HiResCanvas()
        if left { c.line((31, 13), (34, 18), "H") } else { c.line((31, 13), (35, 17), "H") }
        return c.frame
    }

    /// Tomate (Zutat) und Blumenstrauß (Zaubertrick).
    static let tomato: Frame = [".g.", "uuu", "uuu"]
    static let bouquet: Frame = [".f.r.", "frfrf", ".fgf.", "..g..", "..g.."]

    /// Rauchwolke beim Zaubern (klein, groß).
    static let puff: [Frame] = [
        ["..VVV..", ".VVVVV.", "VVVVVVV", ".VVVVV.", "..VVV.."],
        ["..VVVV...", ".VVVVVVV.", "VVVVVVVVV", "VVVVVVVVV", ".VVVVVVV.", "...VVV..."],
    ]

    /// Verwandelt: Frosch und Kaninchen in Clawd-Größe (schauen nach rechts).
    /// Sitzender Frosch in doppelter Auflösung (28×16): Augenhügel, Maul, heller Bauch ("e"),
    /// angewinkeltes Hinterbein, dunkelgrüne Kontur ("d").
    static let frog: Frame = [
        "............................",
        ".................ddd........",
        "...............dddgddd......",
        "...............dggwwgd......",
        "...............dgwwEEd......",
        "..............ddgwwEEddd....",
        ".............ddgggwggggddd..",
        ".......dddddddggggggggggdd..",
        ".....dddggggggggggggggggdd..",
        "....ddgggggdggggggggddddd...",
        "....dgggggggdgggggggggggd...",
        "....dgggggggdgggggggggddd...",
        "....dgggggggeeeeeeegdgdd....",
        "....ddggggggeeeeeeeegggdd...",
        "..dddgggggggeeeeeeedggggdd..",
        "..dgggggggggddddddddgggggd..",
    ]
    /// Sitzendes Kaninchen in doppelter Auflösung (28×16, füllt Clawds 14×8-Fläche): lange Ohren,
    /// helle Brust, weißer Puschelschwanz, braune Kontur – auf hellem wie dunklem Grund gut zu sehen.
    static let rabbit: Frame = [
        "..............HHHHHHH.......",
        ".............HHnHHnnH.......",
        ".............HnnnHnrH.......",
        ".............HnnnHnrH.......",
        ".............HnnnHnrH.......",
        ".............HnnnHnrHHH.....",
        ".............HnnnnnnnnHH....",
        ".......HHHHHHHHnnnnnnnnHH...",
        "...HHHHHnnnnnnnnnnnnEwnnH...",
        "..HHwwHnnnnnnnnnnnnnEEnnH...",
        "..HwwwwnnnnnnnnnnnnnnnnrH...",
        "..HwwwwnnnnnnnnnnUUUnnnHH...",
        "..HHwwnnnnnnnnnnnUUUUHHH....",
        "...HHHnnnnnnnnnnnUUUUH......",
        ".....HHnnnnnnnnnnUUUnHH.....",
        "......HnnnnnnnnnHHHnnnH.....",
    ]

    // MARK: - Claude-Code-Aufgaben: Plan, Terminal, Suche, Subagenten

    /// Klemmbrett mit drei Aufgaben; `checked` davon sind abgehakt (grün).
    static func clipboard(checked: Int) -> Frame {
        var r = Array(repeating: Array(repeating: Character("."), count: 9), count: 11)
        for y in 1..<11 { for x in 0..<9 { r[y][x] = (x == 0 || x == 8 || y == 1 || y == 10) ? "H" : "w" } }
        for x in 3...5 { r[0][x] = "K"; r[1][x] = "K" }        // Klammer
        for (i, y) in [3, 5, 7].enumerated() {
            r[y][2] = i < checked ? "g" : "o"                    // Kästchen
            for x in 4...6 { r[y][x] = "Z" }                     // Text
        }
        return r.map { String($0) }
    }

    enum TerminalState { case running, ok, failed }

    /// Kleines Terminal auf einem Fuß: `lines` Befehlszeilen, Fortschrittsbalken 0…1, Ergebnis.
    static func terminal(lines: Int, progress: CGFloat, state: TerminalState) -> Frame {
        let w = 16
        var r = Array(repeating: Array(repeating: Character("."), count: w), count: 13)
        for y in 0...10 { for x in 0..<w { r[y][x] = (x == 0 || x == w - 1 || y == 0 || y == 10) ? "o" : "E" } }
        r[0][2] = "u"; r[0][4] = "3"; r[0][6] = "g"               // Fensterknöpfe
        let lengths = [7, 5, 9]
        for i in 0..<min(lines, 3) {
            let y = 2 + i * 2
            r[y][2] = "C"                                         // Prompt ">"
            for x in 4..<(4 + lengths[i]) where x < w - 1 { r[y][x] = "C" }
        }
        let filled = Int((CGFloat(10) * min(max(progress, 0), 1)).rounded())
        for x in 2..<12 { r[8][x] = x - 2 < filled ? (state == .failed ? "u" : "C") : "Z" }
        switch state {
        case .running: break
        case .ok: r[8][13] = "C"; r[7][13] = "C"
        case .failed: r[8][13] = "u"; r[7][13] = "u"
        }
        r[11][7] = "o"; r[11][8] = "o"                            // Fuß
        for x in 5...10 { r[12][x] = "o" }
        return r.map { String($0) }
    }

    /// Lupe in der vorderen Hand.
    static func magnifier(raised: Bool) -> Frame {
        var c = HiResCanvas()
        let (cx, cy): (Double, Double) = raised ? (33.5, 8.5) : (33, 13)
        c.ellipse(cx: cx, cy: cy, rx: 2.6, ry: 2.6, edge: "K", fill: "c")
        c.line((31, raised ? 13 : 16), (Int(cx) - 2, Int(cy) + 2), "H")
        return c.frame
    }

    // MARK: - Magnetschuhe

    /// Magnetwelle zwischen Schuhen und Fensterkante (öffnet sich nach rechts zur Kante hin).
    static let magnetArc: Frame = ["k.", ".k", ".k", ".k", "k."]
    /// Kleiner Ring beim Abdocken.
    static let undockPuff: Frame = [".k.", "k.k", ".k."]

    // MARK: - Tennis

    enum RacketPose { case ready, swing }

    /// Schläger in der vorderen Hand (stehend, Hand bei ca. Spalte 31, Zeile 13).
    static func racket(_ pose: RacketPose) -> Frame {
        var c = HiResCanvas()
        switch pose {
        case .ready:
            // Ausgeholt: Schläger schräg nach oben
            c.line((31, 13), (30, 10), "h")
            c.ellipse(cx: 29, cy: 6, rx: 2.6, ry: 3.6, edge: "Q", fill: "q")
        case .swing:
            // Durchgeschwungen: Schlagfläche vorn, von der Seite gesehen
            c.line((31, 13), (32, 13), "h")
            c.ellipse(cx: 34, cy: 13, rx: 1.6, ry: 3.6, edge: "Q", fill: "q")
        }
        return c.frame
    }

    /// Mitte der Schlagfläche beim Durchschwingen, relativ zur Sprite-Mitte unten (in Sprite-Pixeln).
    static let racketHitOffset = CGPoint(x: (34 + 0.5 - 18) / 2, y: (22 - 13 - 0.5) / 2)

    /// Tennisball ohne Rand: Glanzlicht oben links, Schattenseite unten rechts. Wird mit
    /// `ballScale` × Pixelgröße und weichem Schatten gezeichnet (hebt ihn von jedem Hintergrund ab).
    static let ball: Frame = [
        "..TT..",
        ".TwTT.",
        "TwTTTT",
        "TTTTTl",
        ".TTTl.",
        "..ll..",
    ]
    /// Zeichengröße des Balls als Faktor der Pixelgröße (6 Zellen × 0,4 = 2,4 Clawd-Pixel).
    static let ballScale: CGFloat = 0.4

    // MARK: - Requisiten (symmetrisch, werden nicht gespiegelt)

    /// Laptop von hinten (Deckel mit Logo); verdeckt den Bauch, die Augen schauen darüber.
    /// Laptop von hinten in doppelter Auflösung (20×8 Zellen, gezeichnet mit halber Pixelgröße),
    /// damit der dunkle Rand nur einen halben Clawd-Pixel breit ist. Außenmaß wie bisher 10×4.
    static let laptop: Frame = [
        "KKKKKKKKKKKKKKKKKKKK",
        "KGGGGGGGGGGGGGGGGGGK",
        "KGGGGGGGGGGGGGGGGGGK",
        "KGGGGGGGOOOOGGGGGGGK",
        "KGGGGGGGOOOOGGGGGGGK",
        "KGGGGGGGGGGGGGGGGGGK",
        "KGGGGGGGGGGGGGGGGGGK",
        "KKKKKKKKKKKKKKKKKKKK",
    ]
    /// Zeichenmaßstab des Laptops relativ zur Pixelgröße.
    static let laptopScale: CGFloat = 0.5

    /// AirPods Max: Mesh-Kopfband über dem Kopf, Edelstahl-Bügel, große Alu-Muscheln mit
    /// dunklem Polster zum Kopf hin (14 breit wie Clawd).
    /// Zeilen: eine über dem Kopf, Kopfzeile, Augenzeile 1, Augenzeile 2.
    static let headphones: Frame = [
        "...mmmmmmmm...",
        "..s........s..",
        ".cp........pc.",
        ".cp........pc.",
    ]

    // MARK: - Partikel

    static let zGlyph: Frame = [
        "ZZZ",
        ".Z.",
        "ZZZ",
    ]
    static let noteGlyphs: [Frame] = [
        [
            "..NN",
            "..N.",
            "..N.",
            "NNN.",
            "NNN.",
        ],
        [
            ".NNNNN",
            ".N...N",
            ".N...N",
            "NN..NN",
            "NN..NN",
        ],
    ]
    /// Bunte Codezeilen wie in einem Editor mit Syntax-Highlighting.
    static let codeLines: [Frame] = [
        ["NNN.CCCCC"],
        ["..BBB.ZZZZ"],
        ["..CC.OOOO.NN"],
        ["ZZZZ.BB"],
        ["NN.CCC.ZZZ"],
    ]
    /// Schweißtropfen beim Sport.
    static let sweatGlyph: Frame = [
        "S",
        "S",
    ]
}
