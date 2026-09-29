import XCTest
@testable import QuietTraceKit

final class TracerTests: XCTestCase {
    private var tracer: Tracer!
    private var guide: Guide!
    private var clock = 100.0

    override func setUpWithError() throws {
        guide = try Guide(XCTUnwrap(Library.drawing(.shapes, "square")))
        tracer = Tracer()
        tracer.load(guide)
        tracer.isAccepting = true
    }

    private func at(_ x: Double, _ y: Double, pressure: Double = 0) -> PointerSample {
        PointerSample(Point2D(x: x, y: y), pressure: pressure)
    }

    private func tick() -> Double {
        clock += 0.016
        return clock
    }

    @discardableResult
    private func drag(_ id: Int, _ kind: PointerKind, through points: [Point2D]) -> Tracer.Up {
        _ = tracer.down(id: id, kind: kind, sample: PointerSample(points[0]), time: tick())
        for p in points.dropFirst() {
            _ = tracer.move(id: id, kind: kind, latest: PointerSample(p), samples: [PointerSample(p)], time: tick())
        }
        return tracer.up(id: id, kind: kind, time: tick())
    }

    // ---- coverage ----

    func testTracingTheWholeShapeFinishes() {
        let result = drag(1, .touch, through: guide.samples)
        XCTAssertEqual(result, .ended(.finishNow))
        XCTAssertEqual(tracer.coverage, 1, accuracy: 1e-9)
        XCTAssertEqual(tracer.lines.count, 1)
        XCTAssertNil(tracer.liveLine)
    }

    func testCornersOnlyAreEnoughBecauseSegmentsCount() {
        // Straight drags between corners cover every guide point along the way.
        let corners = [(15.0, 15.0), (85.0, 15.0), (85.0, 85.0), (15.0, 85.0), (15.0, 15.0)].map { Point2D(x: $0.0, y: $0.1) }
        var last = Tracer.Up.ignored
        for i in 0..<4 { last = drag(i + 1, .touch, through: [corners[i], corners[i + 1]]) }
        XCTAssertEqual(last, .ended(.finishNow))
    }

    func testMostOfTheWayWaitsForAPause() {
        let n = guide.samples.count
        let result = drag(1, .touch, through: Array(guide.samples[0..<(n * 3 / 4)]))
        XCTAssertEqual(result, .ended(.finishIfIdle))
    }

    func testALittleKeepsGoing() {
        let result = drag(1, .touch, through: Array(guide.samples[0..<20]))
        XCTAssertEqual(result, .ended(.keepGoing))
        XCTAssertGreaterThan(tracer.coverage, 0)
        XCTAssertTrue(tracer.hasDrawn)
    }

    func testScribblingFarAwayCoversNothing() {
        drag(1, .touch, through: [Point2D(x: 50, y: 50), Point2D(x: 60, y: 60), Point2D(x: 40, y: 55)])
        XCTAssertEqual(tracer.covered, 0)
    }

    func testNotAcceptingIgnoresTouchesButNotesThePencil() {
        tracer.isAccepting = false
        XCTAssertEqual(tracer.down(id: 1, kind: .pen, sample: at(15, 15), time: tick()), .ignored)
        tracer.isAccepting = true
        XCTAssertEqual(tracer.down(id: 2, kind: .touch, sample: at(15, 15), time: tick()), .ignored)
    }

    // ---- line shape ----

    func testTinyMovesAreSkippedAndPressureSetsWidth() {
        _ = tracer.down(id: 1, kind: .pen, sample: at(20, 20, pressure: 1), time: tick())
        _ = tracer.move(id: 1, kind: .pen, latest: at(20.1, 20), samples: [at(20.1, 20, pressure: 1)], time: tick())
        XCTAssertEqual(tracer.liveLine?.points.count, 1)
        XCTAssertEqual(tracer.liveLine?.points[0].width ?? 0, Tuning.ink * 1.4, accuracy: 1e-9)
        let r = tracer.move(id: 1, kind: .pen, latest: at(22, 20), samples: [at(21, 20, pressure: 0.2), at(22, 20, pressure: 0.2)], time: tick())
        XCTAssertEqual(r, .extended(from: 1))
        XCTAssertEqual(tracer.liveLine?.points.count, 3)
        // Widths ease toward the new pressure rather than jumping.
        let w = tracer.liveLine!.points.map(\.width)
        XCTAssertGreaterThan(w[0], w[1])
        XCTAssertGreaterThan(w[1], w[2])
        XCTAssertGreaterThan(w[2], Tuning.ink * (0.7 + 0.7 * 0.2))
    }

    // ---- palm rejection ----

    func testPencilInUseIgnoresFingersForAWhile() {
        drag(1, .pen, through: [Point2D(x: 15, y: 15), Point2D(x: 30, y: 15)])
        let now = clock
        XCTAssertEqual(tracer.down(id: 2, kind: .touch, sample: at(50, 50), time: now + 5), .ignored)
        XCTAssertEqual(tracer.down(id: 3, kind: .touch, sample: at(50, 50), time: now + Tuning.penQuietSeconds + 0.1), .began(droppedLine: false))
    }

    func testForgettingThePencilAcceptsFingersAgain() {
        drag(1, .pen, through: [Point2D(x: 15, y: 15), Point2D(x: 30, y: 15)])
        tracer.forgetPen()
        XCTAssertEqual(tracer.down(id: 2, kind: .touch, sample: at(50, 50), time: tick()), .began(droppedLine: false))
    }

    func testPalmBeforePencilIsDropped() {
        _ = tracer.down(id: 1, kind: .touch, sample: at(60, 70), time: tick())
        _ = tracer.move(id: 1, kind: .touch, latest: at(61, 70), samples: [at(61, 70)], time: tick())
        XCTAssertEqual(tracer.down(id: 2, kind: .pen, sample: at(15, 15), time: tick()), .began(droppedLine: true))
        XCTAssertEqual(tracer.lines.count, 1)
        XCTAssertEqual(tracer.activeID, 2)
        XCTAssertEqual(tracer.liveLine?.points.first?.point, Point2D(x: 15, y: 15))
        // The palm lifting later changes nothing.
        XCTAssertEqual(tracer.up(id: 1, kind: .touch, time: tick()), .ignored)
        XCTAssertTrue(tracer.isDrawing)
    }

    func testSecondFingerCannotInterruptAPencil() {
        _ = tracer.down(id: 1, kind: .pen, sample: at(15, 15), time: tick())
        XCTAssertEqual(tracer.down(id: 2, kind: .touch, sample: at(50, 50), time: tick()), .ignored)
        XCTAssertEqual(tracer.move(id: 2, kind: .touch, latest: at(70, 70), samples: [], time: tick()), .ignored)
        XCTAssertEqual(tracer.activeID, 1)
    }

    func testMovingFingerTakesOverFromARestingHand() {
        // The side of a hand lands first and stays put...
        _ = tracer.down(id: 1, kind: .touch, sample: at(60, 70), time: tick())
        _ = tracer.move(id: 1, kind: .touch, latest: at(60.5, 70), samples: [at(60.5, 70)], time: tick())
        // ...then the drawing finger lands and moves.
        XCTAssertEqual(tracer.down(id: 2, kind: .touch, sample: at(15, 15), time: tick()), .ignored)
        XCTAssertEqual(tracer.move(id: 2, kind: .touch, latest: at(15.5, 15), samples: [at(15.5, 15)], time: tick()), .ignored,
                       "a tiny wobble is not enough")
        XCTAssertEqual(tracer.move(id: 2, kind: .touch, latest: at(20, 15), samples: [at(18, 15), at(20, 15)], time: tick()), .restarted)
        XCTAssertEqual(tracer.activeID, 2)
        XCTAssertEqual(tracer.lines.count, 1)
        XCTAssertEqual(tracer.liveLine?.points.map(\.x), [20], "starts where the finger is now")
        XCTAssertEqual(tracer.move(id: 2, kind: .touch, latest: at(24, 15), samples: [at(22, 15), at(24, 15)], time: tick()),
                       .extended(from: 1))
        // The hand moving afterwards does nothing.
        XCTAssertEqual(tracer.move(id: 1, kind: .touch, latest: at(70, 70), samples: [], time: tick()), .ignored)
    }

    func testAFingerThatIsReallyDrawingKeepsTheLine() {
        _ = tracer.down(id: 1, kind: .touch, sample: at(15, 15), time: tick())
        _ = tracer.move(id: 1, kind: .touch, latest: at(40, 15), samples: [at(40, 15)], time: tick())
        _ = tracer.down(id: 2, kind: .touch, sample: at(60, 70), time: tick())
        XCTAssertEqual(tracer.move(id: 2, kind: .touch, latest: at(70, 70), samples: [], time: tick()), .ignored)
        XCTAssertEqual(tracer.activeID, 1)
    }

    func testDroppingALineRecountsCoverage() {
        drag(1, .touch, through: Array(guide.samples[0..<40]))
        let before = tracer.covered
        // A touch lands right on the guide; then the pencil arrives and that touch is dropped as a palm.
        _ = tracer.down(id: 2, kind: .touch, sample: PointerSample(guide.samples[100]), time: tick())
        XCTAssertGreaterThan(tracer.covered, before)
        _ = tracer.down(id: 3, kind: .pen, sample: at(50, 50), time: tick())
        XCTAssertEqual(tracer.covered, before)
    }

    func testResetForgetsEverythingInProgress() {
        _ = tracer.down(id: 1, kind: .pen, sample: at(15, 15), time: tick())
        tracer.reset()
        XCTAssertFalse(tracer.isDrawing)
        XCTAssertFalse(tracer.isAccepting)
        tracer.isAccepting = true
        XCTAssertEqual(tracer.down(id: 2, kind: .touch, sample: at(15, 15), time: tick()), .began(droppedLine: false))
    }

    func testLoadingANewDrawingStartsFresh() throws {
        drag(1, .touch, through: guide.samples)
        let circle = try Guide(XCTUnwrap(Library.drawing(.shapes, "circle")))
        tracer.load(circle)
        XCTAssertEqual(tracer.covered, 0)
        XCTAssertTrue(tracer.lines.isEmpty)
        XCTAssertFalse(tracer.hasDrawn)
    }
}
