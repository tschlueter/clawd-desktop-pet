import AppKit
import CoreAudio
import CoreMediaIO
import IOKit.pwr_mgt

/// Beobachtet, ob gerade ein Video läuft oder eine App den ganzen Bildschirm füllt.
///
/// - Video: Player (IINA, QuickTime, VLC, Browser, Videocalls …) halten während der Wiedergabe den
///   Bildschirm wach ("PreventUserIdleDisplaySleep"). Reine Wach-halte-Tools wie Amphetamine oder
///   caffeinate tun das dauerhaft – sie werden ignoriert.
/// - Anruf: Mikrofon oder Kamera sind gerade in Benutzung (Videocall, auch nur Audio, auch im Browser).
///   Das lässt sich ohne Mikrofon- oder Kamera-Berechtigung abfragen; Clawd selbst nutzt beides nicht.
///   Kein Nachsehen nötig: Audio- und Kamera-System melden Änderungen von selbst (Property-Listener).
///
/// Video und Vollbild werden viermal pro Sekunde geprüft; ein Space-Wechsel löst zusätzlich sofort eine
/// Prüfung aus.
/// - Vollbild: ein normales Fenster einer anderen App, das genau einen ganzen Bildschirm bedeckt.
final class MediaWatcher {
    struct State: Equatable {
        var videoPlaying = false
        var callActive = false
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

    /// Zuletzt gemeldeter Zustand von Mikrofon und Kamera (aus den Listenern).
    private var microphoneActive = false
    private var cameraActive = false
    /// Listener pro Gerät, damit sie beim Abstecken wieder entfernt werden können.
    private var audioListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var cameraListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]

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
        startDeviceListeners()
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
                        callActive: microphoneActive || cameraActive,
                        fullscreenScreens: Self.fullscreenScreens(excluding: ownPID))
        publish(new)
    }

    private func publish(_ new: State) {
        guard new != state else { return }
        state = new
        onChange?(new)
    }

    /// Ein Listener hat sich gemeldet: Mikrofon und Kamera neu auswerten (der Rest bleibt, wie er ist).
    private func deviceStateChanged() {
        microphoneActive = Self.microphoneInUse()
        cameraActive = Self.cameraInUse()
        var new = state
        new.callActive = microphoneActive || cameraActive
        publish(new)
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

    // MARK: - Anruf (Mikrofon, Kamera)

    private static let audioDevicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private static let audioRunningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static let cameraDevicesAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    private static let cameraRunningAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))

    /// Listener für "Gerät läuft" an jedem Mikrofon und jeder Kamera – und für die Geräteliste selbst,
    /// damit auch ein später angestecktes Headset oder eine externe Kamera erfasst wird.
    private func startDeviceListeners() {
        var devices = Self.audioDevicesAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, .main) { [weak self] _, _ in
            self?.refreshDeviceListeners()
        }
        var cameras = Self.cameraDevicesAddress
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameras, .main) { [weak self] _, _ in
            self?.refreshDeviceListeners()
        }
        refreshDeviceListeners()
    }

    private func refreshDeviceListeners() {
        let mics = Set(Self.inputDevices())
        for (id, block) in audioListeners where !mics.contains(id) {
            var addr = Self.audioRunningAddress
            AudioObjectRemovePropertyListenerBlock(id, &addr, .main, block)
            audioListeners[id] = nil
        }
        for id in mics where audioListeners[id] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceStateChanged() }
            var addr = Self.audioRunningAddress
            if AudioObjectAddPropertyListenerBlock(id, &addr, .main, block) == noErr { audioListeners[id] = block }
        }
        let cams = Set(Self.cameraDevices())
        for (id, block) in cameraListeners where !cams.contains(id) {
            var addr = Self.cameraRunningAddress
            CMIOObjectRemovePropertyListenerBlock(id, &addr, .main, block)
            cameraListeners[id] = nil
        }
        for id in cams where cameraListeners[id] == nil {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceStateChanged() }
            var addr = Self.cameraRunningAddress
            if CMIOObjectAddPropertyListenerBlock(id, &addr, .main, block) == 0 { cameraListeners[id] = block }
        }
        DebugLog.log("Anruf-Erkennung: \(audioListeners.count) Mikrofon(e), \(cameraListeners.count) Kamera(s) beobachtet")
        deviceStateChanged()
    }

    /// Alle Audiogeräte mit Eingang (Mikrofone).
    private static func inputDevices() -> [AudioObjectID] {
        var addr = audioDevicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    /// Alle Kameras.
    private static func cameraDevices() -> [CMIOObjectID] {
        var addr = cameraDevicesAddress
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == 0 else { return [] }
        return devices
    }

    /// Nimmt gerade irgendein Programm über ein Mikrofon auf?
    static func microphoneInUse() -> Bool {
        inputDevices().contains { device in
            var addr = audioRunningAddress
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr && value != 0
        }
    }

    /// Ist gerade irgendeine Kamera eingeschaltet?
    static func cameraInUse() -> Bool {
        cameraDevices().contains { device in
            var addr = cameraRunningAddress
            var value: UInt32 = 0
            var used: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == 0
                && value != 0
        }
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
        // Das Dock hat auf jedem normalen Space ein bildschirmgroßes Fenster (Ebene 20); in einem
        // Vollbild-Space fehlt es. Damit lässt sich ein Vollbild unter der Notch von einem bloß
        // maximierten Fenster (bei ausgeblendetem Dock) unterscheiden.
        let dockLayers: [NSRect] = list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 20,
                  (info[kCGWindowOwnerName as String] as? String) == "Dock",
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return DockLocator.cocoaRect(fromTopLeft: cg)
        }
        let screens = NSScreen.screens
        return coveredScreens(windows: windows, screens: screens.map(\.frame), topInsets: screens.map(\.safeAreaInsets.top),
                              dockLayers: dockLayers)
    }

    /// Bildschirme, die von einem Fenster vollständig (±1 pt) bedeckt sind. Bei MacBooks mit Notch
    /// (`topInsets` > 0) lässt ein Vollbildfenster oben den Streifen neben der Kamera frei – es reicht
    /// dann bis knapp unter die Notch (±2 pt).
    /// Ein Fenster in Notch-Höhe zählt nur, wenn auf dem Bildschirm kein Dock-Fenster (`dockLayers`) liegt.
    static func coveredScreens(windows: [NSRect], screens: [NSRect], topInsets: [CGFloat] = [],
                               dockLayers: [NSRect] = []) -> [NSRect] {
        screens.enumerated().filter { i, s in
            let inset = i < topInsets.count ? topInsets[i] : 0
            let normalSpace = dockLayers.contains { $0.intersects(s.insetBy(dx: 1, dy: 1)) }
            return windows.contains { w in
                guard abs(w.minX - s.minX) <= 1, abs(w.minY - s.minY) <= 1, abs(w.width - s.width) <= 1 else { return false }
                if abs(w.height - s.height) <= 1 { return true }
                return inset > 0 && !normalSpace && abs(w.height - (s.height - inset)) <= 2
            }
        }.map(\.element)
    }
}
