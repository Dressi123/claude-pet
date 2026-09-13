import CoreGraphics

/// Alpha copies of images, so a click can be tested against what was drawn
/// rather than the box it was drawn in. Kept out of `PetView` so the mapping
/// from a point to a pixel is stated once, in one place, rather than inline in
/// whatever happens to need it.
enum AlphaMask {
    private static var cache: [ObjectIdentifier: [UInt8]] = [:]

    /// Deliberately not the blink checker's 40. That script asks how far a
    /// silhouette moved, where a generous cut suppresses anti-aliasing noise.
    /// Here the anti-aliased rim is exactly what you reach for when grabbing an
    /// ear or the tip of his tail, so it has to count.
    static let threshold: UInt8 = 10

    /// The alpha channel of an image, one byte per pixel, built on first use
    /// and kept. Images come from a cache of their own, so a given cell is the
    /// same object every time and its mask is built once rather than once per
    /// click.
    ///
    /// Drawn into a context rather than read from `dataProvider`, which would
    /// be cheaper and wrong: a cell is a crop of a larger sheet, and a crop can
    /// hand back the whole sheet's bytes with the crop carried as metadata.
    static func of(_ image: CGImage) -> [UInt8] {
        let key = ObjectIdentifier(image)
        if let cached = cache[key] { return cached }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var mask = [UInt8](repeating: 0, count: width * height)
        for i in mask.indices { mask[i] = pixels[i * 4 + 3] }
        cache[key] = mask
        return mask
    }

    /// Whether a point inside `frame` lands on the image rather than on the
    /// transparent margin around it. The image is assumed to fill `frame`,
    /// which it does for the pet: a cell is drawn with `resizeAspect` into a
    /// box of its own proportions, so there is no letterboxing to allow for.
    ///
    /// The y axis flips here: a view's grows upwards and a mask's downwards.
    static func hits(_ image: CGImage, point: CGPoint, in frame: CGRect) -> Bool {
        guard frame.contains(point), frame.width > 0, frame.height > 0 else { return false }
        let across = (point.x - frame.minX) / frame.width
        let down = 1 - (point.y - frame.minY) / frame.height
        let x = min(image.width - 1, max(0, Int(across * CGFloat(image.width))))
        let y = min(image.height - 1, max(0, Int(down * CGFloat(image.height))))
        return of(image)[y * image.width + x] > threshold
    }
}
