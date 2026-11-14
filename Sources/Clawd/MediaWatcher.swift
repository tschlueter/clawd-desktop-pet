import AppKit
import IOKit.pwr_mgt

/// Beobachtet, ob gerade ein Video läuft oder eine App den ganzen Bildschirm füllt.
///
/// - Video: Player (IINA, QuickTime, VLC, Browser, Videocalls …) halten während der Wiedergabe den
///   Bildschirm wach ("PreventUserIdleDisplaySleep"). Reine Wach-halte-Tools wie Amphetamine oder
///   caffeinate tun das dauerhaft – sie werden ignoriert.
/// - Vollbild: ein normales Fenster einer anderen App, das genau einen ganzen Bildschirm bedeckt.
final class MediaWatcher {
    struct State: Equatable {
        var videoPlaying = false
        /// Bildschirme (Cocoa-Rahmen), auf denen gerade eine App im Vollbild läuft.
        var fullscreenScreens: [NSRect] = []
    }

    private(set) var state = State()
    var onChange: ((State) -> Void)?
    private var timer: Timer?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Prozesse, die den Bildschirm nur wach halten – kein Video.
    static let keepAwakeTools: Set<String> = [
        "amphetamine", "caffeinate", "keepingyouawake", "lungo", "caffeine", "theine", "jolt of caffeine",
        "owly", "powerd",
    ]

    private var observers: [NSObjectProtocol] = []

    init() {
        // Regelmäßig nachsehen (Video starten/stoppen, Vollbild im selben Space) …
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // … und sofort, wenn der Space wechselt oder eine andere App nach vorn kommt – eine App, die ins
        // Vollbild geht, landet in einem eigenen Space. Die Fensterliste ist dann nicht immer gleich
        // aktuell, daher kurz hintereinander mehrmals prüfen.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.pollSoon()
            })
        }
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    /// Jetzt und kurz danach noch einmal prüfen.
    private func pollSoon() {
        poll()
        for delay in [0.05, 0.15, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.poll() }
        }
    }

    func poll() {
        let new = State(videoPlaying: Self.videoPlaying(excluding: ownPID),
                        fullscreenScreens: Self.fullscreenScreens(excluding: ownPID))
        guard new != state else { return }
        state = new
        onChange?(new)
    }

    // MARK: - Video

    static func videoPlaying(excluding ownPID: pid_t) -> Bool {
        var ref: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&ref) == kIOReturnSuccess,
              let byPID = ref?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return false }
        for (pid, assertions) in byPID where pid.int32Value != ownPID {
            let holdsDisplay = assertions.contains { a in
                let type = a[kIOPMAssertionTypeKey] as? String
                return type == kIOPMAssertionTypePreventUserIdleDisplaySleep || type == kIOPMAssertionTypeNoDisplaySleep
            }
            guard holdsDisplay else { continue }
            let names = assertions.compactMap { $0[kIOPMAssertionNameKey] as? String }
            if isVideo(processName: processName(pid.int32Value), assertionNames: names) { return true }
        }
        return false
    }

    /// Wach-halte-Tools zählen nicht als Video (am Prozess- oder Assertion-Namen erkannt).
    static func isVideo(processName: String, assertionNames: [String]) -> Bool {
        let process = processName.lowercased()
        if keepAwakeTools.contains(process) { return false }
        let tool = assertionNames.contains { name in keepAwakeTools.contains { name.lowercased().hasPrefix($0) } }
        return !tool
    }

    private static func processName(_ pid: pid_t) -> String {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }

    // MARK: - Vollbild

    static func fullscreenScreens(excluding ownPID: pid_t) -> [NSRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let windows: [NSRect] = list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return DockLocator.cocoaRect(fromTopLeft: cg)
        }
        return coveredScreens(windows: windows, screens: NSScreen.screens.map(\.frame))
    }

    /// Bildschirme, die von einem Fenster vollständig (±1 pt) bedeckt sind.
    static func coveredScreens(windows: [NSRect], screens: [NSRect]) -> [NSRect] {
        screens.filter { s in
            windows.contains { w in
                abs(w.minX - s.minX) <= 1 && abs(w.minY - s.minY) <= 1 && abs(w.width - s.width) <= 1 && abs(w.height - s.height) <= 1
            }
        }
    }
}
