// Draws the Clearout icon: the half-circle map on a dark tile.
import AppKit

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)

let tile = color(0x17201B)
tile.setFill()
NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185).fill()

let center = NSPoint(x: 512, y: 352)
func band(_ from: CGFloat, _ to: CGFloat, _ inner: CGFloat, _ outer: CGFloat, _ fill: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: outer, startAngle: from, endAngle: to, clockwise: true)
    path.appendArc(withCenter: center, radius: inner, startAngle: to, endAngle: from, clockwise: false)
    path.close()
    fill.setFill()
    path.fill()
    tile.setStroke()
    path.lineWidth = 14
    path.lineJoinStyle = .round
    path.stroke()
}

band(180, 100, 120, 235, color(0x3987E5))
band(100, 52, 120, 235, color(0xEB6834))
band(52, 22, 120, 235, color(0x1BAF7A))
band(22, 0, 120, 235, color(0xEDA100))
band(180, 140, 235, 335, color(0x3987E5, 0.65))
band(140, 108, 235, 305, color(0x3987E5, 0.65))
band(100, 60, 235, 335, color(0xEB6834, 0.65))
band(52, 28, 235, 295, color(0x1BAF7A, 0.65))

color(0xEEF1EC).setFill()
let hub = NSBezierPath()
hub.appendArc(withCenter: center, radius: 94, startAngle: 0, endAngle: 180)
hub.close()
hub.fill()

NSGraphicsContext.current?.flushGraphics()
try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
