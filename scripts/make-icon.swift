import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let sizes = [16, 32, 128, 256, 512]
for base in sizes {
    for scale in [1, 2] {
        let size = base * scale
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        let c = CGFloat(size) / 1024
        let transform = NSAffineTransform(); transform.scale(by: c); transform.concat()
        let rect = NSRect(x: 70, y: 70, width: 884, height: 884)
        let path = NSBezierPath(roundedRect: rect, xRadius: 195, yRadius: 195)
        NSGradient(starting: NSColor(srgbRed: 0.14, green: 0.19, blue: 0.21, alpha: 1), ending: NSColor(srgbRed: 0.04, green: 0.07, blue: 0.09, alpha: 1))!.draw(in: path, angle: -60)
        NSColor(srgbRed: 0.68, green: 0.98, blue: 0.79, alpha: 1).setFill()
        let heights: [CGFloat] = [100, 220, 360, 500, 630, 460, 300, 180, 90]
        for (index, height) in heights.enumerated() {
            let bar = NSRect(x: 227 + CGFloat(index) * 65, y: (1024 - height) / 2, width: 36, height: height)
            NSBezierPath(roundedRect: bar, xRadius: 18, yRadius: 18).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try representation.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
    }
}
