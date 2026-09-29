import QuartzCore
import QuietTraceKit
import UIKit

protocol StageViewDelegate: AnyObject {
    func stageDidBeginLine(_ stage: StageView)
    func stage(_ stage: StageView, didEndLineWith verdict: Tracer.Verdict)
    func stageDidRequestExit(_ stage: StageView)
}

/// The tracing screen: the dotted guide, the child's ink, the start dot and the celebration,
/// plus the invisible grown-up exit in the top-left corner.
final class StageView: UIView {
    weak var delegate: StageViewDelegate?
    let tracer = Tracer()

    var isAccepting: Bool {
        get { tracer.isAccepting }
        set { tracer.isAccepting = newValue }
    }

    var isDrawing: Bool { tracer.isDrawing }

    private var layout = BoxLayout(width: 0, height: 0)
    private var colour = UIColor.black
    private var tint = UIColor.white

    private let art = UIView()
    private let trackLayer = CAShapeLayer()
    private let dashLayer = CAShapeLayer()
    private let sweepLayer = CAShapeLayer()
    private let ink = InkView()
    private let fxLayer = CALayer()
    private let dotLayer = CALayer()
    private let haloLayer = CAShapeLayer()
    private let coreLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private var sparkles: [CAShapeLayer] = []
    private let exitCorner = ExitCornerView()

    private var touchIDs: [ObjectIdentifier: Int] = [:]
    private var nextTouchID = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear

        art.isUserInteractionEnabled = false
        art.alpha = 0
        addSubview(art)

        for shape in [trackLayer, dashLayer, sweepLayer, glowLayer, haloLayer, coreLayer] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
        }
        trackLayer.strokeColor = Colours.track.cgColor
        dashLayer.strokeColor = Colours.dash.cgColor
        sweepLayer.opacity = 0.45
        sweepLayer.strokeEnd = 0
        glowLayer.opacity = 0
        glowLayer.shadowOpacity = 1
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = 11
        coreLayer.opacity = 0.9
        dotLayer.opacity = 0
        dotLayer.addSublayer(haloLayer)
        dotLayer.addSublayer(coreLayer)

        // Guide under the ink; start dot, glow and sparkles over it.
        art.layer.addSublayer(trackLayer)
        art.layer.addSublayer(dashLayer)
        art.layer.addSublayer(sweepLayer)
        art.addSubview(ink)
        art.layer.addSublayer(fxLayer)
        fxLayer.addSublayer(glowLayer)
        fxLayer.addSublayer(dotLayer)
        ink.tracer = tracer

        exitCorner.canStart = { [weak self] in !(self?.tracer.isDrawing ?? false) }
        exitCorner.onHold = { [weak self] in
            guard let self else { return }
            self.delegate?.stageDidRequestExit(self)
        }
        addSubview(exitCorner)

        // No words on screen, but VoiceOver users can hear what to trace and draw directly.
        isAccessibilityElement = true
        accessibilityLabel = "Tracing"
        accessibilityTraits = .allowsDirectInteraction
        accessibilityIdentifier = "stage"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // ---- layout ----

    override func layoutSubviews() {
        super.layoutSubviews()
        art.frame = bounds
        ink.frame = bounds
        let corner = CGFloat(Tuning.exitCorner)
        exitCorner.frame = CGRect(x: 0, y: 0, width: corner, height: corner)
        let next = BoxLayout(width: Double(bounds.width), height: Double(bounds.height))
        guard next != layout else { return }
        layout = next
        withoutAnimation {
            for l in [trackLayer, dashLayer, sweepLayer, fxLayer] { l.frame = bounds }
            glowLayer.frame = fxLayer.bounds
        }
        ink.setBoxTransform(layout.transform)
        drawGuide()
        ink.rebuild()
    }

    private func drawGuide() {
        let k = CGFloat(layout.unit)
        var transform = layout.transform
        let path = tracer.guide.flatMap { $0.path.copy(using: &transform) }
        withoutAnimation {
            for shape in [trackLayer, dashLayer, sweepLayer, glowLayer] { shape.path = path }
            trackLayer.lineWidth = CGFloat(Tuning.track) * k
            sweepLayer.lineWidth = CGFloat(Tuning.track) * k
            dashLayer.lineWidth = CGFloat(Tuning.dashWidth) * k
            dashLayer.lineDashPattern = Tuning.dash.map { NSNumber(value: Double($0 * Double(k))) }
            glowLayer.lineWidth = CGFloat(Tuning.ink * 0.6) * k
            glowLayer.shadowPath = path.map { $0.copy(strokingWithWidth: glowLayer.lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10) }

            if let start = tracer.guide?.start {
                dotLayer.position = layout.toScreen(start).cg
                haloLayer.path = CGPath(ellipseIn: CGRect(x: -4.4 * k, y: -4.4 * k, width: 8.8 * k, height: 8.8 * k), transform: nil)
                coreLayer.path = CGPath(ellipseIn: CGRect(x: -2.1 * k, y: -2.1 * k, width: 4.2 * k, height: 4.2 * k), transform: nil)
            }
            // Sparkles were placed for the old size; they're nearly gone anyway.
            sparkles.forEach { $0.removeFromSuperlayer() }
            sparkles = []
        }
    }

    // ---- what's on screen ----

    func setColour(_ swatch: Swatch) {
        colour = UIColor(rgb: swatch.rgb)
        tint = UIColor(rgb: swatch.tint)
        ink.colour = colour
        withoutAnimation {
            sweepLayer.strokeColor = colour.cgColor
            glowLayer.strokeColor = colour.cgColor
            glowLayer.shadowColor = colour.cgColor
            haloLayer.fillColor = colour.cgColor
            coreLayer.fillColor = colour.cgColor
        }
    }

    /// Shows a new drawing to trace (while the art is hidden).
    func load(_ guide: Guide) {
        tracer.load(guide)
        accessibilityValue = guide.drawing.name
        withoutAnimation {
            sweepLayer.removeAllAnimations()
            sweepLayer.strokeEnd = 0
            glowLayer.removeAllAnimations()
            glowLayer.opacity = 0
        }
        drawGuide()
        ink.clear()
        showDot()
    }

    func unload() {
        tracer.unload()
        accessibilityValue = nil
        withoutAnimation {
            dotLayer.removeAllAnimations()
            dotLayer.opacity = 0
            sweepLayer.removeAllAnimations()
            sweepLayer.strokeEnd = 0
            glowLayer.removeAllAnimations()
            glowLayer.opacity = 0
        }
        drawGuide()
        ink.clear()
    }

    func setArtVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.8, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.art.alpha = visible ? 1 : 0
        }
    }

    /// Stops any drawing in progress and forgets the pencil (back at the colours).
    func stopInput() {
        tracer.reset()
        exitCorner.cancel()
    }

    func forgetPen() {
        tracer.forgetPen()
    }

    // ---- the start dot: a slow, soft pulse where the first stroke begins, until drawing starts ----

    private func showDot() {
        let pulse = CAAnimationGroup()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 3.5 / 4.4
        grow.toValue = 5.3 / 4.4
        let brighten = CABasicAnimation(keyPath: "opacity")
        brighten.fromValue = 0.1
        brighten.toValue = 0.3
        pulse.animations = [grow, brighten]
        pulse.duration = 1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.isRemovedOnCompletion = false
        withoutAnimation {
            haloLayer.opacity = 0.2
            haloLayer.add(pulse, forKey: "pulse")
        }
        fadeDot(to: 1)
    }

    private func fadeDot(to opacity: Float) {
        let from = dotLayer.presentation()?.opacity ?? dotLayer.opacity
        guard from != opacity || dotLayer.opacity != opacity else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = opacity
        fade.duration = 0.8
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        withoutAnimation {
            dotLayer.opacity = opacity
            dotLayer.add(fade, forKey: "fade")
        }
    }

    // ---- finishing: the colour runs along the guide, a soft glow, and a few sparkles ----

    func celebrate() {
        guard let guide = tracer.guide else { return }
        let now = CACurrentMediaTime()

        let sweep = CABasicAnimation(keyPath: "strokeEnd")
        sweep.fromValue = 0
        sweep.toValue = 1
        sweep.duration = Tuning.sweepSeconds
        sweep.timingFunction = easeInOutQuad

        let glow = CAKeyframeAnimation(keyPath: "opacity")
        glow.values = (0...12).map { sin(Double($0) / 12 * .pi) * 0.5 }
        glow.beginTime = now + Tuning.sweepSeconds - 0.15
        glow.duration = Tuning.glowSeconds

        withoutAnimation {
            sweepLayer.strokeEnd = 1
            sweepLayer.add(sweep, forKey: "sweep")
            glowLayer.add(glow, forKey: "glow")
            for _ in 0..<16 {
                let at = guide.samples.randomElement()!
                addSparkle(at: at, begin: now + 0.3 + Double.random(in: 0..<0.6))
            }
        }
    }

    private func addSparkle(at p: Point2D, begin: CFTimeInterval) {
        let k = layout.unit
        let r = (0.8 + Double.random(in: 0..<1.3)) * k
        let drift = Point2D(x: Double.random(in: -0.5..<0.5) * 4, y: -(3 + Double.random(in: 0..<6))) * k
        let start = layout.toScreen(p)

        let sparkle = CAShapeLayer()
        sparkle.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        sparkle.fillColor = (Bool.random() ? tint : colour).cgColor
        sparkle.position = start.cg
        sparkle.opacity = 0

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(cgPoint: start.cg)
        move.toValue = NSValue(cgPoint: (start + drift).cg)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.9, 0]
        fade.keyTimes = [0, 0.2, 1]
        let life = CAAnimationGroup()
        life.animations = [move, fade]
        life.beginTime = begin
        life.duration = 1.6 + Double.random(in: 0..<0.9)
        sparkle.add(life, forKey: "life")

        fxLayer.addSublayer(sparkle)
        sparkles.append(sparkle)
    }

    // ---- touches ----

    private func kind(of touch: UITouch) -> PointerKind {
        switch touch.type {
        case .pencil: return .pen
        case .indirectPointer: return .mouse
        default: return .touch
        }
    }

    private func sample(_ touch: UITouch) -> PointerSample {
        let p = touch.preciseLocation(in: self)
        // A force of 1 is an average press; the web app's pressure of 0.5 means the same.
        let pressure = touch.type == .pencil ? min(1, Double(touch.force) / 2) : 0
        return PointerSample(layout.toBox(x: Double(p.x), y: Double(p.y)), pressure: pressure)
    }

    private func didBegin() {
        // A hand steadying the iPad at the corner shouldn't end the game mid-line.
        exitCorner.cancel()
        fadeDot(to: 0)
        delegate?.stageDidBeginLine(self)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch.type == .indirectPointer, let mask = event?.buttonMask, !mask.contains(.primary) { continue }
            let id = nextTouchID
            nextTouchID += 1
            touchIDs[ObjectIdentifier(touch)] = id
            let result = tracer.down(id: id, kind: kind(of: touch), sample: sample(touch), time: touch.timestamp)
            guard case .began(let dropped) = result else { continue }
            if dropped { ink.liveRestarted() } else { ink.liveExtended(from: 0) }
            didBegin()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let id = touchIDs[ObjectIdentifier(touch)] else { continue }
            let readings = event?.coalescedTouches(for: touch) ?? [touch]
            let result = tracer.move(id: id, kind: kind(of: touch), latest: sample(touch),
                                     samples: readings.map(sample), time: touch.timestamp)
            switch result {
            case .ignored:
                continue
            case .extended(let from):
                ink.liveExtended(from: from)
            case .restarted:
                ink.liveRestarted()
                didBegin()
            }
            if tracer.activeID == id, let width = tracer.liveLine?.points.last?.width {
                let ahead = event?.predictedTouches(for: touch) ?? []
                ink.setPredicted(ahead.map {
                    let p = sample($0).location
                    return InkPoint(x: p.x, y: p.y, width: width)
                })
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let id = touchIDs.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            let line = tracer.liveLine
            let result = tracer.up(id: id, kind: kind(of: touch), time: touch.timestamp)
            guard case .ended(let verdict) = result else { continue }
            if let line { ink.commit(line) }
            delegate?.stage(self, didEndLineWith: verdict)
        }
    }
}
