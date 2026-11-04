// Draws the 1024x1024 app icon: a white shield on a blue gradient with a speech bubble inside.
// Run from the repo root:  swift scripts/make_app_icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// No alpha channel: App Store icons must be opaque.
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Flip so y grows downward, easier to reason about.
ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, 1])! }

let top = rgb(0.29, 0.47, 1.0), bottom = rgb(0.13, 0.25, 0.80)
let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])

// Shield
let cx: CGFloat = 512, topY: CGFloat = 200, bottomY: CGFloat = 860, halfW: CGFloat = 300
let shield = CGMutablePath()
shield.move(to: CGPoint(x: cx, y: topY))
shield.addCurve(to: CGPoint(x: cx + halfW, y: topY + 90), control1: CGPoint(x: cx + 110, y: topY + 70), control2: CGPoint(x: cx + 220, y: topY + 90))
shield.addLine(to: CGPoint(x: cx + halfW, y: 480))
shield.addCurve(to: CGPoint(x: cx, y: bottomY), control1: CGPoint(x: cx + halfW, y: 680), control2: CGPoint(x: cx + 150, y: 800))
shield.addCurve(to: CGPoint(x: cx - halfW, y: 480), control1: CGPoint(x: cx - 150, y: 800), control2: CGPoint(x: cx - halfW, y: 680))
shield.addLine(to: CGPoint(x: cx - halfW, y: topY + 90))
shield.addCurve(to: CGPoint(x: cx, y: topY), control1: CGPoint(x: cx - 220, y: topY + 90), control2: CGPoint(x: cx - 110, y: topY + 70))
shield.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: rgb(0.05, 0.10, 0.35).copy(alpha: 0.45))
// A thick round-joined stroke softens the corners.
ctx.addPath(shield); ctx.setFillColor(rgb(1, 1, 1)); ctx.setStrokeColor(rgb(1, 1, 1))
ctx.setLineWidth(56); ctx.setLineJoin(.round)
// One transparency layer so the fill and stroke cast a single shadow.
ctx.beginTransparencyLayer(auxiliaryInfo: nil); ctx.drawPath(using: .fillStroke); ctx.endTransparencyLayer()
ctx.restoreGState()

// Speech bubble inside the shield, in the brand blue.
var bubble = CGMutablePath()
let bubbleRect = CGRect(x: cx - 180, y: 375, width: 360, height: 250)
bubble.addRoundedRect(in: bubbleRect, cornerWidth: 75, cornerHeight: 75)
ctx.addPath(bubble); ctx.setFillColor(rgb(0.20, 0.36, 0.95)); ctx.fillPath()
// The tail is filled on its own so its winding can't cut a hole where it overlaps the bubble.
bubble = CGMutablePath()
bubble.move(to: CGPoint(x: cx - 90, y: bubbleRect.maxY - 10))
bubble.addLine(to: CGPoint(x: cx - 120, y: bubbleRect.maxY + 70))
bubble.addLine(to: CGPoint(x: cx - 20, y: bubbleRect.maxY - 10))
bubble.closeSubpath()
ctx.addPath(bubble); ctx.setFillColor(rgb(0.20, 0.36, 0.95)); ctx.fillPath()

// White check mark, centered in the bubble with room around it.
ctx.setStrokeColor(rgb(1, 1, 1)); ctx.setLineWidth(38); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: cx - 68, y: 505)); ctx.addLine(to: CGPoint(x: cx - 20, y: 550)); ctx.addLine(to: CGPoint(x: cx + 70, y: 452))
ctx.strokePath()

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
