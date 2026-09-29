import QuietTraceKit
import UIKit

/// Eight softly breathing colours. No words: a child just taps one.
final class PickerView: UIView {
    var onChoose: ((Int) -> Void)?

    private var swatches: [SwatchView] = []
    private var isLeaving = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Colours.paper
        accessibilityLabel = "Choose a colour"
        for (i, swatch) in Palette.swatches.enumerated() {
            let view = SwatchView(swatch: swatch, index: i)
            view.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            addSubview(view)
            swatches.append(view)
        }
        breathe()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let shorter = min(bounds.width, bounds.height)
        let size = min(shorter * 0.17, 150), gap = min(shorter * 0.06, 52)
        let area = bounds.inset(by: safeAreaInsets)
        let columns = 4, rows = (swatches.count + columns - 1) / columns
        let left = area.midX - (CGFloat(columns) * size + CGFloat(columns - 1) * gap) / 2
        let top = area.midY - (CGFloat(rows) * size + CGFloat(rows - 1) * gap) / 2
        for (i, view) in swatches.enumerated() {
            let col = CGFloat(i % columns), row = CGFloat(i / columns)
            // bounds + center, since the chosen swatch may be scaled.
            view.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            view.center = CGPoint(x: left + col * (size + gap) + size / 2, y: top + row * (size + gap) + size / 2)
        }
    }

    @objc private func tapped(_ sender: SwatchView) {
        onChoose?(sender.index)
    }

    /// The chosen colour grows while the others fade away.
    func leave(chosen: Int) {
        isLeaving = true
        for view in swatches { view.stopBreathing() }
        UIView.animate(withDuration: 0.7, delay: 0, options: .curveEaseInOut) {
            self.swatches[chosen].transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }
        UIView.animate(withDuration: 0.6, delay: 0, options: .curveEaseInOut) {
            for view in self.swatches where view.index != chosen { view.alpha = 0 }
        }
    }

    /// Back to eight colours, ready to choose again.
    func reset() {
        isLeaving = false
        UIView.animate(withDuration: 0.7, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            for view in self.swatches {
                view.alpha = 1
                view.transform = .identity
            }
        } completion: { _ in
            // Unless a colour was chosen again before the swatches settled.
            if !self.isLeaving { self.breathe() }
        }
    }

    private func breathe() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        for view in swatches { view.breathe() }
    }
}

final class SwatchView: UIControl {
    let index: Int
    private let shade = CAGradientLayer()

    init(swatch: Swatch, index: Int) {
        self.index = index
        super.init(frame: .zero)
        backgroundColor = UIColor(rgb: swatch.rgb)
        // A soft shadow below, and a faint shade inside the lower edge.
        layer.shadowColor = UIColor(red: 90 / 255, green: 70 / 255, blue: 50 / 255, alpha: 1).cgColor
        layer.shadowOpacity = 0.45
        layer.shadowOffset = CGSize(width: 0, height: 10)
        layer.shadowRadius = 13
        shade.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.06).cgColor]
        shade.locations = [0.62, 1]
        shade.masksToBounds = true
        layer.addSublayer(shade)

        isAccessibilityElement = true
        accessibilityLabel = swatch.name
        accessibilityIdentifier = swatch.name
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.width / 2
        layer.cornerRadius = radius
        // The shadow is inset, like CSS's negative spread, so it sits softly under the disc.
        layer.shadowPath = UIBezierPath(ovalIn: bounds.insetBy(dx: 14, dy: 14)).cgPath
        withoutAnimation {
            shade.frame = bounds
            shade.cornerRadius = radius
        }
    }

    func breathe() {
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 1
        breath.toValue = 1.05
        breath.duration = 3
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // Each swatch is a little further through its breath than the one before.
        breath.timeOffset = Double(index) * 0.75
        breath.isRemovedOnCompletion = false
        layer.add(breath, forKey: "breathe")
    }

    func stopBreathing() {
        // Hold the current size so removing the animation doesn't jump.
        let scale = (layer.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat) ?? 1
        layer.removeAnimation(forKey: "breathe")
        transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}
