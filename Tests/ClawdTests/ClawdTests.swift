import AppKit
import Testing
import AVFoundation
import QuartzCore
@testable import Clawd

/// Reproduzierbarer Zufall für Tests (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Fenster-Oberkanten

@Suite struct WindowTopsTests {
    let screen = (frame: NSRect(x: 0, y: 0, width: 1000, height: 800), visibleMaxY: CGFloat(775))

    @Test func singleWindowGivesFullTopEdge() {
        let tops = World.windowTops([(1, NSRect(x: 100, y: 100, width: 400, height: 300))], screens: [screen])
        #expect(tops.count == 1)
        #expect(tops[0].kind == .window(1))
        #expect(tops[0].minX == 100 && tops[0].maxX == 500 && tops[0].y == 400)
    }

    @Test func frontWindowCutsTopEdgeIntoTwoSegments() {
        let back = (id: CGWindowID(2), rect: NSRect(x: 0, y: 100, width: 600, height: 300)) // Oberkante y = 400
        let front = (id: CGWindowID(1), rect: NSRect(x: 200, y: 300, width: 100, height: 300)) // verdeckt 200…300
        let tops = World.windowTops([front, back], screens: [screen]).filter { $0.kind == .window(2) }
        #expect(tops.map(\.minX) == [0, 300])
        #expect(tops.map(\.maxX) == [200, 600])
    }

    @Test func tooShortSegmentsAreDropped() {
        let back = (id: CGWindowID(2), rect: NSRect(x: 0, y: 100, width: 300, height: 300))
        let front = (id: CGWindowID(1), rect: NSRect(x: 40, y: 300, width: 220, height: 300)) // Reste: 40 und 40 breit
        let tops = World.windowTops([front, back], screens: [screen]).filter { $0.kind == .window(2) }
        #expect(tops.isEmpty)
    }

    @Test func maximizedWindowUnderMenuBarIsNotWalkable() {
        let tops = World.windowTops([(1, NSRect(x: 0, y: 0, width: 1000, height: 775))], screens: [screen])
        #expect(tops.isEmpty)
    }

    @Test func edgeIsClippedToScreen() {
        let tops = World.windowTops([(1, NSRect(x: -200, y: 100, width: 600, height: 300))], screens: [screen])
        #expect(tops.first?.minX == 0)
        #expect(tops.first?.maxX == 400)
    }
}

// MARK: - Schütteln

@Suite struct ShakeDetectorTests {
    @Test func steadyDragIsNoShake() {
        var detector = ShakeDetector()
        var reading = ShakeDetector.Reading(samples: 0, reversals: 0, path: 0)
        for i in 0..<20 {
            reading = detector.add(CGPoint(x: Double(i) * 30, y: 0), now: Double(i) * 0.03)
        }
        #expect(reading.reversals == 0)
        #expect(!reading.isShaking)
    }

    @Test func backAndForthIsShake() {
        var detector = ShakeDetector()
        let xs: [CGFloat] = [0, 80, 0, 80, 0, 80]
        var reading = ShakeDetector.Reading(samples: 0, reversals: 0, path: 0)
        for (i, x) in xs.enumerated() {
            reading = detector.add(CGPoint(x: x, y: 0), now: Double(i) * 0.05)
        }
        #expect(reading.reversals >= 2)
        #expect(reading.isShaking)
    }

    @Test func vigorousNeedsMoreThanAWiggle() {
        func shake(_ moves: Int) -> ShakeDetector.Reading {
            var detector = ShakeDetector(window: 1.6)
            var reading = ShakeDetector.Reading(samples: 0, reversals: 0, path: 0)
            for i in 0...moves {
                reading = detector.add(CGPoint(x: i % 2 == 0 ? 0 : 120, y: 0), now: Double(i) * 0.08)
            }
            return reading
        }
        let short = shake(6)   // 5 Richtungswechsel: früher genug, jetzt nicht mehr
        let long = shake(10)   // 9 Richtungswechsel
        #expect(short.isShaking && !short.isVigorous)
        #expect(long.isVigorous)
    }

    @Test func oldSamplesExpire() {
        var detector = ShakeDetector()
        for (i, x) in [0, 80, 0, 80].enumerated() {
            _ = detector.add(CGPoint(x: x, y: 0), now: Double(i) * 0.05)
        }
        let later = detector.add(CGPoint(x: 0, y: 0), now: 5)
        #expect(later.samples == 1)
        #expect(!later.isShaking)
    }
}

// MARK: - Jobs

@Suite struct ThrowTests {
    typealias Sample = (t: CFTimeInterval, p: CGPoint)
    /// Gleichmäßig nach rechts gezogen: 10 pt alle 10 ms (= 1000 pt/s) bis t = 1.0.
    let samples: [Sample] = (0...10).map { i in (0.9 + Double(i) * 0.01, CGPoint(x: CGFloat(i) * 10, y: 0)) }

    @Test func releasingWhileMovingThrows() {
        let v = PetController.throwVelocity(samples: samples, release: (1.0, CGPoint(x: 100, y: 0)), limit: 1400)
        #expect(abs(v.dx - 1000) < 1)
        #expect(v.dy == 0)
    }

    @Test func restingBeforeReleaseDoesNotThrow() {
        // 0,3 s stillgehalten: keine neuen Bewegungen, die letzte Bewegung darf nicht mehr zählen.
        let v = PetController.throwVelocity(samples: samples, release: (1.3, CGPoint(x: 100, y: 0)), limit: 1400)
        #expect(v == .zero)
    }

    @Test func shortRestSlowsTheThrow() {
        // 50 ms still: nur noch die halbe Strecke im Fenster → deutlich langsamer.
        let v = PetController.throwVelocity(samples: samples, release: (1.05, CGPoint(x: 100, y: 0)), limit: 1400)
        #expect(v.dx > 0 && v.dx < 600)
    }

    @Test func speedIsLimited() {
        let fast: [Sample] = [(0.95, .zero)]
        let v = PetController.throwVelocity(samples: fast, release: (1.0, CGPoint(x: 500, y: -500)), limit: 1400)
        #expect(v.dx == 1400 && v.dy == -1400)
    }
}

@Suite struct SafelyTests {
    @Test func catchesAVFoundationException() {
        // Ein Player ohne Engine wirft beim Abspielen – wie beim Zuklappen, wenn das Audiogerät verschwindet.
        let ok = Safely.run("Test") { AVAudioPlayerNode().play() }
        #expect(!ok)
    }

    @Test func catchesInvalidLayerGeometry() {
        #expect(!Safely.run("Test") { CALayer().position = CGPoint(x: CGFloat.nan, y: 0) })
        #expect(Safely.run("Test") { CALayer().position = .zero })
    }

    @Test func timerKeepsFiringAfterException() {
        // Ohne Sicherheitsnetz bliebe der Timer nach der Exception für immer stehen (Clawd eingefroren).
        var fires = 0
        let timer = Timer(timeInterval: 0.01, repeats: true) { _ in
            fires += 1
            Safely.run("Test") { if fires == 2 { CALayer().position = CGPoint(x: CGFloat.nan, y: 0) } }
        }
        RunLoop.current.add(timer, forMode: .default)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        timer.invalidate()
        #expect(fires > 5)
    }
}

@Suite struct WeekendTests {
    @Test func weekendFavorsLeisureOverWork() {
        #expect(Jobs.weight("kite", weekend: true) > Jobs.weight("kite", weekend: false))
        #expect(Jobs.weight("review", weekend: true) < Jobs.weight("review", weekend: false))
        #expect(Jobs.weight("windows", weekend: true) == Jobs.weight("windows", weekend: false))
    }

    @Test func categoriesNameRealJobs() {
        let names = Set(Jobs.all.map(\.name))
        #expect(Jobs.leisure.isSubset(of: names))
        #expect(Jobs.chores.isSubset(of: names))
        #expect(Jobs.leisure.isDisjoint(with: Jobs.chores))
    }

    @Test func weekendPicksMoreLeisure() {
        var rng = SeededRandom(state: 7)
        let pool: [Job.Type] = [KiteJob.self, CodeReviewJob.self]
        func kites(weekend: Bool) -> Int {
            (0..<2000).filter { _ in Jobs.pick(from: pool, avoiding: [], weekend: weekend, using: &rng) == KiteJob.self }.count
        }
        #expect(kites(weekend: true) > kites(weekend: false) + 400)
    }
}

@Suite struct WorkplaceSpriteTests {
    @Test func framesAreRectangularWithKnownColors() {
        let S = ClawdSprite.self
        let frames = [S.padlock(open: true, cracked: true), S.padlock(open: false, cracked: false), S.shieldGlyph,
                      S.floppy("B"), S.tapeReel(spin: 1), S.retroReader(tape: true, spin: 1, progress: 0.5, busy: true),
                      S.retroReader(tape: false), S.ssd, S.serverRack(filled: 2, blink: true),
                      S.mediaCrate(floppy: true, reel: true), S.dataBit,
                      S.dashboard(heights: [5, 8, 6, 11], glitch: true, trend: 1),
                      S.prototype(elements: 4, buttonOffset: 2, guide: true)]
        for f in frames {
            #expect(f.allSatisfy { $0.count == f[0].count })
            for ch in f.joined() where ch != "." {
                #expect(S.rgb(ch, theme: .light) != nil && S.rgb(ch, theme: .dark) != nil, "Zeichen \(ch)")
            }
        }
        // Lock: offen und zu gleich groß, damit nichts springt.
        #expect(S.padlock(open: true, cracked: false).count == S.padlock(open: false, cracked: false).count)
    }
}

@Suite struct ThinkingHatsTests {
    @Test func programsStartAndEndWithBlue() {
        for program in ThinkingHatsJob.programs {
            #expect(program.first == .blue && program.last == .blue)
        }
    }

    @Test func longestProgramUsesAllSixHats() {
        let longest = ThinkingHatsJob.programs.max { $0.count < $1.count } ?? []
        #expect(Set(longest) == Set(ThinkingHatsJob.Hat.allCases))
    }

    @Test func hatsShareOneShapeAndKnownColors() {
        let hats = ClawdSprite.thinkingHats
        #expect(hats.count == ThinkingHatsJob.Hat.allCases.count)
        let shape = hats[0].map { $0.map { $0 == "." } }
        for hat in hats {
            #expect(hat.allSatisfy { $0.count == 28 })
            #expect(hat.map { $0.map { $0 == "." } } == shape, "alle Hüte haben dieselbe Form")
            for ch in hat.joined() where ch != "." {
                #expect(ClawdSprite.rgb(ch, theme: .light) != nil && ClawdSprite.rgb(ch, theme: .dark) != nil)
            }
        }
        #expect(ClawdSprite.hasShadow(hats[1]))  // weiß: Schatten statt Rand
        #expect(!ClawdSprite.hasShadow(hats[0]))
    }
}

@Suite struct JobsTests {
    @Test func namesAreUniqueAndWeighted() {
        let names = Jobs.all.map { $0.name }
        #expect(Set(names).count == names.count)
        #expect(Set(names) == Set(Jobs.weights.keys))
        let builtInNames: [String] = Jobs.builtIn.map { $0.name }
        #expect(Set(names).isDisjoint(with: builtInNames))
        for name in names { #expect(Jobs.named(name) != nil) }
    }

    @Test func pickAvoidsRecentJobs() {
        var rng = SeededRandom(state: 42)
        let pool: [Job.Type] = [CoffeeJob.self, StampJob.self, FireJob.self]
        for _ in 0..<200 {
            let picked = Jobs.pick(from: pool, avoiding: ["coffee", "stamp"], using: &rng)
            #expect(picked == FireJob.self)
        }
    }

    @Test func pickFallsBackWhenEverythingIsRecent() {
        var rng = SeededRandom(state: 7)
        let picked = Jobs.pick(from: [CoffeeJob.self], avoiding: ["coffee"], using: &rng)
        #expect(picked == CoffeeJob.self)
    }

    @Test func pickFollowsWeights() {
        // coffee hat Gewicht 3, fire Gewicht 1 → etwa 75 % coffee.
        var rng = SeededRandom(state: 1)
        let pool: [Job.Type] = [CoffeeJob.self, FireJob.self]
        let coffee = (0..<4000).filter { _ in Jobs.pick(from: pool, avoiding: [], using: &rng) == CoffeeJob.self }.count
        #expect((2800...3200).contains(coffee))
    }

    @Test func emptyPoolGivesNil() {
        var rng = SeededRandom(state: 3)
        #expect(Jobs.pick(from: [], avoiding: [], using: &rng) == nil)
    }
}

// MARK: - Demo-Aktionen

@Suite struct DemoActionTests {
    @Test func parsesAllForms() {
        guard case .behavior(.wave) = DemoAction(argument: "wave") else { Issue.record("wave"); return }
        guard case .job(let type) = DemoAction(argument: "job:coffee"), type == CoffeeJob.self else {
            Issue.record("job:coffee"); return
        }
        guard case .encounter(.hug) = DemoAction(argument: "enc:hug") else { Issue.record("enc:hug"); return }
    }

    @Test func builtInJobsKeepTheirShortNames() {
        for name in ["eat", "sweep", "tennis"] {
            guard case .job(let type) = DemoAction(argument: name) else { Issue.record("kein Job: \(name)"); continue }
            #expect(type.name == name)
        }
    }

    @Test func rejectsUnknown() {
        #expect(DemoAction(argument: "job:nope") == nil)
        #expect(DemoAction(argument: "enc:nope") == nil)
        #expect(DemoAction(argument: "nope") == nil)
    }

    @Test func nameRoundTrips() {
        let all: [DemoAction] = DemoAction.Behavior.allCases.map { .behavior($0) }
            + (Jobs.all + Jobs.builtIn).map { .job($0) }
            + Encounter.Kind.allCases.map { .encounter($0) }
        for action in all {
            #expect(DemoAction(argument: action.name)?.name == action.name)
        }
    }
}

// MARK: - Demo-Menü

@Suite struct DemoMenuTests {
    @Test func everyActionAppearsExactlyOnce() {
        let names = AppDelegate.demoGroups.flatMap { $0.items.map(\.action.name) }
        let expected = DemoAction.Behavior.allCases.map { DemoAction.behavior($0).name }
            // "Post austragen" startet im Menü direkt die Begegnung, nicht den Job davor.
            + (Jobs.all + Jobs.builtIn).filter { $0 != MailJob.self }.map { DemoAction.job($0).name }
            + Encounter.Kind.allCases.map { DemoAction.encounter($0).name }
        #expect(names.count == Set(names).count, "doppelte Einträge")
        #expect(Set(names) == Set(expected))
    }

    @Test func allTitlesAreTranslated() {
        let keys = AppDelegate.demoGroups.flatMap { [$0.title] + $0.items.map(\.title) }
        for key in keys {
            #expect(L10n.de[key] != nil && L10n.en[key] != nil, "fehlt: \(key)")
        }
    }
}

// MARK: - Startargumente

@Suite struct LaunchOptionsTests {
    @Test func parsesDropThrowAndForce() {
        let o = LaunchOptions(arguments: ["Clawd", "--drop", "700,500", "--throw", "-300", "--force", "job:coffee"])
        #expect(o.drop == CGPoint(x: 700, y: 500))
        #expect(o.throwVX == -300)
        #expect(o.force?.name == "job:coffee")
        #expect(!o.isDebugging)
    }

    @Test func encounterWinsOverPair() {
        let o = LaunchOptions(arguments: ["Clawd", "--pair", "--encounter", "hug"])
        guard case .encounter(.hug) = o.scenario else { Issue.record("Szenario"); return }
        #expect(o.isDebugging)
    }

    @Test func demoTurnsOnLogging() {
        #expect(LaunchOptions(arguments: ["Clawd", "--demo", "wave"]).isDebugging)
    }
}

// MARK: - Sprites

/// Seriell: ClawdSprite hat statische Caches, die die App nur vom Main-Thread aus benutzt.
@Suite(.serialized) struct SpriteTests {
    static let clawdFrames: [ClawdSprite.Frame] = [ClawdSprite.stand, ClawdSprite.blink, ClawdSprite.squash,
                                                   ClawdSprite.sit, ClawdSprite.sleep, ClawdSprite.flail]
        + ClawdSprite.walkCycle + ClawdSprite.lookCycle + ClawdSprite.wave
        + [ClawdSprite.coverHide] + ClawdSprite.coverPeek

    @Test func clawdFramesHaveSpriteSize() {
        for frame in Self.clawdFrames {
            #expect(frame.count == ClawdSprite.rows)
            #expect(frame.allSatisfy { $0.count == ClawdSprite.columns })
        }
    }

    @Test func framesUseOnlyKnownColors() {
        for frame in Self.clawdFrames + Self.clawdFrames.map(ClawdSprite.sporty) {
            for ch in frame.joined() where ch != "." {
                #expect(ClawdSprite.rgb(ch, theme: .light) != nil, "unbekanntes Zeichen \(ch)")
                #expect(ClawdSprite.rgb(ch, theme: .dark) != nil, "unbekanntes Zeichen \(ch)")
            }
        }
    }

    @Test func sportyAddsHeadbandAndLegWarmers() {
        let sporty = ClawdSprite.sporty(ClawdSprite.stand)
        #expect(sporty[ClawdSprite.headRow(ClawdSprite.stand)].contains("M"))
        #expect(sporty.last?.contains("L") == true)
        #expect(sporty.count == ClawdSprite.stand.count)
    }

    @Test func bootsColorOnlyTheFeet() {
        let booted = ClawdSprite.withBoots(ClawdSprite.stand)
        #expect(booted.dropLast() == ClawdSprite.stand.dropLast())
        #expect(booted.last?.contains("u") == true)
        #expect(booted.last?.contains("X") == false)
    }

    @Test func walkFrameAdvancesWithDistance() {
        let px: CGFloat = 4
        let step = ClawdSprite.stepLength
        #expect(ClawdSprite.walkFrame(walked: 0, px: px) == ClawdSprite.walkCycle[0])
        #expect(ClawdSprite.walkFrame(walked: step, px: px) == ClawdSprite.walkCycle[1 % ClawdSprite.walkCycle.count])
    }

    @Test func coverSequenceFreezesLooksAroundThenStandsUp() {
        typealias S = ClawdSprite
        #expect(S.coverFrame(sinceRelease: nil) == S.coverHide)
        #expect(S.coverFrame(sinceRelease: 1.9) == S.coverHide) // 2 s regungslos
        let lookStart = S.coverFreeze
        let seen = stride(from: lookStart + 0.01, to: lookStart + S.coverLookStep * 4, by: S.coverLookStep)
            .map { S.coverFrame(sinceRelease: $0) }
        #expect(seen == S.coverPeek) // umschauen – Arme noch oben
        let armsDown = lookStart + S.coverLookStep * 4 + 0.01
        #expect(S.coverFrame(sinceRelease: armsDown) == S.sit)
        #expect(S.coverFrame(sinceRelease: S.coverDuration - 0.01) == S.stand)
    }
}

// MARK: - Texte

@Suite struct L10nTests {
    @Test func everyKeyExistsInBothLanguages() {
        #expect(Set(L10n.de.keys).symmetricDifference(L10n.en.keys).isEmpty)
    }

    @Test func settingsTitlesAreTranslated() {
        let keys = Settings.sizes.map(\.title) + Settings.speeds.map(\.title) + Settings.talkLevels.map(\.title)
            + Settings.activityLevels.map(\.title) + Settings.appearances.map(\.title)
        for key in keys { #expect(L10n.en[key] != nil, "fehlt: \(key)") }
    }
}

// MARK: - Einstellungen

@Suite struct UserDefaultTests {
    @Test func clampsAndFallsBack() {
        let store = UserDefaults(suiteName: "ClawdTests-\(UUID().uuidString)")!
        var volume = UserDefault<Double>(key: "volume", defaultValue: 0.6,
                                         clamp: { min(max($0, 0), 1) }, store: store)
        #expect(volume.wrappedValue == 0.6)
        volume.wrappedValue = 3
        #expect(volume.wrappedValue == 1)
        volume.wrappedValue = 0.25
        #expect(volume.wrappedValue == 0.25)
    }
}

// MARK: - Gesprächigkeit

@Suite struct TalkativenessTests {
    @Test func eventProbabilityPerLevel() {
        let p = Settings.talkLevels.map { PetController.eventProbability(talkativeness: $0.factor) }
        #expect(p == [0, 0.4, 1, 1]) // Still, Wortkarg, Normal, Plappermaul (nicht häufiger als immer)
    }
}

// MARK: - Ruhige Phase

@Suite struct CalmPhaseTests {
    @Test func normalIsOneToTwoMinutes() {
        #expect(PetController.calmPhase(activity: 1) == 60...120)
    }

    @Test func scalesWithActivity() {
        let lazy = PetController.calmPhase(activity: 0.35), hyper = PetController.calmPhase(activity: 2.6)
        #expect(lazy.lowerBound > 170 && lazy.upperBound < 345)
        #expect(hyper.lowerBound > 23 && hyper.upperBound < 47)
    }
}

// MARK: - Tennis

@Suite struct TennisTests {
    @Test func shotsFlyInVisibleArcs() {
        for _ in 0..<200 {
            let drive = TennisJob.arcShape(distance: 300, lob: false)
            let lob = TennisJob.arcShape(distance: 300, lob: true)
            #expect(drive.arc >= 70, "Drive zu flach")
            #expect(lob.arc > drive.arc)
            #expect(lob.duration >= drive.duration)
        }
    }

    @Test func longShotsStayInBounds() {
        for _ in 0..<200 {
            let lob = TennisJob.arcShape(distance: 1000, lob: true)
            #expect(lob.arc <= 260 && lob.duration <= 2.4)
        }
    }

    @Test func leisureSpritesUseThemedColors() {
        for frame in [ClawdSprite.kite, ClawdSprite.paperPlane, ClawdSprite.frog, ClawdSprite.rabbit, ClawdSprite.target]
            + ClawdSprite.paperFolds {
            for ch in frame.joined() where ch != "." {
                #expect(ClawdSprite.rgb(ch, theme: .light) != nil && ClawdSprite.rgb(ch, theme: .dark) != nil, "Zeichen \(ch)")
            }
        }
        // Papier ist weiß; auf weißen Fenstern machen es die grauen Falzkanten und der Schatten sichtbar.
        #expect(ClawdSprite.rgb("a", theme: .light).map { $0.r + $0.g + $0.b < 3 * 0xC0 } == true)
        #expect(ClawdSprite.kite.allSatisfy { $0.count == ClawdSprite.kite[0].count })
    }

    @Test func arrowHeadingFollowsTheArc() {
        let right = BallArc(from: .zero, to: CGPoint(x: 200, y: 0), start: 0, duration: 1, arc: 40)
        #expect(right.heading(0) > 0.3)                 // steigt am Anfang
        #expect(abs(right.heading(0.5)) < 0.01)         // oben waagerecht
        #expect(right.heading(1) < -0.3)                // fällt am Ende
        let left = BallArc(from: .zero, to: CGPoint(x: -200, y: 0), start: 0, duration: 1, arc: 40)
        #expect(abs(left.heading(0.5)) > 3.1)           // nach links: Spitze zeigt nach links
    }

    @Test func ballIsSquareAndOutlined() {
        #expect(ClawdSprite.ball.allSatisfy { $0.count == ClawdSprite.ball.count })
        #expect(ClawdSprite.ball.joined().contains("o"))
    }
}

// MARK: - Spielplatz

@Suite struct PlaygroundLayoutTests {
    static let sizes: [NSSize] = [PlaygroundLayout.minimumSize, NSSize(width: 720, height: 460), NSSize(width: 1600, height: 1000)]

    @Test func everythingFitsInside() {
        for size in Self.sizes {
            let area = NSRect(origin: CGPoint(x: 300, y: 200), size: size)
            let p = PlaygroundLayout(area: area)
            #expect(area.contains(p.dock))
            for icon in p.icons {
                #expect(p.dock.contains(icon))
                #expect(!icon.intersects(p.trash))
            }
            #expect(p.dock.contains(p.trash))
            for box in p.boxes {
                #expect(area.contains(box.rect))
                #expect(box.rect.maxY + 40 <= area.maxY, "Platz für Clawd auf dem Kasten")
                #expect(box.rect.width >= 120, "breit genug für Fenster-Jobs")
            }
        }
    }

    @Test func boxesAreReachableByJumping() {
        // Clawd springt 30–170 pt hoch: der erste Kasten vom Boden/Dock, der zweite vom ersten aus.
        for size in Self.sizes {
            let p = PlaygroundLayout(area: NSRect(origin: .zero, size: size))
            let first = p.boxes[0].rect.maxY - p.dock.maxY
            #expect(first > 30 && first < 170)
            if p.boxes.count > 1 {
                let second = p.boxes[1].rect.maxY - p.boxes[0].rect.maxY
                #expect(second > 30 && second < 170)
            }
        }
    }
}

// MARK: - Klettern

@Suite struct ClimbTests {
    // Fenster reicht bis zum Boden (y 74) und ist hoch genug.
    let windows: [CGWindowID: NSRect] = [7: NSRect(x: 500, y: 70, width: 300, height: 400)]

    @Test func reachesLeftSideFromTheLeft() {
        let wall = PetController.climbableWall(in: windows, groundY: 74, from: 498, to: 501, direction: 1)
        #expect(wall?.id == 7 && wall?.side == -1)
    }

    @Test func reachesRightSideFromTheRight() {
        let wall = PetController.climbableWall(in: windows, groundY: 74, from: 802, to: 799, direction: -1)
        #expect(wall?.id == 7 && wall?.side == 1)
    }

    @Test func ignoresFloatingAndLowWindows() {
        let floating: [CGWindowID: NSRect] = [1: NSRect(x: 500, y: 200, width: 300, height: 300)]
        let low: [CGWindowID: NSRect] = [2: NSRect(x: 500, y: 70, width: 300, height: 60)]
        #expect(PetController.climbableWall(in: floating, groundY: 74, from: 498, to: 501, direction: 1) == nil)
        #expect(PetController.climbableWall(in: low, groundY: 74, from: 498, to: 501, direction: 1) == nil)
    }

    @Test func noClimbWithoutCrossingOrWalkingAway() {
        #expect(PetController.climbableWall(in: windows, groundY: 74, from: 480, to: 490, direction: 1) == nil)
        #expect(PetController.climbableWall(in: windows, groundY: 74, from: 501, to: 498, direction: -1) == nil)
    }
}

// MARK: - Sprung zwischen Fenstern

@Suite struct WallJumpTests {
    // Fenster 1 rechts von x 600, Fenster 2 dahinter mit 80 pt Lücke.
    let windows: [CGWindowID: NSRect] = [
        1: NSRect(x: 300, y: 100, width: 300, height: 500),
        2: NSRect(x: 680, y: 150, width: 300, height: 500),
    ]

    @Test func jumpsAcrossNarrowGap() {
        let t = PetController.wallJumpTarget(from: 600, side: 1, footY: 300, selfID: 1, windows: windows, margin: 28)
        #expect(t?.id == 2 && t?.gap == 80)
        let back = PetController.wallJumpTarget(from: 680, side: -1, footY: 300, selfID: 2, windows: windows, margin: 28)
        #expect(back?.id == 1 && back?.gap == 80)
    }

    @Test func noJumpWithoutHoldOrTooWide() {
        // Zu tief: Fenster 2 bietet dort keinen Halt.
        #expect(PetController.wallJumpTarget(from: 600, side: 1, footY: 160, selfID: 1, windows: windows, margin: 28) == nil)
        // Falsche Seite: von der linken Seite aus liegt rechts nichts.
        #expect(PetController.wallJumpTarget(from: 300, side: -1, footY: 300, selfID: 1, windows: windows, margin: 28) == nil)
        let wide: [CGWindowID: NSRect] = [1: windows[1]!, 2: NSRect(x: 1000, y: 150, width: 300, height: 500)]
        #expect(PetController.wallJumpTarget(from: 600, side: 1, footY: 300, selfID: 1, windows: wide, margin: 28) == nil)
    }
}

// MARK: - Magnet beim Ziehen

@Suite struct MagnetTests {
    let windows: [CGWindowID: NSRect] = [5: NSRect(x: 500, y: 100, width: 300, height: 400)]

    @Test func attractsWhenCloseToLeftEdge() {
        let body = NSRect(x: 420, y: 250, width: 56, height: 32) // rechte Seite bei 476, 24 pt vor der Kante
        let m = PetController.magnetTarget(body: body, windows: windows, reach: 40, margin: 28)
        #expect(m?.id == 5 && m?.side == -1 && m?.distance == 24)
    }

    @Test func attractsWhenCloseToRightEdge() {
        let body = NSRect(x: 830, y: 250, width: 56, height: 32)
        let m = PetController.magnetTarget(body: body, windows: windows, reach: 40, margin: 28)
        #expect(m?.side == 1 && m?.distance == 30)
    }

    @Test func noAttractionFarAwayOrWithoutHold() {
        #expect(PetController.magnetTarget(body: NSRect(x: 380, y: 250, width: 56, height: 32),
                                           windows: windows, reach: 40, margin: 28) == nil) // 64 pt entfernt
        #expect(PetController.magnetTarget(body: NSRect(x: 420, y: 470, width: 56, height: 32),
                                           windows: windows, reach: 40, margin: 28) == nil) // zu weit oben
        #expect(PetController.magnetTarget(body: NSRect(x: 600, y: 250, width: 56, height: 32),
                                           windows: windows, reach: 40, margin: 28) == nil) // über dem Fenster
    }
}

// MARK: - Abspringen

@Suite struct JumpDownTests {
    @Test func chanceGrowsWithClimbingTime() {
        #expect(PetController.jumpDownChance(climbing: 5) == 0)
        #expect(PetController.jumpDownChance(climbing: 15) == 0)
        #expect(PetController.jumpDownChance(climbing: 45) == 0.25)
        #expect(PetController.jumpDownChance(climbing: 600) == 0.5)
    }
}

// MARK: - Sichtbare Kanten

@Suite struct EdgeVisibilityTests {
    // Fenster 2 liegt hinten; Fenster 1 davor verdeckt dessen linke Kante zwischen y 200 und 400.
    let frames: [CGWindowID: NSRect] = [
        1: NSRect(x: 450, y: 200, width: 200, height: 200),
        2: NSRect(x: 500, y: 100, width: 400, height: 500),
    ]
    let order: [CGWindowID: Int] = [1: 0, 2: 1]

    @Test func frontWindowCoversBackEdge() {
        #expect(!World.isEdgeVisible(2, at: CGPoint(x: 500, y: 300), frames: frames, order: order))
        #expect(World.isEdgeVisible(2, at: CGPoint(x: 500, y: 500), frames: frames, order: order))
        #expect(World.isEdgeVisible(1, at: CGPoint(x: 450, y: 300), frames: frames, order: order))
    }

    @Test func coveredEdgesAreNoJumpTargets() {
        let visible: (CGWindowID, CGPoint) -> Bool = { id, p in
            World.isEdgeVisible(id, at: p, frames: self.frames, order: self.order)
        }
        // Von x 380 nach rechts: Fenster 2 (Lücke 120) ist auf Höhe 300 verdeckt, Fenster 1 (Lücke 70) nicht.
        let t = PetController.wallJumpTarget(from: 380, side: 1, footY: 300, selfID: 99, windows: frames, margin: 28, visible: visible)
        #expect(t?.id == 1)
        let onlyBack = frames.filter { $0.key == 2 }
        #expect(PetController.wallJumpTarget(from: 380, side: 1, footY: 300, selfID: 99, windows: onlyBack, margin: 28,
                                             visible: visible) == nil)
    }
}

// MARK: - Video und Vollbild

@Suite struct MediaWatcherTests {
    @Test func keepAwakeToolsAreNoVideo() {
        #expect(!MediaWatcher.isVideo(processName: "Amphetamine", assertionNames: ["Amphetamine (Single-Use - Display)"]))
        #expect(!MediaWatcher.isVideo(processName: "caffeinate", assertionNames: ["caffeinate command-line tool"]))
        #expect(!MediaWatcher.isVideo(processName: "Helper", assertionNames: ["Amphetamine Session"]))
    }

    @Test func playersAreVideo() {
        #expect(MediaWatcher.isVideo(processName: "IINA", assertionNames: ["IINA playback is in progress"]))
        #expect(MediaWatcher.isVideo(processName: "Google Chrome Helper", assertionNames: ["Video Wake Lock"]))
    }

    @Test func detectsWindowCoveringWholeScreen() {
        let screens = [NSRect(x: 0, y: 0, width: 1800, height: 1169), NSRect(x: 1800, y: 0, width: 2560, height: 1440)]
        let fullscreen = NSRect(x: 1800, y: 0, width: 2560, height: 1440)
        let maximized = NSRect(x: 0, y: 74, width: 1800, height: 1070) // unter der Menüleiste, über dem Dock
        #expect(MediaWatcher.coveredScreens(windows: [fullscreen, maximized], screens: screens) == [screens[1]])
        #expect(MediaWatcher.coveredScreens(windows: [maximized], screens: screens).isEmpty)
    }
}

// MARK: - Migration

@Suite struct MigrationTests {
    @Test func soundsOffBecomesSilent() {
        let store = UserDefaults(suiteName: "ClawdTests-\(UUID().uuidString)")!
        store.set(false, forKey: "soundEnabled")
        store.set(2.5, forKey: "talkativeness")
        Settings.migrate(store: store)
        #expect(store.double(forKey: "talkativeness") == 0)
        #expect(store.object(forKey: "soundEnabled") == nil)
    }

    @Test func soundsOnKeepsTalkativeness() {
        let store = UserDefaults(suiteName: "ClawdTests-\(UUID().uuidString)")!
        store.set(true, forKey: "soundEnabled")
        store.set(0.4, forKey: "talkativeness")
        Settings.migrate(store: store)
        #expect(store.double(forKey: "talkativeness") == 0.4)
        #expect(store.object(forKey: "soundEnabled") == nil)
    }
}

// MARK: - Stimme

@Suite(.serialized) struct VoiceTests {
    @Test func everySoundRendersAClippedBuffer() throws {
        let voice = Voice()
        for sound in Voice.Sound.allCases {
            let buffer = try #require(voice.buffer(for: sound), "kein Puffer für \(sound)")
            #expect(buffer.frameLength > 0)
            let data = try #require(buffer.floatChannelData?[0])
            let samples = UnsafeBufferPointer(start: data, count: Int(buffer.frameLength))
            #expect(samples.allSatisfy { abs($0) <= 1 })
            #expect(samples.contains { $0 != 0 }, "\(sound) ist stumm")
        }
    }
}

// MARK: - Bildschirmränder und Boden neben dem Dock

@Suite struct ScreenEdgeTests {
    let screen = ScreenArea(frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
                            visibleFrame: NSRect(x: 0, y: 70, width: 1440, height: 805))

    @Test func singleScreenHasTwoMagneticEdges() {
        let edges = World.screenEdges([screen])
        #expect(edges.count == 2)
        #expect(edges.keys.allSatisfy(World.isScreenEdge))
        #expect(edges.values.contains { $0.maxX == 0 })     // linker Rand = rechte Seite eines Rahmens
        #expect(edges.values.contains { $0.minX == 1440 })  // rechter Rand = linke Seite eines Rahmens
    }

    @Test func edgesBetweenScreensAreNotMagnetic() {
        let second = ScreenArea(frame: NSRect(x: 1440, y: 0, width: 1920, height: 1080),
                                visibleFrame: NSRect(x: 1440, y: 0, width: 1920, height: 1055))
        let edges = World.screenEdges([screen, second])
        #expect(edges.count == 2)
        #expect(Set(edges.values.map { $0.maxX == 0 ? 0 : $0.minX }) == [0, 3360])
    }

    @Test func walkingIntoTheLeftEdgeClimbsIt() {
        let edges = World.screenEdges([screen])
        let wall = PetController.climbableWall(in: edges, groundY: 0, from: 3, to: -1, direction: -1)
        #expect(wall?.side == 1)
        #expect(wall.map { World.isScreenEdge($0.id) } == true)
        let right = PetController.climbableWall(in: edges, groundY: 0, from: 1437, to: 1441, direction: 1)
        #expect(right?.side == -1)
    }

    @Test func draggedNearTheEdgeIsAttracted() {
        let edges = World.screenEdges([screen])
        let m = PetController.magnetTarget(body: NSRect(x: 20, y: 400, width: 56, height: 32),
                                           windows: edges, reach: 40, margin: 28)
        #expect(m?.side == 1)
        #expect(m?.distance == 20)
    }

    @Test func floorIsSplitAroundTheDock() {
        let dock = Platform(kind: .dock, minX: 400, maxX: 1000, y: 70)
        let floor = World.floorSegments(screens: [screen], dock: dock)
        #expect(floor.map { [$0.minX, $0.maxX] } == [[0, 400], [1000, 1440]])
        #expect(floor.allSatisfy { $0.kind == .floor(0) && $0.y == 0 })
        #expect(World.floorSegments(screens: [screen], dock: nil).count == 1)
    }
}

// MARK: - Neigung

@Suite struct TiltTests {
    @Test func parsesLateralAxisFromReport() {
        var report = [UInt8](repeating: 0, count: 22)
        let value = Int32(-0.25 * 65536) // −0,25 g
        withUnsafeBytes(of: value.littleEndian) { bytes in
            for (i, b) in bytes.enumerated() { report[TiltSensor.axisOffset + i] = b }
        }
        let g = report.withUnsafeBufferPointer { TiltSensor.lateral(from: $0) }
        #expect(g == -0.25 * TiltSensor.axisSign)
        #expect([UInt8](repeating: 0, count: 4).withUnsafeBufferPointer { TiltSensor.lateral(from: $0) } == nil)
    }

    @Test func slidingStartsAboveFriction() {
        // Ab der Startneigung muss der Hangabtrieb (g = 2600 pt/s²) die Haftreibung übersteigen.
        #expect(PetController.slideStart * 2600 > Double(PetController.slideFriction))
        #expect(PetController.slideBusy > PetController.slideStart)
    }
}

// MARK: - Wand am Bildschirmrand

@Suite struct WallRoomTests {
    let screens = [NSRect(x: 0, y: 0, width: 1800, height: 1169)]

    @Test func windowSideInsideTheScreenHolds() {
        #expect(PetController.wallHasRoom(x: 600, side: -1, depth: 48, y: 400, screens: screens))
        #expect(PetController.wallHasRoom(x: 1100, side: 1, depth: 48, y: 400, screens: screens))
    }

    @Test func maximizedWindowPushesHimOffTheScreen() {
        // Fenster auf volle Breite gezogen: die linke Seite liegt bei x = 0, der Körper ragt hinaus.
        #expect(!PetController.wallHasRoom(x: 0, side: -1, depth: 48, y: 400, screens: screens))
        #expect(!PetController.wallHasRoom(x: 1800, side: 1, depth: 48, y: 400, screens: screens))
    }

    @Test func neighbourScreenGivesRoom() {
        let two = screens + [NSRect(x: -1440, y: 0, width: 1440, height: 900)]
        #expect(PetController.wallHasRoom(x: 0, side: -1, depth: 48, y: 400, screens: two))
    }
}
