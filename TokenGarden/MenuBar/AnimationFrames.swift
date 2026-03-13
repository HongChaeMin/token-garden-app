import AppKit

@MainActor
enum AnimationFrames {
    private static let size = NSSize(width: 18, height: 18)

    // seed → sprout → small plant → plant → flower (no tree)
    static let frameCount = 5

    private static let cachedFrames: [NSImage] = (0..<frameCount).map { renderFrame($0) }

    static func image(for index: Int) -> NSImage {
        cachedFrames[index % frameCount]
    }

    static func idleImage() -> NSImage {
        cachedFrames[2]
    }

    private static func renderFrame(_ frame: Int) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.controlTextColor.setStroke()
            NSColor.controlTextColor.setFill()

            switch frame {
            case 0: drawSeed(in: rect)
            case 1: drawSprout(in: rect)
            case 2: drawSmallPlant(in: rect)
            case 3: drawPlant(in: rect)
            case 4: drawFlower(in: rect)
            default: drawSeed(in: rect)
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - Frame drawings (all 18x18pt)

    // Frame 0: Seed
    private static func drawSeed(in rect: NSRect) {
        let cx = rect.midX
        let ground = NSBezierPath()
        ground.move(to: NSPoint(x: cx - 5, y: 4))
        ground.line(to: NSPoint(x: cx + 5, y: 4))
        ground.lineWidth = 1.5
        ground.stroke()
        let seed = NSBezierPath(ovalIn: NSRect(x: cx - 1.5, y: 4.5, width: 3, height: 3))
        seed.fill()
    }

    // Frame 1: Sprout
    private static func drawSprout(in rect: NSRect) {
        let cx = rect.midX
        let ground = NSBezierPath()
        ground.move(to: NSPoint(x: cx - 5, y: 4))
        ground.line(to: NSPoint(x: cx + 5, y: 4))
        ground.lineWidth = 1.5
        ground.stroke()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: cx, y: 4))
        stem.line(to: NSPoint(x: cx, y: 10))
        stem.lineWidth = 1.5
        stem.stroke()
        let leftLeaf = NSBezierPath()
        leftLeaf.move(to: NSPoint(x: cx, y: 9))
        leftLeaf.curve(to: NSPoint(x: cx - 4, y: 11),
                       controlPoint1: NSPoint(x: cx - 1, y: 11),
                       controlPoint2: NSPoint(x: cx - 3, y: 12))
        leftLeaf.lineWidth = 1.2
        leftLeaf.stroke()
        let rightLeaf = NSBezierPath()
        rightLeaf.move(to: NSPoint(x: cx, y: 9))
        rightLeaf.curve(to: NSPoint(x: cx + 4, y: 11),
                        controlPoint1: NSPoint(x: cx + 1, y: 11),
                        controlPoint2: NSPoint(x: cx + 3, y: 12))
        rightLeaf.lineWidth = 1.2
        rightLeaf.stroke()
    }

    // Frame 2: Small plant
    private static func drawSmallPlant(in rect: NSRect) {
        let cx = rect.midX
        let ground = NSBezierPath()
        ground.move(to: NSPoint(x: cx - 5, y: 3))
        ground.line(to: NSPoint(x: cx + 5, y: 3))
        ground.lineWidth = 1.5
        ground.stroke()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: cx, y: 3))
        stem.line(to: NSPoint(x: cx, y: 12))
        stem.lineWidth = 1.5
        stem.stroke()
        let leftLeaf = NSBezierPath()
        leftLeaf.move(to: NSPoint(x: cx, y: 8))
        leftLeaf.curve(to: NSPoint(x: cx - 5, y: 10),
                       controlPoint1: NSPoint(x: cx - 2, y: 10),
                       controlPoint2: NSPoint(x: cx - 4, y: 11))
        leftLeaf.lineWidth = 1.2
        leftLeaf.stroke()
        let rightLeaf = NSBezierPath()
        rightLeaf.move(to: NSPoint(x: cx, y: 10))
        rightLeaf.curve(to: NSPoint(x: cx + 5, y: 12),
                        controlPoint1: NSPoint(x: cx + 2, y: 12),
                        controlPoint2: NSPoint(x: cx + 4, y: 13))
        rightLeaf.lineWidth = 1.2
        rightLeaf.stroke()
        let bud = NSBezierPath(ovalIn: NSRect(x: cx - 1.5, y: 12, width: 3, height: 3))
        bud.fill()
    }

    // Frame 3: Plant with leaves
    private static func drawPlant(in rect: NSRect) {
        let cx = rect.midX
        let ground = NSBezierPath()
        ground.move(to: NSPoint(x: cx - 5, y: 3))
        ground.line(to: NSPoint(x: cx + 5, y: 3))
        ground.lineWidth = 1.5
        ground.stroke()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: cx, y: 3))
        stem.line(to: NSPoint(x: cx, y: 13))
        stem.lineWidth = 1.5
        stem.stroke()
        drawLeafPair(cx: cx, y: 6, spread: 5, size: 3)
        drawLeafPair(cx: cx, y: 10, spread: 4, size: 2.5)
        let top = NSBezierPath(ovalIn: NSRect(x: cx - 1.5, y: 13, width: 3, height: 2.5))
        top.fill()
    }

    // Frame 4: Flower
    private static func drawFlower(in rect: NSRect) {
        let cx = rect.midX
        let ground = NSBezierPath()
        ground.move(to: NSPoint(x: cx - 5, y: 3))
        ground.line(to: NSPoint(x: cx + 5, y: 3))
        ground.lineWidth = 1.5
        ground.stroke()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: cx, y: 3))
        stem.line(to: NSPoint(x: cx, y: 11))
        stem.lineWidth = 1.5
        stem.stroke()
        drawLeafPair(cx: cx, y: 6, spread: 4, size: 2)
        let petalR: CGFloat = 2.2
        let centerY: CGFloat = 13
        for i in 0..<5 {
            let angle = CGFloat(i) * (2 * .pi / 5) - .pi / 2
            let px = cx + cos(angle) * 3
            let py = centerY + sin(angle) * 3
            let petal = NSBezierPath(ovalIn: NSRect(x: px - petalR, y: py - petalR, width: petalR * 2, height: petalR * 2))
            petal.lineWidth = 1
            petal.stroke()
        }
        let center = NSBezierPath(ovalIn: NSRect(x: cx - 1.5, y: centerY - 1.5, width: 3, height: 3))
        center.fill()
    }

    // MARK: - Helpers

    private static func drawLeafPair(cx: CGFloat, y: CGFloat, spread: CGFloat, size: CGFloat) {
        let left = NSBezierPath()
        left.move(to: NSPoint(x: cx, y: y))
        left.curve(to: NSPoint(x: cx - spread, y: y + size * 0.5),
                   controlPoint1: NSPoint(x: cx - spread * 0.3, y: y + size),
                   controlPoint2: NSPoint(x: cx - spread * 0.7, y: y + size))
        left.lineWidth = 1.2
        left.stroke()

        let right = NSBezierPath()
        right.move(to: NSPoint(x: cx, y: y))
        right.curve(to: NSPoint(x: cx + spread, y: y + size * 0.5),
                    controlPoint1: NSPoint(x: cx + spread * 0.3, y: y + size),
                    controlPoint2: NSPoint(x: cx + spread * 0.7, y: y + size))
        right.lineWidth = 1.2
        right.stroke()
    }
}
