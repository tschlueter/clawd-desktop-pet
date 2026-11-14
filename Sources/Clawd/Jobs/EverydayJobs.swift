import AppKit

// MARK: - Alltag

/// Kaffee kochen: brühen, trinken – danach ist Clawd fünf Minuten lang munterer.
final class CoffeeJob: Job {
    override class var name: String { "coffee" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Brühen
            pose = Encounter.Pose(sprite: Int(t / 0.8) % 3 == 2 ? ClawdSprite.blink : ClawdSprite.stand,
                                  prop: ClawdSprite.coffeeMachine(brewing: true, drip: Int(t / 0.2), cupFull: t > 1.5))
            if once("brew") { c.say(.pour) }
            if t >= 2.6 { next(now) }
        case 1:
            // Trinken
            pose = Encounter.Pose(sprite: ClawdSprite.stand,
                                  prop: ClawdSprite.coffeeCupDrinking, particles: .steam)
            if t >= 0.3, once("sip") { c.say(.slurp) }
            if t >= 1.6 { next(now) }
        default:
            // Hellwach!
            pose = Encounter.Pose(sprite: ClawdSprite.flail, lift: t < 0.4 ? 2 * sin(.pi * t / 0.4) : 0)
            if once("awake") {
                c.caffeinatedUntil = now + 120 // 2 Minuten aufgedreht
                c.say(.happy)
            }
            if t >= 0.9 { finish(walkAway: true) }
        }
    }
}

/// Post austragen: Brief zu einem anderen Clawd bringen; die Übergabe ist eine kleine Begegnung.
final class MailJob: Job {
    override class var name: String { "mail" }
    override class func isPossible(_ c: PetController) -> Bool { c.stage?.mailRecipient(for: c) != nil }

    private weak var receiver: PetController?

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        let scale = px * 0.7
        let envelopeOrigin = CGPoint(x: c.center - CGFloat(ClawdSprite.envelope[0].count) * scale / 2, y: c.groundY + 9 * px)
        switch phase {
        case 0:
            if once("pick") { receiver = c.stage?.mailRecipient(for: c) }
            pose = Encounter.Pose(sprite: ClawdSprite.yawnStretch)
            showEffect("letter", ClawdSprite.envelope, origin: envelopeOrigin, scale: scale)
            if t >= 0.5 { next(now) }
        default:
            guard let r = receiver, r.canBeLandedOn, r.surfaceKind == c.surfaceKind else { finish(); return }
            let dir: CGFloat = r.center >= c.center ? 1 : -1
            let arrived = walk(to: r.center - dir * 18 * px, speed: 1.3, dt: dt)
            pose = Encounter.Pose(sprite: walkFrame(stride: 1.2))
            showEffect("letter", ClawdSprite.envelope, origin: envelopeOrigin, scale: scale)
            if arrived || abs(r.center - c.center) <= 20 * px {
                c.stage?.startMail(from: c, to: r) // übernimmt beide Clawds
                if c.job === self { finish() }
            }
            if t > 20 { finish() }
        }
    }
}

/// Wäsche aufhängen: zwei Pfosten aufstellen, Leine spannen, bunte Wäsche aufhängen.
final class LaundryJob: Job {
    override class var name: String { "laundry" }
    override class func isPossible(_ c: PetController) -> Bool {
        guard let r = c.centerRange else { return false }
        return r.upperBound - r.lowerBound >= 170
    }

    private var dir: CGFloat = 1
    private var x0: CGFloat = 0
    private var x1: CGFloat = 0
    private var nextHang: CGFloat = 0
    private var items = 0
    private var hangUntil: CFTimeInterval = 0
    private let lineSegments = 24

    private var topY: CGFloat { c.groundY + 13 * px }
    private func lineY(_ x: CGFloat) -> CGFloat {
        let p = (x - x0) / (x1 - x0)
        return topY - 2 * px * sin(.pi * min(max(p, 0), 1))
    }

    private func drawPole(_ key: String, at x: CGFloat) {
        showRect(key, CGRect(x: x - px / 2, y: c.groundY, width: px * 0.75, height: 13.5 * px),
                 color: CGColor(srgbRed: 0.45, green: 0.3, blue: 0.18, alpha: 1))
    }

    private func drawLine(to end: CGFloat, sag: Bool) {
        let lineColor = CGColor(srgbRed: 0.55, green: 0.55, blue: 0.58, alpha: 1)
        for i in 0..<lineSegments {
            let a = x0 + (end - x0) * CGFloat(i) / CGFloat(lineSegments)
            let b = x0 + (end - x0) * CGFloat(i + 1) / CGFloat(lineSegments)
            let y = sag ? lineY((a + b) / 2) : topY
            showRect("line\(i)", CGRect(x: min(a, b), y: y, width: abs(b - a) + 0.5, height: px * 0.4), color: lineColor)
        }
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") {
                dir = roomierDirection()
                x0 = c.center + dir * 10 * px
                if let r = c.centerRange {
                    let room = dir > 0 ? r.upperBound - c.center : c.center - r.lowerBound
                    x1 = x0 + dir * min(room - 4, 140)
                }
                c.face(dir)
            }
            pose = Encounter.Pose(sprite: ClawdSprite.sit)
            if t >= 0.4 { drawPole("pole0", at: x0) }
            if t >= 0.7 { next(now) }
        case 1:
            // Leine abrollen bis zum zweiten Pfosten
            let arrived = walk(to: x1 - dir * 8 * px, dt: dt)
            drawLine(to: c.center + dir * 7 * px, sag: false)
            pose = Encounter.Pose(sprite: walkFrame())
            if arrived { next(now) }
        case 2:
            pose = Encounter.Pose(sprite: ClawdSprite.sit)
            if t >= 0.4 {
                drawPole("pole1", at: x1)
                drawLine(to: x1, sag: true)
            }
            if t >= 0.7 {
                c.face(-dir)
                nextHang = x1 - dir * 12
                next(now)
            }
        case 3:
            // Zurückgehen und alle ~28 pt ein Wäschestück aufhängen
            if now < hangUntil {
                pose = Encounter.Pose(sprite: ClawdSprite.yawnStretch)
            } else {
                let hangX = nextHang
                let arrived = walk(to: hangX + dir * 1, dt: dt)
                pose = Encounter.Pose(sprite: walkFrame())
                if arrived {
                    let item = ClawdSprite.laundryItem(items, color: ["1", "2", "3", "4", "v"][items % 5])
                    let scale = px * 0.7
                    let w = CGFloat(item[0].count) * scale, h = CGFloat(item.count) * scale
                    showEffect("item\(items)", item, origin: CGPoint(x: hangX - w / 2, y: lineY(hangX) - h + px * 0.2), scale: scale)
                    items += 1
                    hangUntil = now + 0.6
                    nextHang = hangX - dir * 28
                    if dir > 0 ? nextHang < x0 + 8 : nextHang > x0 - 8 { next(now) }
                }
            }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if once("done"), c.isChatty { c.say(.happy) }
            if t >= 1.0 {
                for key in ["pole0", "pole1"] + (0..<lineSegments).map({ "line\($0)" }) + (0..<items).map({ "item\($0)" }) {
                    leaveBehind(key, lifetime: 40)
                }
                finish()
            }
        }
    }
}

/// Akten stapeln: Ordner für Ordner auf einen Stapel, der irgendwann wackelt – schnell festhalten!
final class FilesJob: Job {
    override class var name: String { "files" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var count = 0
    private var dir: CGFloat = 1

    private func drawPile(wobble: Int) {
        let frame = ClawdSprite.folderPile(count: count, wobble: wobble)
        guard !frame.isEmpty else { return }
        let scale = px * 0.6
        let w = CGFloat(frame[0].count) * scale
        showEffect("pile", frame, origin: CGPoint(x: c.center + dir * 10 * px - w / 2, y: c.groundY), scale: scale)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            if once("setup") { dir = c.facing }
            // Ordner holen (umdrehen) und ablegen
            let cycle = t.truncatingRemainder(dividingBy: 1.0)
            if cycle < 0.45 {
                c.face(-dir)
                pose = Encounter.Pose(sprite: ClawdSprite.wave[1])
            } else {
                c.face(dir)
                pose = Encounter.Pose(sprite: ClawdSprite.squash)
                if once("put\(Int(t))") {
                    count += 1
                    c.say(.wallPock)
                }
            }
            drawPile(wobble: 0)
            if count >= 6 { next(now) }
        case 1:
            // Wackelt! Festhalten.
            c.face(dir)
            let wobble = t < 1.0 ? (Int(t / 0.15) % 2 == 0 ? 1 : -1) : 0
            pose = Encounter.Pose(sprite: t < 1.0 ? ClawdSprite.flail : ClawdSprite.stand)
            if once("eep") { c.say(.eep) }
            drawPile(wobble: wobble)
            if t >= 1.4 { next(now) }
        case 2:
            // Letzter Ordner, ganz vorsichtig
            pose = Encounter.Pose(sprite: ClawdSprite.squash)
            if t >= 0.5, once("last") {
                count += 1
                c.say(.wallPock)
            }
            drawPile(wobble: 0)
            if t >= 0.9 { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            drawPile(wobble: 0)
            if once("done"), c.isChatty { c.say(.happy) }
            if t >= 1.0 {
                leaveBehind("pile", lifetime: 30)
                finish()
            }
        }
    }
}

/// Videocall: Headset auf, anrufen (es tutet), der Freund hebt ab, kurz plaudern,
/// "Byeeee!" und auflegen.
final class CallJob: Job {
    override class var name: String { "call" }
    override class func isPossible(_ c: PetController) -> Bool { c.surfaceKind != nil }

    private var friendVoice: Voice.Channel?
    private var friendBye: Voice.Sound = .byeFalling
    /// Reihum durch die Verabschiedungen (über alle Anrufe hinweg).
    private static var nextBye = 0
    private var dir: CGFloat = 1

    override func cleanup() {
        friendVoice?.close()
        friendVoice = nil
        super.cleanup()
    }

    private func showWindow(_ screen: ClawdSprite.CallScreen) {
        let frame = ClawdSprite.callWindow(screen)
        let scale = px * 0.8
        let w = CGFloat(frame[0].count) * scale
        let x = dir > 0 ? c.center + 8 * px : c.center - 8 * px - w
        showEffect("call", frame, origin: CGPoint(x: x, y: c.groundY + 6 * px), scale: scale, shadow: true)
    }

    private func friendSays(_ sound: Voice.Sound) {
        guard c.eventAudible else { return } // der Anrufer gehört zum selben Ereignis
        friendVoice?.play(sound)
    }

    override func step(now: CFTimeInterval, dt: TimeInterval) {
        let t = t(now)
        switch phase {
        case 0:
            // Headset aufsetzen
            if once("setup") {
                dir = c.facing
                let pitch = Bool.random() ? Double.random(in: 0.72...0.85) : Double.random(in: 1.2...1.35)
                friendVoice = c.voice.sibling(pitch: pitch)
                // Gedämpfte "Telefonstimme"
                friendVoice?.style = Voice.Style(breathGain: 0.8, breathDuck: 0.2, smoothing: 0.3, lowBoost: 1, gain: 0.75)
            }
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: t >= 0.3 ? ClawdSprite.headset : nil)
            if t >= 0.7 { next(now) }
        case 1:
            // Anrufen – es tutet dreimal
            showWindow(.ringing(dots: Int(t / 0.4) % 3 + 1))
            for (i, at) in [0.3, 1.9, 3.5].enumerated() where t >= at {
                if once("ring\(i)") { c.say(.ring) }
            }
            let waiting = [ClawdSprite.stand, ClawdSprite.blink, ClawdSprite.lookCycle[1], ClawdSprite.stand]
            pose = Encounter.Pose(sprite: waiting[Int(t / 0.9) % waiting.count], prop: ClawdSprite.headset)
            if t >= 4.8 { next(now) }
        case 2:
            // Abgehoben!
            if once("pickup") { c.say(.pickup) }
            if t >= 0.3, once("hi"), c.isChatty { c.say(.happy) }
            showWindow(.talking(mouthOpen: false, waving: true))
            pose = Encounter.Pose(sprite: ClawdSprite.wave[Int(t / 0.18) % 2], prop: ClawdSprite.headset)
            if t >= 1.1 { next(now) }
        case 3:
            // Plaudern, abwechselnd
            let turn = Int(t / 1.25)
            let clawdTalks = turn % 2 == 0
            if clawdTalks {
                if once("talk\(turn)"), c.isChatty { c.say(.murmur) }
                showWindow(.talking(mouthOpen: false, waving: false))
                pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.headset, bubble: true)
            } else {
                if once("talk\(turn)"), c.isChatty { friendSays(.murmur) }
                showWindow(.talking(mouthOpen: Int(t / 0.12) % 2 == 0, waving: false))
                let local = t.truncatingRemainder(dividingBy: 1.25)
                pose = Encounter.Pose(sprite: local > 0.6 && local < 0.75 ? ClawdSprite.blink : ClawdSprite.stand,
                                      prop: ClawdSprite.headset)
            }
            if t >= 5.0 { next(now) }
        case 4:
            // "Byeeee!"
            // Beide verabschieden sich – jeder mit einer anderen Variante; bei jedem Anruf die nächste.
            if once("bye") {
                let byes = Voice.Sound.byes
                c.say(byes[Self.nextBye % byes.count])
                friendBye = byes[(Self.nextBye + 1) % byes.count]
                Self.nextBye += 1
            }
            if t >= 1.0, once("bye-friend") { friendSays(friendBye) }
            showWindow(.talking(mouthOpen: t >= 1.0 && Int(t / 0.12) % 2 == 0, waving: true))
            pose = Encounter.Pose(sprite: ClawdSprite.wave[Int(t / 0.18) % 2], prop: ClawdSprite.headset)
            if t >= 2.1 { next(now) }
        case 5:
            // Auflegen
            if once("hangup") {
                c.say(.hangup)
                hideEffect("call")
            }
            pose = Encounter.Pose(sprite: ClawdSprite.stand, prop: ClawdSprite.headset)
            if t >= 0.6 { next(now) }
        default:
            pose = Encounter.Pose(sprite: ClawdSprite.happyStand)
            if t >= 0.5 { finish() }
        }
    }
}
