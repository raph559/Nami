import CoreText
import SwiftUI

enum SubtitleFont: String, CaseIterable, Identifiable {
    case standard, nami, legible, serif
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .nami: "Nami"
        case .legible: t("Lisible", "Legible")
        case .serif: t("Classique", "Classic")
        }
    }

    /// The family mpv asks libass for. The three named ones ship with Nami.
    var mpvName: String {
        switch self {
        case .standard: "sans-serif"
        case .nami: "Hanken Grotesk"
        case .legible: "Atkinson Hyperlegible"
        case .serif: "PT Serif"
        }
    }

    /// The font Settings draws the preview with.
    func font(size: CGFloat) -> Font {
        SubtitleFonts.registerForPreview()
        switch self {
        case .standard: return .system(size: size, weight: .semibold)
        case .nami: return .custom("HankenGrotesk-Bold", fixedSize: size)
        case .legible: return .custom("AtkinsonHyperlegible-Bold", fixedSize: size)
        case .serif: return .custom("PTSerif-Bold", fixedSize: size)
        }
    }
}

enum SubtitleColor: String, CaseIterable, Identifiable {
    case white, yellow
    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: t("Blanc", "White")
        case .yellow: t("Jaune", "Yellow")
        }
    }

    var hex: String { self == .white ? "#FFFFFF" : "#FFE14D" }
    var color: Color { self == .white ? .white : Color(red: 1, green: 0xE1 / 255, blue: 0x4D / 255) }
}

enum SubtitleOutline: String, CaseIterable, Identifiable {
    case none, thin, thick
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: t("Aucun", "None")
        case .thin: t("Fin", "Thin")
        case .thick: t("Épais", "Thick")
        }
    }

    /// mpv's sub-border-size, in pixels of a 720-line screen. Thick is mpv's own default.
    var size: Double {
        switch self {
        case .none: 0
        case .thin: 1.5
        case .thick: 3
        }
    }
}

/// How subtitles look. Subtitles that bring their own design (ASS) keep it, apart
/// from the size, unless `force` is on. Same keys as the @AppStorage in Settings.
struct SubtitleStyle: Equatable {
    var size = 100
    var font = SubtitleFont.standard
    var color = SubtitleColor.white
    var outline = SubtitleOutline.thick
    /// A dark box behind the text.
    var box = false
    /// How far above the bottom, from 0 (mpv's usual place) to 100.
    var lift = 0
    var force = false

    static let maxLift = 100

    static var current: SubtitleStyle {
        let d = UserDefaults.standard
        return SubtitleStyle(
            size: d.object(forKey: "subtitleSize") as? Int ?? 100,
            font: SubtitleFont(rawValue: d.string(forKey: "subtitleFont") ?? "") ?? .standard,
            color: SubtitleColor(rawValue: d.string(forKey: "subtitleColor") ?? "") ?? .white,
            outline: SubtitleOutline(rawValue: d.string(forKey: "subtitleOutline") ?? "") ?? .thick,
            box: d.bool(forKey: "subtitleBox"),
            lift: min(max(d.integer(forKey: "subtitleLift"), 0), maxLift),
            force: d.bool(forKey: "subtitleForce"))
    }

    /// mpv's bottom margin, in pixels of a 720-line screen; 22 is mpv's default.
    var marginY: Int { 22 + lift * 2 }

    /// The mpv settings for the subtitle being shown. `styled` says it is an ASS
    /// subtitle with its own design.
    func mpv(styled: Bool) -> [(String, String)] {
        let mine = force || !styled
        return [
            ("sub-scale", String(Double(size) / 100)),
            ("sub-font", font.mpvName),
            ("sub-color", color.hex),
            ("sub-border-size", String(outline.size)),
            ("sub-margin-y", String(marginY)),
            ("sub-ass-override", force ? "force" : "scale"),
            // libass's opaque box, coloured with the outline colour, the same way as
            // on Android and Windows. Never on a design kept as is.
            ("sub-ass-style-overrides", box && mine ? "BorderStyle=3,Outline=3,Shadow=0,OutlineColour=&H60000000" : ""),
        ]
    }
}

/// The subtitle fonts, shipped in the app for mpv.
enum SubtitleFonts {
    static var directory: String? { Bundle.module.url(forResource: "SubtitleFonts", withExtension: nil)?.path }

    private static var registered = false

    /// SwiftUI only finds a bundled font once it is registered.
    static func registerForPreview() {
        guard !registered, let dir = directory else { return }
        registered = true
        for name in ["HankenGrotesk-Bold", "AtkinsonHyperlegible-Bold", "PTSerif-Bold"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).ttf")
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// A line of subtitle over a dark scene, drawn the way `style` says, for Settings.
struct SubtitlePreview: View {
    let style: SubtitleStyle

    var body: some View {
        GeometryReader { geo in
            // Sizes follow mpv's: 55 px text and the margin on a 720-line screen.
            let unit = geo.size.height / 720
            let size = 55 * unit * CGFloat(style.size) / 100
            let text = Text(t("On se retrouve demain, au même endroit.", "See you tomorrow, same place."))
                .font(style.font.font(size: size))
                .multilineTextAlignment(.center)
            let stroke = style.outline.size * unit
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(red: 0.23, green: 0.29, blue: 0.36), Color(red: 0.48, green: 0.35, blue: 0.28),
                                        Color(red: 0.11, green: 0.12, blue: 0.15)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                ZStack {
                    if !style.box && stroke > 0 {
                        // An outline made of shadows, close to libass's border.
                        text.foregroundStyle(.black)
                            .shadow(color: .black, radius: 0, x: stroke, y: 0).shadow(color: .black, radius: 0, x: -stroke, y: 0)
                            .shadow(color: .black, radius: 0, x: 0, y: stroke).shadow(color: .black, radius: 0, x: 0, y: -stroke)
                    }
                    text.foregroundStyle(style.color.color)
                }
                .padding(.horizontal, style.box ? 6 * unit : 0)
                .padding(.vertical, style.box ? 3 * unit : 0)
                .background(style.box ? Color.black.opacity(0.62) : .clear)
                .padding(.horizontal, 24 * unit)
                .padding(.bottom, CGFloat(style.marginY) * unit)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}
