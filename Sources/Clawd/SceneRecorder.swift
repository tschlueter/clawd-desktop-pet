import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Nimmt eine Szene im Spielplatz als Endlos-GIF auf (Startoption `--record`): Bild für Bild
/// werden die Layer des Spielplatzes gerendert – genau die Grafik der App, ohne Bildschirmaufnahme.
final class SceneRecorder {
    private let playground: Playground
    private let rect: CGRect?
    private let scale: CGFloat
    private let duration: TimeInterval
    private let fps: Double = 20
    private let url: URL
    private let done: () -> Void
    private var frames: [CGImage] = []
    private var timer: Timer?
    private var startedAt: CFTimeInterval = 0

    init(playground: Playground, rect: CGRect?, scale: CGFloat, duration: TimeInterval, path: String,
         done: @escaping () -> Void) {
        self.playground = playground
        self.rect = rect
        self.scale = scale
        self.duration = duration
        self.url = URL(fileURLWithPath: path)
        self.done = done
    }

    func start() {
        guard timer == nil else { return }
        startedAt = CACurrentMediaTime()
        DebugLog.write("Aufnahme läuft: \(Int(duration)) s")
        let t = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in self?.capture() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        capture()
    }

    private func capture() {
        if let image = playground.snapshot(rect: rect, scale: scale) { frames.append(image) }
        if CACurrentMediaTime() - startedAt >= duration { finish() }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        let ok = Self.writeGIF(frames, delay: 1 / fps, to: url)
        DebugLog.write(ok ? "GIF gespeichert: \(url.path) (\(frames.count) Bilder)" : "GIF konnte nicht gespeichert werden")
        done()
    }

    static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) -> Bool {
        guard !frames.isEmpty,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { return false }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                          kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(dest, frame, frameProps) }
        return CGImageDestinationFinalize(dest)
    }
}
