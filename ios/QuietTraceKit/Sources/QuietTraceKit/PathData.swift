import Foundation

/// One step of a path, in absolute coordinates. Arcs are converted to cubic Béziers.
public enum PathOp: Equatable, Sendable {
    case move(Point2D)
    case line(Point2D)
    case quad(Point2D, Point2D)           // control, end
    case cubic(Point2D, Point2D, Point2D)   // control 1, control 2, end
    case close
}

public enum PathDataError: Error, Equatable {
    case unexpected(Character, offset: Int)
    case missingNumber(command: Character, offset: Int)
}

/// Reads SVG path data (the `d` attribute): M L H V C S Q T A Z, absolute or relative.
public enum PathData {
    public static func parse(_ d: String) throws -> [PathOp] {
        var scanner = PathScanner(Array(d.utf8))
        var ops: [PathOp] = []
        var current = Point2D(x: 0, y: 0)
        var start = current
        var lastCubicControl: Point2D?
        var lastQuadControl: Point2D?
        var command: UInt8?

        while true {
            scanner.skipSeparators()
            guard let next = scanner.peek() else { break }
            if PathScanner.isCommand(next) {
                command = next
                scanner.advance()
            } else if command == nil || !PathScanner.startsNumber(next) {
                throw PathDataError.unexpected(Character(UnicodeScalar(next)), offset: scanner.offset)
            }
            guard let cmd = command else { break }
            let relative = cmd >= UInt8(ascii: "a")
            let upper = relative ? cmd - 32 : cmd
            let base = relative ? current : Point2D(x: 0, y: 0)
            func number() throws -> Double {
                guard let v = scanner.number() else {
                    throw PathDataError.missingNumber(command: Character(UnicodeScalar(cmd)), offset: scanner.offset)
                }
                return v
            }
            func point() throws -> Point2D {
                let x = try number()
                let y = try number()
                return Point2D(x: base.x + x, y: base.y + y)
            }

            var cubicControl: Point2D?
            var quadControl: Point2D?
            switch upper {
            case UInt8(ascii: "M"):
                current = try point()
                start = current
                ops.append(.move(current))
                // Further pairs after a moveto are implicit linetos.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "L"):
                current = try point()
                ops.append(.line(current))
            case UInt8(ascii: "H"):
                current = Point2D(x: (relative ? current.x : 0) + (try number()), y: current.y)
                ops.append(.line(current))
            case UInt8(ascii: "V"):
                current = Point2D(x: current.x, y: (relative ? current.y : 0) + (try number()))
                ops.append(.line(current))
            case UInt8(ascii: "C"):
                let c1 = try point(), c2 = try point(), end = try point()
                ops.append(.cubic(c1, c2, end))
                cubicControl = c2
                current = end
            case UInt8(ascii: "S"):
                let c1 = lastCubicControl.map { current * 2 - $0 } ?? current
                let c2 = try point(), end = try point()
                ops.append(.cubic(c1, c2, end))
                cubicControl = c2
                current = end
            case UInt8(ascii: "Q"):
                let c = try point(), end = try point()
                ops.append(.quad(c, end))
                quadControl = c
                current = end
            case UInt8(ascii: "T"):
                let c = lastQuadControl.map { current * 2 - $0 } ?? current
                let end = try point()
                ops.append(.quad(c, end))
                quadControl = c
                current = end
            case UInt8(ascii: "A"):
                let rx = try number(), ry = try number(), rotation = try number()
                guard let large = scanner.flag(), let sweep = scanner.flag() else {
                    throw PathDataError.missingNumber(command: Character(UnicodeScalar(cmd)), offset: scanner.offset)
                }
                let end = try point()
                ops += arc(from: current, rx: rx, ry: ry, rotation: rotation, largeArc: large, sweep: sweep, to: end)
                current = end
            case UInt8(ascii: "Z"):
                ops.append(.close)
                current = start
                command = nil
            default:
                throw PathDataError.unexpected(Character(UnicodeScalar(cmd)), offset: scanner.offset)
            }
            lastCubicControl = cubicControl
            lastQuadControl = quadControl
        }
        return ops
    }

    /// An elliptical arc as cubic Béziers, following the SVG spec's endpoint-to-centre conversion
    /// (including scaling up radii that are too small to reach the end point).
    static func arc(from p0: Point2D, rx: Double, ry: Double, rotation: Double,
                    largeArc: Bool, sweep: Bool, to p1: Point2D) -> [PathOp] {
        if p0 == p1 { return [] }
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 { return [.line(p1)] }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx2 + sinPhi * dy2
        let y1 = -sinPhi * dx2 + cosPhi * dy2

        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let rx2 = rx * rx, ry2 = ry * ry
        let num = rx2 * ry2 - rx2 * y1 * y1 - ry2 * x1 * x1
        let den = rx2 * y1 * y1 + ry2 * x1 * x1
        let coef = (den == 0 ? 0 : max(0, num / den).squareRoot()) * (largeArc == sweep ? -1 : 1)
        let cx1 = coef * rx * y1 / ry
        let cy1 = coef * -ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let ux = (x1 - cx1) / rx, uy = (y1 - cy1) / ry
        let vx = (-x1 - cx1) / rx, vy = (-y1 - cy1) / ry
        let theta = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, vx, vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // No piece wider than a quarter turn keeps the Bézier within 0.03% of the true arc.
        let pieces = max(1, Int((abs(delta) / (.pi / 2) - 1e-9).rounded(.up)))
        let step = delta / Double(pieces)
        let k = 4.0 / 3.0 * tan(step / 4)
        func onEllipse(_ ex: Double, _ ey: Double) -> Point2D {
            Point2D(x: cx + rx * cosPhi * ex - ry * sinPhi * ey,
                  y: cy + rx * sinPhi * ex + ry * cosPhi * ey)
        }
        var ops: [PathOp] = []
        for i in 0..<pieces {
            let a1 = theta + Double(i) * step, a2 = a1 + step
            let c1 = onEllipse(cos(a1) - k * sin(a1), sin(a1) + k * cos(a1))
            let c2 = onEllipse(cos(a2) + k * sin(a2), sin(a2) - k * cos(a2))
            let end = i == pieces - 1 ? p1 : onEllipse(cos(a2), sin(a2))
            ops.append(.cubic(c1, c2, end))
        }
        return ops
    }
}

/// A small byte scanner for path data.
private struct PathScanner {
    let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    static func isCommand(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: "M"), UInt8(ascii: "L"), UInt8(ascii: "H"), UInt8(ascii: "V"),
             UInt8(ascii: "C"), UInt8(ascii: "S"), UInt8(ascii: "Q"), UInt8(ascii: "T"),
             UInt8(ascii: "A"), UInt8(ascii: "Z"):
            return true
        case UInt8(ascii: "m"), UInt8(ascii: "l"), UInt8(ascii: "h"), UInt8(ascii: "v"),
             UInt8(ascii: "c"), UInt8(ascii: "s"), UInt8(ascii: "q"), UInt8(ascii: "t"),
             UInt8(ascii: "a"), UInt8(ascii: "z"):
            return true
        default:
            return false
        }
    }

    static func isDigit(_ b: UInt8) -> Bool { b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") }

    static func startsNumber(_ b: UInt8) -> Bool {
        isDigit(b) || b == UInt8(ascii: "-") || b == UInt8(ascii: "+") || b == UInt8(ascii: ".")
    }

    func peek() -> UInt8? { offset < bytes.count ? bytes[offset] : nil }

    mutating func advance() { offset += 1 }

    mutating func skipSeparators() {
        while let b = peek(), b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == UInt8(ascii: ",") {
            offset += 1
        }
    }

    /// An arc flag: a single 0 or 1, which may be written with no separator after it.
    mutating func flag() -> Bool? {
        skipSeparators()
        guard let b = peek(), b == UInt8(ascii: "0") || b == UInt8(ascii: "1") else { return nil }
        offset += 1
        return b == UInt8(ascii: "1")
    }

    mutating func number() -> Double? {
        skipSeparators()
        let begin = offset
        if let b = peek(), b == UInt8(ascii: "-") || b == UInt8(ascii: "+") { offset += 1 }
        var digits = false
        while let b = peek(), PathScanner.isDigit(b) { offset += 1; digits = true }
        if peek() == UInt8(ascii: ".") {
            offset += 1
            while let b = peek(), PathScanner.isDigit(b) { offset += 1; digits = true }
        }
        guard digits else { offset = begin; return nil }
        if let b = peek(), b == UInt8(ascii: "e") || b == UInt8(ascii: "E") {
            let mark = offset
            offset += 1
            if let s = peek(), s == UInt8(ascii: "-") || s == UInt8(ascii: "+") { offset += 1 }
            var expDigits = false
            while let d = peek(), PathScanner.isDigit(d) { offset += 1; expDigits = true }
            if !expDigits { offset = mark }
        }
        return Double(String(decoding: bytes[begin..<offset], as: UTF8.self))
    }
}
