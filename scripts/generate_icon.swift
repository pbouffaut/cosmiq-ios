// Generates the 1024x1024 app icon: a dive profile line descending through
// an ocean gradient, with surface waves and rising bubbles.
// Run: swift scripts/generate_icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "App/Assets.xcassets/AppIcon.appiconset/icon1024.png"

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgba(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// CoreGraphics origin is bottom-left; the design below thinks in "screen"
// coordinates (y grows downward), so flip once.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// 1. Ocean gradient, light at the surface, abyss at the bottom.
let gradient = CGGradient(colorsSpace: colorSpace, colors: [
    rgba(0x0FB8CE), rgba(0x0A7EA3), rgba(0x0B4F6C), rgba(0x061B2C),
] as CFArray, locations: [0.0, 0.3, 0.65, 1.0])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 512, y: 0),
                       end: CGPoint(x: 512, y: 1024),
                       options: [])

// 2. Surface waves: three translucent sine bands near the top.
func wavePath(baseY: CGFloat, amplitude: CGFloat, wavelength: CGFloat, phase: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -10, y: baseY))
    var x: CGFloat = -10
    while x <= 1034 {
        let y = baseY + amplitude * sin((x / wavelength) * 2 * .pi + phase)
        path.addLine(to: CGPoint(x: x, y: y))
        x += 8
    }
    path.addLine(to: CGPoint(x: 1034, y: -10))
    path.addLine(to: CGPoint(x: -10, y: -10))
    path.closeSubpath()
    return path
}
for (index, alpha) in [0.20, 0.14, 0.10].enumerated() {
    ctx.setFillColor(rgba(0xB9FBF0, alpha))
    ctx.addPath(wavePath(baseY: CGFloat(120 + index * 46),
                         amplitude: CGFloat(16 + index * 6),
                         wavelength: CGFloat(300 + index * 80),
                         phase: CGFloat(index) * 1.7))
    ctx.fillPath()
}

// 3. The dive profile: descend, cruise, ascend with a safety stop.
let profilePoints: [CGPoint] = [
    CGPoint(x: 96, y: 236),
    CGPoint(x: 250, y: 700),
    CGPoint(x: 400, y: 762),
    CGPoint(x: 560, y: 740),
    CGPoint(x: 700, y: 470),
    CGPoint(x: 800, y: 470),  // safety stop
    CGPoint(x: 928, y: 240),
]
let profile = CGMutablePath()
profile.move(to: profilePoints[0])
for point in profilePoints.dropFirst() {
    profile.addLine(to: point)
}

// Soft glow pass, then the crisp line.
for (width, alpha) in [(CGFloat(64), 0.18), (CGFloat(36), 0.28), (CGFloat(18), 1.0)] {
    ctx.setStrokeColor(rgba(0xEAFDF8, alpha))
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(profile)
    ctx.strokePath()
}

// Max-depth marker dot.
ctx.setFillColor(rgba(0x7DF9E4))
ctx.fillEllipse(in: CGRect(x: 400 - 26, y: 762 - 26, width: 52, height: 52))
ctx.setFillColor(rgba(0x0B4F6C))
ctx.fillEllipse(in: CGRect(x: 400 - 13, y: 762 - 13, width: 26, height: 26))

// 4. Bubbles rising from the diver's deepest point.
let bubbles: [(x: CGFloat, y: CGFloat, r: CGFloat, a: CGFloat)] = [
    (452, 640, 14, 0.5), (486, 540, 20, 0.42), (452, 430, 27, 0.34),
    (500, 316, 35, 0.26), (452, 190, 44, 0.18),
]
for bubble in bubbles {
    ctx.setStrokeColor(rgba(0xEAFDF8, bubble.a))
    ctx.setLineWidth(bubble.r * 0.28)
    ctx.strokeEllipse(in: CGRect(x: bubble.x - bubble.r, y: bubble.y - bubble.r,
                                 width: bubble.r * 2, height: bubble.r * 2))
}

// Write the PNG.
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: outputPath) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Failed to write \(outputPath)")
}
print("Wrote \(outputPath)")
