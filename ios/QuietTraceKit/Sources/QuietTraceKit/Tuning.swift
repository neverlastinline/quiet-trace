/// Every number that shapes how Quiet Trace looks and feels, matching the web app's app.js.
///
/// Drawing sizes are in box units: every drawing lives in a 100 × 100 box.
public enum Tuning {
    /// Share of the shorter screen side the box fills.
    public static let box = 0.74
    /// The child's line width.
    public static let ink = 3.4
    /// Soft track under the guide.
    public static let track = 6.5
    public static let dashWidth = 1.6
    public static let dash: [Double] = [2.8, 3.2]
    /// How near the child's line must pass for a guide point to count.
    public static let reach = 5.5
    /// Spacing of guide points.
    public static let step = 1.2

    /// Share of guide points covered to finish...
    public static let doneAt = 0.85
    /// ...or this much, followed by a pause of `idleSeconds`.
    public static let idleDoneAt = 0.65
    public static let idleSeconds = 3.0

    /// Fingers and palms are ignored until the pencil has been unused this long.
    public static let penQuietSeconds = 10.0
    /// A touch whose line stays this close to where it landed is a resting hand...
    public static let still = 3.0
    /// ...and loses the line to another touch that moves this far.
    public static let moved = 1.5

    public static let sweepSeconds = 0.9
    public static let glowSeconds = 1.4
    public static let holdSeconds = 2.7
    public static let fadeSeconds = 0.85
    public static let exitHoldSeconds = 3.0
    /// Side of the invisible grown-up exit in the top-left corner, in points.
    public static let exitCorner = 88.0
}
