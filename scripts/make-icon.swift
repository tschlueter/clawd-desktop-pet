// Erzeugt das App-Symbol: Clawd hinter seinem Laptop auf einer abgerundeten macOS-Kachel.
// Aufruf: swift scripts/make-icon.swift /tmp/AppIcon.iconset && iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// Clawd sitzend (14×8, wie im Spiel) und Laptop von hinten in doppelter Auflösung (20×8).
let clawd = [
    "..............", "..............",
    "..XXXXXXXXXX..", "..XXEXXXXEXX..", "..XXEXXXXEXX..",
    "XXXXXXXXXXXXXX", "XXXXXXXXXXXXXX", "..XXXXXXXXXX..",
]
// Etwas flacher als im Spiel, damit Kopf und Augen frei bleiben (deckt nur den Oberkörper).
let laptop = [
    "KKKKKKKKKKKKKKKKKKKK", "KGGGGGGGGGGGGGGGGGGK", "KGGGGGGGOOOOGGGGGGGK",
    "KGGGGGGGOOOOGGGGGGGK", "KGGGGGGGGGGGGGGGGGGK", "KKKKKKKKKKKKKKKKKKKK",
]
func rgb(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let colors: [Character: NSColor] = ["X": rgb(0xD97757), "E": rgb(0x1A1A1A), "K": rgb(0x3A3F45),
                                    "G": rgb(0xC9CED4), "O": rgb(0xD97757)]

/// Zeichnet das Symbol in ein 1024er-Raster (Ursprung unten links).
func drawIcon() {
    // Kachel mit leichtem Schatten
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    rgb(0xF6E7DC).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: rgb(0xFFF8F2), ending: rgb(0xF2DCCB))!.draw(in: path, angle: -90)

    // Pixel: Clawd 14×8 mit 48 px je Zelle (sichtbar sind 6 Zeilen), mittig; Laptop davor mit 24 px je Zelle
    let cell: CGFloat = 48
    let x0: CGFloat = 512 - 7 * cell, yBottom: CGFloat = 512 - 3 * cell

    // Weicher Bodenschatten unter Clawd
    rgb(0x000000).withAlphaComponent(0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: 512 - 290, y: yBottom - 30, width: 580, height: 56)).fill()
    func pixels(_ rows: [String], x: CGFloat, bottom: CGFloat, size: CGFloat) {
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                guard let color = colors[ch] else { continue }
                color.setFill()
                NSRect(x: x + CGFloat(c) * size, y: bottom + CGFloat(rows.count - 1 - r) * size,
                       width: size, height: size).fill()
            }
        }
    }
    pixels(clawd, x: x0, bottom: yBottom, size: cell)
    pixels(laptop, x: x0 + 2 * cell, bottom: yBottom, size: cell / 2)
}

func render(_ pixelsWide: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsWide,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.cgContext.scaleBy(x: CGFloat(pixelsWide) / 1024, y: CGFloat(pixelsWide) / 1024)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
    try render(size * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}
print("Fertig: \(out)")
