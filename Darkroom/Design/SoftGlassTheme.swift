//
//  SoftGlassTheme.swift
//  Darkroom
//
//  THE MAIN THEME — SOFT LIGHT.
//
//  The field is one continuous mesh gradient, built from the reference art:
//  mint at the top-left, a warm grey along the top, olive at the right edge, a
//  rose-magenta core through the middle, and lilac and rust pooling along the
//  foot. The hue relationships are the reference's, not a hue of them is
//  invented — what is changed is the luminance, because this language writes
//  every word in white. Each stop is held below a relative luminance of about
//  0.10, which keeps white ink at 7:1 or better wherever it lands.
//
//  On top of the field sit two very different kinds of surface — white capsules
//  with black ink for anything you can press, and saturated gradient tiles for
//  anything you only need to read. The tiles carry the reference cards' own
//  ramps: hot pink into magenta, mint into forest, lilac into plum, orange into
//  rust, each lit from one corner rather than shaded evenly.
//

import SwiftUI

enum SoftGlassTheme {
    // MARK: Field

    /// The field is black, as the reference screens are: colour lives in the
    /// cards and the control glows, never in the plane behind them.
    static let background = Color(red: 0.023, green: 0.023, blue: 0.028)
    static let backgroundLift = Color(red: 0.075, green: 0.075, blue: 0.086)

    // MARK: Ink

    static let ink = Color.white.opacity(0.97)
    static let inkSoft = Color.white.opacity(0.62)
    static let inkFaint = Color.white.opacity(0.36)
    static let hairline = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.14)
    static let surface = Color.white.opacity(0.05)
    static let surfaceRaised = Color.white.opacity(0.09)

    // MARK: Controls
    //
    // In this language the "accent" is simply white: a solid white capsule with
    // black ink is the only loud thing on the screen, so the colour underneath
    // stays the subject.

    static let amber = Color.white
    static let amberSoft = Color(red: 0.99, green: 0.99, blue: 1.0)
    static let amberDeep = Color(white: 0.80)
    static let amberInk = Color.black

    // MARK: Chroma
    //
    // Sampled from the reference: the hot pink of its radial glow, the magenta
    // at that glow's core, the mint wash over the first screen, the olive at
    // the right of the field, the rust of its warmest card.

    static let pink = Color(red: 0.941, green: 0.435, blue: 0.690)     // #F06FB0
    static let magenta = Color(red: 0.878, green: 0.098, blue: 0.498)  // #E0197F
    static let violet = Color(red: 0.784, green: 0.478, blue: 0.918)   // #C87AEA
    static let lilac = Color(red: 0.780, green: 0.651, blue: 0.878)    // #C7A6E0
    static let blue = Color(red: 0.290, green: 0.420, blue: 0.878)     // #4A6BE0
    static let mint = Color(red: 0.608, green: 0.851, blue: 0.706)     // #9BD9B4
    static let forest = Color(red: 0.212, green: 0.376, blue: 0.259)   // #366042
    static let olive = Color(red: 0.604, green: 0.604, blue: 0.235)    // #9A9A3C
    static let orange = Color(red: 0.851, green: 0.384, blue: 0.180)   // #D9622E
    static let lime = Color(red: 0.776, green: 0.878, blue: 0.290)     // #C6E04A
    static let peach = Color(red: 0.949, green: 0.639, blue: 0.478)    // #F2A37A

    // MARK: Shape
    //
    // Cards and controls are oversized and soft. Nothing in this language is square.

    static let cardRadius: CGFloat = 32
    static let controlRadius: CGFloat = 26
    static let tileRadius: CGFloat = 26

    // MARK: Fills

    /// The white capsule ramp. Kept almost flat on purpose: a white button with a
    /// hard gradient reads as plastic.
    static let amberGradient = LinearGradient(
        colors: [amberSoft, amber, amberDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let panelGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.085),
            Color.white.opacity(0.028),
            Color.black.opacity(0.26)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The reference's strongest card: hot pink at the top-left, magenta at the
    /// foot. This is the tile the radial glow sits behind.
    static let pinkGradient = LinearGradient(
        colors: [pink, magenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The "average" tile: lilac paper into plum violet.
    static let magentaGradient = LinearGradient(
        colors: [lilac, Color(red: 0.408, green: 0.220, blue: 0.580)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The "vitamin" tile: violet into a deep indigo.
    static let violetGradient = LinearGradient(
        colors: [violet, Color(red: 0.310, green: 0.196, blue: 0.612)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The blue tile: a lit royal blue falling to navy.
    static let blueGradient = LinearGradient(
        colors: [Color(red: 0.420, green: 0.553, blue: 0.949), Color(red: 0.106, green: 0.157, blue: 0.518)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The cool tile: mint wash into forest, the green of the first reference screen.
    static let mintGradient = LinearGradient(
        colors: [mint, forest],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The warm tile: amber orange into rust.
    static let orangeGradient = LinearGradient(
        colors: [Color(red: 0.894, green: 0.494, blue: 0.204), Color(red: 0.620, green: 0.192, blue: 0.110)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The olive tile: lime into the field's own olive.
    static let limeGradient = LinearGradient(
        colors: [lime, Color(red: 0.435, green: 0.541, blue: 0.157)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The quiet tile: deep forest into olive, for figures that are not the point.
    static let forestGradient = LinearGradient(
        colors: [Color(red: 0.157, green: 0.259, blue: 0.176), Color(red: 0.322, green: 0.435, blue: 0.196)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Ambient field

    /// The lamp chosen in Appearance, brought into this language. Controls stay
    /// white — that is the language — but the field is lit by the palette.
    static var accent: Color { Preferences.shared.accent.base }

    /// Black, with the chosen lamp bleeding in only at the very edges: a wash of
    /// its soft light at the foot-left, its bloom at the foot-right, and its base
    /// at the top. Everything on the screen still sits on near-black, the way the
    /// reference screens do — only the light in the room changes with the palette.
    static func backdrop(intensity: Double = 1.0) -> some View {
        let lamp = Preferences.shared.accent

        return ZStack {
            Rectangle()
                .fill(Color(red: 0.020, green: 0.020, blue: 0.024))

            bloom(color: lamp.soft, opacity: 0.10 * intensity, size: 620, blur: 82)
                .offset(x: -160, y: 390)

            bloom(color: lamp.bloom, opacity: 0.13 * intensity, size: 660, blur: 84)
                .offset(x: 190, y: 410)

            bloom(color: lamp.base, opacity: 0.07 * intensity, size: 520, blur: 84)
                .offset(x: 40, y: -380)

            // A light hand at both ends so the chrome's own fades have somewhere
            // to land — deep enough to settle the field, never a band.
            LinearGradient(
                colors: [background.opacity(0.45), Color.clear, background.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private static func bloom(color: Color, opacity: Double, size: CGFloat, blur: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(opacity),
                        color.opacity(opacity * 0.34),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .blur(radius: blur)
    }

    // MARK: Card ramps

    /// A card ramp for any accent colour: the accent lit at its top-left, a
    /// deepened shade of the same hue at the foot. The reference's tiles are
    /// always two tones of one hue, lit from a corner.
    static func ramp(for accent: Color) -> LinearGradient {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(accent).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let lit = Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation, 0.35), 0.85)),
            brightness: Double(min(max(brightness, 0.55), 0.85))
        )
        let deep = Color(
            hue: Double(hue),
            saturation: Double(min(saturation + 0.08, 1.0)),
            brightness: Double(max(brightness * 0.42, 0.16))
        )
        return LinearGradient(colors: [lit, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The ramp a library row wears, picked from the chosen palette by the
    /// record's key, so a given film always wears the same tile.
    static func rowGradient(for key: String) -> LinearGradient {
        let lamp = Preferences.shared.accent
        let ramps = [ramp(for: lamp.base), ramp(for: lamp.bloom), ramp(for: lamp.soft), ramp(for: lamp.deep)]
        var hash: UInt64 = 5381
        for scalar in key.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        return ramps[Int(hash % UInt64(ramps.count))]
    }
}
