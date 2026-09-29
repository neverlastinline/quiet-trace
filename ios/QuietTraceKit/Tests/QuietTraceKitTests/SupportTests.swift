import XCTest
@testable import QuietTraceKit

/// A small seeded generator so picks are repeatable in tests.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class ItemPickerTests: XCTestCase {
    func testNeverTheSameCategoryTwiceInARow() {
        var picker = ItemPicker(rng: SplitMix64(state: 1))
        var last: DrawingCategory?
        for _ in 0..<500 {
            let d = picker.next()
            XCTAssertNotEqual(d.category, last)
            last = d.category
        }
    }

    func testNothingRepeatsUntilTheBagIsEmpty() {
        var picker = ItemPicker(rng: SplitMix64(state: 7))
        var seen: [DrawingCategory: [String]] = [:]
        for _ in 0..<2000 {
            let d = picker.next()
            seen[d.category, default: []].append(d.name)
        }
        for category in DrawingCategory.allCases {
            let names = seen[category] ?? []
            let size = Library.drawings(in: category).count
            XCTAssertGreaterThan(names.count, size, "\(category) should go round at least once")
            for start in stride(from: 0, to: names.count - size + 1, by: size) {
                XCTAssertEqual(Set(names[start..<(start + size)]).count, size, "\(category) repeated within a bag")
            }
        }
    }

    func testCategoriesFollowTheirWeights() {
        var picker = ItemPicker(rng: SplitMix64(state: 42))
        var counts: [DrawingCategory: Int] = [:]
        for _ in 0..<20000 { counts[picker.next().category, default: 0] += 1 }
        // Objects are the most common and squiggles the rarest.
        XCTAssertGreaterThan(counts[.objects]!, counts[.shapes]!)
        XCTAssertGreaterThan(counts[.shapes]!, counts[.squiggles]!)
        XCTAssertGreaterThan(counts[.letters]!, counts[.squiggles]!)
    }

    func testNoteShownChangesTheNextCategory() throws {
        var picker = ItemPicker(rng: SplitMix64(state: 3))
        let square = try XCTUnwrap(Library.drawing(.shapes, "square"))
        picker.noteShown(square)
        for _ in 0..<1 { XCTAssertNotEqual(picker.next().category, .shapes) }
    }
}

final class ChimeTests: XCTestCase {
    func testEveryChimeIsGentleAndDiesAway() {
        let rate = 44_100.0
        for v in 0..<Chime.variations {
            let s = Chime.render(variation: v, sampleRate: rate)
            XCTAssertEqual(s.count, Int(Chime.duration * rate))
            XCTAssert(s.allSatisfy { $0.isFinite })
            let peak = s.map { abs($0) }.max()!
            XCTAssertGreaterThan(peak, 0.05, "audible")
            XCTAssertLessThan(peak, 0.5, "soft, and nowhere near clipping")
            func rms(_ range: Range<Int>) -> Float {
                (s[range].reduce(0) { $0 + $1 * $1 } / Float(range.count)).squareRoot()
            }
            let start = rms(0..<Int(0.5 * rate))
            let end = rms((s.count - Int(0.3 * rate))..<s.count)
            XCTAssertLessThan(end, start * 0.002, "the echo has faded by the end")
            XCTAssertEqual(s.last!, 0)
        }
    }

    func testChimesDiffer() {
        let a = Chime.render(variation: 0, sampleRate: 22_050)
        let b = Chime.render(variation: 3, sampleRate: 22_050)
        XCTAssertNotEqual(a, b)
    }
}

final class PaletteAndLayoutTests: XCTestCase {
    func testMixMatchesTheWebApp() {
        XCTAssertEqual(Palette.mix(0xF28B9B, 0xFFFFFF, 0.55), 0xF9CBD2)
        XCTAssertEqual(Palette.mix(0x000000, 0xFFFFFF, 0), 0x000000)
        XCTAssertEqual(Palette.mix(0x000000, 0xFFFFFF, 1), 0xFFFFFF)
        XCTAssertEqual(Palette.swatches.count, 8)
    }

    func testBoxIsCentredOnTheShorterSide() {
        let layout = BoxLayout(width: 1024, height: 768)
        XCTAssertEqual(layout.size, 768 * 0.74, accuracy: 1e-9)
        XCTAssertEqual(layout.originX, (1024 - layout.size) / 2, accuracy: 1e-9)
        let centre = layout.toBox(x: 512, y: 384)
        XCTAssertEqual(centre.x, 50, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 50, accuracy: 1e-9)
        let back = layout.toScreen(Point2D(x: 15, y: 85))
        let again = layout.toBox(x: back.x, y: back.y)
        XCTAssertEqual(again.x, 15, accuracy: 1e-9)
        XCTAssertEqual(again.y, 85, accuracy: 1e-9)
    }
}
