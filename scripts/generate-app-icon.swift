#!/usr/bin/env swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("ExileRoute/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Unable to create icon bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = CGFloat(size) * 0.055
    let outer = NSBezierPath(roundedRect: canvas.insetBy(dx: inset, dy: inset), xRadius: CGFloat(size) * 0.17, yRadius: CGFloat(size) * 0.17)
    outer.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.086, green: 0.098, blue: 0.106, alpha: 1),
        NSColor(calibratedRed: 0.043, green: 0.051, blue: 0.059, alpha: 1)
    ])!.draw(in: canvas, angle: -58)

    NSColor(calibratedRed: 0.72, green: 0.57, blue: 0.35, alpha: 0.92).setStroke()
    outer.lineWidth = max(CGFloat(size) * 0.018, 1)
    outer.stroke()

    let center = NSPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
    let radius = CGFloat(size) * 0.265
    let diamond = NSBezierPath()
    diamond.move(to: NSPoint(x: center.x, y: center.y + radius))
    diamond.line(to: NSPoint(x: center.x + radius, y: center.y))
    diamond.line(to: NSPoint(x: center.x, y: center.y - radius))
    diamond.line(to: NSPoint(x: center.x - radius, y: center.y))
    diamond.close()
    NSColor(calibratedRed: 0.44, green: 0.66, blue: 0.65, alpha: 0.95).setStroke()
    diamond.lineWidth = max(CGFloat(size) * 0.026, 1.2)
    diamond.stroke()

    for factor in [0.31, 0.17] as [CGFloat] {
        let circleRadius = CGFloat(size) * factor
        let circle = NSBezierPath(ovalIn: NSRect(
            x: center.x - circleRadius, y: center.y - circleRadius,
            width: circleRadius * 2, height: circleRadius * 2
        ))
        NSColor(calibratedRed: 0.44, green: 0.66, blue: 0.65, alpha: factor == 0.31 ? 0.55 : 0.9).setStroke()
        circle.lineWidth = max(CGFloat(size) * 0.014, 1)
        circle.stroke()
    }

    let emberRadius = CGFloat(size) * 0.067
    NSColor(calibratedRed: 0.78, green: 0.36, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - emberRadius, y: center.y - emberRadius,
        width: emberRadius * 2, height: emberRadius * 2
    )).fill()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Unable to encode icon") }
    try data.write(to: output.appendingPathComponent("icon_\(size).png"), options: .atomic)
}
