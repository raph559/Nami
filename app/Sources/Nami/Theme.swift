import SwiftUI
import UIKit

/// The "Salle obscure" tokens shared with the Android and Windows app (DESIGN.md).
enum Nami {
    static let ground = Color(hex: "#0A0A0B")!
    static let text = Color(hex: "#EDEAE4")!
    static let textSecondary = Color(hex: "#B8B3AA")!
    static let textMuted = Color(hex: "#8F8B83")!
    /// Amber for cautions (10:1 on the cards); always next to an icon and words.
    static let warning = Color(hex: "#F2C14E")!
    /// Card surface on the sources sheet.
    static let card = Color(hex: "#1B1B1E")!
    /// Control borders: text at 45 %, 3.9:1 on the ground.
    static let border = text.opacity(0.45)

    /// The anime's color, lightened until text in it reaches 4.5:1 on the ground.
    static func accent(_ hex: String?) -> Color {
        var c = UIColor(Color(hex: hex) ?? text)
        let ground = UIColor(Nami.ground)
        for _ in 0..<20 where contrast(c, ground) < 4.5 {
            c = blend(c, .white, 0.12)
        }
        return Color(c)
    }

    private static func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { v <= 0.03928 ? Double(v) / 12.92 : pow((Double(v) + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}
