// Renders the README artwork straight from the atlas, so it stays honest to
// what the app actually draws and carries no desktop background with it.
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

/// The hero: Mikkel with a speech bubble, drawn the way the app draws it.
func hero(row: Int, col: Int, text: String, timer: String?, accent: NSColor, name: String) {
    let scale: CGFloat = 1.4
    let spriteW = CGFloat(cw) * scale, spriteH = CGFloat(ch) * scale
    let font = NSFont.systemFont(ofSize: 15, weight: .medium)
    let timerFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

    let textW = (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    let timerW = timer == nil ? 0 : ((timer! as NSString)
        .size(withAttributes: [.font: timerFont]).width.rounded(.up) + 14)
    let pad: CGFloat = 16
    let boxW = textW + timerW + pad * 2, boxH: CGFloat = 38
    let tailH: CGFloat = 9, tailW: CGFloat = 18

    let w = Int(max(boxW, spriteW) + 8), h = Int(spriteH + tailH + boxH + 8)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high

    let spriteX = (CGFloat(w) - spriteW) / 2
    ctx.draw(cell(row, col), in: CGRect(x: spriteX, y: 0, width: spriteW, height: spriteH))

    let boxX = (CGFloat(w) - boxW) / 2, boxY = spriteH + tailH
    let box = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)
    let path = CGMutablePath()
    path.addRoundedRect(in: box, cornerWidth: 13, cornerHeight: 13)
    let tip = CGFloat(w) / 2
    path.move(to: CGPoint(x: tip - tailW/2, y: boxY + 1))
    path.addLine(to: CGPoint(x: tip, y: boxY - tailH))
    path.addLine(to: CGPoint(x: tip + tailW/2, y: boxY + 1))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.18, alpha: 0.96).cgColor)
    ctx.setStrokeColor(accent.cgColor)
    ctx.setLineWidth(1.5)
    ctx.drawPath(using: .fillStroke)

    func draw(_ s: String, _ f: NSFont, _ colour: NSColor, x: CGFloat) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: s, attributes: [.font: f, .foregroundColor: colour]))
        ctx.textPosition = CGPoint(x: x, y: boxY + 13)
        CTLineDraw(line, ctx)
    }
    draw(text, font, NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1), x: boxX + pad)
    if let timer {
        draw(timer, timerFont, NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.25, alpha: 0.9),
             x: boxX + boxW - pad - timerW + 14)
    }
    write(ctx.makeImage()!, name)
}

print("writing:")
hero(row: 7, col: 2, text: "Let me run the test suite", timer: "0:14",
     accent: NSColor(calibratedRed: 0.55, green: 0.68, blue: 0.92, alpha: 0.6), name: "hero.png")
hero(row: 6, col: 0, text: "Claude needs your permission to use Bash", timer: nil,
     accent: NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.20, alpha: 0.95), name: "asking.png")

sprite(0, 6, scale: 0.85, name: "idle.png")
sprite(7, 2, scale: 0.85, name: "working.png")
sprite(8, 1, scale: 0.85, name: "inspecting.png")
sprite(6, 0, scale: 0.85, name: "waiting.png")
sprite(5, 1, scale: 0.85, name: "failed.png")
sprite(11, 5, scale: 0.85, name: "asleep.png")
sprite(4, 4, scale: 0.85, name: "jumping.png")
