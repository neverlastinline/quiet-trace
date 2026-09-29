import QuietTraceKit
import UIKit

/// The whole game: pick a colour, then trace one thing after another, for as long as you like.
final class GameViewController: UIViewController, StageViewDelegate {
    private enum Phase {
        case picking, changing, tracing, celebrating
    }

    private var phase = Phase.picking
    private let picker = PickerView()
    private let stage = StageView()
    private var items = ItemPicker(rng: SystemRandomNumberGenerator())
    private var guides: [Drawing: Guide] = [:]
    private let chime = ChimePlayer()

    private var scheduled: [Int: Task<Void, Never>] = [:]
    private var nextTaskKey = 0
    private var idleWait: Task<Void, Never>?

    /// UI tests can choose the first drawing: `-QuietTraceFirst shapes/square`.
    private var firstDrawing: Drawing? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-QuietTraceFirst"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: "/").map(String.init)
        guard parts.count == 2, let category = DrawingCategory(rawValue: parts[0]) else { return nil }
        return Library.drawing(category, parts[1])
        #else
        return nil
        #endif
    }()

    // Full screen, nothing to tap by accident: no status bar, the home indicator fades away, and
    // a swipe from any edge needs a second swipe before the system takes over.
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = Colours.paper
        for screen in [stage, picker] {
            screen.frame = root.bounds
            screen.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            root.addSubview(screen)
        }
        stage.alpha = 0
        stage.isHidden = true
        stage.isUserInteractionEnabled = false
        stage.delegate = self
        picker.onChoose = { [weak self] index in self?.choose(index) }
        view = root
    }

    /// A new session always accepts fingers again.
    func didEnterBackground() {
        stage.forgetPen()
    }

    // ---- colours ----

    private func choose(_ index: Int) {
        guard phase == .picking else { return }
        phase = .changing
        stage.setColour(Palette.swatches[index])
        picker.leave(chosen: index)
        later(0.65) { [weak self] in
            guard let self else { return }
            self.crossfade(from: self.picker, to: self.stage)
        }
        later(1.15) { [weak self] in
            self?.nextDrawing()
            self?.stage.setArtVisible(true)
        }
    }

    private func backToPicker() {
        cancelScheduled()
        idleWait?.cancel()
        phase = .picking
        stage.stopInput()
        stage.setArtVisible(false)
        picker.reset()
        crossfade(from: stage, to: picker)
        later(0.8) { [weak self] in self?.stage.unload() }
    }

    private func crossfade(from old: UIView, to new: UIView) {
        new.isHidden = false
        new.isUserInteractionEnabled = true
        old.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.7, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            old.alpha = 0
            new.alpha = 1
        } completion: { _ in
            if old.alpha == 0 { old.isHidden = true }
        }
    }

    // ---- tracing ----

    private func nextDrawing() {
        var drawing = items.next()
        if let first = firstDrawing {
            firstDrawing = nil
            drawing = first
            items.noteShown(first)
        }
        guard let guide = measured(drawing) else { return nextDrawing() }
        stage.load(guide)
        phase = .tracing
        stage.isAccepting = true
    }

    private func measured(_ drawing: Drawing) -> Guide? {
        if let guide = guides[drawing] { return guide }
        let guide = try? Guide(drawing)
        guides[drawing] = guide
        return guide
    }

    func stageDidBeginLine(_ stage: StageView) {
        idleWait?.cancel()
        idleWait = nil
    }

    func stage(_ stage: StageView, didEndLineWith verdict: Tracer.Verdict) {
        guard phase == .tracing else { return }
        switch verdict {
        case .finishNow:
            later(0.25) { [weak self] in self?.celebrate() }
        case .finishIfIdle:
            idleWait?.cancel()
            idleWait = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Tuning.idleSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.celebrate()
            }
        case .keepGoing:
            break
        }
    }

    func stageDidRequestExit(_ stage: StageView) {
        backToPicker()
    }

    private func celebrate() {
        // Mid-line, wait: lifting the pencil will ask again.
        guard phase == .tracing, !stage.isDrawing else { return }
        phase = .celebrating
        stage.isAccepting = false
        idleWait?.cancel()
        chime.play()
        stage.celebrate()
        later(Tuning.holdSeconds) { [weak self] in self?.stage.setArtVisible(false) }
        later(Tuning.holdSeconds + Tuning.fadeSeconds) { [weak self] in
            self?.nextDrawing()
            self?.stage.setArtVisible(true)
        }
    }

    // ---- timing ----

    private func later(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        let key = nextTaskKey
        nextTaskKey += 1
        scheduled[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.scheduled[key] = nil
            action()
        }
    }

    private func cancelScheduled() {
        scheduled.values.forEach { $0.cancel() }
        scheduled = [:]
    }
}
