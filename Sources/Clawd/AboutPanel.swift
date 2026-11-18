import AppKit

/// "Über Clawd Desktop Pet": das Standard-Info-Fenster von macOS mit winkendem Clawd, Version,
/// Links zu Lizenz und Quellcode und dem Hinweis aus der README.
enum AboutPanel {
    static let repository = URL(string: "https://github.com/tschlueter/clawd-desktop-pet")!
    static let license = URL(string: "https://github.com/tschlueter/clawd-desktop-pet/blob/main/LICENSE")!

    static func show() {
        // Menüleisten-App: erst nach vorn holen, sonst öffnet das Fenster hinter anderen.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Clawd Desktop Pet",
            .applicationIcon: clawdImage(),
            .credits: credits(),
        ])
    }

    /// Winkender Clawd, scharf vergrößert, mittig auf einer quadratischen Fläche.
    static func clawdImage(size: CGFloat = 128) -> NSImage {
        let frame = ClawdSprite.wave[1]
        let sprite = ClawdSprite.cgImage(frame)
        let scale = (size * 0.85 / CGFloat(frame[0].count)).rounded(.down)
        let w = CGFloat(frame[0].count) * scale, h = CGFloat(frame.count) * scale
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(sprite, in: CGRect(x: ((size - w) / 2).rounded(), y: ((size - h) / 2).rounded(), width: w, height: h))
            return true
        }
        image.accessibilityDescription = "Clawd"
        return image
    }

    /// Text unter der Version: Herz-Zeile, Links, Hinweis auf das inoffizielle Fan-Projekt.
    static func credits() -> NSAttributedString {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: center,
        ]
        let note: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ]
        func link(_ title: String, _ url: URL) -> NSAttributedString {
            var attrs = body
            attrs[.link] = url
            return NSAttributedString(string: title, attributes: attrs)
        }
        let text = NSMutableAttributedString(string: "Made with 🧡 and a lot of tiny pixels\n\n", attributes: body)
        text.append(link(L10n.t("about.license"), license))
        text.append(NSAttributedString(string: "  ·  ", attributes: body))
        text.append(link(L10n.t("about.source"), repository))
        text.append(NSAttributedString(string: "\n\n", attributes: body))
        text.append(NSAttributedString(
            string: "Clawd Desktop Pet is an unofficial fan project and is not affiliated with or endorsed by Anthropic.",
            attributes: note))
        return text
    }
}
