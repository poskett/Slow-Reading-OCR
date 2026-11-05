// Declaration: Code generated using Anthropic Claude (Sonnet 5.5)
import AppKit
import CoreGraphics

let outputFolder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

let parchmentTop = color(0.98, 0.955, 0.895)
let parchmentMiddle = color(0.93, 0.89, 0.80)
let parchmentBottom = color(0.86, 0.80, 0.68)
let cream = color(0.97, 0.94, 0.86)
let shellLight = color(0.91, 0.39, 0.28)
let shellRed = color(0.77, 0.22, 0.15)
let shellDeep = color(0.46, 0.10, 0.07)
let bodyLight = color(0.34, 0.28, 0.23)
let bodyDark = color(0.14, 0.11, 0.09)
let farLight = color(0.17, 0.14, 0.11)
let farDark = color(0.07, 0.06, 0.05)

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

let tortoiseOrigin = CGPoint(x: 490, y: 420)
let tortoiseScale: CGFloat = 0.95
let groundY: CGFloat = 420 - 84 * 0.95

var seed: UInt64 = 7

func random() -> CGFloat {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
}

func roundedRect(_ context: CGContext, _ rect: CGRect, _ radius: CGFloat) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
}

func fillWithGradient(_ context: CGContext, top: CGColor, bottom: CGColor, yTop: CGFloat, yBottom: CGFloat, path: () -> Void) {
    context.saveGState()
    path()
    context.clip()
    context.drawLinearGradient(
        gradient([top, bottom], [0, 1]), start: CGPoint(x: 0, y: yTop), end: CGPoint(x: 0, y: yBottom),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func drawTile(_ context: CGContext) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0.12, 0.08, 0.04, 0.3))
    context.addPath(tilePath)
    context.setFillColor(parchmentBottom)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.drawLinearGradient(
        gradient([parchmentTop, parchmentMiddle, parchmentBottom], [0, 0.5, 1]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.drawRadialGradient(
        gradient([color(1, 1, 0.97, 0.45), color(1, 1, 0.97, 0)], [0, 1]),
        startCenter: CGPoint(x: 360, y: 840), startRadius: 0,
        endCenter: CGPoint(x: 360, y: 840), endRadius: 560, options: [])
    context.drawRadialGradient(
        gradient([color(0.35, 0.22, 0.08, 0), color(0.35, 0.22, 0.08, 0.16)], [0, 1]),
        startCenter: CGPoint(x: 512, y: 512), startRadius: 330,
        endCenter: CGPoint(x: 512, y: 512), endRadius: 620, options: [.drawsAfterEndLocation])
    seed = 7
    for _ in 0..<7000 {
        let x = 100 + random() * 824
        let y = 100 + random() * 824
        let size = 1.2 + random() * 2.2
        let dark = random() > 0.45
        context.setFillColor(dark ? color(0.36, 0.26, 0.14, 0.035 + random() * 0.035) : color(1, 1, 0.96, 0.05 + random() * 0.05))
        context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
    }
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: 4, dy: 4), cornerWidth: 181, cornerHeight: 181, transform: nil))
    context.clip(using: .evenOdd)
    context.drawLinearGradient(
        gradient([color(1, 1, 1, 0.85), color(1, 1, 1, 0.1), color(0.3, 0.2, 0.08, 0.22)], [0, 0.55, 1]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.addPath(tilePath)
    context.setStrokeColor(color(0.3, 0.2, 0.08, 0.2))
    context.setLineWidth(2)
    context.strokePath()
    context.restoreGState()
}

func drawTextLines(_ context: CGContext) {
    let widths: [CGFloat] = [560, 620, 590, 620, 470, 620, 600, 540, 620, 380, 620, 590]
    seed = 21
    for k in -2...8 {
        let y = groundY + CGFloat(k) * 62
        let width = k == 0 ? 624 : widths[(k + 2) % widths.count]
        let alpha = max(0.08, 0.26 - abs(CGFloat(k) - 1) * 0.02)
        var x: CGFloat = 206
        let end = 206 + width
        while x < end {
            var segment = min(70 + random() * 170, end - x)
            if end - x - segment < 60 {
                segment = end - x
            }
            let rect = CGRect(x: x, y: y - 7, width: segment, height: 14)
            context.setFillColor(color(1, 1, 0.95, 0.55))
            roundedRect(context, rect.offsetBy(dx: 0, dy: -2.5), 7)
            context.fillPath()
            context.setFillColor(color(0.2, 0.15, 0.1, alpha))
            roundedRect(context, rect, 7)
            context.fillPath()
            x += segment + 11
        }
    }
}

func shellPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -210, y: 0))
    path.addCurve(to: CGPoint(x: 210, y: 0), control1: CGPoint(x: -215, y: 345), control2: CGPoint(x: 215, y: 345))
    path.closeSubpath()
    return path
}

func drawScutes(_ context: CGContext, strokeColor: CGColor, width: CGFloat, offset: CGSize, facets: Bool) {
    context.saveGState()
    context.translateBy(x: offset.width, y: offset.height)
    context.scaleBy(x: 1, y: 1.35)
    let hexagon = [
        CGPoint(x: 0, y: 150), CGPoint(x: 50, y: 120), CGPoint(x: 50, y: 62),
        CGPoint(x: 0, y: 34), CGPoint(x: -50, y: 62), CGPoint(x: -50, y: 120),
    ]
    if facets {
        context.move(to: hexagon[0])
        for point in hexagon.dropFirst() {
            context.addLine(to: point)
        }
        context.closePath()
        context.setFillColor(color(1, 0.8, 0.7, 0.09))
        context.fillPath()
    }
    context.setStrokeColor(strokeColor)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: hexagon[0])
    for point in hexagon.dropFirst() {
        context.addLine(to: point)
    }
    context.closePath()
    context.move(to: hexagon[1]); context.addLine(to: CGPoint(x: 130, y: 150))
    context.move(to: hexagon[2]); context.addLine(to: CGPoint(x: 140, y: 20))
    context.move(to: hexagon[5]); context.addLine(to: CGPoint(x: -130, y: 150))
    context.move(to: hexagon[4]); context.addLine(to: CGPoint(x: -140, y: 20))
    context.move(to: hexagon[3]); context.addLine(to: CGPoint(x: 0, y: -10))
    context.strokePath()
    context.restoreGState()
}

func drawTortoise(_ context: CGContext) {
    context.saveGState()
    context.translateBy(x: 505, y: groundY + 6)
    context.scaleBy(x: 1, y: 0.1)
    context.drawRadialGradient(
        gradient([color(0.1, 0.06, 0.03, 0.5), color(0.1, 0.06, 0.03, 0)], [0, 1]),
        startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 330, options: [])
    context.restoreGState()

    context.saveGState()
    context.translateBy(x: tortoiseOrigin.x, y: tortoiseOrigin.y)
    context.scaleBy(x: tortoiseScale, y: tortoiseScale)

    fillWithGradient(context, top: farLight, bottom: farDark, yTop: 14, yBottom: -70) {
        roundedRect(context, CGRect(x: 30, y: -70, width: 66, height: 84), 28)
        roundedRect(context, CGRect(x: -120, y: -70, width: 66, height: 84), 28)
    }

    func bodyParts() {
        roundedRect(context, CGRect(x: 96, y: -84, width: 88, height: 96), 36)
        roundedRect(context, CGRect(x: -196, y: -84, width: 88, height: 96), 36)
        roundedRect(context, CGRect(x: 176, y: -8, width: 86, height: 70), 32)
        context.addEllipse(in: CGRect(x: 224, y: -2, width: 104, height: 84))
        context.move(to: CGPoint(x: -200, y: 14))
        context.addLine(to: CGPoint(x: -268, y: -8))
        context.addLine(to: CGPoint(x: -200, y: -26))
        context.closePath()
    }
    fillWithGradient(context, top: bodyLight, bottom: bodyDark, yTop: 82, yBottom: -84, path: bodyParts)

    context.saveGState()
    context.addEllipse(in: CGRect(x: 224, y: -2, width: 104, height: 84))
    context.clip()
    context.drawRadialGradient(
        gradient([color(1, 1, 1, 0.22), color(1, 1, 1, 0)], [0, 1]),
        startCenter: CGPoint(x: 268, y: 62), startRadius: 0,
        endCenter: CGPoint(x: 268, y: 62), endRadius: 52, options: [])
    context.restoreGState()

    context.setFillColor(color(0.06, 0.05, 0.04))
    context.fillEllipse(in: CGRect(x: 292, y: 50, width: 15, height: 15))
    context.setFillColor(color(1, 1, 1, 0.85))
    context.fillEllipse(in: CGRect(x: 299, y: 57, width: 4.5, height: 4.5))

    fillWithGradient(context, top: color(0.24, 0.19, 0.15), bottom: color(0.06, 0.05, 0.04), yTop: 20, yBottom: -30) {
        roundedRect(context, CGRect(x: -228, y: -30, width: 456, height: 50), 25)
    }

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0, 0, 0, 0.4))
    context.addPath(shellPath())
    context.setFillColor(shellRed)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shellPath())
    context.clip()
    context.drawRadialGradient(
        gradient([shellLight, shellRed, shellDeep], [0, 0.5, 1]),
        startCenter: CGPoint(x: -90, y: 200), startRadius: 0,
        endCenter: CGPoint(x: -20, y: 110), endRadius: 360, options: [.drawsAfterEndLocation])
    context.drawLinearGradient(
        gradient([color(0.25, 0.04, 0.02, 0), color(0.25, 0.04, 0.02, 0.35)], [0, 1]),
        start: CGPoint(x: 0, y: 90), end: CGPoint(x: 0, y: 0), options: [.drawsAfterEndLocation])

    drawScutes(context, strokeColor: color(0.22, 0.03, 0.02, 0.5), width: 11, offset: CGSize(width: 2, height: -5), facets: false)
    drawScutes(context, strokeColor: cream, width: 9, offset: .zero, facets: true)
    drawScutes(context, strokeColor: color(1, 1, 1, 0.35), width: 3, offset: CGSize(width: -1, height: 2.5), facets: false)

    context.drawLinearGradient(
        gradient([color(1, 0.95, 0.9, 0.28), color(1, 0.95, 0.9, 0)], [0, 1]),
        start: CGPoint(x: 0, y: 262), end: CGPoint(x: 0, y: 150), options: [])
    context.addPath(shellPath())
    context.setStrokeColor(color(0.25, 0.03, 0.02, 0.45))
    context.setLineWidth(8)
    context.strokePath()
    context.restoreGState()

    context.restoreGState()
}

func drawRibbon(_ context: CGContext) {
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 700, y: 930))
    path.addLine(to: CGPoint(x: 770, y: 930))
    path.addLine(to: CGPoint(x: 770, y: 740))
    path.addLine(to: CGPoint(x: 735, y: 772))
    path.addLine(to: CGPoint(x: 700, y: 740))
    path.closeSubpath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 3, height: -6), blur: 10, color: color(0.15, 0.05, 0.02, 0.38))
    context.addPath(path)
    context.setFillColor(shellRed)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        gradient([shellLight, shellRed, shellDeep], [0, 0.5, 1]),
        start: CGPoint(x: 700, y: 900), end: CGPoint(x: 772, y: 800), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.drawLinearGradient(
        gradient([color(0.25, 0.04, 0.02, 0), color(0.25, 0.04, 0.02, 0.4)], [0, 1]),
        start: CGPoint(x: 0, y: 800), end: CGPoint(x: 0, y: 740), options: [.drawsAfterEndLocation])
    context.setStrokeColor(color(1, 0.85, 0.8, 0.5))
    context.setLineWidth(3)
    context.move(to: CGPoint(x: 703, y: 930))
    context.addLine(to: CGPoint(x: 703, y: 745))
    context.strokePath()
    context.setStrokeColor(color(0.3, 0.04, 0.02, 0.35))
    context.setLineWidth(3)
    context.move(to: CGPoint(x: 767, y: 930))
    context.addLine(to: CGPoint(x: 767, y: 745))
    context.strokePath()
    context.restoreGState()
    context.restoreGState()
}

func drawIcon(size: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawTile(context)
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    drawTextLines(context)
    context.restoreGState()
    drawTortoise(context)
    drawRibbon(context)
    return context.makeImage()!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes {
    let bitmap = NSBitmapImageRep(cgImage: drawIcon(size: size))
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: outputFolder.appendingPathComponent(name + ".png"))
}
