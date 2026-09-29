import XCTest
@testable import QuietTraceKit

final class PathDataTests: XCTestCase {
    private func p(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    func testLinesAndClose() throws {
        XCTAssertEqual(try PathData.parse("M15 15 H85 V85 H15 Z"), [
            .move(p(15, 15)), .line(p(85, 15)), .line(p(85, 85)), .line(p(15, 85)), .close,
        ])
    }

    func testImplicitLinetoAfterMoveAndCommas() throws {
        XCTAssertEqual(try PathData.parse("M1,2 3,4 5 6"), [.move(p(1, 2)), .line(p(3, 4)), .line(p(5, 6))])
    }

    func testRelativeCommands() throws {
        XCTAssertEqual(try PathData.parse("m10 10 l5 0 h5 v-5 z l1 1"), [
            .move(p(10, 10)), .line(p(15, 10)), .line(p(20, 10)), .line(p(20, 5)), .close, .line(p(11, 11)),
        ])
    }

    func testCompactNumbers() throws {
        XCTAssertEqual(try PathData.parse("M-1.5-2.5L.5.25 1e1 2E-1"), [
            .move(p(-1.5, -2.5)), .line(p(0.5, 0.25)), .line(p(10, 0.2)),
        ])
    }

    func testSmoothQuadraticReflectsTheLastControl() throws {
        XCTAssertEqual(try PathData.parse("M0 0 Q10 -10 20 0 T40 0"), [
            .move(p(0, 0)), .quad(p(10, -10), p(20, 0)), .quad(p(30, 10), p(40, 0)),
        ])
    }

    func testSmoothCubicReflectsTheLastControl() throws {
        XCTAssertEqual(try PathData.parse("M0 0 C0 10 10 10 10 0 S20 -10 20 0"), [
            .move(p(0, 0)), .cubic(p(0, 10), p(10, 10), p(10, 0)), .cubic(p(10, -10), p(20, -10), p(20, 0)),
        ])
    }

    func testArcFlagsWithoutSeparators() throws {
        let spaced = try PathData.parse("M0 0 A10 10 0 1 1 20 0")
        let packed = try PathData.parse("M0 0 A10 10 0 1120 0")
        XCTAssertEqual(spaced, packed)
    }

    func testFullCircleLengthAndStart() throws {
        let strokes = try Guide.measure(Library.circle(50, 50, 40), step: 1.2)
        XCTAssertEqual(strokes.count, 1)
        XCTAssertEqual(strokes[0].length, 2 * .pi * 40, accuracy: 0.05)
        XCTAssertEqual(strokes[0].points.first!, p(50, 10))
        // Anticlockwise from the top: the next points head left.
        XCTAssertLessThan(strokes[0].points[3].x, 50)
    }

    func testArcRadiiTooSmallAreScaledUp() throws {
        // Endpoints 40 apart with radius 10: the spec scales the radius to 20, a semicircle.
        let strokes = try Guide.measure("M0 0 A10 10 0 0 1 40 0", step: 1)
        XCTAssertEqual(strokes[0].length, .pi * 20, accuracy: 0.02)
        let top = strokes[0].points.min { $0.y < $1.y }!
        XCTAssertEqual(top.y, -20, accuracy: 0.05)
    }

    func testEachMoveStartsAStroke() throws {
        let strokes = try Guide.measure("M0 0 L10 0 M0 5 L0 15 L5 15", step: 1)
        XCTAssertEqual(strokes.map(\.length), [10, 15])
        XCTAssertEqual(strokes[1].points.count, 16)
        XCTAssertEqual(strokes[1].points.last!, p(5, 15))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try PathData.parse("M0 0 X5 5"))
        XCTAssertThrowsError(try PathData.parse("M0"))
        XCTAssertThrowsError(try PathData.parse("5 5"))
    }

    func testEveryDrawingParses() throws {
        for drawing in Library.all {
            let guide = try Guide(drawing)
            XCTAssertFalse(guide.strokes.isEmpty, drawing.name)
            XCTAssertGreaterThan(guide.length, 20, drawing.name)
            for s in guide.samples {
                XCTAssert((-1...101).contains(s.x) && (-1...101).contains(s.y), "\(drawing.name) leaves the box at \(s)")
            }
        }
    }
}
