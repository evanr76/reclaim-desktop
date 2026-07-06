import AppKit

// Renders a neutral, non-branded app icon: a blue "squircle" with a white
// checkmark. Output: a 1024×1024 PNG at the path given as argv[1].

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    color.set()
    let r = NSRect(origin: .zero, size: image.size)
    image.draw(in: r)
    r.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let s = CGFloat(size)
let inset = s * 0.094                    // transparent padding around the squircle
let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
let radius = rect.width * 0.2237         // macOS-style continuous-ish corner

let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.33, green: 0.60, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.12, green: 0.34, blue: 0.90, alpha: 1),
])!
gradient.draw(in: rect, angle: -90)
NSGraphicsContext.restoreGraphicsState()

let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .bold)
if let base = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let mark = tinted(base, .white)
    let m = mark.size
    let origin = CGPoint(x: (s - m.width) / 2, y: (s - m.height) / 2)
    mark.draw(in: CGRect(origin: origin, size: m))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8)); exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
