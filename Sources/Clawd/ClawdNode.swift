import AppKit

/// Ein Clawd auf der Bühne: ein Container-Layer mit dem Sprite unten in der Mitte, Requisiten
/// (Laptop, Kopfhörer, Sportgeräte) und aufsteigenden Partikeln (Zzz, Noten, Code, Schweiß).
/// Zeigt gecachte Bilder an – ein Frame-Wechsel tauscht nur `contents`, nichts wird neu gezeichnet.
final class ClawdNode {
    enum Particles {
        case none, zzz, notes, code, flow, sweat, steam, dust, dustFall, hearts, sneeze, water, sparks, birds, confetti, foam, paper, cables
    }

    /// Rand um das Sprite in Sprite-Pixeln.
    static let marginX = 4
    static let marginTop = 8

    static func canvasSize(pixel: CGFloat) -> NSSize {
        NSSize(width: CGFloat(ClawdSprite.columns + 2 * marginX) * pixel,
               height: CGFloat(ClawdSprite.rows + marginTop) * pixel)
    }

    /// Container; `position` ist die untere linke Ecke (anchorPoint = 0,0) im Overlay.
    let layer = CALayer()

    var pixel: CGFloat { didSet { if pixel != oldValue { layoutAll() } } }

    var facingLeft = false {
        didSet {
            guard facingLeft != oldValue else { return }
            updateSprite()
            updateSportProp()
            updateDustPile()
            layoutBubble()
            layoutHat()
        }
    }

    var sprite: ClawdSprite.Frame = ClawdSprite.stand {
        didSet {
            guard sprite != oldValue else { return }
            updateSprite()
            if ClawdSprite.headRow(sprite) != ClawdSprite.headRow(oldValue) {
                layoutProps()
                layoutBubble()
                layoutHat()
            }
        }
    }

    /// Clawd ein paar Sprite-Pixel anheben (z. B. beim Seilspringen).
    var liftPixels: CGFloat = 0 {
        didSet { if liftPixels != oldValue { layoutSpriteFrame() } }
    }

    var showLaptop = false {
        didSet { if showLaptop != oldValue { laptopLayer.isHidden = !showLaptop } }
    }

    var showHeadphones = false {
        didSet { if showHeadphones != oldValue { headphonesLayer.isHidden = !showHeadphones } }
    }

    /// Staubhaufen vor Clawd: 0 = keiner, 1…3 = wachsend.
    var dustPile = 0 {
        didSet { if dustPile != oldValue { updateDustPile() } }
    }

    /// Sportgerät im 18×11-Requisitenraster (oder nil).
    var sportProp: ClawdSprite.Frame? {
        didSet {
            guard sportProp != oldValue else { return }
            updateSportProp()
        }
    }

    var particles: Particles = .none {
        didSet {
            guard particles != oldValue else { return }
            particleGlyphIndex = Array(repeating: -1, count: particleLayers.count)
            animateParticles()
        }
    }

    private let spriteLayer = CALayer()
    private let laptopLayer = CALayer()
    private let headphonesLayer = CALayer()
    private let sportLayer = CALayer()
    private let pileLayer = CALayer()
    private let bubbleLayer = CALayer()
    private let hatLayer = CALayer()

    /// Kopfbedeckung (z. B. Bauhelm), sitzt eine Reihe über dem Kopf.
    var hat: ClawdSprite.Frame? {
        didSet {
            guard hat != oldValue else { return }
            hatLayer.isHidden = hat == nil
            layoutHat()
        }
    }

    /// Inhalt der Sprechblase (Standard: "…").
    var bubbleFrame: ClawdSprite.Frame = ClawdSprite.speechBubble {
        didSet { if bubbleFrame != oldValue { layoutBubble() } }
    }

    /// Sprechblase "…" über dem Kopf (beim Plaudern).
    var showBubble = false {
        didSet {
            guard showBubble != oldValue else { return }
            bubbleLayer.isHidden = !showBubble
            layoutBubble()
        }
    }
    private let particleLayers = (0..<3).map { _ in CALayer() }
    private var particleGlyphIndex = [-1, -1, -1]

    init(pixel: CGFloat) {
        self.pixel = pixel
        layer.anchorPoint = .zero
        // Keine impliziten Animationen – Clawd bewegt sich selbst.
        let none: [String: CAAction] = ["position", "bounds", "frame", "contents", "opacity", "hidden",
                                         "sublayers", "onOrderIn", "onOrderOut", "transform", "anchorPoint", "shadowOpacity"]
            .reduce(into: [:]) { $0[$1] = NSNull() }
        layer.actions = none
        for l in [spriteLayer, headphonesLayer, laptopLayer, sportLayer, pileLayer, bubbleLayer, hatLayer] + particleLayers {
            l.actions = none
            l.magnificationFilter = .nearest
            l.isHidden = l !== spriteLayer
            layer.addSublayer(l)
        }
        laptopLayer.contents = ClawdSprite.cgImage(ClawdSprite.laptop)
        headphonesLayer.contents = ClawdSprite.cgImage(ClawdSprite.headphones)
        layoutAll()
    }

    /// Nach einem Theme-Wechsel alle Bilder neu setzen.
    func refreshTheme() {
        updateSprite()
        laptopLayer.contents = ClawdSprite.cgImage(ClawdSprite.laptop)
        headphonesLayer.contents = ClawdSprite.cgImage(ClawdSprite.headphones)
        updateSportProp()
        updateDustPile()
        layoutBubble()
        layoutHat()
        particleGlyphIndex = Array(repeating: -1, count: particleLayers.count)
        animateParticles()
    }

    // MARK: - Layout

    private var spriteOriginX: CGFloat { CGFloat(Self.marginX) * pixel }

    private func layoutAll() {
        layer.bounds = CGRect(origin: .zero, size: Self.canvasSize(pixel: pixel))
        layoutSpriteFrame()
        updateSprite()
        sportLayer.frame = CGRect(x: spriteOriginX - 2 * pixel, y: 0,
                                  width: CGFloat(ClawdSprite.propColumns) * pixel,
                                  height: CGFloat(ClawdSprite.propRows) * pixel)
        layoutProps()
        particleGlyphIndex = Array(repeating: -1, count: particleLayers.count)
        animateParticles()
    }

    private func layoutSpriteFrame() {
        spriteLayer.frame = CGRect(x: spriteOriginX, y: (liftPixels * pixel).rounded(),
                                   width: CGFloat(ClawdSprite.columns) * pixel,
                                   height: CGFloat(ClawdSprite.rows) * pixel)
        layoutBubble()
        layoutHat()
    }

    /// Requisiten hängen an der Kopfhöhe des aktuellen Frames (z. B. beim Mitwippen).
    private func layoutProps() {
        let px = pixel
        let headRow = ClawdSprite.headRow(sprite)

        // Laptop: 10 breit, mittig vor dem Bauch, unten bündig.
        laptopLayer.frame = CGRect(x: spriteOriginX + 2 * px, y: 0,
                                   width: CGFloat(ClawdSprite.laptop[0].count) * px * ClawdSprite.laptopScale,
                                   height: CGFloat(ClawdSprite.laptop.count) * px * ClawdSprite.laptopScale)

        // Kopfhörer: oberste Zeile eine Reihe über dem Kopf.
        let rowsHigh = ClawdSprite.headphones.count
        let topRow = headRow - 1
        let bottomY = CGFloat(ClawdSprite.rows - topRow - rowsHigh) * px
        headphonesLayer.frame = CGRect(x: spriteOriginX, y: bottomY,
                                       width: CGFloat(ClawdSprite.columns) * px,
                                       height: CGFloat(rowsHigh) * px)
    }

    /// Magnetschuhe an den Füßen zeigen.
    var boots = false {
        didSet { if boots != oldValue { updateSprite() } }
    }

    /// Schuhe leuchten auf (ein Fenster ist zum Andocken nah genug).
    var bootsGlow = false {
        didSet { if bootsGlow != oldValue { updateSprite() } }
    }

    private func updateSprite() {
        // Schuhe nur an Clawd selbst – nicht, wenn er gerade in einen Frosch verwandelt ist.
        let wearsBoots = boots && sprite.contains { $0.contains("X") }
        let frame = wearsBoots ? ClawdSprite.withBoots(sprite, color: bootsGlow ? "k" : "u") : sprite
        spriteLayer.contents = ClawdSprite.cgImage(frame, mirrored: facingLeft)
    }

    private func layoutHat() {
        guard let hat else { return }
        let headTop = (CGFloat(ClawdSprite.rows - ClawdSprite.headRow(sprite)) + liftPixels) * pixel
        hatLayer.contents = ClawdSprite.cgImage(hat, mirrored: facingLeft)
        EffectLayers.applyShadow(ClawdSprite.hasShadow(hat), to: hatLayer, scale: pixel)
        // Hut ist so breit wie das Sprite (14 Spalten, oder 28 in doppelter Auflösung).
        // Krempe (unterste Zeile) liegt auf der obersten Kopfzeile, der Rest ragt darüber.
        let scale = pixel * CGFloat(ClawdSprite.columns) / CGFloat(hat[0].count)
        hatLayer.frame = CGRect(x: spriteOriginX, y: headTop - pixel,
                                width: CGFloat(hat[0].count) * scale, height: CGFloat(hat.count) * scale)
    }

    private func layoutBubble() {
        guard showBubble else { return }
        let b = bubbleFrame
        let scale = pixel * 0.75
        let width = CGFloat(b[0].count) * scale
        let headTop = (CGFloat(ClawdSprite.rows - ClawdSprite.headRow(sprite)) + liftPixels) * pixel
        let center = spriteOriginX + CGFloat(ClawdSprite.columns) * pixel / 2 + (facingLeft ? -3 : 3) * pixel
        bubbleLayer.contents = ClawdSprite.cgImage(b, mirrored: facingLeft)
        bubbleLayer.frame = CGRect(x: center - width / 2, y: headTop + pixel,
                                   width: width, height: CGFloat(b.count) * scale)
    }

    /// Staubhaufen direkt vor dem Besen (vor Clawds Füßen in Blickrichtung).
    private func updateDustPile() {
        pileLayer.isHidden = dustPile == 0
        guard dustPile > 0 else { return }
        let frame = ClawdSprite.dustPiles[min(dustPile, 3) - 1]
        let width = CGFloat(frame[0].count) * pixel
        let front = facingLeft ? spriteOriginX - width - pixel
                               : spriteOriginX + CGFloat(ClawdSprite.columns + 2) * pixel
        pileLayer.contents = ClawdSprite.cgImage(frame)
        pileLayer.frame = CGRect(x: front, y: 0, width: width, height: CGFloat(frame.count) * pixel)
    }

    /// Requisite (Hantel, Seil, Schüssel, Schläger) – folgt der Blickrichtung.
    private func updateSportProp() {
        sportLayer.isHidden = sportProp == nil
        if let sportProp { sportLayer.contents = ClawdSprite.cgImage(sportProp, mirrored: facingLeft) }
    }

    // MARK: - Partikel

    private var glyphs: [ClawdSprite.Frame] {
        switch particles {
        case .none: []
        case .zzz: [ClawdSprite.zGlyph]
        case .notes: ClawdSprite.noteGlyphs
        case .code: ClawdSprite.codeLines
        case .flow: ClawdSprite.codeLines + ClawdSprite.noteGlyphs
        case .sweat: [ClawdSprite.sweatGlyph]
        case .steam: [ClawdSprite.steamGlyph]
        case .dust, .dustFall: [ClawdSprite.dustGlyph]
        case .hearts: [ClawdSprite.heartGlyph]
        case .sneeze, .water: [ClawdSprite.sweatGlyph]
        case .sparks: [ClawdSprite.sparkleGlyph]
        case .birds: ClawdSprite.birdFrames
        case .confetti: ClawdSprite.confettiGlyphs
        case .paper: [ClawdSprite.paperSheet]
        case .cables: ClawdSprite.cableBits
        case .foam: [["U", "U"].map { $0 + $0 }]
        }
    }

    private var period: Double {
        switch particles {
        case .zzz: 2.4
        case .notes: 1.8
        case .code: 2.0
        case .flow: 1.9
        case .sweat: 1.1
        case .steam: 1.6
        case .dust: 0.9
        case .dustFall: 0.7
        case .hearts: 1.7
        case .sneeze: 0.5
        case .water: 0.45
        case .sparks: 0.35
        case .birds: 1.2
        case .confetti: 1.1
        case .paper: 0.7
        case .cables: 0.75
        case .foam: 0.4
        case .none: 1
        }
    }

    /// Drei Vögelchen kreisen flatternd über dem Kopf (wie nach einem Schlag im Comic).
    private func animateBirds(t: CFTimeInterval, headTop: CGFloat, centerX: CGFloat) {
        let scale = pixel * 0.6
        for (k, l) in particleLayers.enumerated() {
            let flap = (Int(t / 0.12) + k) % 2
            let g = ClawdSprite.birdFrames[flap]
            l.contents = ClawdSprite.cgImage(g)
            l.bounds = CGRect(x: 0, y: 0, width: CGFloat(g[0].count) * scale, height: CGFloat(g.count) * scale)
            let angle = t * 2 * .pi / 1.2 + Double(k) * 2 * .pi / 3
            let x = centerX + CGFloat(cos(angle)) * 5 * pixel - l.bounds.width / 2
            let y = headTop + pixel + CGFloat(sin(angle)) * 1.3 * pixel
            l.frame.origin = CGPoint(x: (x / (pixel / 2)).rounded() * (pixel / 2), y: (y / (pixel / 2)).rounded() * (pixel / 2))
            l.opacity = 1
            l.isHidden = false
        }
        particleGlyphIndex = Array(repeating: -1, count: particleLayers.count)
    }

    /// Schweiß: nur ab und zu eine einzelne, winzige Perle, die vom Kopf abperlt und herunterfällt.
    private func animateSweat(t: CFTimeInterval, headTop: CGFloat, centerX: CGFloat) {
        particleLayers.dropFirst().forEach { $0.isHidden = true }
        let l = particleLayers[0]
        let period = 2.6
        let flight = 0.3 // Anteil des Zyklus, in dem eine Perle unterwegs ist
        let cycle = t / period
        let phase = cycle.truncatingRemainder(dividingBy: 1)
        guard phase < flight else {
            l.isHidden = true
            return
        }
        let half = pixel / 2
        if particleGlyphIndex[0] != 0 {
            particleGlyphIndex[0] = 0
            l.contents = ClawdSprite.cgImage(ClawdSprite.sweatGlyph)
            l.bounds = CGRect(x: 0, y: 0, width: half, height: pixel)
        }
        let p = CGFloat(phase / flight)
        let lane: CGFloat = Int(cycle) % 2 == 0 ? 1 : -1 // abwechselnd links/rechts
        let x = centerX + lane * (4.5 + p * 2.5) * pixel
        let y = headTop - pixel + (sin(p * .pi) * 1.5 - p * 2.5) * pixel
        l.frame.origin = CGPoint(x: (x / half).rounded() * half, y: (y / half).rounded() * half)
        l.opacity = Float(p < 0.75 ? 1 : (1 - p) / 0.25)
        l.isHidden = false
    }

    /// Bewegt die Partikel (pro Tick aufrufen, solange welche sichtbar sind).
    func animateParticles() {
        let glyphs = glyphs
        guard !glyphs.isEmpty else {
            particleLayers.forEach { $0.isHidden = true }
            return
        }
        let t = CACurrentMediaTime()
        let px = pixel
        let scale = px * ([.steam, .dust, .dustFall, .sneeze, .water, .sparks, .confetti, .foam, .paper].contains(particles) ? 0.5 : 0.75)
        let headTop = (CGFloat(ClawdSprite.rows - ClawdSprite.headRow(sprite)) + liftPixels) * px
        let side: CGFloat = facingLeft ? -1 : 1
        let centerX = spriteOriginX + CGFloat(ClawdSprite.columns) * px / 2

        if particles == .sweat {
            animateSweat(t: t, headTop: headTop, centerX: centerX)
            return
        }
        if particles == .birds {
            animateBirds(t: t, headTop: headTop, centerX: centerX)
            return
        }

        for (k, l) in particleLayers.enumerated() {
            let cycleTime = t / period + Double(k) / 3
            let phase = cycleTime.truncatingRemainder(dividingBy: 1)
            let p = CGFloat(phase)

            // Bei jedem neuen Durchlauf ein anderes Motiv (z. B. eine andere Codezeile).
            // Flow: gerade Ebenen zeigen Code, ungerade Noten.
            let pool = particles == .flow ? (k % 2 == 0 ? ClawdSprite.codeLines : ClawdSprite.noteGlyphs) : glyphs
            let glyphIndex = (Int(cycleTime) * particleLayers.count + k) % pool.count
            if particleGlyphIndex[k] != glyphIndex {
                particleGlyphIndex[k] = glyphIndex
                let g = pool[glyphIndex]
                l.contents = ClawdSprite.cgImage(g)
                l.bounds = CGRect(x: 0, y: 0, width: CGFloat(g[0].count) * scale, height: CGFloat(g.count) * scale)
            }
            l.isHidden = false

            var origin: CGPoint
            switch particles {
            case .zzz:
                let startX = spriteOriginX + (facingLeft ? 1 : CGFloat(ClawdSprite.columns - 4)) * px
                origin = CGPoint(x: startX + (p * 4).rounded() * px * side, y: headTop + (p * 5).rounded() * px)
            case .flow where k % 2 == 0:
                // Flow: Codezeilen steigen über dem Laptop auf …
                let x = centerX - 4 * px + CGFloat(k - 1) * px * side
                origin = CGPoint(x: x, y: headTop + (p * 7).rounded() * px)
            case .notes, .flow:
                // Abwechselnd links und rechts vom Kopf, leicht schwingend (Flow: … und Noten daneben).
                let lane: CGFloat = k % 2 == 0 ? 1 : -1
                let sway = (sin(p * .pi * 2 + CGFloat(k)) * 1.5).rounded()
                let x = centerX + lane * 5 * px + sway * px - l.bounds.width / 2
                origin = CGPoint(x: x, y: headTop + (p * 6).rounded() * px)
            case .code:
                // Codezeilen steigen über dem Laptop auf, leicht versetzt eingerückt.
                let x = centerX - 4 * px + CGFloat(k - 1) * px * side
                origin = CGPoint(x: x, y: headTop + (p * 7).rounded() * px)
            case .cables:
                // Kabelstücke und Stecker fliegen in hohen Bögen nach vorn und hinten weg.
                let out: CGFloat = k % 2 == 0 ? side : -side
                let start = centerX + side * 10 * px
                let x = start + out * (p * 14 + CGFloat(k) * 2) * px - l.bounds.width / 2
                origin = CGPoint(x: x, y: (2 + sin(p * .pi) * (8 + CGFloat(k) * 2) - p * 3) * px)
            case .paper:
                // Papierflut: Blätter schießen vorne aus dem Drucker und flattern zu Boden.
                let x = centerX + side * (11 + p * 9 + CGFloat(k) * 1.5) * px - l.bounds.width / 2
                origin = CGPoint(x: x, y: (3 + sin(p * .pi) * 3 - p * 3) * px)
            case .confetti:
                // Bunte Schnipsel regnen um Clawd herum herunter.
                let lane = CGFloat(k - 1) * 5
                let x = centerX + lane * px + (sin(p * .pi * 4 + CGFloat(k)) * 1.5).rounded() * px
                origin = CGPoint(x: x, y: headTop + 6 * px - (p * 10).rounded() * px)
            case .foam:
                // Löschschaum spritzt nach vorn.
                let x = centerX + side * (9 + p * 6 + CGFloat(k)) * px - l.bounds.width / 2
                origin = CGPoint(x: x, y: (5 + CGFloat(k - 1) * 0.8 - p * 1.5) * px)
            case .sparks:
                // Funken springen vorne am Boden auf.
                let x = centerX + side * (8.5 + CGFloat(k - 1) * 1.2 + p * 1.5) * px - l.bounds.width / 2
                origin = CGPoint(x: x, y: (p * 3 + CGFloat(k % 2)).rounded() * px)
            case .water:
                // Wasser tropft vorne aus der Gießkanne.
                let x = centerX + side * (8.5 + CGFloat(k - 1) * 0.5) * px - l.bounds.width / 2
                origin = CGPoint(x: x, y: 4 * px - (p * 5).rounded() * px)
            case .sneeze:
                // Tröpfchen fliegen schnell nach vorn aus dem Gesicht.
                let x = centerX + side * (5 + p * 9) * px - l.bounds.width / 2
                origin = CGPoint(x: (x / (px / 2)).rounded() * (px / 2),
                                 y: headTop - (3 + CGFloat(k - 1) * 1.2 + p * 1.5) * px)
            case .hearts:
                // Herzchen steigen zwischen den beiden (vorn) auf.
                let x = centerX + side * (7 + CGFloat(k % 2) * 2) * px - l.bounds.width / 2
                origin = CGPoint(x: x + (sin(p * .pi * 2 + CGFloat(k)) * 1).rounded() * px,
                                 y: headTop + (p * 6).rounded() * px)
            case .dust:
                // Staubwölkchen wirbeln vorne am Besen auf.
                let front = centerX + side * (8 + CGFloat(k)) * px - l.bounds.width / 2
                origin = CGPoint(x: front + side * (p * 2).rounded() * px, y: (p * 3).rounded() * px)
            case .dustFall:
                // Staub rieselt vorne aus dem gekippten Kehrblech nach unten (in den Papierkorb).
                let x = centerX + side * (8.5 + CGFloat(k - 1) * 0.5) * px - l.bounds.width / 2
                origin = CGPoint(x: x, y: 2 * px - (p * 10).rounded() * px)
            case .steam:
                // Dampf steigt aus der Schüssel auf.
                let lane = CGFloat(k - 1) * 2.5
                let x = centerX + lane * px - l.bounds.width / 2 + (sin(p * .pi * 2) * 0.5).rounded() * px
                origin = CGPoint(x: x, y: 3 * px + (p * 6).rounded() * px)
            case .sweat:
                // Tropfen fliegen seitlich vom Kopf weg.
                let lane: CGFloat = k % 2 == 0 ? 1 : -1
                let x = centerX + lane * (5 + (p * 4).rounded()) * px - l.bounds.width / 2
                origin = CGPoint(x: x, y: headTop - px + (sin(p * .pi) * 3).rounded() * px)
            case .none, .birds: // Vögel haben eigene Bahnen (animateBirds)
                origin = .zero
            }
            l.frame.origin = origin
            l.opacity = Float(sin(.pi * phase))
        }
    }
}
