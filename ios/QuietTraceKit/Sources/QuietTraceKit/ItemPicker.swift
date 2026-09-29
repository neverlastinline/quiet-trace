/// Chooses what to trace next: a weighted choice of category, never the same category
/// twice in a row, and within each category a shuffled bag, so nothing repeats until
/// the whole bag has been used.
public struct ItemPicker<RNG: RandomNumberGenerator> {
    /// How often each kind of thing comes up.
    public static var weights: [(DrawingCategory, Double)] {
        [(.objects, 0.35), (.shapes, 0.25), (.letters, 0.25), (.squiggles, 0.15)]
    }

    public private(set) var lastCategory: DrawingCategory?
    private var bags: [DrawingCategory: [Drawing]] = [:]
    private var rng: RNG

    public init(rng: RNG) {
        self.rng = rng
    }

    public mutating func next() -> Drawing {
        take(from: pickCategory())
    }

    /// Records a drawing shown by other means (so the next pick still changes category).
    public mutating func noteShown(_ drawing: Drawing) {
        lastCategory = drawing.category
        bags[drawing.category]?.removeAll { $0 == drawing }
    }

    mutating func pickCategory() -> DrawingCategory {
        let options = Self.weights.filter { $0.0 != lastCategory }
        var r = Double.random(in: 0..<1, using: &rng) * options.reduce(0) { $0 + $1.1 }
        var chosen = options[options.count - 1].0
        for (category, weight) in options {
            r -= weight
            if r <= 0 {
                chosen = category
                break
            }
        }
        lastCategory = chosen
        return chosen
    }

    mutating func take(from category: DrawingCategory) -> Drawing {
        if bags[category]?.isEmpty ?? true {
            bags[category] = Library.drawings(in: category).shuffled(using: &rng)
        }
        return bags[category]!.removeLast()
    }
}
