#!/usr/bin/env swift
// Renders QLite's app icon into Resources/Assets.xcassets/AppIcon.appiconset.
// Run with: swift Scripts/generate-icon.swift

import AppKit
import Foundation

let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels,
                                     pixelsHigh: pixels,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)
    let rect = CGRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)

    // Rounded square with a blue gradient background.
    let squircle = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.22, green: 0.51, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.29, blue: 0.78, alpha: 1)
    ])
    gradient?.draw(in: squircle, angle: -90)

    // Three stacked "table rows" suggesting a database.
    let inset = rect.insetBy(dx: s * 0.17, dy: s * 0.20)
    let rowHeight = inset.height / 3.4
    NSColor.white.withAlphaComponent(0.95).setFill()
    for index in 0..<3 {
        let y = inset.maxY - CGFloat(index + 1) * rowHeight - CGFloat(index) * rowHeight * 0.16
        let row = CGRect(x: inset.minX, y: y, width: inset.width, height: rowHeight)
        let path = NSBezierPath(roundedRect: row, xRadius: rowHeight * 0.22, yRadius: rowHeight * 0.22)
        if index == 0 {
            path.fill()
        } else {
            NSColor.white.withAlphaComponent(index == 1 ? 0.75 : 0.5).setFill()
            path.fill()
        }
    }

    // Column divider.
    NSColor(calibratedRed: 0.10, green: 0.29, blue: 0.78, alpha: 1).setFill()
    CGRect(x: inset.minX + inset.width * 0.38, y: inset.minY, width: max(1, s * 0.018), height: inset.height).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

var images: [[String: String]] = []
for (size, scale) in sizes {
    let pixels = size * scale
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    guard let data = drawIcon(pixels: pixels) else { continue }
    try data.write(to: iconSet.appendingPathComponent(name))
    images.append([
        "idiom": "mac",
        "size": "\(size)x\(size)",
        "scale": "\(scale)x",
        "filename": name
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "qlite"]
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconSet.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon images to \(iconSet.path)")
