import QuietTraceKit
import UIKit

/// The child's lines. Finished lines are painted once into a bitmap; only the line being drawn
/// is redrawn as it grows, and only where it changed, so the pencil stays quick at 120–240 Hz.
final class InkView: UIView {
    weak var tracer: Tracer? {
        didSet { live.tracer = tracer }
    }

    var colour: UIColor = .black {
        didSet { live.colour = colour }
    }

    /// Box units → view points.
    private(set) var boxTransform: CGAffineTransform = .identity

    private let frozen = UIView()
    private let live = LiveInkView()
    private var bitmap: CGContext?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for v in [frozen, live] {
            v.isUserInteractionEnabled = false
            v.backgroundColor = .clear
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        frozen.frame = bounds
        live.frame = bounds
    }

    func setBoxTransform(_ transform: CGAffineTransform) {
        boxTransform = transform
        live.boxTransform = transform
    }

    /// Repaints every finished line from scratch (after a size or colour change).
    func rebuild() {
        bitmap = makeBitmap()
        if let ctx = bitmap, let tracer {
            for line in tracer.finishedLines { InkRenderer.drawLine(line.points, in: ctx) }
        }
        publish()
        live.forgetAll()
    }

    func clear() {
        bitmap = nil
        frozen.layer.contents = nil
        live.forgetAll()
    }

    /// The live line gained points from `index` on.
    func liveExtended(from index: Int) { live.extended(from: index) }

    /// The live line was replaced by a new one (a palm's line was dropped).
    func liveRestarted() { live.restarted() }

    func setPredicted(_ points: [InkPoint]) { live.setPredicted(points) }

    /// The live line ended: paint it into the bitmap for good.
    func commit(_ line: InkLine) {
        if bitmap == nil { bitmap = makeBitmap() }
        if let ctx = bitmap { InkRenderer.drawLine(line.points, in: ctx) }
        publish()
        live.lineEnded()
    }

    private func publish() {
        frozen.layer.contents = bitmap?.makeImage()
    }

    private func makeBitmap() -> CGContext? {
        let scale = max(1, traitCollection.displayScale)
        let width = Int((bounds.width * scale).rounded(.up)), height = Int((bounds.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Top-left origin in points, like UIKit, then box units.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.concatenate(boxTransform)
        InkRenderer.prepare(ctx, colour: colour)
        frozen.layer.contentsScale = scale
        return ctx
    }
}

/// Draws the line being drawn, plus a short predicted extension to hide touch latency.
private final class LiveInkView: UIView {
    weak var tracer: Tracer?
    var colour: UIColor = .black
    var boxTransform: CGAffineTransform = .identity

    private var predicted: [InkPoint] = []
    /// View-space areas drawn so far, so they can be cleared again.
    private var liveRect = CGRect.null
    private var predictedRect = CGRect.null

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        clearsContextBeforeDrawing = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func extended(from index: Int) {
        guard let points = tracer?.liveLine?.points, index < points.count else { return }
        // Piece i reaches back to the midpoint of points i-2 and i-1, and the tail of i-1 is redrawn too.
        var dirty = rect(for: points[max(0, index - 2)...])
        dirty = dirty.union(predictedRect)
        predicted = []
        predictedRect = .null
        invalidate(dirty)
    }

    func restarted() {
        invalidate(liveRect.union(predictedRect))
        liveRect = .null
        predicted = []
        predictedRect = .null
        extended(from: 0)
    }

    func setPredicted(_ points: [InkPoint]) {
        guard let last = tracer?.liveLine?.points.last else { return }
        let old = predictedRect
        predicted = points
        predictedRect = points.isEmpty ? .null : rect(for: [last] + points)
        invalidate(old.union(predictedRect))
    }

    func lineEnded() {
        let dirty = liveRect.union(predictedRect)
        liveRect = .null
        predicted = []
        predictedRect = .null
        if !dirty.isNull { setNeedsDisplay(dirty) }
    }

    func forgetAll() {
        liveRect = .null
        predicted = []
        predictedRect = .null
        setNeedsDisplay()
    }

    private func invalidate(_ r: CGRect) {
        guard !r.isNull else { return }
        liveRect = liveRect.union(r)
        setNeedsDisplay(r)
    }

    /// View-space bounds of some points' ink, padded for line width and anti-aliasing.
    private func rect<C: Collection>(for points: C) -> CGRect where C.Element == InkPoint {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        var widest = 0.0
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            widest = max(widest, p.width)
        }
        guard minX <= maxX else { return .null }
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -widest, dy: -widest)
        return box.applying(boxTransform).insetBy(dx: -2, dy: -2)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let points = tracer?.liveLine?.points, !points.isEmpty else { return }
        ctx.concatenate(boxTransform)
        InkRenderer.prepare(ctx, colour: colour)
        let dirty = rect.applying(boxTransform.inverted())
        for i in points.indices {
            let lo = max(0, i - 2)
            if pieceBounds(points, lo...i).intersects(dirty) { InkRenderer.drawPiece(points, i, in: ctx) }
        }
        InkRenderer.drawTail(points, in: ctx)
        if let last = points.last, !predicted.isEmpty {
            ctx.setLineWidth(CGFloat(last.width))
            ctx.beginPath()
            ctx.move(to: last.point.cg)
            for p in predicted { ctx.addLine(to: p.point.cg) }
            ctx.strokePath()
        }
    }

    private func pieceBounds(_ points: [InkPoint], _ range: ClosedRange<Int>) -> CGRect {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for i in range {
            let p = points[i]
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let w = points[range.upperBound].width
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -w, dy: -w)
    }
}

/// The web app's line style: each point adds a piece smoothed through midpoints, with its own width.
/// Coordinates are box units; the context's transform maps them to the screen.
enum InkRenderer {
    static func prepare(_ ctx: CGContext, colour: UIColor) {
        ctx.setStrokeColor(colour.cgColor)
        ctx.setFillColor(colour.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
    }

    static func drawLine(_ points: [InkPoint], in ctx: CGContext) {
        for i in points.indices { drawPiece(points, i, in: ctx) }
        drawTail(points, in: ctx)
    }

    /// The piece that point i adds.
    static func drawPiece(_ points: [InkPoint], _ i: Int, in ctx: CGContext) {
        let p = points[i]
        if i == 0 {
            let r = p.width / 2
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: p.width, height: p.width))
            return
        }
        let a = points[i - 1]
        ctx.setLineWidth(CGFloat(p.width))
        ctx.beginPath()
        if i == 1 {
            ctx.move(to: a.point.cg)
            ctx.addLine(to: a.point.midpoint(p.point).cg)
        } else {
            ctx.move(to: points[i - 2].point.midpoint(a.point).cg)
            ctx.addQuadCurve(to: a.point.midpoint(p.point).cg, control: a.point.cg)
        }
        ctx.strokePath()
    }

    /// The last half-segment, from the final midpoint to the final point.
    static func drawTail(_ points: [InkPoint], in ctx: CGContext) {
        guard points.count >= 2 else { return }
        let a = points[points.count - 2], p = points[points.count - 1]
        ctx.setLineWidth(CGFloat(p.width))
        ctx.beginPath()
        ctx.move(to: a.point.midpoint(p.point).cg)
        ctx.addLine(to: p.point.cg)
        ctx.strokePath()
    }
}
