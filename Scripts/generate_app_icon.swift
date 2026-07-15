#!/usr/bin/env swift

import AppKit
import Foundation

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = projectRoot
    .appendingPathComponent("Sortwell/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon() {
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()

    let backgroundRect = NSRect(x: 54, y: 54, width: 916, height: 916)
    let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 214, yRadius: 214)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.04, alpha: 0.32)
    shadow.shadowBlurRadius = 42
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.24, alpha: 1).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(calibratedRed: 0.24, green: 0.48, blue: 0.38, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.22, alpha: 1)
    ])?.draw(in: background, angle: -72)

    let highlight = NSBezierPath(roundedRect: NSRect(x: 92, y: 610, width: 840, height: 302), xRadius: 164, yRadius: 164)
    NSColor(calibratedWhite: 1, alpha: 0.055).setFill()
    highlight.fill()

    let documents: [(NSRect, NSColor, CGFloat)] = [
        (NSRect(x: 174, y: 472, width: 528, height: 348), NSColor(calibratedRed: 0.72, green: 0.83, blue: 0.76, alpha: 1), -7),
        (NSRect(x: 247, y: 352, width: 528, height: 348), NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.87, alpha: 1), -1),
        (NSRect(x: 320, y: 232, width: 528, height: 348), NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.90, alpha: 1), 5)
    ]

    for (index, document) in documents.enumerated() {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: document.0.midX, yBy: document.0.midY)
        transform.rotate(byDegrees: document.2)
        transform.translateX(by: -document.0.midX, yBy: -document.0.midY)
        transform.concat()

        let path = NSBezierPath(roundedRect: document.0, xRadius: 58, yRadius: 58)
        let cardShadow = NSShadow()
        cardShadow.shadowColor = NSColor(calibratedWhite: 0.02, alpha: 0.24)
        cardShadow.shadowBlurRadius = 22
        cardShadow.shadowOffset = NSSize(width: 0, height: -12)
        cardShadow.set()
        document.1.setFill()
        path.fill()

        NSGraphicsContext.restoreGraphicsState()

        if index == documents.count - 1 {
            let lineColour = NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.29, alpha: 0.72)
            lineColour.setFill()
            for line in 0..<3 {
                let width: CGFloat = line == 2 ? 226 : 310
                NSBezierPath(
                    roundedRect: NSRect(x: 430, y: 466 - CGFloat(line) * 72, width: width, height: 25),
                    xRadius: 12,
                    yRadius: 12
                ).fill()
            }
            NSColor(calibratedRed: 0.28, green: 0.57, blue: 0.44, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 365, y: 444, width: 38, height: 38), xRadius: 12, yRadius: 12).fill()
        }
    }
}

func render(size: Int) throws {
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
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    try data.write(to: outputDirectory.appendingPathComponent("AppIcon-\(size).png"), options: .atomic)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for size in sizes {
    try render(size: size)
}
