import AppKit

/// Ablauf in Phasen, wie ihn Arbeiten (`Job`) und Begegnungen (`Encounter`) spielen:
/// Phasenzähler mit Startzeit und Einmal-Marken ("Laut nur einmal abspielen").
struct Choreography {
    private(set) var phase = 0
    private(set) var phaseStart: CFTimeInterval
    private var cues: Set<String> = []

    init(now: CFTimeInterval = CACurrentMediaTime()) {
        phaseStart = now
    }

    /// Sekunden seit Beginn der aktuellen Phase.
    func elapsed(_ now: CFTimeInterval) -> TimeInterval { now - phaseStart }

    mutating func next(_ now: CFTimeInterval) {
        go(to: phase + 1, now: now)
    }

    mutating func go(to phase: Int, now: CFTimeInterval) {
        self.phase = phase
        phaseStart = now
    }

    /// true nur beim ersten Aufruf mit diesem Schlüssel.
    mutating func once(_ key: String) -> Bool { cues.insert(key).inserted }
}

/// Effekt-Layer auf der Bühne (Funkeln, Ball, Requisiten …), nach Schlüssel verwaltet.
/// Ursprung ist jeweils unten links in globalen Cocoa-Koordinaten.
final class EffectLayers {
    private weak var stage: Stage?
    private var layers: [String: CALayer] = [:]

    init(stage: Stage?) {
        self.stage = stage
    }

    /// Layer ohne implizite Animationen, scharf hochskaliert.
    static func makeLayer() -> CALayer {
        let l = CALayer()
        l.anchorPoint = .zero
        l.magnificationFilter = .nearest
        l.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "hidden": NSNull(),
                     "opacity": NSNull(), "backgroundColor": NSNull(), "shadowOpacity": NSNull()]
        return l
    }

    /// Weicher, dunkler Schatten der Sprite-Kontur (folgt dem Alphakanal des Bildes).
    static func applyShadow(_ on: Bool, to l: CALayer, scale: CGFloat) {
        l.shadowOpacity = on ? 0.45 : 0
        guard on else { return }
        l.shadowColor = CGColor(gray: 0, alpha: 1)
        l.shadowRadius = max(1, scale * 0.6)
        l.shadowOffset = CGSize(width: 0, height: -scale * 0.3)
    }

    private func layer(_ key: String) -> CALayer {
        if let l = layers[key] { return l }
        let l = Self.makeLayer()
        layers[key] = l
        return l
    }

    /// Sprite-Frame zeigen; `scale` = Kantenlänge eines Sprite-Pixels.
    /// - Parameter shadow: leichter Schatten entlang der Kontur, damit helle Requisiten auch auf weißem
    ///   Hintergrund erkennbar bleiben.
    func show(_ key: String, _ frame: ClawdSprite.Frame, origin: CGPoint, scale: CGFloat, opacity: Float = 1,
              mirrored: Bool = false, shadow: Bool = false) {
        let l = layer(key)
        l.contents = ClawdSprite.cgImage(frame, mirrored: mirrored)
        l.bounds = CGRect(x: 0, y: 0, width: CGFloat(frame[0].count) * scale, height: CGFloat(frame.count) * scale)
        l.opacity = opacity
        Self.applyShadow(shadow, to: l, scale: scale)
        stage?.place(layer: l, origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()))
    }

    /// Sprite-Frame um seinen Mittelpunkt `center` gedreht zeigen (z. B. ein Pfeil entlang seiner Flugbahn).
    func show(_ key: String, _ frame: ClawdSprite.Frame, center: CGPoint, scale: CGFloat, angle: CGFloat) {
        let l = layer(key)
        l.contents = ClawdSprite.cgImage(frame)
        l.bounds = CGRect(x: 0, y: 0, width: CGFloat(frame[0].count) * scale, height: CGFloat(frame.count) * scale)
        l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        l.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        l.opacity = 1
        stage?.place(layer: l, origin: CGPoint(x: center.x.rounded(), y: center.y.rounded()))
    }

    /// Sprite-Frame waagerecht um `x` zentriert zeigen.
    func show(_ key: String, _ frame: ClawdSprite.Frame, centerX x: CGFloat, bottom y: CGFloat, scale: CGFloat,
              opacity: Float = 1) {
        let width = CGFloat(frame[0].count) * scale
        show(key, frame, origin: CGPoint(x: x - width / 2, y: y), scale: scale, opacity: opacity)
    }

    /// Einfarbige Fläche zeigen, z. B. frische Farbe.
    func showRect(_ key: String, _ rect: CGRect, color: CGColor) {
        let l = layer(key)
        l.backgroundColor = color
        l.bounds = CGRect(origin: .zero, size: rect.size)
        // Auf ganze Punkte legen, damit kleine Flächen (Punkte einer Schnur) scharf bleiben.
        stage?.place(layer: l, origin: CGPoint(x: rect.origin.x.rounded(), y: rect.origin.y.rounded()))
    }

    func hide(_ key: String) {
        guard let l = layers[key], l.superlayer != nil else { return }
        l.removeFromSuperlayer()
    }

    /// Layer aus der Verwaltung lösen (er bleibt auf der Bühne), z. B. zum Liegenlassen.
    func detach(_ key: String) -> CALayer? {
        layers.removeValue(forKey: key)
    }

    /// Alle Layer der Bühne übergeben, die sie nach `lifetime` s ausblendet (Verblassen in den letzten `fade` s).
    func fadeOutAll(lifetime: TimeInterval, fade: TimeInterval) {
        for l in layers.values where l.superlayer != nil {
            stage?.leave(l, lifetime: lifetime, fade: fade)
        }
        layers = [:]
    }

    func removeAll() {
        layers.values.forEach { $0.removeFromSuperlayer() }
        layers = [:]
    }
}

/// Ball im Bogenflug von `from` nach `to` (Tennis, Ball zuspielen).
struct BallArc {
    var from: CGPoint
    var to: CGPoint
    var start: CFTimeInterval
    var duration: TimeInterval
    /// Scheitelhöhe über der geraden Verbindung.
    var arc: CGFloat

    /// 0…1, wie weit der Flug ist.
    func progress(_ now: CFTimeInterval) -> Double { min((now - start) / duration, 1) }

    func position(_ now: CFTimeInterval) -> CGPoint {
        let p = CGFloat(progress(now))
        return CGPoint(x: from.x + (to.x - from.x) * p, y: from.y + (to.y - from.y) * p + arc * sin(.pi * p))
    }

    /// Flugrichtung (Winkel gegen die Waagerechte) – z. B. damit ein Pfeil mit der Spitze voran fliegt.
    func heading(_ now: CFTimeInterval) -> CGFloat {
        let p = CGFloat(progress(now))
        return atan2((to.y - from.y) + arc * .pi * cos(.pi * p), to.x - from.x)
    }
}

/// Ball, der nach einem Fehlschlag über den Boden davonhüpft.
struct BouncingBall {
    var pos: CGPoint
    var vel: CGVector
    var until: CFTimeInterval

    mutating func step(dt: TimeInterval, floor: CGFloat) {
        vel.dy -= 1500 * CGFloat(dt)
        pos.x += vel.dx * CGFloat(dt)
        pos.y += vel.dy * CGFloat(dt)
        if pos.y <= floor {
            pos.y = floor
            vel.dy = abs(vel.dy) * 0.45
            vel.dx *= 0.7
        }
    }
}
