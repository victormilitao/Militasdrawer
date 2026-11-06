// Run from the repository root: swift scripts/generate-app-icon.swift
// Original geometric layer mark, matching the app's navy palette.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high
NSColor.white.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let navy = NSColor(srgbRed: 30 / 255, green: 58 / 255, blue: 138 / 255, alpha: 1)
navy.setStroke()
navy.setFill()

// Coordinates are in AppKit's bottom-left coordinate system.
for y: CGFloat in [278, 408] {
    let layer = NSBezierPath()
    layer.move(to: NSPoint(x: 238, y: y + 97))
    layer.line(to: NSPoint(x: 512, y: y - 54))
    layer.line(to: NSPoint(x: 786, y: y + 97))
    layer.lineWidth = 58
    layer.lineCapStyle = .round
    layer.lineJoinStyle = .round
    layer.stroke()
}
let top = NSBezierPath()
top.move(to: NSPoint(x: 512, y: 802))
top.line(to: NSPoint(x: 786, y: 651))
top.line(to: NSPoint(x: 512, y: 500))
top.line(to: NSPoint(x: 238, y: 651))
top.close()
top.lineWidth = 30
top.lineJoinStyle = .round
top.fill()
top.stroke()
NSGraphicsContext.restoreGraphicsState()
let destination = URL(fileURLWithPath: "Militasdrawer/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let image = context.makeImage()!
let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, image, nil)
precondition(CGImageDestinationFinalize(output), "Could not write icon")
print("Generated \(destination.path)")
