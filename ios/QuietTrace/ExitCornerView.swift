import QuietTraceKit
import UIKit

/// The invisible grown-up exit: hold the top-left corner for three seconds to go back to the
/// colours. Nothing shows it, and it won't start while a line is being drawn.
final class ExitCornerView: UIView {
    var onHold: (() -> Void)?
    /// Asked when a finger lands; returning false (someone is drawing) ignores it.
    var canStart: (() -> Bool)?

    private var hold: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func cancel() {
        hold?.cancel()
        hold = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancel()
        guard canStart?() ?? true else { return }
        hold = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Tuning.exitHoldSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.hold = nil
            self.onHold?()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Sliding off the corner lets go.
        if let touch = touches.first, !bounds.contains(touch.location(in: self)) { cancel() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { cancel() }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancel() }
}
