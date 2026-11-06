import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brand = root.appendingPathComponent("Resources/Brand")
func render(_ name: String, size: Int, destination: URL) throws {
    let source = brand.appendingPathComponent(name + ".svg")
    guard let image = NSImage(contentsOf: source) else { fatalError("Could not read \(name) SVG") }
    let canvas = NSSize(width: size, height: size)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Could not create bitmap") }
    bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: canvas), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
    try data.write(to: destination)
}

try render("AlwaysOnline-MenuBar", size: 32, destination: brand.appendingPathComponent("AlwaysOnline-MenuBar.png"))
try render("AlwaysOnline-AppIcon", size: 1024, destination: brand.appendingPathComponent("AlwaysOnline-AppIcon-Preview.png"))

let iconset = URL(fileURLWithPath: "/private/tmp/always-online.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
