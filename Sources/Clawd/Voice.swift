import AVFoundation
import QuartzCore

/// Clawds Stimme: ein süßes, synthetisiertes Kauderwelsch-Murmeln (keine Audiodateien).
///
/// Eine gemeinsame Audio-Engine; jeder Clawd bekommt einen eigenen `Channel` mit eigener
/// Tonhöhe, damit sich mehrere Clawds nicht gegenseitig abschneiden.
final class Voice {
    /// Die Stimme eines einzelnen Clawds.
    final class Channel {
        fileprivate weak var voice: Voice?
        /// Stimme
        fileprivate let player = Track()
        /// Eigene Spur für Geräusche (Landung, Enterhaken, Triebwerk): schneiden die Stimme nicht ab
        /// und werden nicht von ihr abgeschnitten.
        fileprivate let noise = Track()
        let pitch: Double

        fileprivate init(voice: Voice, pitch: Double) {
            self.voice = voice
            self.pitch = pitch
        }

        func play(_ sound: Sound) {
            voice?.play(sound, on: self, track: player)
        }

        func playNoise(_ sound: Sound) {
            voice?.play(sound, on: self, track: noise)
        }

        /// Eigener Klangstil nur für diesen Kanal (z. B. gedämpfte "Telefonstimme").
        var style: Style?

        /// Weiterer Kanal auf derselben Engine (z. B. der Gesprächspartner im Videocall).
        func sibling(pitch: Double) -> Channel? { voice?.makeChannel(pitch: pitch) }

        /// Kanal von der Engine lösen (wenn der Clawd verschwindet).
        func close() {
            Safely.run("Kanal schließen") {
                for track in [player, noise] {
                    track.node.stop()
                    voice?.engine.detach(track.node)
                }
            }
        }
    }

    /// Eine Tonspur: ein Player und bis wann er gerade spielt.
    fileprivate final class Track {
        let node = AVAudioPlayerNode()
        var busyUntil: CFTimeInterval = 0
    }

    /// Läuft auf der Spur noch ein Laut, der höchstens so lange (s) dauert, wird der neue dahinter
    /// angestellt statt ihn abzuschneiden – kurze Laute überdecken sich nicht. Längere werden
    /// unterbrochen, damit nichts merklich verspätet kommt.
    static let queueWindow: CFTimeInterval = 0.35

    /// Neuen Laut hinten anstellen (true) oder den laufenden unterbrechen (false)?
    static func shouldQueue(remaining: CFTimeInterval) -> Bool {
        remaining > 0 && remaining <= queueWindow
    }

    enum Sound: CaseIterable {
        /// Die Verabschiedungen, im Wechsel verwendet.
        static let byes: [Sound] = [.byeRising, .byeFalling, .byeHop]
        /// Varianten für dieselbe Situation – pro Auslösung wird zufällig eine gewählt.
        static let startled: [Sound] = [.eep, .huch, .huhUch]     // Schreck
        static let cheer: [Sound] = [.whee, .uiii, .uiiiSlide]    // Juchzen
        static let whine: [Sound] = [.weeh, .weehEeh]             // Jammern
        static let fluster: [Sound] = [.oiWorried, .oiExcited]    // Aufregung
        static let landing: [Sound] = [.landSoft, .landCushion, .landPlop] // "Plumps" (Geräusch, im Wechsel)

        case murmur // zufälliges Plappern
        case happy  // fröhlich aufsteigend (Winken)
        case eep    // erschrocken (hochgehoben, geweckt)
        case oof    // Aufprall
        case hop    // kleiner Hüpfer
        case snore  // leises Schnarchen
        case whee   // "Wiiieee" beim Fallen
        case hum    // summt eine kleine Melodie mit (Musik hören)
        case sleepyWe // Cartoon-Schnarchen: einatmen … "we we we we"
        case slurp  // Nudeln schlürfen
        case munch  // fröhliches "nom nom nom" beim Kauen, mit zufriedenem Quietscher
        case pock   // Ball trifft Schläger
        case plop   // kurzes "Plopp" (Pfeil abgeschossen)
        case wallPock // Ball trifft die Wand
        case swish  // Besenstrich
        case pour   // Staub rieselt aus dem Kehrblech
        case haa    // Niesen, Anlauf: "ha… ha…"
        case achoo  // Niesen: "TSCHIII!"
        case giggle // nach dem Niesen: "huhuhuhu"
        case yawn   // Gähnen: "aaahhh-mmm"
        case tweet  // Vögelchen: "piep piep"
        case scold  // empörtes Schimpfen
        case ring   // Freizeichen "tuut"
        case pickup // Abheben "blip"
        case byeRising  // "Bye": hoher Ton, dann ein tieferer, beide leicht steigend (endet offen)
        case byeFalling // "Bye-bye": zwei ruhige Töne eine Quarte abwärts
        case byeHop     // "Bye": zwei kurze, helle Hüpfer, der zweite tiefer
        case hangup // Auflegen "düdüt"
        case squeak // Quietscheente
        case alarm  // Alarm "düü-daa"
        case beep   // kurzer Countdown-Piep
        case launch // Raketenstart: zischendes Rauschen
        case print  // Drucker "brrrt"
        case ding   // Küchenwecker-Klingeln
        case clap   // Applaus
        case clink  // Tassen anstoßen
        case uiii       // dunkles "u", dann ein langes, helles "iii"
        case uiiiSlide  // "uiii", das immer weiter ansteigt (Abrutschen)
        case huch       // kurzer Schreck, im Wechsel "Hu!", "Ui!", "Hö?"
        case huhUch     // zweisilbiger Schreck, im Wechsel "Hu-hu!", "Hu-ui!", "Ah-hu!"
        case weeh       // langes, weinerliches "weeeh"
        case weehEeh    // zweiteiliges Jammern "weeh-eeh"
        case oiWorried  // fünf schnelle "oi", die tiefer werden
        case oiExcited  // fünf schnelle "oi", die höher werden
        case uff        // hauchiges "uff" mit Ausatmen
        case autsch     // "au" mit kurzem "tsch" (harte Landung nach einem Sturz)
        case bonk       // Comic-Aufprall gegen Decke oder Bildschirmrand
        case hmpf       // beleidigtes Schnauben
        case grrr       // tiefes, rollendes Knurren
        case naWarte    // "Na warte!"
        case relief     // erleichtertes Durchschnaufen nach einer sanften Landung (im Wechsel)
        // Geräusche (keine Stimme): spielen unabhängig von der Gesprächigkeit, siehe `PetController.playNoise`.
        case grappleShot  // Enterhaken abgefeuert: aufsteigendes "Fwiiip"
        case grappleCatch // Haken greift: metallisches "Klonk-kling"
        case jetCough     // Triebwerk stottert: dumpfes "Puff"
        case jetThrust    // Triebwerk auf vollem Schub: lautes, steigendes Rauschen
        case landSoft     // Landung: weiches, kurzes "Plumps"
        case landCushion  // Landung: luftig, wie auf ein Kissen
        case landPlop     // Landung: leichtes "Plopp"
        case umbrellaOpen   // Regenschirm springt auf: aufsteigendes "Fwupp"
        case balloonInflate // Ballon aufgepustet: steigendes Pfeifen
    }

    struct Syllable {
        var start: Double
        var duration: Double
        var f0: Double      // Startfrequenz
        var f1: Double      // Endfrequenz
        var amp: Double
        var breath: Double = 0 // Rauschanteil
        var vibrato: Double = 0.025
        /// 0 = summend (fast reiner Sinus), 1 = normaler Plapper-Klang.
        var brightness: Double = 1
        /// Ungefiltertes Rauschen für Zischlaute ("tsch").
        var hiss: Double = 0
    }


    /// Klangcharakter der Synthese (wie viel Atemrauschen, wie stark gefiltert).
    /// Standard ist der klare Klang ("Variante C").
    struct Style {
        /// Lautstärke des Atemrauschens.
        var breathGain: Double = 0.8
        /// Wie stark der Ton bei Atemanteil zurückgenommen wird (1 = ganz).
        var breathDuck: Double = 0.2
        /// Glättung des Tiefpasses: klein = dumpf, 1 = ungefiltert.
        var smoothing: Double = 0.8
        /// Tiefe Silben (unter 300 Hz) um diesen Faktor höher legen.
        var lowBoost: Double = 1
        /// Gesamtlautstärke dieses Stils.
        var gain: Double = 1
    }

    /// Gesamtlautstärke aller Clawds (0…1).
    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = min(max(newValue, 0), 1) }
    }

    fileprivate let engine = AVAudioEngine()
    private let sampleRate: Double = 44_100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private var configObserver: NSObjectProtocol?
    /// Plappern/Schnarchen/Freuen aller Clawds zusammen höchstens alle 0,8 s.
    private var lastAmbient: CFTimeInterval = 0
    private let ambientGap: CFTimeInterval = 0.8

    init() {
        engine.mainMixerNode.outputVolume = 0.6
        // Bei Wechsel des Ausgabegeräts stoppt die Engine – dann neu starten.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.startIfNeeded() }
    }

    func makeChannel(pitch: Double = 1) -> Channel {
        let channel = Channel(voice: self, pitch: pitch)
        Safely.run("Kanal anlegen") {
            for track in [channel.player, channel.noise] {
                engine.attach(track.node)
                engine.connect(track.node, to: engine.mainMixerNode, format: format)
            }
        }
        return channel
    }

    /// Stumm, solange ein Video läuft oder eine App im Vollbild ist (setzt der MediaWatcher).
    var muted = false

    fileprivate func play(_ sound: Sound, on channel: Channel, track: Track) {
        guard !muted else { return }
        switch sound {
        case .murmur, .snore, .happy, .hum, .sleepyWe:
            let now = CACurrentMediaTime()
            guard now - lastAmbient >= ambientGap else { return }
            lastAmbient = now
        default:
            break
        }
        startIfNeeded()
        guard engine.isRunning, let buffer = buffer(for: sound, pitch: channel.pitch, style: channel.style) else { return }
        // Wechselt gerade das Ausgabegerät (z. B. beim Zuklappen), wirft AVFoundation hier eine
        // Objective-C-Exception – dann fällt der Laut eben aus.
        let now = CACurrentMediaTime()
        let duration = Double(buffer.frameLength) / sampleRate
        let remaining = track.busyUntil - now
        let queue = Self.shouldQueue(remaining: remaining)
        Safely.run("Laut \(sound)") {
            track.node.scheduleBuffer(buffer, at: nil, options: queue ? [] : .interrupts)
            if !track.node.isPlaying { track.node.play() }
        }
        track.busyUntil = (queue ? track.busyUntil : now) + duration
    }

    /// Erzeugt den Laut als Audiopuffer (auch für Tests nutzbar).
    func buffer(for sound: Sound, pitch: Double = 1, style override: Style? = nil) -> AVAudioPCMBuffer? {
        let style = override ?? Style()
        let syllables = syllables(for: sound).map { s -> Syllable in
            var s = s
            let boost = s.f0 < 300 ? style.lowBoost : 1
            s.f0 *= pitch * boost
            s.f1 *= pitch * boost
            return s
        }
        return render(syllables, style: style)
    }

    private func startIfNeeded() {
        guard !engine.isRunning else { return }
        Safely.run("Audio starten") { try? engine.start() }
    }

    // MARK: - Laute

    // MARK: Bausteine, die mehrere Laute teilen

    /// Hauchiges "Uff" (ohne das Zischen am Ende).
    private static let uffBreath = Syllable(start: 0, duration: 0.2, f0: 470, f1: 330, amp: 0.22, breath: 0.45,
                                            vibrato: 0, brightness: 0.6)
    /// Langes, abfallendes "Aaah" vom Gähnen.
    private static let yawnSigh = Syllable(start: 0, duration: 0.95, f0: 520, f1: 300, amp: 0.14, breath: 0.4,
                                           vibrato: 0.02, brightness: 0.6)
    /// Zufriedenes "mm" am Ende des Gähnens.
    private static let contentHum = Syllable(start: 0, duration: 0.28, f0: 270, f1: 240, amp: 0.08, vibrato: 0, brightness: 0.1)
    /// Fröhlich aufsteigend (Winken).
    private static let happyRise = [
        Syllable(start: 0, duration: 0.08, f0: 680, f1: 760, amp: 0.22),
        Syllable(start: 0.11, duration: 0.08, f0: 820, f1: 900, amp: 0.22),
        Syllable(start: 0.22, duration: 0.14, f0: 960, f1: 1180, amp: 0.22),
    ]
    /// Verlegenes, schnelles "huhuhuhu", leicht abfallend.
    private static func giggle(count: Int) -> [Syllable] {
        (0..<count).map { i in
            let f = 760 - Double(i) * 25
            return Syllable(start: Double(i) * 0.115, duration: 0.07, f0: f * 1.05, f1: f * 0.9, amp: 0.13,
                            breath: 0.25, vibrato: 0, brightness: 0.5)
        }
    }

    private func syllables(for sound: Sound) -> [Syllable] {
        switch sound {
        case .murmur:
            let base = Double.random(in: 560...720)
            let count = Int.random(in: 3...6)
            let rising = Bool.random() // Frage oder Feststellung
            var out: [Syllable] = []
            var t = 0.0
            for i in 0..<count {
                let isLast = i == count - 1
                let f = base * Double.random(in: 0.88...1.22)
                let glide = isLast ? (rising ? 1.25 : 0.8) : Double.random(in: 0.9...1.1)
                let d = isLast ? Double.random(in: 0.12...0.16) : Double.random(in: 0.06...0.1)
                out.append(Syllable(start: t, duration: d, f0: f, f1: f * glide, amp: 0.22))
                t += d + Double.random(in: 0.025...0.055)
            }
            return out
        case .happy:
            return Self.happyRise
        case .eep:
            return [Syllable(start: 0, duration: 0.13, f0: 880, f1: 1450, amp: 0.24)]
        case .oof:
            return [
                Syllable(start: 0, duration: 0.08, f0: 520, f1: 400, amp: 0.26),
                Syllable(start: 0.1, duration: 0.15, f0: 430, f1: 320, amp: 0.24),
            ]
        case .hop:
            return [Syllable(start: 0, duration: 0.07, f0: 720, f1: 980, amp: 0.15)]
        case .whee:
            // Hoch einsetzen, dann lang nach unten gleiten – mit kräftigem Vibrato.
            return [
                Syllable(start: 0, duration: 0.09, f0: 1050, f1: 1250, amp: 0.2),
                Syllable(start: 0.1, duration: 0.55, f0: 1300, f1: 620, amp: 0.2, vibrato: 0.05),
            ]
        case .hum:
            // Kleine pentatonische Melodie, gebunden gesummt ("mm-mm-mmm").
            let scale = [0, 2, 4, 7, 9, 12].map { pow(2, Double($0) / 12) }
            let base = Double.random(in: 380...460)
            var t = 0.0
            var step = Int.random(in: 0...3)
            var out: [Syllable] = []
            for i in 0..<Int.random(in: 6...9) {
                step = min(max(step + Int.random(in: -2...2), 0), scale.count - 1)
                let f = base * scale[step]
                let d = (i % 3 == 2) ? 0.32 : Double.random(in: 0.16...0.22)
                out.append(Syllable(start: t, duration: d, f0: f, f1: f * 0.99, amp: 0.13,
                                    vibrato: 0.012, brightness: 0.15))
                t += d + 0.015
            }
            return out
        case .slurp:
            // Luftiges, aufsteigendes "fwüüp".
            return [Syllable(start: 0, duration: 0.28, f0: 380, f1: 1100, amp: 0.11, vibrato: 0,
                             brightness: 0.4, hiss: 0.35)]
        case .munch:
            // Schnelle, hüpfende Kau-Silben ("nom nom nom"), dann ein kleiner Quietscher.
            var out: [Syllable] = []
            var t = 0.0
            let base = Double.random(in: 640...760)
            for i in 0..<Int.random(in: 3...5) {
                let f = base * (i % 2 == 0 ? 1.0 : 1.12) * Double.random(in: 0.97...1.03)
                out.append(Syllable(start: t, duration: 0.065, f0: f * 1.08, f1: f * 0.85, amp: 0.17,
                                    vibrato: 0, brightness: 0.7))
                t += 0.065 + 0.045
            }
            if Bool.random() {
                out.append(Syllable(start: t + 0.04, duration: 0.12, f0: base * 1.3, f1: base * 1.7, amp: 0.15))
            }
            return out
        case .swish:
            // Kurzes, helles "schh"
            return [Syllable(start: 0, duration: 0.16, f0: 300, f1: 260, amp: 0.05, vibrato: 0, brightness: 0, hiss: 0.85)]
        case .haa:
            // Zweimal hauchig einatmen, jedes Mal etwas höher.
            return [
                Syllable(start: 0, duration: 0.28, f0: 480, f1: 600, amp: 0.12, breath: 0.55, vibrato: 0, brightness: 0.6),
                Syllable(start: 0.55, duration: 0.34, f0: 560, f1: 760, amp: 0.14, breath: 0.5, vibrato: 0, brightness: 0.6),
            ]
        case .achoo:
            // Kurzer Stoß "t", dann zischendes "schiii" mit hoher, fallender Stimme.
            return [
                Syllable(start: 0, duration: 0.04, f0: 900, f1: 900, amp: 0.2, vibrato: 0, hiss: 0.9),
                Syllable(start: 0.03, duration: 0.42, f0: 1500, f1: 1150, amp: 0.2, vibrato: 0.01, hiss: 0.45),
            ]
        case .giggle:
            return Self.giggle(count: Int.random(in: 4...6))
        case .squeak:
            return [
                Syllable(start: 0, duration: 0.07, f0: 1500, f1: 1150, amp: 0.13, vibrato: 0, brightness: 0.6),
                Syllable(start: 0.1, duration: 0.07, f0: 1550, f1: 1200, amp: 0.13, vibrato: 0, brightness: 0.6),
            ]
        case .alarm:
            return [
                Syllable(start: 0, duration: 0.18, f0: 880, f1: 880, amp: 0.09, vibrato: 0, brightness: 0.3),
                Syllable(start: 0.2, duration: 0.18, f0: 660, f1: 660, amp: 0.09, vibrato: 0, brightness: 0.3),
            ]
        case .beep:
            return [Syllable(start: 0, duration: 0.1, f0: 880, f1: 880, amp: 0.09, vibrato: 0, brightness: 0.1)]
        case .print:
            return [Syllable(start: 0, duration: 0.5, f0: 260, f1: 240, amp: 0.06, vibrato: 0.08, brightness: 0.8, hiss: 0.4)]
        case .clap:
            return (0..<5).map { i in
                Syllable(start: Double(i) * 0.14 + Double.random(in: 0...0.03), duration: 0.04, f0: 900, f1: 700,
                         amp: 0.12, vibrato: 0, brightness: 0.3, hiss: 0.9)
            }
        case .clink:
            return [
                Syllable(start: 0, duration: 0.09, f0: 2100, f1: 2050, amp: 0.08, vibrato: 0, brightness: 0.4),
                Syllable(start: 0.06, duration: 0.12, f0: 2600, f1: 2550, amp: 0.06, vibrato: 0, brightness: 0.4),
            ]
        case .ding:
            return [
                Syllable(start: 0, duration: 0.5, f0: 1600, f1: 1600, amp: 0.1, vibrato: 0.01, brightness: 0.3),
                Syllable(start: 0.45, duration: 0.5, f0: 1600, f1: 1600, amp: 0.09, vibrato: 0.01, brightness: 0.3),
            ]
        case .launch:
            return [Syllable(start: 0, duration: 1.3, f0: 140, f1: 320, amp: 0.12, vibrato: 0, brightness: 0.2, hiss: 0.6)]
        case .ring:
            // Deutsches Freizeichen: 425 Hz, fast reiner Ton
            return [Syllable(start: 0, duration: 0.9, f0: 425, f1: 425, amp: 0.09, vibrato: 0, brightness: 0)]
        case .pickup:
            return [Syllable(start: 0, duration: 0.08, f0: 620, f1: 940, amp: 0.1, vibrato: 0, brightness: 0.2)]
        case .byeRising:
            return [
                Syllable(start: 0, duration: 0.16, f0: 900, f1: 1000, amp: 0.2, vibrato: 0),
                Syllable(start: 0.2, duration: 0.28, f0: 620, f1: 820, amp: 0.2, vibrato: 0.03, brightness: 0.7),
            ]
        case .byeFalling:
            return [
                Syllable(start: 0, duration: 0.18, f0: 900, f1: 880, amp: 0.2, vibrato: 0.01),
                Syllable(start: 0.24, duration: 0.3, f0: 680, f1: 650, amp: 0.2, vibrato: 0.02, brightness: 0.6),
            ]
        case .byeHop:
            return [
                Syllable(start: 0, duration: 0.1, f0: 1050, f1: 1250, amp: 0.2, vibrato: 0),
                Syllable(start: 0.17, duration: 0.22, f0: 720, f1: 900, amp: 0.2, vibrato: 0, brightness: 0.8),
            ]
        case .hangup:
            return [
                Syllable(start: 0, duration: 0.12, f0: 700, f1: 700, amp: 0.09, vibrato: 0, brightness: 0),
                Syllable(start: 0.16, duration: 0.14, f0: 500, f1: 500, amp: 0.09, vibrato: 0, brightness: 0),
            ]
        case .tweet:
            return [
                Syllable(start: 0, duration: 0.05, f0: 2300, f1: 2900, amp: 0.06, vibrato: 0, brightness: 0.2),
                Syllable(start: 0.09, duration: 0.05, f0: 2400, f1: 3000, amp: 0.06, vibrato: 0, brightness: 0.2),
            ]
        case .scold:
            // Schnelles, abgehacktes, tieferes Gezeter mit empörtem Schluss ("hmpf!").
            var out: [Syllable] = []
            var t = 0.0
            let base = Double.random(in: 380...450)
            for _ in 0..<Int.random(in: 5...7) {
                let f = base * Double.random(in: 0.9...1.25)
                out.append(Syllable(start: t, duration: 0.07, f0: f * 1.1, f1: f * 0.8, amp: 0.2, vibrato: 0))
                t += 0.07 + Double.random(in: 0.015...0.04)
            }
            out.append(Syllable(start: t + 0.05, duration: 0.18, f0: base * 1.4, f1: base * 0.9, amp: 0.22, vibrato: 0.03))
            return out
        case .yawn:
            // "Aaaah" ansteigend, lang abfallend, zum Schluss ein zufriedenes "mm".
            return [
                Syllable(start: 0, duration: 0.35, f0: 380, f1: 520, amp: 0.13, breath: 0.35, vibrato: 0.01, brightness: 0.7),
                Self.yawnSigh.at(0.3),
                Self.contentHum.at(1.3),
            ]
        case .pour:
            // Feines Rieseln
            return [Syllable(start: 0, duration: 0.7, f0: 260, f1: 200, amp: 0.05, vibrato: 0, brightness: 0, hiss: 0.9)]
        case .plop:
            return [Syllable(start: 0, duration: 0.05, f0: 360, f1: 170, amp: 0.2, vibrato: 0, brightness: 0.15)]
        case .grappleShot:
            return [Syllable(start: 0, duration: 0.24, f0: 380, f1: 1500, amp: 0.17, vibrato: 0, brightness: 0.3, hiss: 0.45)]
        case .grappleCatch:
            return [
                Syllable(start: 0, duration: 0.07, f0: 900, f1: 780, amp: 0.2, vibrato: 0, brightness: 0.5),
                Syllable(start: 0.03, duration: 0.16, f0: 1900, f1: 1850, amp: 0.09, vibrato: 0, brightness: 0.4),
            ]
        case .jetCough:
            return [Syllable(start: 0, duration: 0.1, f0: 160, f1: 110, amp: 0.24, vibrato: 0, brightness: 0.2, hiss: 0.75)]
        case .jetThrust:
            return [Syllable(start: 0, duration: 1.7, f0: 120, f1: 300, amp: 0.2, vibrato: 0, brightness: 0.2, hiss: 0.65)]
        case .landSoft:
            return [Syllable(start: 0, duration: 0.09, f0: 260, f1: 170, amp: 0.16, vibrato: 0, brightness: 0, hiss: 0.08)]
        case .landCushion:
            return [Syllable(start: 0, duration: 0.12, f0: 220, f1: 160, amp: 0.13, breath: 0.5, vibrato: 0, brightness: 0)]
        case .umbrellaOpen:
            return [Syllable(start: 0, duration: 0.14, f0: 200, f1: 600, amp: 0.18, vibrato: 0, brightness: 0.2, hiss: 0.6)]
        case .balloonInflate:
            return [Syllable(start: 0, duration: 0.35, f0: 400, f1: 1400, amp: 0.14, vibrato: 0.04, brightness: 0.6, hiss: 0.3)]
        case .landPlop:
            return [Syllable(start: 0, duration: 0.07, f0: 300, f1: 150, amp: 0.14, vibrato: 0, brightness: 0.15)]
        case .pock:
            return [Syllable(start: 0, duration: 0.035, f0: 950, f1: 760, amp: 0.13, vibrato: 0, brightness: 0.3)]
        case .wallPock:
            return [Syllable(start: 0, duration: 0.03, f0: 620, f1: 520, amp: 0.09, vibrato: 0, brightness: 0.3)]
        case .sleepyWe:
            // Einatmen mit Schnarchen, dann beim Ausatmen leise, hohe "we"s.
            var out = [Syllable(start: 0, duration: 0.65, f0: 150, f1: 200, amp: 0.06, breath: 0.7)]
            var t = 0.85
            let count = Int.random(in: 4...6)
            for i in 0..<count {
                let f = 1050 - Double(i) * 25
                out.append(Syllable(start: t, duration: 0.075, f0: f * 0.75, f1: f, amp: 0.1,
                                    vibrato: 0, brightness: 0.5))
                t += 0.075 + 0.05
            }
            return out
        case .snore:
            return [Syllable(start: 0, duration: 0.7, f0: 190, f1: 150, amp: 0.06, breath: 0.7)]
        case .uiii:
            return [
                Syllable(start: 0, duration: 0.09, f0: 520, f1: 680, amp: 0.2, vibrato: 0, brightness: 0.3),
                Syllable(start: 0.08, duration: 0.5, f0: 1050, f1: 1250, amp: 0.2, vibrato: 0.04),
            ]
        case .uiiiSlide:
            return [
                Syllable(start: 0, duration: 0.1, f0: 560, f1: 700, amp: 0.2, vibrato: 0, brightness: 0.3),
                Syllable(start: 0.09, duration: 0.75, f0: 900, f1: 1450, amp: 0.2, vibrato: 0.05),
            ]
        case .huch:
            // Ohne Zischlaut am Ende, im Wechsel: "Hu!", "Ui!", "Hö?"
            return [
                [Syllable(start: 0, duration: 0.14, f0: 760, f1: 1050, amp: 0.2, breath: 0.12, vibrato: 0, brightness: 0.6)],
                [Syllable(start: 0, duration: 0.17, f0: 600, f1: 1250, amp: 0.2, vibrato: 0.03, brightness: 0.8)],
                [Syllable(start: 0, duration: 0.19, f0: 650, f1: 920, amp: 0.2, breath: 0.1, vibrato: 0.02, brightness: 0.5)],
            ].randomElement()!
        case .huhUch:
            // Zweisilbig, im Wechsel: "Hu-hu!", "Hu-ui!", "Ah-hu!"
            return [
                [
                    Syllable(start: 0, duration: 0.09, f0: 820, f1: 1050, amp: 0.2, breath: 0.1, vibrato: 0, brightness: 0.6),
                    Syllable(start: 0.12, duration: 0.15, f0: 1050, f1: 820, amp: 0.2, breath: 0.08, vibrato: 0.02, brightness: 0.7),
                ],
                [
                    Syllable(start: 0, duration: 0.09, f0: 820, f1: 1000, amp: 0.2, breath: 0.1, vibrato: 0, brightness: 0.6),
                    Syllable(start: 0.12, duration: 0.16, f0: 900, f1: 1350, amp: 0.2, vibrato: 0.03, brightness: 0.8),
                ],
                [
                    Syllable(start: 0, duration: 0.08, f0: 900, f1: 860, amp: 0.18, vibrato: 0, brightness: 0.7),
                    Syllable(start: 0.11, duration: 0.15, f0: 700, f1: 1050, amp: 0.21, breath: 0.08, vibrato: 0.02, brightness: 0.6),
                ],
            ].randomElement()!
        case .weeh:
            return [
                Syllable(start: 0, duration: 0.1, f0: 480, f1: 820, amp: 0.2, vibrato: 0, brightness: 0.5),
                Syllable(start: 0.09, duration: 0.85, f0: 860, f1: 640, amp: 0.21, breath: 0.15, vibrato: 0.06, brightness: 0.9),
            ]
        case .weehEeh:
            return [
                Syllable(start: 0, duration: 0.1, f0: 500, f1: 880, amp: 0.2, vibrato: 0, brightness: 0.5),
                Syllable(start: 0.09, duration: 0.42, f0: 900, f1: 760, amp: 0.21, breath: 0.15, vibrato: 0.07),
                Syllable(start: 0.53, duration: 0.55, f0: 820, f1: 560, amp: 0.2, breath: 0.2, vibrato: 0.08),
            ]
        case .uff:
            return [
                Self.uffBreath,
                Syllable(start: 0.17, duration: 0.12, f0: 300, f1: 280, amp: 0.07, vibrato: 0, brightness: 0.1, hiss: 0.8),
            ]
        case .relief:
            // Erleichtertes Durchschnaufen, aus vorhandenen Lauten zusammengesetzt, im Wechsel:
            // "Uff", Gähn-Seufzer "Haaah … mm", "Uff … hi-hi-hiii!" (Freuen), "Uff … huhuhu" (Kichern).
            return [
                [Self.uffBreath],
                [Self.yawnSigh.at(0, duration: 0.6), Self.contentHum.at(0.62, duration: 0.24)],
                [Self.uffBreath] + Self.happyRise.map { $0.at($0.start + 0.35) },
                [Self.uffBreath] + Self.giggle(count: 4).map { $0.at($0.start + 0.32) },
            ].randomElement()!
        case .autsch:
            return [
                Syllable(start: 0, duration: 0.2, f0: 760, f1: 560, amp: 0.22, vibrato: 0.02, brightness: 0.9),
                Syllable(start: 0.19, duration: 0.05, f0: 900, f1: 900, amp: 0.12, vibrato: 0, hiss: 0.9),
                Syllable(start: 0.23, duration: 0.14, f0: 1200, f1: 1100, amp: 0.1, vibrato: 0, brightness: 0.2, hiss: 0.7),
            ]
        case .bonk:
            return [
                Syllable(start: 0, duration: 0.06, f0: 330, f1: 170, amp: 0.24, vibrato: 0, brightness: 0.2),
                Syllable(start: 0.07, duration: 0.11, f0: 780, f1: 720, amp: 0.07, vibrato: 0.02, brightness: 0.1),
            ]
        case .hmpf:
            return [
                Syllable(start: 0, duration: 0.16, f0: 330, f1: 290, amp: 0.2, vibrato: 0, brightness: 0.15),
                Syllable(start: 0.15, duration: 0.1, f0: 300, f1: 280, amp: 0.08, vibrato: 0, brightness: 0.1, hiss: 0.75),
            ]
        case .grrr:
            // Dichte Folge winziger, tiefer Silben ergibt ein rollendes "rrr".
            var out = [Syllable(start: 0, duration: 0.08, f0: 300, f1: 340, amp: 0.16, vibrato: 0, brightness: 0.6)]
            for i in 0..<16 {
                let f = 250 - Double(i) * 3
                out.append(Syllable(start: 0.07 + Double(i) * 0.03, duration: 0.032, f0: f * 1.06, f1: f, amp: 0.24,
                                    breath: 0.2, vibrato: 0, brightness: 0.9))
            }
            return out
        case .naWarte:
            return [
                Syllable(start: 0, duration: 0.09, f0: 470, f1: 500, amp: 0.21, vibrato: 0),
                Syllable(start: 0.12, duration: 0.13, f0: 640, f1: 620, amp: 0.23, vibrato: 0),
                Syllable(start: 0.28, duration: 0.16, f0: 470, f1: 380, amp: 0.21, vibrato: 0.02),
            ]
        case .oiWorried, .oiExcited:
            // Fünf schnelle "oi", jedes von unten nach oben gleitend; besorgt sinkend, aufgeregt steigend.
            let worried = sound == .oiWorried
            let base: Double = worried ? 760 : 640
            let step = worried ? 0.96 : 1.07
            let gap = worried ? 0.04 : 0.03
            return (0..<5).map { i in
                let f = base * pow(step, Double(i))
                return Syllable(start: Double(i) * (0.11 + gap), duration: 0.11, f0: f * 0.8, f1: f * 1.25,
                                amp: 0.2, vibrato: 0, brightness: 0.8)
            }
        }
    }

    // MARK: - Synthese

    func render(_ syllables: [Syllable], style: Style = Style()) -> AVAudioPCMBuffer? {
        guard let end = syllables.map({ $0.start + $0.duration }).max() else { return nil }
        let frameCount = AVAudioFrameCount((end + 0.05) * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) { data[i] = 0 }

        for s in syllables {
            let startIndex = Int(s.start * sampleRate)
            let n = Int(s.duration * sampleRate)
            var phase = 0.0
            var noise = 0.0
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let p = t / s.duration
                // Tonhöhe gleitet, dazu leichtes Vibrato.
                let vibrato = 1 + s.vibrato * sin(2 * .pi * 7 * t)
                let freq = (s.f0 + (s.f1 - s.f0) * p) * vibrato
                phase += 2 * .pi * freq / sampleRate
                // Weicher, "summender" Klang: Grundton + wenige Obertöne.
                let b = s.brightness
                var v = sin(phase) + b * (0.35 * sin(2 * phase) + 0.12 * sin(3 * phase))
                // "m"-artiger Einsatz: Obertöne öffnen sich erst nach und nach.
                v = sin(phase) * (1 - min(p * 4, 1) * 0.4) + v * min(p * 4, 1) * 0.6
                if s.breath > 0 {
                    noise = noise * 0.92 + Double.random(in: -1...1) * 0.08
                    v = v * (1 - s.breath * style.breathDuck) + noise * style.breathGain * s.breath
                }
                if s.hiss > 0 {
                    v = v * (1 - s.hiss) + Double.random(in: -1...1) * s.hiss
                }
                // Hüllkurve: kurzer Anstieg, sanftes Abklingen.
                let attack = min(t / 0.012, 1)
                let release = pow(1 - p, 1.4)
                let sample = v * attack * release * s.amp
                let idx = startIndex + i
                if idx < Int(frameCount) { data[idx] += Float(sample) }
            }
        }

        // Sanfter Tiefpass für einen runden Klang.
        var y: Float = 0
        for i in 0..<Int(frameCount) {
            y += Float(style.smoothing) * (data[i] - y)
            data[i] = max(-1, min(1, y * Float(style.gain)))
        }
        return buffer
    }
}

extension Voice.Syllable {
    /// Dieselbe Silbe zu einem anderen Zeitpunkt (und optional mit anderer Dauer) – zum Wiederverwenden
    /// von Silben in zusammengesetzten Lauten.
    func at(_ start: Double, duration: Double? = nil) -> Voice.Syllable {
        var s = self
        s.start = start
        if let duration { s.duration = duration }
        return s
    }
}
