// Draws the app icon (a light-blue shield holding a white speech bubble on navy) in its light, dark and
// tinted variants, plus the same mark as a vector PDF for use inside the app.
// Run from the repo root:  swift scripts/make_app_icon.swift App/Assets.xcassets
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let assets = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

let navyTop = rgb(0.10, 0.17, 0.44), navyBottom = rgb(0.06, 0.10, 0.29)
let shieldBlue = rgb(0.30, 0.49, 1.0)
let white = rgb(1, 1, 1)

/// Draws the mark in a 100x100 space with y growing downward. The shield spans about x 17...83, y 15...87.
func drawMark(_ ctx: CGContext, shield: CGColor, bubble: CGColor) {
    let s = CGMutablePath()
    s.move(to: CGPoint(x: 50, y: 16))
    s.addCurve(to: CGPoint(x: 79, y: 24), control1: CGPoint(x: 58, y: 21), control2: CGPoint(x: 68, y: 24))
    s.addQuadCurve(to: CGPoint(x: 82, y: 27), control: CGPoint(x: 82, y: 24))
    s.addLine(to: CGPoint(x: 82, y: 48))
    s.addCurve(to: CGPoint(x: 50, y: 86), control1: CGPoint(x: 82, y: 67), control2: CGPoint(x: 67, y: 78))
    s.addCurve(to: CGPoint(x: 18, y: 48), control1: CGPoint(x: 33, y: 78), control2: CGPoint(x: 18, y: 67))
    s.addLine(to: CGPoint(x: 18, y: 27))
    s.addQuadCurve(to: CGPoint(x: 21, y: 24), control: CGPoint(x: 18, y: 24))
    s.addCurve(to: CGPoint(x: 50, y: 16), control1: CGPoint(x: 32, y: 24), control2: CGPoint(x: 42, y: 21))
    s.closeSubpath()

    let b = CGMutablePath()
    b.move(to: CGPoint(x: 38, y: 35))
    b.addLine(to: CGPoint(x: 62, y: 35))
    b.addQuadCurve(to: CGPoint(x: 69, y: 42), control: CGPoint(x: 69, y: 35))
    b.addLine(to: CGPoint(x: 69, y: 54))
    b.addQuadCurve(to: CGPoint(x: 62, y: 61), control: CGPoint(x: 69, y: 61))
    b.addLine(to: CGPoint(x: 49, y: 61))
    b.addLine(to: CGPoint(x: 40, y: 70))
    b.addLine(to: CGPoint(x: 41, y: 61))
    b.addLine(to: CGPoint(x: 38, y: 61))
    b.addQuadCurve(to: CGPoint(x: 31, y: 54), control: CGPoint(x: 31, y: 61))
    b.addLine(to: CGPoint(x: 31, y: 42))
    b.addQuadCurve(to: CGPoint(x: 38, y: 35), control: CGPoint(x: 31, y: 35))
    b.closeSubpath()

    // Round-joined strokes soften the shield's top point and the bubble's tail.
    ctx.setLineJoin(.round)
    for (path, color, width) in [(s, shield, 3.0), (b, bubble, 1.5)] {
        ctx.addPath(path); ctx.setFillColor(color); ctx.setStrokeColor(color); ctx.setLineWidth(width)
        ctx.drawPath(using: .fillStroke)
    }
}

func writePNG(_ name: String, opaque: Bool, draw: (CGContext) -> Void) {
    let size = 1024
    // The light icon has no alpha channel: App Store icons must be opaque. Dark and tinted ones are transparent
    // so iOS can put its own background behind them.
    let info = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: info.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 10.24, y: -10.24)
    draw(ctx)
    let url = assets.appendingPathComponent("AppIcon.appiconset/\(name)")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

writePNG("AppIcon.png", opaque: true) { ctx in
    let gradient = CGGradient(colorsSpace: space, colors: [navyTop, navyBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 100), options: [])
    drawMark(ctx, shield: shieldBlue, bubble: white)
}
writePNG("AppIcon-Dark.png", opaque: false) { drawMark($0, shield: shieldBlue, bubble: white) }
// iOS tints by brightness, so the bubble stays the brightest part.
writePNG("AppIcon-Tinted.png", opaque: false) { drawMark($0, shield: rgb(0.55, 0.55, 0.55), bubble: white) }

// The in-app mark: the shield cropped to its bounds, as a PDF so it stays sharp at any size.
var box = CGRect(x: 0, y: 0, width: 70, height: 76)
let pdfURL = assets.appendingPathComponent("BrandMark.imageset/BrandMark.pdf")
let pdf = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
pdf.beginPDFPage(nil)
pdf.translateBy(x: -15, y: 76 + 13); pdf.scaleBy(x: 1, y: -1)
drawMark(pdf, shield: shieldBlue, bubble: white)
pdf.endPDFPage()
pdf.closePDF()
