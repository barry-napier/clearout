import AppKit

/// A tiny half-circle map for the menu bar. macOS colors it to match.
@MainActor
enum MenuIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            let center = NSPoint(x: 10, y: 3)
            for (from, to, radius) in [(180.0, 112.0, 10.0), (102.0, 48.0, 10.0), (38.0, 0.0, 8.0)] {
                let band = NSBezierPath()
                band.appendArc(withCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: true)
                band.appendArc(withCenter: center, radius: 4, startAngle: to, endAngle: from, clockwise: false)
                band.close()
                NSColor.black.setFill()
                band.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
