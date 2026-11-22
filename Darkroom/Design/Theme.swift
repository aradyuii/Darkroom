//
//  Theme.swift
//  Darkroom
//
//  The shared visual language. Every token resolves to the darkroom defaults, or
//  to the main theme's soft-glass values while Soft Light is on.
//

import SwiftUI

enum DarkroomThemeDefaults {
    static let base = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let baseLift = Color(red: 0.072, green: 0.078, blue: 0.088)

    static let amber = Color(red: 0.976, green: 0.667, blue: 0.196)
    static let amberSoft = Color(red: 1.0, green: 0.812, blue: 0.494)
    static let amberDeep = Color(red: 0.839, green: 0.463, blue: 0.098)
    static let amberInk = Color(red: 0.106, green: 0.075, blue: 0.020)

    static let ink = Color.white.opacity(0.94)
    static let inkSoft = Color.white.opacity(0.64)
    static let inkFaint = Color.white.opacity(0.38)
    static let hairline = Color.white.opacity(0.09)
    static let border = Color.white.opacity(0.12)
    static let raised = Color.white.opacity(0.06)
}

enum Theme {
    private static var store: AppearanceStore { .shared }

    /// True while Soft Light, the main theme, owns the interface.
    static var isSoft: Bool { store.isSoftGlassActive }

    // MARK: Fields

    static var base: Color {
        isSoft ? SoftGlassTheme.background : DarkroomThemeDefaults.base
    }

    static var baseLift: Color {
        isSoft ? SoftGlassTheme.backgroundLift : DarkroomThemeDefaults.baseLift
    }

    static var surfaceRaised: Color {
        isSoft ? SoftGlassTheme.surfaceRaised : DarkroomThemeDefaults.raised
    }

    // MARK: Inks

    static var ink: Color {
        isSoft ? SoftGlassTheme.ink : DarkroomThemeDefaults.ink
    }

    static var inkSoft: Color {
        isSoft ? SoftGlassTheme.inkSoft : DarkroomThemeDefaults.inkSoft
    }

    static var inkFaint: Color {
        isSoft ? SoftGlassTheme.inkFaint : DarkroomThemeDefaults.inkFaint
    }

    static var hairline: Color {
        isSoft ? SoftGlassTheme.hairline : DarkroomThemeDefaults.hairline
    }

    static var border: Color {
        isSoft ? SoftGlassTheme.border : DarkroomThemeDefaults.border
    }

    // MARK: Accents

    static var amber: Color {
        isSoft ? SoftGlassTheme.amber : Preferences.shared.accent.base
    }

    static var amberSoft: Color {
        isSoft ? SoftGlassTheme.amberSoft : Preferences.shared.accent.soft
    }

    static var amberDeep: Color {
        isSoft ? SoftGlassTheme.amberDeep : Preferences.shared.accent.deep
    }

    /// Ink that sits on top of the accent block.
    static var amberInk: Color {
        isSoft ? SoftGlassTheme.amberInk : Preferences.shared.accent.ink
    }

    static var accentWash: Color {
        isSoft ? SoftGlassTheme.amber.opacity(0.14) : Preferences.shared.accent.base.opacity(0.13)
    }

    /// The track a switch takes when it is on. White is the soft-glass signal
    /// for *pressable*, not for *on*: a white track around a white knob reads
    /// as one blank pill, so the switch takes a quieter grey there.
    static var switchTint: Color {
        isSoft ? Color(white: 0.58) : Preferences.shared.accent.base
    }

    /// Decorative blooms. Soft Light pools the chosen lamp's own two lights, so
    /// the field carries a gradient instead of one flat wash.
    static var magenta: Color {
        isSoft ? Preferences.shared.accent.bloom : Preferences.shared.accent.deep
    }

    static var mint: Color {
        Preferences.shared.accent.soft
    }

    // MARK: Fills

    static var amberGradient: LinearGradient {
        if isSoft { return SoftGlassTheme.amberGradient }
        let accent = Preferences.shared.accent
        return LinearGradient(
            colors: [accent.soft, accent.base, accent.deep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var panelGradient: LinearGradient {
        if isSoft { return SoftGlassTheme.panelGradient }
        return LinearGradient(
            colors: [Color.white.opacity(0.10), Color.white.opacity(0.028), Color.black.opacity(0.24)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension Font {
    /// Tabular figures — every number in the app uses this so digits never jump.
    static func figures(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}
