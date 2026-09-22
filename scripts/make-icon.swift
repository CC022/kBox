// Draws the kBox app icon into the asset catalog (iOS 1024 + macOS 16–512@2x).
// Usage: swift scripts/make-icon.swift [App/Assets.xcassets/AppIcon.appiconset]
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Renders the icon at `pixels`×`pixels`, drawing in a 1024-point canvas (macOS icon grid).
func render(pixels: Int, inset: Bool) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icons sit on the Big Sur grid with a shadow; iOS icons are full-bleed and masked by the system.
    let margin: CGFloat = inset ? 100 : 0
    let side = 1024 - margin * 2
    let radius: CGFloat = inset ? 185 : 230
    let body = NSBezierPath(roundedRect: NSRect(x: margin, y: margin, width: side, height: side),
                            xRadius: radius, yRadius: radius)

    if inset {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor(srgbRed: 0, green: 0.4, blue: 0.88, alpha: 1).setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGradient(
        starting: NSColor(srgbRed: 0.0, green: 0.38, blue: 0.86, alpha: 1),
        ending: NSColor(srgbRed: 0.33, green: 0.66, blue: 1.0, alpha: 1)
    )!.draw(in: body, angle: 90)

    let symbolSize: CGFloat = inset ? 420 : 520
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: 512 - size.width / 2, y: (inset ? 505 : 512) - size.height / 2,
                               width: size.width, height: size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Draw once at full size, then downscale: small bitmap contexts rasterize the symbol poorly.
func master(inset: Bool) -> NSImage { NSImage(data: render(pixels: 1024, inset: inset))! }

func scaled(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

struct Entry {
    let filename: String
    let idiom: String
    let size: String
    /// Single-size icons (iOS 17+) carry no scale.
    let scale: String?
    let platform: String?
}

var entries: [Entry] = []
var files: [String: Data] = [:]

// iOS: one 1024 full-bleed image
let ios = master(inset: false)
files["icon-ios-1024.png"] = scaled(ios, pixels: 1024)
entries.append(Entry(filename: "icon-ios-1024.png", idiom: "universal", size: "1024x1024", scale: nil, platform: "ios"))

// macOS: the classic set, inset on the icon grid
let mac = master(inset: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let name = "icon-mac-\(points)x\(points)@\(scale)x.png"
    files[name] = scaled(mac, pixels: pixels)
    entries.append(Entry(filename: name, idiom: "mac", size: "\(points)x\(points)", scale: "\(scale)x", platform: nil))
}

for (name, data) in files {
    try data.write(to: output.appending(path: name))
}

let imageJSON = entries.map { entry in
    var fields = ["\"filename\" : \"\(entry.filename)\"", "\"idiom\" : \"\(entry.idiom)\""]
    if let platform = entry.platform { fields.append("\"platform\" : \"\(platform)\"") }
    if let scale = entry.scale { fields.append("\"scale\" : \"\(scale)\"") }
    fields.append("\"size\" : \"\(entry.size)\"")
    return "    {\n      " + fields.sorted().joined(separator: ",\n      ") + "\n    }"
}.joined(separator: ",\n")

let contents = """
{
  "images" : [
\(imageJSON)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: output.appending(path: "Contents.json"), atomically: true, encoding: .utf8)

// The asset catalog itself needs a Contents.json too.
let catalog = output.deletingLastPathComponent()
let catalogContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try catalogContents.write(to: catalog.appending(path: "Contents.json"), atomically: true, encoding: .utf8)

print("Wrote \(files.count) icons to \(output.path)")
