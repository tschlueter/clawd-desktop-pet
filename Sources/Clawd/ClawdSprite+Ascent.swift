import Foundation

/// Hoch hinaus: Enterhaken und Jetpack. Requisiten in doppelter Auflösung (mit `px / 2` zeichnen),
/// Clawd-Frames normal (14 × 8, Blick nach rechts).
extension ClawdSprite {
    // MARK: - Clawd

    /// Zielen: vorderer Arm ganz hoch (die Pistole sitzt auf der Hand, Spalte 12–13).
    static let aimUp: Frame = [
        "..XXXXXXXXXXXX",
        "..XXXEXXXXEXXX",
        "..XXXEXXXXEX..",
        "XXXXXXXXXXXX..",
        "XXXXXXXXXXXX..",
        "..XXXXXXXXXX..",
        "..X.X....X.X..",
        "..X.X....X.X..",
    ]

    /// Am Seil hochziehen, im Wechsel: Arm ganz oben ↔ Arm auf Kopfhöhe, die Beine baumeln.
    static let ropeClimb: [Frame] = [
        [
            "..XXXXXXXXXXXX",
            "..XXXEXXXXEXXX",
            "..XXXEXXXXEX..",
            "XXXXXXXXXXXX..",
            "XXXXXXXXXXXX..",
            "..XXXXXXXXXX..",
            "..X.X....X.X..",
            "...X......X...",
        ],
        [
            "..XXXXXXXXXX..",
            "..XXXEXXXXEXXX",
            "..XXXEXXXXEXXX",
            "XXXXXXXXXXXX..",
            "XXXXXXXXXXXX..",
            "..XXXXXXXXXX..",
            "..X.X....X.X..",
            "..X......X....",
        ],
    ]

    /// Fliegen mit dem Jetpack: Blick nach vorn, die Beine baumeln.
    static let jetFly: Frame = [
        "..XXXXXXXXXX..",
        "..XXXEXXXXEX..",
        "..XXXEXXXXEX..",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        "..XXXXXXXXXX..",
        "..X.X....X.X..",
        "...X.X....X.X.",
    ]

    /// Stehen mit Blick nach vorn (Triebwerk anwerfen).
    static let jetStand: Frame = [
        "..XXXXXXXXXX..",
        "..XXXEXXXXEX..",
        "..XXXEXXXXEX..",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        "..XXXXXXXXXX..",
        "..X.X....X.X..",
        "..X.X....X.X..",
    ]

    // MARK: - Enterhaken

    /// Enterhaken-Pistole, nach oben gerichtet (7 × 11); vorn schauen die Zinken des Hakens heraus.
    /// Griff in Spalte 4–5.
    static let grappleLauncher: Frame = [
        "..q..q.",
        "..qqqq.",
        ".oooooo",
        ".oqqqqo",
        ".oqqqqo",
        "ouuuuuo",
        "ouuuuuo",
        "oqqqqqo",
        "ooooooo",
        "....KK.",
        "....KK.",
    ]

    /// Haken im Flug (7 × 9): drei Zinken, Öse unten (Spalte 3).
    static let grappleHook: Frame = [
        "q.....q",
        "qq...qq",
        ".q.q.q.",
        "..qqq..",
        "...q...",
        "...q...",
        "..ooo..",
        "..o.o..",
        "..ooo..",
    ]

    /// Haken eingerastet (9 × 7): Zinken auf der Kante (Zeile 2), Öse unten (Spalte 4).
    static let grappleHookCaught: Frame = [
        "...qqq...",
        ".qq.q.qq.",
        "q...q...q",
        "....q....",
        "...ooo...",
        "...o.o...",
        "...ooo...",
    ]

    /// Seil im Flug, geschlängelt (3 breit, Seil schwingt um die Mitte).
    static func wavyRope(length: Int) -> Frame {
        (0..<max(length, 1)).map { i in
            switch [0, 1, 1, 0, -1, -1][i % 6] {
            case 1: "..n"
            case -1: "n.."
            default: ".n."
            }
        }
    }

    /// Gespanntes Seil (1 breit), wird gedreht gezeigt.
    static func tautRope(length: Int) -> Frame {
        Array(repeating: "n", count: max(length, 1))
    }

    // MARK: - Jetpack

    /// Jetpack von vorn (16 × 14): steht vor Clawd, bevor er es umschnallt.
    static let jetpackFront: Frame = [
        "..oooo....oooo..",
        ".oqwqqo..oqwqqo.",
        ".oqwqqoooqqwqqo.",
        ".ouuuuoKKouuuuo.",
        ".oqwqqoKKoqwqqo.",
        ".oqwqqoKKoqwqqo.",
        ".oqqqqoKKoqqqqo.",
        ".ouuuuoooouuuuo.",
        ".oqqqqo..oqqqqo.",
        ".oqqqqo..oqqqqo.",
        "..oKKo....oKKo..",
        "..oKKo....oKKo..",
        "..oooo....oooo..",
        "...oo......oo...",
    ]

    /// Jetpack von der Seite, auf dem Rücken (8 × 14); Düse unten in Spalte 3–4.
    static let jetpackSide: Frame = [
        "..oooo..",
        ".oqwqqo.",
        ".oqwqqo.",
        ".ouuuuo.",
        ".oqwqqo.",
        ".oqwqqo.",
        ".oqqqqo.",
        ".ouuuuo.",
        ".oqqqqo.",
        ".oqqqqo.",
        "..oKKo..",
        "..oKKo..",
        "..oooo..",
        "...oo...",
    ]

    /// Triebwerk stottert: vereinzelte Funken (6 breit, `spark` wechselt das Muster).
    static func jetSputter(_ spark: Int) -> Frame {
        [["..3...", ".....3", "......"], ["......", "3.....", "...3.."], ["...k..", "......", "....3."]][spark % 3]
    }

    /// Kurze Flamme, während sich der Druck aufbaut (6 breit).
    static let jetFlameShort: Frame = ["..kk..", ".kwwk.", ".k33k.", "..3u..", "..u..."]

    /// Voller Schub (8 breit), flackert zwischen zwei Längen.
    static func jetFlameFull(_ flicker: Int) -> Frame {
        let flame: Frame = [
            ".kwwwwk.",
            "kkwwwwkk",
            "3kkwwkk3",
            "3kkwwkk3",
            ".3kkkk3.",
            ".33kk33.",
            "..3kk3..",
            "..3kuu..",
            "..u3uu..",
            "...uu...",
            "...u....",
            "....u...",
        ]
        return flicker % 2 == 0 ? flame : Array(flame.dropLast(2))
    }

    /// Rauchwolke (6 × 4) und kleines Wölkchen (4 × 3).
    static let smokePuff: Frame = ["..VV..", ".VVVV.", "VVVZVV", ".VZZV."]
    static let smokePuffSmall: Frame = [".VV.", "VVZV", ".VV."]

    /// Hochgeschobene Fliegerbrille (als Hut, 28 breit): Gläser über den Augen, Band über der Stirn.
    static let flightGoggles: Frame = [
        ".........oooo......oooo.....",
        "........ozzwo.....ozzwo.....",
        "....oooooooooooooooooooo....",
        "............................",
    ]
}
