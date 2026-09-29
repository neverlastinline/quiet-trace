import AVFoundation
import QuietTraceKit

/// Plays the one soft chime per finished drawing. The chimes are synthesised once at launch
/// (see `Chime`), and the audio session is "ambient", so the chime follows the silent switch
/// and never interrupts other audio.
final class ChimePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var buffers: [AVAudioPCMBuffer] = []
    private var rest: DispatchWorkItem?

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let sampleRate = format.sampleRate
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let chimes = (0..<Chime.variations).map { Chime.render(variation: $0, sampleRate: sampleRate) }
            DispatchQueue.main.async { self?.store(chimes) }
        }
    }

    private func store(_ chimes: [[Float]]) {
        buffers = chimes.compactMap { samples in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return nil }
            for (i, s) in samples.enumerated() { channel[i] = s }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            return buffer
        }
    }

    func play() {
        guard let buffer = buffers.randomElement() else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()

        // Let the audio hardware rest once the echo has faded.
        rest?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.player.stop()
            self?.engine.stop()
        }
        rest = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Chime.duration + 1, execute: work)
    }
}
