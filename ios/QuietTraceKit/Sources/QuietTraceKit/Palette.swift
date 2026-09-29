/// A colour the child can choose.
public struct Swatch: Equatable, Sendable {
    /// Spoken by VoiceOver; never shown.
    public let name: String
    /// 0xRRGGBB
    public let rgb: UInt32

    /// The lighter shade used for half of the sparkles.
    public var tint: UInt32 { Palette.mix(rgb, 0xFFFFFF, 0.55) }
}

/// Warm paper tones and eight soft colours, as in the web app.
public enum Palette {
    public static let swatches: [Swatch] = [
        Swatch(name: "rose", rgb: 0xF28B9B), Swatch(name: "peach", rgb: 0xF6A96B),
        Swatch(name: "sunflower", rgb: 0xF2C94C), Swatch(name: "mint", rgb: 0x6FCF97),
        Swatch(name: "sky", rgb: 0x56CCF2), Swatch(name: "ocean", rgb: 0x5B8DEF),
        Swatch(name: "lavender", rgb: 0xA98BEA), Swatch(name: "berry", rgb: 0xD16BA5),
    ]

    public static let paper: UInt32 = 0xFAF6EF
    public static let track: UInt32 = 0xEFE8DD
    public static let dash: UInt32 = 0xCDC3B4

    /// Mixes two 0xRRGGBB colours: t = 0 gives `a`, t = 1 gives `b`.
    public static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        var out: UInt32 = 0
        for shift in [16, 8, 0] as [UInt32] {
            let ca = Double((a >> shift) & 0xFF), cb = Double((b >> shift) & 0xFF)
            out |= UInt32((ca + (cb - ca) * t).rounded()) << shift
        }
        return out
    }
}
