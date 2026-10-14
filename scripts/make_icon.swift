// Renders the MyAltTab app icon into Resources/AppIcon.icns.
// Usage: swift scripts/make_icon.swift
import AppKit

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)

    // Background squircle on Apple's 1024 grid (824pt body, drop shadow).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.20, blue: 0.55, alpha: 1),
                        NSColor(srgbRed: 0.42, green: 0.25, blue: 0.85, alpha: 1)])!
        .draw(in: body, angle: 60)
    NSGraphicsContext.restoreGraphicsState()

    // Two stacked windows: a translucent one behind, a solid one in front.
    func window(_ rect: NSRect, fill: NSColor, bar: NSColor, dots: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 36, yRadius: 36)
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.3)
        s.shadowOffset = NSSize(width: 0, height: -10)
        s.shadowBlurRadius = 24
        s.set()
        fill.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        bar.setFill()
        NSRect(x: rect.minX, y: rect.maxY - 70, width: rect.width, height: 70).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard dots else { return }
        let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (i, color) in colors.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 34 + CGFloat(i) * 46, y: rect.maxY - 51, width: 32, height: 32)).fill()
        }
    }
    window(NSRect(x: 210, y: 420, width: 480, height: 360),
           fill: NSColor.white.withAlphaComponent(0.35), bar: NSColor.white.withAlphaComponent(0.25), dots: false)
    let front = NSRect(x: 334, y: 236, width: 480, height: 360)
    window(front, fill: .white, bar: NSColor(white: 0.9, alpha: 1), dots: true)

    // ⌥⇥ glyph in the front window.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let glyph = NSAttributedString(string: "⌥⇥", attributes: [
        .font: NSFont.systemFont(ofSize: 150, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.30, green: 0.24, blue: 0.75, alpha: 1),
        .paragraphStyle: paragraph,
    ])
    let content = NSRect(x: front.minX, y: front.minY, width: front.width, height: front.height - 70)
    let height = glyph.size().height
    glyph.draw(in: NSRect(x: content.minX, y: content.midY - height / 2, width: content.width, height: height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(pixels: 1024).write(to: root.appendingPathComponent("Resources/AppIcon-preview.png"))

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
print(process.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
