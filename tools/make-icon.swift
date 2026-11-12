// Draws the Dérive app icon: a record with a winding dotted path drifting across it,
// on a warm-to-dark gradient like the player window's tint.
// Usage: swift tools/make-icon.swift <output.png>   (1024 x 1024)
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// macOS icon grid: an 824-point rounded square centered on the 1024 canvas, with a soft shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0x2B1B5A))
ctx.fillPath()
ctx.restoreGState()

// Background gradient, amber at the top left to deep indigo at the bottom right.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let background = CGGradient(colorsSpace: space,
                            colors: [color(0xF29A3E), color(0xC2416E), color(0x3A1E6B), color(0x160F33)] as CFArray,
                            locations: [0, 0.38, 0.75, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: tile.minX, y: tile.maxY),
                       end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

// The record, low and to the right, partly out of the tile.
let center = CGPoint(x: 600, y: 420)
let radius: CGFloat = 330
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.45))
ctx.setFillColor(color(0x121016))
ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
ctx.restoreGState()
// Grooves.
ctx.setLineWidth(2)
for r in stride(from: radius - 18, to: 120, by: -14) {
    ctx.setStrokeColor(color(0xFFFFFF, r.truncatingRemainder(dividingBy: 28) < 14 ? 0.07 : 0.035))
    ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
}
// A light sheen across the grooves.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
ctx.clip()
let sheen = CGGradient(colorsSpace: space,
                       colors: [color(0xFFFFFF, 0), color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray,
                       locations: [0.35, 0.5, 0.65])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: center.x - radius, y: center.y + radius),
                       end: CGPoint(x: center.x + radius, y: center.y - radius), options: [])
ctx.restoreGState()
// Label and hole.
let label: CGFloat = 105
let labelGradient = CGGradient(colorsSpace: space, colors: [color(0xF29A3E), color(0xC2416E)] as CFArray,
                               locations: [0, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - label, y: center.y - label, width: label * 2, height: label * 2))
ctx.clip()
ctx.drawLinearGradient(labelGradient, start: CGPoint(x: center.x - label, y: center.y + label),
                       end: CGPoint(x: center.x + label, y: center.y - label), options: [])
ctx.restoreGState()
ctx.setFillColor(color(0x121016))
ctx.fillEllipse(in: CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32))

// The drift: a winding dotted path from the bottom left, over the record, out to the top right.
let drift = CGMutablePath()
drift.move(to: CGPoint(x: 170, y: 250))
drift.addCurve(to: CGPoint(x: 330, y: 560), control1: CGPoint(x: 330, y: 260), control2: CGPoint(x: 180, y: 470))
drift.addCurve(to: CGPoint(x: 560, y: 690), control1: CGPoint(x: 460, y: 640), control2: CGPoint(x: 470, y: 760))
drift.addCurve(to: CGPoint(x: 800, y: 790), control1: CGPoint(x: 650, y: 620), control2: CGPoint(x: 700, y: 820))
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 14, color: color(0xFFFFFF, 0.55))
ctx.addPath(drift)
ctx.setStrokeColor(color(0xFFF4E6))
ctx.setLineWidth(26)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [0.1, 54])
ctx.strokePath()
ctx.restoreGState()
// Where the walk is now: a brighter point at its end.
ctx.setShadow(offset: .zero, blur: 24, color: color(0xFFFFFF, 0.8))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: 800 - 26, y: 790 - 26, width: 52, height: 52))
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
