import QuartzCore
import QuietTraceKit
import UIKit

extension UIColor {
    /// From 0xRRGGBB.
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

enum Colours {
    static let paper = UIColor(rgb: Palette.paper)
    static let track = UIColor(rgb: Palette.track)
    static let dash = UIColor(rgb: Palette.dash)
}

extension Point2D {
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

extension BoxLayout {
    /// Box units → screen points.
    var transform: CGAffineTransform {
        CGAffineTransform(a: CGFloat(unit), b: 0, c: 0, d: CGFloat(unit), tx: CGFloat(originX), ty: CGFloat(originY))
    }
}

extension Guide {
    /// Every stroke as one path, in box units.
    var path: CGPath {
        let path = CGMutablePath()
        for stroke in strokes {
            for op in stroke.ops {
                switch op {
                case .move(let p): path.move(to: p.cg)
                case .line(let p): path.addLine(to: p.cg)
                case .quad(let c, let p): path.addQuadCurve(to: p.cg, control: c.cg)
                case .cubic(let c1, let c2, let p): path.addCurve(to: p.cg, control1: c1.cg, control2: c2.cg)
                case .close: path.closeSubpath()
                }
            }
        }
        return path
    }
}

/// Changes layer properties at once, without Core Animation's implicit quarter-second animation.
func withoutAnimation(_ changes: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    changes()
    CATransaction.commit()
}

/// easeInOutQuad, the curve the web app's colour sweep uses.
let easeInOutQuad = CAMediaTimingFunction(controlPoints: 0.455, 0.03, 0.515, 0.955)
