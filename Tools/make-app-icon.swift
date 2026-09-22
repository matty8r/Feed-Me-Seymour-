import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let C: CGFloat = 1024               // design canvas

/// Apple-style continuous-corner squircle.
func squircle(inset: CGFloat, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = (C - 2*inset)/2, cx = C/2, cy = C/2
    for i in 0...720 {
        let t = CGFloat(i)/720 * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2/n)
        let y = cy + a * (st < 0 ? -1 : 1) * pow(abs(st), 2/n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func load(_ path: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

/// `zoom` > 1 crops into the centre of the artwork so it survives small sizes.
func draw(_ ctx: CGContext, _ art: CGImage, rounded: Bool, zoom: CGFloat, focus: CGPoint) {
    ctx.saveGState()
    let inset: CGFloat = rounded ? 92 : 0
    ctx.addPath(squircle(inset: inset, n: rounded ? 5 : 1000))
    ctx.clip()

    let side = (C - 2*inset) * zoom
    // focus is in unit coords of the artwork (0,0 bottom-left .. 1,1 top-right)
    let x = inset + (C - 2*inset)/2 - side * focus.x
    let y = inset + (C - 2*inset)/2 - side * focus.y
    ctx.interpolationQuality = .high
    ctx.draw(art, in: CGRect(x: x, y: y, width: side, height: side))
    ctx.restoreGState()
}

func render(_ art: CGImage, size: Int, rounded: Bool, zoom: CGFloat, focus: CGPoint, to path: String) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(size)/C
    ctx.scaleBy(x: k, y: k)
    draw(ctx, art, rounded: rounded, zoom: zoom, focus: focus)
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let art   = load(CommandLine.arguments[1])
let out   = CommandLine.arguments[2]
let focus = CGPoint(x: 0.52, y: 0.56)      // the photographic trap at the collage's heart

// The collage is dense: shown whole it turns to mush below ~256px. So the frame
// tightens onto the central trap as the icon shrinks — full artwork where there
// are pixels to carry it, a legible plant where there aren't.
let macZoom: [Int: CGFloat] = [
    16: 2.50, 32: 2.50, 64: 2.10, 128: 1.75, 256: 1.35, 512: 1.05, 1024: 1.0,
]

for (n, z) in macZoom.sorted(by: { $0.key < $1.key }) {
    render(art, size: n, rounded: true, zoom: z, focus: focus, to: "\(out)/icon-mac-\(n).png")
}

// iOS ships a single 1024 and the system derives every other size from it, so it
// has to survive the home screen on its own: a middle crop, not the full collage.
render(art, size: 1024, rounded: false, zoom: 1.55, focus: focus, to: "\(out)/icon-ios-1024.png")
print("rendered")
