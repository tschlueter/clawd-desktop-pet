import CoreGraphics
import QuartzCore

/// Erkennt, ob ein Fenster geschüttelt wird: mindestens zwei Richtungswechsel (hin-her-hin)
/// und ordentlich Weg innerhalb von 0,8 s – normales Verschieben löst das nicht aus.
struct ShakeDetector {
    struct Reading {
        var samples: Int
        var reversals: Int
        var path: CGFloat
        var isShaking: Bool { reversals >= 2 && path > 150 }
        /// Heftiges Schütteln (Clawd am Mauszeiger): acht Richtungswechsel und viel Weg.
        /// Braucht ein längeres Zeitfenster, siehe `ShakeDetector(window:)`.
        var isVigorous: Bool { reversals >= 8 && path > 900 }
    }

    private var samples: [(t: CFTimeInterval, p: CGPoint)] = []
    /// Wie weit zurück Bewegungen zählen (Sekunden).
    let window: CFTimeInterval

    init(window: CFTimeInterval = 0.8) { self.window = window }

    /// Neue Position melden; liefert die Auswertung der letzten `window` Sekunden.
    mutating func add(_ origin: CGPoint, now: CFTimeInterval) -> Reading {
        if samples.last?.p != origin { samples.append((now, origin)) }
        samples.removeAll { now - $0.t > window }
        guard samples.count >= 4 else { return Reading(samples: samples.count, reversals: 0, path: 0) }
        var reversals = 0
        var path: CGFloat = 0
        var lastSign: (x: CGFloat, y: CGFloat) = (0, 0)
        for (a, b) in zip(samples, samples.dropFirst()) {
            let dx = b.p.x - a.p.x, dy = b.p.y - a.p.y
            path += hypot(dx, dy)
            if abs(dx) > 2 {
                let s: CGFloat = dx > 0 ? 1 : -1
                if lastSign.x != 0, s != lastSign.x { reversals += 1 }
                lastSign.x = s
            }
            if abs(dy) > 2 {
                let s: CGFloat = dy > 0 ? 1 : -1
                if lastSign.y != 0, s != lastSign.y { reversals += 1 }
                lastSign.y = s
            }
        }
        return Reading(samples: samples.count, reversals: reversals, path: path)
    }

    mutating func reset() { samples = [] }
}
