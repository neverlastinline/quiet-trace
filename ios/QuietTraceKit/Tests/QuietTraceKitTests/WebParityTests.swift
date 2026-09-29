import Foundation
import XCTest
@testable import QuietTraceKit

/// The iOS guides must match the web app's: same drawings, same strokes, same guide points.
/// The fixture is measured by Chromium from shapes.js (see ios/scripts/web-reference.cjs).
final class WebParityTests: XCTestCase {
    struct Reference: Decodable {
        struct Item: Decodable {
            let category: String
            let name: String
            let strokes: [Stroke]
        }
        struct Stroke: Decodable {
            let length: Double
            let count: Int
            /// [index, x, y]
            let points: [[Double]]
        }
        let step: Double
        let items: [Item]
    }

    private func reference() throws -> Reference {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "web-reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
    }

    func testSameDrawingsAsTheWebApp() throws {
        let ref = try reference()
        let web = Set(ref.items.map { "\($0.category)/\($0.name)" })
        let ios = Set(Library.all.map { "\($0.category.rawValue)/\($0.name)" })
        XCTAssertEqual(ios, web)
        XCTAssertEqual(Library.all.count, 69)
    }

    func testGuidesMatchTheBrowser() throws {
        let ref = try reference()
        XCTAssertEqual(ref.step, Tuning.step)
        var strokes = 0, compared = 0, worst = 0.0
        for item in ref.items {
            let category = try XCTUnwrap(DrawingCategory(rawValue: item.category))
            let drawing = try XCTUnwrap(Library.drawing(category, item.name), item.name)
            let guide = try Guide(drawing)
            let label = "\(item.category)/\(item.name)"
            XCTAssertEqual(guide.strokes.count, item.strokes.count, "\(label): stroke count")
            for (k, (mine, theirs)) in zip(guide.strokes, item.strokes).enumerated() {
                XCTAssertEqual(mine.length, theirs.length, accuracy: max(0.05, theirs.length * 0.002), "\(label) stroke \(k): length")
                XCTAssertLessThanOrEqual(abs(mine.points.count - theirs.count), 1, "\(label) stroke \(k): point count")
                strokes += 1
                guard mine.points.count == theirs.count else { continue }
                compared += 1
                for p in theirs.points {
                    let q = mine.points[Int(p[0])]
                    worst = max(worst, hypot(q.x - p[1], q.y - p[2]))
                    XCTAssertEqual(q.x, p[1], accuracy: 0.05, "\(label) stroke \(k) point \(Int(p[0])): x")
                    XCTAssertEqual(q.y, p[2], accuracy: 0.05, "\(label) stroke \(k) point \(Int(p[0])): y")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(Double(compared), Double(strokes) * 0.95, "point-by-point check skipped too often")
        print("parity: \(compared)/\(strokes) strokes compared point by point; worst offset \(worst) box units")
    }
}
