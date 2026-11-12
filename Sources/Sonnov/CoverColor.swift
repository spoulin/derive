import AppKit

/// Picks the color a cover is mostly made of, for tinting the player.
enum CoverColor {
    /// Neutral tint used before the first cover and for black-and-white covers.
    static let neutral = NSColor(white: 0.16, alpha: 1)

    /// The main vivid color of the image, darkened enough for light text on top.
    /// Covers with almost no vivid color give a dark gray with a hint of their average hue.
    static func tint(of image: NSImage) -> NSColor {
        let size = 24
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
        else { return neutral }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Group vivid pixels by hue, weighted by how vivid they are.
        let bucketCount = 12
        var weights = [CGFloat](repeating: 0, count: bucketCount)
        var sums = [(r: CGFloat, g: CGFloat, b: CGFloat)](repeating: (0, 0, 0), count: bucketCount)
        var average = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
        let count = size * size
        for i in 0..<count {
            let r = CGFloat(pixels[i * 4]) / 255
            let g = CGFloat(pixels[i * 4 + 1]) / 255
            let b = CGFloat(pixels[i * 4 + 2]) / 255
            average.r += r; average.g += g; average.b += b
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
            NSColor(red: r, green: g, blue: b, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
            guard saturation > 0.25, brightness > 0.2 else { continue }
            let bucket = min(Int(hue * CGFloat(bucketCount)), bucketCount - 1)
            let weight = saturation * brightness
            weights[bucket] += weight
            sums[bucket].r += r * weight; sums[bucket].g += g * weight; sums[bucket].b += b * weight
        }

        let best = weights.indices.max { weights[$0] < weights[$1] }!
        // Less than about 8% of the cover is vivid: keep the player neutral.
        guard weights[best] > CGFloat(count) * 0.08 * 0.4 else {
            let n = CGFloat(count)
            return darkened(NSColor(red: average.r / n, green: average.g / n, blue: average.b / n, alpha: 1),
                            maxSaturation: 0.15)
        }
        let w = weights[best]
        return darkened(NSColor(red: sums[best].r / w, green: sums[best].g / w, blue: sums[best].b / w, alpha: 1),
                        maxSaturation: 0.65)
    }

    private static func darkened(_ color: NSColor, maxSaturation: CGFloat) -> NSColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return NSColor(hue: hue, saturation: min(saturation, maxSaturation),
                       brightness: min(max(brightness * 0.45, 0.14), 0.3), alpha: 1)
    }
}
