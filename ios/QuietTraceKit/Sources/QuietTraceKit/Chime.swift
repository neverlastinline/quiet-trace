import Foundation

/// One soft chime per finished drawing: two bell notes from the C major pentatonic
/// (so any two sound gentle together) with a soft echo, like a small room.
/// A sample-for-sample rendering of the web app's Web Audio graph.
public enum Chime {
    public static let notes: [Double] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]

    /// Number of different chimes: the first note can be any but the top two.
    public static var variations: Int { notes.count - 2 }

    /// Seconds of audio `render` produces, echo tail included.
    public static let duration = 5.0

    /// Mono samples in -1...1 for chime number `variation`.
    public static func render(variation: Int, sampleRate: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        var dry = [Double](repeating: 0, count: count)
        let i = min(max(variation, 0), variations - 1)
        bell(notes[i], at: 0, peak: 0.1, into: &dry, sampleRate: sampleRate)
        bell(notes[i + 2], at: 0.16, peak: 0.07, into: &dry, sampleRate: sampleRate)

        // Echo: a 0.3 s delay whose output is softened (low-pass at 1600 Hz), fed back at 0.3
        // and mixed in at 0.35.
        let delay = max(1, Int(0.3 * sampleRate))
        var line = [Double](repeating: 0, count: delay)
        var damp = LowPass(cutoff: 1600, qDecibels: 1, sampleRate: sampleRate)
        var out = [Float](repeating: 0, count: count)
        var head = 0
        for n in 0..<count {
            let echo = damp.process(line[head])
            out[n] = Float(dry[n] + 0.35 * echo)
            line[head] = dry[n] + 0.3 * echo
            head = head + 1 == delay ? 0 : head + 1
        }

        // A short fade so the (by now silent) tail can't click.
        let fade = min(count, Int(0.05 * sampleRate))
        for k in 0..<fade {
            out[count - 1 - k] *= Float(k) / Float(fade)
        }
        return out
    }

    /// A bell: a sine and two quieter overtones, each rising in 20 ms and dying away
    /// exponentially (higher overtones die sooner).
    static func bell(_ freq: Double, at start: Double, peak: Double, into buffer: inout [Double], sampleRate: Double) {
        let floor = 0.0001, attack = 0.02
        for (mult, share) in [(1.0, 1.0), (2.0, 0.25), (3.0, 0.08)] {
            let top = peak * share
            let length = 2.5 / mult
            let first = Int(start * sampleRate)
            let last = min(buffer.count, Int((start + length + 0.05) * sampleRate))
            guard first < last else { continue }
            let omega = 2 * Double.pi * freq * mult / sampleRate
            for n in first..<last {
                let t = Double(n) / sampleRate - start
                let gain: Double
                if t < attack {
                    gain = floor * pow(top / floor, t / attack)
                } else if t < length {
                    gain = top * pow(floor / top, (t - attack) / (length - attack))
                } else {
                    gain = floor
                }
                buffer[n] += gain * sin(omega * Double(n - first))
            }
        }
    }
}

/// A standard (RBJ cookbook) low-pass biquad; Q is in decibels, as in Web Audio.
struct LowPass {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(cutoff: Double, qDecibels: Double, sampleRate: Double) {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(w0) / (2 * pow(10, qDecibels / 20))
        let cosw = cos(w0)
        let a0 = 1 + alpha
        b0 = (1 - cosw) / 2 / a0
        b1 = (1 - cosw) / a0
        b2 = (1 - cosw) / 2 / a0
        a1 = -2 * cosw / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}
