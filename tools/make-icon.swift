import AppKit

// Package ImageGen artwork without redrawing its design. Keep the unmasked source
// for iOS / Icon Composer; add a macOS silhouette only to the legacy .icns export.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Resources/AppIcon-source.png")
guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Missing Resources/AppIcon-source.png\n", stderr)
    exit(1)
}
let output = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]
for (pixels, name) in variants {
    let side = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let inset = side * 0.05
    let plate = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    NSBezierPath(roundedRect: plate, xRadius: side * 0.20, yRadius: side * 0.20).addClip()
    source.draw(in: plate, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
    try data.write(to: output.appendingPathComponent(name))
    if pixels == 1024 { try data.write(to: root.appendingPathComponent("Resources/AppIcon-preview.png")) }
}
print("Packaged iconset: \(output.path)")
