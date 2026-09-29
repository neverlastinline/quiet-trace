import Foundation

/// One continuous stroke of a drawing: everything from one moveto to the next.
public struct Stroke: Equatable, Sendable {
    /// Path steps, starting with `.move`.
    public let ops: [PathOp]
    /// Length along the stroke, in box units.
    public let length: Double
    /// Guide points spaced evenly along the stroke, first and last included.
    public let points: [Point2D]
}

/// A drawing measured and ready to trace.
public struct Guide: Sendable {
    public let drawing: Drawing
    public let strokes: [Stroke]
    /// Total length of every stroke.
    public let length: Double
    /// Every stroke's guide points, in order. Tracing is checked against these.
    public let samples: [Point2D]

    /// Where the pulsing "begin here" dot goes: the start of the first stroke.
    public var start: Point2D { strokes[0].points[0] }

    public init(_ drawing: Drawing, step: Double = Tuning.step) throws {
        self.drawing = drawing
        strokes = try Guide.measure(drawing.pathData, step: step)
        length = strokes.reduce(0) { $0 + $1.length }
        samples = strokes.flatMap(\.points)
    }

    /// Splits path data into strokes (each moveto starts one) and samples points along each,
    /// every `step` box units, like the web app's QT.measure.
    public static func measure(_ pathData: String, step: Double) throws -> [Stroke] {
        var groups: [[PathOp]] = []
        for op in try PathData.parse(pathData) {
            if case .move = op { groups.append([op]) } else if !groups.isEmpty { groups[groups.count - 1].append(op) }
        }
        return groups.map { ops in
            let polyline = flatten(ops)
            var cumulative = [0.0]
            cumulative.reserveCapacity(polyline.count)
            for i in 1..<max(1, polyline.count) {
                cumulative.append(cumulative[i - 1] + polyline[i - 1].distance(to: polyline[i]))
            }
            let length = cumulative.last ?? 0
            let n = max(1, Int((length / step).rounded(.up)))
            var points: [Point2D] = []
            points.reserveCapacity(n + 1)
            var j = 0
            for i in 0...n {
                let target = length * Double(i) / Double(n)
                while j < polyline.count - 2 && cumulative[j + 1] < target { j += 1 }
                if polyline.count < 2 {
                    points.append(polyline[0])
                    continue
                }
                let span = cumulative[j + 1] - cumulative[j]
                let t = span > 0 ? min(1, max(0, (target - cumulative[j]) / span)) : 0
                points.append(polyline[j] + (polyline[j + 1] - polyline[j]) * t)
            }
            return Stroke(ops: ops, length: length, points: points)
        }
    }

    /// Finely divided polyline through a stroke, closepaths included.
    static func flatten(_ ops: [PathOp]) -> [Point2D] {
        var out: [Point2D] = []
        var current = Point2D(x: 0, y: 0)
        var start = current
        func add(_ p: Point2D) {
            if let last = out.last, last == p { return }
            out.append(p)
        }
        for op in ops {
            switch op {
            case .move(let p):
                current = p
                start = p
                add(p)
            case .line(let p):
                add(p)
                current = p
            case .quad(let c, let p):
                let a = current
                let n = pieces(a.distance(to: c) + c.distance(to: p))
                for i in 1...n {
                    let t = Double(i) / Double(n), u = 1 - t
                    add(a * (u * u) + c * (2 * u * t) + p * (t * t))
                }
                current = p
            case .cubic(let c1, let c2, let p):
                let a = current
                let n = pieces(a.distance(to: c1) + c1.distance(to: c2) + c2.distance(to: p))
                for i in 1...n {
                    let t = Double(i) / Double(n), u = 1 - t
                    add(a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + p * (t * t * t))
                }
                current = p
            case .close:
                add(start)
                current = start
            }
        }
        if out.isEmpty { out.append(current) }
        return out
    }

    /// Enough straight pieces that each is at most ~0.2 box units long.
    private static func pieces(_ hullLength: Double) -> Int {
        min(2000, max(8, Int((hullLength / 0.2).rounded(.up))))
    }
}
