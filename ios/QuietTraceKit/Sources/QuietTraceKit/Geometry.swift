import Foundation

/// A point in box units (or any plane; the kit has no UIKit types).
public struct Point2D: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x - b.x, y: a.y - b.y) }
    public static func * (a: Point2D, k: Double) -> Point2D { Point2D(x: a.x * k, y: a.y * k) }

    public func distance(to other: Point2D) -> Double { hypot(x - other.x, y - other.y) }
    public func midpoint(_ other: Point2D) -> Point2D { Point2D(x: (x + other.x) / 2, y: (y + other.y) / 2) }
}

/// Where the 100 × 100 box sits on a screen: centred, filling `Tuning.box` of the shorter side.
public struct BoxLayout: Equatable, Sendable {
    public let width: Double
    public let height: Double
    /// Side of the box in screen points.
    public let size: Double
    public let originX: Double
    public let originY: Double

    public init(width: Double, height: Double, fill: Double = Tuning.box) {
        self.width = width
        self.height = height
        size = min(width, height) * fill
        originX = (width - size) / 2
        originY = (height - size) / 2
    }

    /// Screen points per box unit.
    public var unit: Double { size / 100 }

    public func toBox(x: Double, y: Double) -> Point2D {
        Point2D(x: (x - originX) / unit, y: (y - originY) / unit)
    }

    public func toScreen(_ p: Point2D) -> Point2D {
        Point2D(x: originX + p.x * unit, y: originY + p.y * unit)
    }
}
