import AVFoundation
import QuietTraceKit

/// Plays the one soft chime per finished drawing. The chimes are synthesised once at launch
/// (see `Chime`), and the audio session is "ambient", so the chime follows the silent switch
/// and never interrupts other audio.
///
/// Everything touching audio runs on its own queue: starting the audio hardware can take a
/// moment, and the celebration on screen shouldn't wait for it.
final class ChimePlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "QuietTrace.chime", qos: .userInitiated)
    // Only touched on `queue`.
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffers: [AVAudioPCMBuffer] = []
    private var rest: DispatchWorkItem?

    init() {
        queue.async { self.setUp() }
    }

    func play() {
        queue.async { self.playNow() }
    }

    private func setUp() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffers = (0..<Chime.variations).compactMap { variation in
            let samples = Chime.render(variation: variation, sampleRate: format.sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return nil }
            for (i, s) in samples.enumerated() { channel[i] = s }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            return buffer
        }
        self.engine = engine
        self.player = player
    }

    private func playNow() {
        guard let engine, let player, let buffer = buffers.randomElement() else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()

        // Let the audio hardware rest once the echo has faded.
        rest?.cancel()
        let work = DispatchWorkItem {
            player.stop()
            engine.stop()
        }
        rest = work
        queue.asyncAfter(deadline: .now() + Chime.duration + 1, execute: work)
    }
}
