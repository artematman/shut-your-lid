import AppKit

// Package the owner-selected artwork at native macOS icon resolutions.
let folder = CommandLine.arguments[1]
let source = CommandLine.arguments[2]
guard let artwork = NSImage(contentsOfFile: source) else { fatalError("Selected logo is missing") }
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    artwork.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    for base in [16, 32, 128, 256, 512] {
        if size == base { try data.write(to: URL(fileURLWithPath: folder + "/icon_\(base)x\(base).png")) }
        if size == base * 2 { try data.write(to: URL(fileURLWithPath: folder + "/icon_\(base)x\(base)@2x.png")) }
    }
}
