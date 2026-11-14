import Foundation

/// Requisiten für den Rollenspielabend (zwei Clawds am Spieltisch). Doppelte Auflösung
/// (mit `px / 2` zeichnen); allgemeine Fantasy-Motive, kein bestimmtes Spiel.
extension ClawdSprite {
    /// Niedriger Spieltisch (64 × 10).
    static let gameTable: Frame = [String(repeating: "H", count: 64), String(repeating: "H", count: 64),
                                   String(repeating: "n", count: 64)]
        + Array(repeating: "...HH" + String(repeating: ".", count: 54) + "HH...", count: 7)

    /// Spielplan mit Kachelraster, flach auf dem Tisch (40 × 2).
    static let battleMap: Frame = [
        "qwqwqwqwqwqwqwqwqwqwqwqwqwqwqwqwqwqwqwqw",
        "wgwgwgwqwqwqwqwzwzwzwqwqwqwqwqwqwqwqwqwq",
    ]

    /// Spielleiter-Schirm (18 × 12): aufgestellte Pappe mit zwei Knicken, Verzierungen und rotem Drachen.
    static let gmScreen: Frame = [
        "oooooooooooooooooo",
        "otttttottttttottto",
        "otttttotuttutottto",
        "okktttotuuuutottko",
        "otttttotuuuutottto",
        "okktttottuuttottko",
        "otttttotttkttottto",
        "otttttottttttottto",
        "otttttottttttottto",
        "otttttottttttottto",
        "otttttottttttottto",
        "oooooooooooooooooo",
    ]

    /// Zwanzigseitiger Würfel (7 × 7) mit der Zahl als Fleck in der Mitte; `tumble` = gedrehte Lage.
    static func d20(face: Int? = nil, tumble: Bool = false) -> Frame {
        if tumble { return ["...u...", "..uuu..", ".uwuwu.", "uuuwuuu", ".uwuwu.", "..uuu..", "...u..."] }
        switch face {
        case 20: return ["..uuu..", ".uwuwu.", "uuuwuuu", "uwkkkwu", "uuwkwuu", ".uuwuu.", "..uuu.."]
        case 1: return ["..uuu..", ".uwuwu.", "uuuwuuu", "uwuKuwu", "uuwKwuu", ".uuwuu.", "..uuu.."]
        default: return ["..uuu..", ".uwuwu.", "uuuwuuu", "uwuuuwu", "uuwuwuu", ".uuwuu.", "..uuu.."]
        }
    }

    /// Miniaturen (Halbraster): Ritter, Zauberin, Drache – der Drache auch umgekippt.
    static let miniKnight: Frame = [".q.", "qBq", ".B.", ".B.", "BBB", "KKK"]
    static let miniWizard: Frame = [".4.", "444", ".X.", "4X4", "444", "KKK"]
    static let miniDragon: Frame = ["g...g", "gg.gg", ".ggg.", "ggggg", ".g.g.", "KKKKK"]
    static let miniDragonFallen: Frame = ["g.gg.", "ggggg", ".gggg", "KKKKK"]

    /// Charakterbogen (8 × 2, flach) und Bleistift.
    static let characterSheet: Frame = ["wwwwwwww", "wZwZZwZw"]
    static let pencil: Frame = ["kkkkkqo"]

    /// Chipsschale (10 × 4).
    static let snackBowl: Frame = [".k.y.k.y..", "y3k3y3k3y.", "nnnnnnnnnn", ".nnnnnnnn."]

    /// Lila Zauberhut mit goldenem Stern (28 × 12, doppelte Auflösung, sitzt auf dem Kopf).
    static let rpgWizardHat: Frame = [
        "..............44............",
        ".............444............",
        ".............4444...........",
        "............44444...........",
        "............444k44..........",
        "...........44kkk44..........",
        "...........4444k444.........",
        "..........444444444.........",
        "..........4444444444........",
        ".........44444444444........",
        "......44444444444444444.....",
        "....4444444444444444444444..",
    ]
}
