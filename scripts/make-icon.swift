// Draws the kBox app icon into an .iconset folder (convert with `iconutil -c icns`).
// Usage: swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Renders the icon at `pixels`×`pixels`, drawing in a 1024-point canvas (macOS icon grid).
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)

    // soft drop shadow under the tile
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(srgbRed: 0, green: 0.4, blue: 0.88, alpha: 1).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    // blue gradient, lighter at the top
    NSGradient(
        starting: NSColor(srgbRed: 0.0, green: 0.38, blue: 0.86, alpha: 1),
        ending: NSColor(srgbRed: 0.33, green: 0.66, blue: 1.0, alpha: 1)
    )!.draw(in: body, angle: 90)

    // white SF Symbol
    let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: 512 - size.width / 2, y: 505 - size.height / 2, width: size.width, height: size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(name: String, pixels: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
// Draw once at full size, then downscale: small bitmap contexts rasterize the symbol poorly.
let master = NSImage(data: render(pixels: 1024))!
func scaled(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for size in sizes {
    try scaled(pixels: size.pixels).write(to: output.appending(path: "icon_\(size.name).png"))
}
print("Wrote \(sizes.count) icons to \(output.path)")
