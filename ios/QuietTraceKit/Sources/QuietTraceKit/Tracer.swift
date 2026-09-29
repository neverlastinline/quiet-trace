import Foundation

/// What kind of thing is touching the screen.
public enum PointerKind: Sendable {
    case pen, touch, mouse
}

/// One reading from a pointer, already in box units.
public struct PointerSample: Equatable, Sendable {
    public var location: Point2D
    /// 0...1 for a pencil (0.5 is an average press); 0 when unknown.
    public var pressure: Double

    public init(_ location: Point2D, pressure: Double = 0) {
        self.location = location
        self.pressure = pressure
    }
}

/// A point on the child's line, in box units, with the line's width there.
public struct InkPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double

    public init(x: Double, y: Double, width: Double) {
        self.x = x
        self.y = y
        self.width = width
    }

    public var point: Point2D { Point2D(x: x, y: y) }
}

/// One line the child drew, from touching down to lifting off.
public struct InkLine: Equatable, Sendable {
    public fileprivate(set) var points: [InkPoint] = []
    /// How far the line has ever strayed from where it landed; a resting hand stays near zero.
    public fileprivate(set) var reach = 0.0
}

/// Everything about tracing one drawing that isn't pixels: which touch is drawing (and which
/// is a resting hand or palm), the child's lines, and how much of the guide they cover.
///
/// Mirrors the web app: with Apple Pencil in use, fingers and palms are ignored; with fingers,
/// whichever touch moves is the one that draws.
public final class Tracer {
    public enum Verdict: Equatable, Sendable {
        /// Not enough covered yet.
        case keepGoing
        /// Enough covered: celebrate now.
        case finishNow
        /// Nearly there: celebrate if nothing else is drawn for a moment.
        case finishIfIdle
    }

    public enum Down: Equatable, Sendable {
        case ignored
        /// A new line started. `droppedLine`: a palm's line was thrown away to make room.
        case began(droppedLine: Bool)
    }

    public enum Move: Equatable, Sendable {
        case ignored
        /// Points were added to the live line from this index on.
        case extended(from: Int)
        /// The resting touch's line was thrown away and this touch started a new one.
        case restarted
    }

    public enum Up: Equatable, Sendable {
        case ignored
        /// The live line ended.
        case ended(Verdict)
    }

    public private(set) var guide: Guide?
    /// All of the child's lines for this drawing; the last one is live while `isDrawing`.
    public private(set) var lines: [InkLine] = []
    public private(set) var covered = 0
    /// Whether anything has been drawn on this drawing yet (the start dot fades once it has).
    public private(set) var hasDrawn = false
    public private(set) var activeID: Int?
    /// Off while celebrating or choosing a colour: touches are ignored (pencil use is still noted).
    public var isAccepting = false

    private var hasLive = false
    private var activeKind = PointerKind.touch
    /// Touches that landed while another touch was drawing: id → where they landed.
    private var waiting: [Int: Point2D] = [:]
    private var lastPenAt = -Double.infinity
    private var hits: [Bool] = []

    public init() {}

    public var isDrawing: Bool { activeID != nil }

    public var liveLine: InkLine? { hasLive ? lines.last : nil }

    public var finishedLines: ArraySlice<InkLine> { hasLive ? lines.dropLast() : lines[...] }

    /// Share of guide points covered, 0...1.
    public var coverage: Double {
        guard !hits.isEmpty else { return 0 }
        return Double(covered) / Double(hits.count)
    }

    public func isPenRecent(at time: Double) -> Bool {
        time - lastPenAt < Tuning.penQuietSeconds
    }

    /// Starts a new drawing.
    public func load(_ guide: Guide) {
        self.guide = guide
        lines = []
        hasLive = false
        activeID = nil
        waiting = [:]
        hits = Array(repeating: false, count: guide.samples.count)
        covered = 0
        hasDrawn = false
    }

    public func unload() {
        guide = nil
        lines = []
        hasLive = false
        activeID = nil
        waiting = [:]
        hits = []
        covered = 0
        hasDrawn = false
    }

    /// Back to the colours: forget any touch in progress and any pencil use.
    public func reset() {
        isAccepting = false
        activeID = nil
        hasLive = false
        waiting = [:]
        lastPenAt = -.infinity
    }

    /// A new session always accepts fingers again.
    public func forgetPen() {
        lastPenAt = -.infinity
    }

    // ---- pointer events; `time` is in seconds on any steadily increasing clock ----

    public func down(id: Int, kind: PointerKind, sample: PointerSample, time: Double) -> Down {
        notePen(kind, time)
        guard isAccepting, guide != nil else { return .ignored }
        // While the pencil is in use, fingers and palms are ignored.
        if kind == .touch && isPenRecent(at: time) { return .ignored }
        var dropped = false
        if activeID != nil {
            if kind == .touch && activeKind == .touch { waiting[id] = sample.location }
            guard kind == .pen && activeKind == .touch else { return .ignored }
            // A palm landed before the pencil: drop the palm's line.
            dropLine()
            dropped = true
        }
        begin(id: id, kind: kind, sample: sample)
        return .began(droppedLine: dropped)
    }

    /// `latest` is where the pointer is now; `samples` are all readings since the last move
    /// (coalesced touches), `latest` included.
    public func move(id: Int, kind: PointerKind, latest: PointerSample, samples: [PointerSample], time: Double) -> Move {
        notePen(kind, time)
        var restarted = false
        if id != activeID {
            guard takeOver(id: id, kind: kind, at: latest) else { return .ignored }
            restarted = true
        }
        guard hasLive else { return .ignored }
        // A takeover's line already starts at `latest`; its older readings would only double back.
        if restarted { return .restarted }
        let from = lines[lines.count - 1].points.count
        for sample in samples.isEmpty ? [latest] : samples { addPoint(sample, kind: kind) }
        return .extended(from: from)
    }

    public func up(id: Int, kind: PointerKind, time: Double) -> Up {
        notePen(kind, time)
        waiting[id] = nil
        guard id == activeID else { return .ignored }
        hasLive = false
        activeID = nil
        guard isAccepting else { return .ended(.keepGoing) }
        let done = coverage
        if done >= Tuning.doneAt { return .ended(.finishNow) }
        if done >= Tuning.idleDoneAt { return .ended(.finishIfIdle) }
        return .ended(.keepGoing)
    }

    // ---- internals ----

    private func notePen(_ kind: PointerKind, _ time: Double) {
        if kind == .pen { lastPenAt = time }
    }

    private func begin(id: Int, kind: PointerKind, sample: PointerSample) {
        activeID = id
        activeKind = kind
        hasDrawn = true
        lines.append(InkLine())
        hasLive = true
        addPoint(sample, kind: kind)
    }

    private func dropLine() {
        lines.removeLast()
        hasLive = false
        activeID = nil
        recount()
    }

    /// With two touches down, the one that moves is drawing and the still one is a resting hand.
    private func takeOver(id: Int, kind: PointerKind, at sample: PointerSample) -> Bool {
        guard let from = waiting[id], isAccepting, activeKind == .touch, hasLive,
              lines[lines.count - 1].reach <= Tuning.still else { return false }
        if sample.location.distance(to: from) < Tuning.moved { return false }
        waiting[id] = nil
        dropLine()
        begin(id: id, kind: kind, sample: sample)
        return true
    }

    private func addPoint(_ sample: PointerSample, kind: PointerKind) {
        let index = lines.count - 1
        let p = sample.location
        let prev = lines[index].points.last
        if let prev, (p.x - prev.x) * (p.x - prev.x) + (p.y - prev.y) * (p.y - prev.y) < 0.04 { return }
        var width = Tuning.ink
        if kind == .pen && sample.pressure > 0 { width = Tuning.ink * (0.7 + 0.7 * min(1, sample.pressure)) }
        if let prev { width = prev.width * 0.6 + width * 0.4 }
        lines[index].points.append(InkPoint(x: p.x, y: p.y, width: width))
        let first = lines[index].points[0]
        lines[index].reach = max(lines[index].reach, p.distance(to: first.point))
        cover(from: prev?.point ?? p, to: p)
    }

    /// Marks guide points within reach of the segment a→b.
    private func cover(from a: Point2D, to b: Point2D) {
        guard let samples = guide?.samples else { return }
        let r2 = Tuning.reach * Tuning.reach
        let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
        for (i, s) in samples.enumerated() where !hits[i] {
            var t = len2 > 0 ? ((s.x - a.x) * dx + (s.y - a.y) * dy) / len2 : 0
            t = t < 0 ? 0 : t > 1 ? 1 : t
            let ex = a.x + t * dx - s.x, ey = a.y + t * dy - s.y
            if ex * ex + ey * ey <= r2 {
                hits[i] = true
                covered += 1
            }
        }
    }

    private func recount() {
        covered = 0
        hits = Array(repeating: false, count: hits.count)
        for line in lines {
            for (i, p) in line.points.enumerated() {
                cover(from: i > 0 ? line.points[i - 1].point : p.point, to: p.point)
            }
        }
    }
}
