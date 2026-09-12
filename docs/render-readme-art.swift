// Renders the README's sprite artwork straight from the atlas, so it stays
// honest to what the app draws and carries no desktop background with it.
//
// The two balloon pictures, hero.png and asking.png, are NOT made here. They
// come out of the app itself via `ClaudePet --snapshot`, because a second
// implementation of the balloon is a second thing to keep in step, and it fell
// out of step the first time the design changed. See the README.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let atlasPath = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let cw = 192, ch = 208

let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: atlasPath) as CFURL, nil)!
let atlas = CGImageSourceCreateImageAtIndex(src, 0, nil)!

func cell(_ row: Int, _ col: Int) -> CGImage {
    atlas.cropping(to: CGRect(x: col*cw, y: row*ch, width: cw, height: ch))!
}

func write(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: "\(outDir)/\(name)")
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, image, nil)
    CGImageDestinationFinalize(d)
    print("  \(name)")
}

/// One sprite on transparency, scaled. Used for the states table.
func sprite(_ row: Int, _ col: Int, scale: CGFloat, name: String) {
    let w = Int(CGFloat(cw) * scale), h = Int(CGFloat(ch) * scale)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(cell(row, col), in: CGRect(x: 0, y: 0, width: w, height: h))
    write(ctx.makeImage()!, name)
}

print("writing:")
sprite(0, 6, scale: 0.85, name: "idle.png")
sprite(7, 2, scale: 0.85, name: "working.png")
sprite(8, 1, scale: 0.85, name: "inspecting.png")
sprite(6, 0, scale: 0.85, name: "waiting.png")
sprite(5, 1, scale: 0.85, name: "failed.png")
sprite(11, 5, scale: 0.85, name: "asleep.png")
sprite(4, 4, scale: 0.85, name: "jumping.png")
