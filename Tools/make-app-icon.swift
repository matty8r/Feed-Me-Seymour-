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
    // focus is in unit coords of the artwork (0,0 bottom-left .. 1,1 top-right).
    // Clamp it so the crop window can never run off the edge of the art: at
    // zoom 1 that forces it back to centre and the whole piece shows, which is
    // what the large sizes want.
    let half = 0.5 / zoom
    let fx = min(max(focus.x, half), 1 - half)
    let fy = min(max(focus.y, half), 1 - half)
    let x = inset + (C - 2*inset)/2 - side * fx
    let y = inset + (C - 2*inset)/2 - side * fy
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
let focus = CGPoint(x: 0.34, y: 0.62)      // the big trap at upper left

// The whole piece wherever there are pixels to carry it — 256 and up show the
// artwork as painted. Below that the collage turns to confetti, so the frame
// tightens onto the big trap at upper left and the icon stays a plant.
let macZoom: [Int: CGFloat] = [
    16: 2.80, 32: 2.60, 64: 2.20, 128: 1.70, 256: 1.0, 512: 1.0, 1024: 1.0,
]

for (n, z) in macZoom.sorted(by: { $0.key < $1.key }) {
    render(art, size: n, rounded: true, zoom: z, focus: focus, to: "\(out)/icon-mac-\(n).png")
}

// iOS ships a single 1024 and the system derives every other size from it, so
// this one asset is both the high-resolution icon and the home screen one. Shown
// whole, as here, the home screen icon is dense — raise this if that matters
// more than the artwork surviving intact at full size.
render(art, size: 1024, rounded: false, zoom: 1.0, focus: focus, to: "\(out)/icon-ios-1024.png")
print("rendered")
