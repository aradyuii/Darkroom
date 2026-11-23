//
//  ThemeStore.swift
//  Darkroom
//
//  The app's two interfaces and the density they are drawn at. Soft Light is the
//  main theme and the one a fresh install opens in; Darkroom is the alternative.
//  Both are drawn by the app's own screens and lit by the palette chosen in
//  Preferences — a theme never changes what the app does, only how it is shown.
//

import SwiftUI

// MARK: - The themes

/// The two interfaces the app ships with, in the order Appearance lists them.
/// The first is the main theme and the default.
enum ThemeChoice: String, CaseIterable, Identifiable {
    /// The main theme: a black field, white capsules for anything you can press,
    /// and colour cards for the figures.
    case softLight = "softLight"

    /// The alternative: frosted panels, a capsule dock and a lit bench. Its raw
    /// value is the one earlier builds stored for it, so it is kept.
    case darkroom = "liquidGlass"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .softLight: return "Soft Light"
        case .darkroom: return "Darkroom"
        }
    }

    /// Where the theme sits in the app: the one it opens in, or the other one.
    var role: String {
        switch self {
        case .softLight: return "Main theme"
        case .darkroom: return "Alternative theme"
        }
    }

    var glyph: String {
        switch self {
        case .softLight: return "circle.grid.2x2.fill"
        case .darkroom: return "circle.hexagongrid.fill"
        }
    }

    var tagline: String {
        switch self {
        case .softLight: return "White capsules, colour cards"
        case .darkroom: return "Frosted glass, a lit bench"
        }
    }

    var detail: String {
        switch self {
        case .softLight:
            return "A black field lit by your palette, white capsules for anything you can press, and colour cards for the figures."
        case .darkroom:
            return "The app's original interface: frosted panels, a capsule dock and a lit bench behind everything."
        }
    }

    var isSoftLight: Bool { self == .softLight }
}

// MARK: - Density

/// How much room the interface takes. Compact also shortens the native controls.
enum InterfaceDensity: String, CaseIterable, Identifiable {
    case compact
    case regular
    case spacious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .spacious: return "Spacious"
        }
    }
}

// MARK: - Store

/// The one theme choice and the density it is drawn at. Every write persists and
/// publishes, so the app root re-dresses as soon as the choice changes.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let choice = "designLanguage.language"
        static let density = "designLanguage.density"
        /// Earlier builds kept Soft Glass in its own store. Read once, then removed.
        static let legacySoftGlass = "appearance.language"
        /// Earlier builds kept compact controls as a separate switch, which was
        /// folded into density. Read once, then removed.
        static let retiredCompact = "appearance.compactControls"
        /// Set once, when Soft Light became the main theme. An install that was
        /// on Darkroom, or on one of the themes this build no longer ships, opens
        /// on the main theme one time; a later choice of Darkroom sticks.
        static let migratedToSoftLight = "themes.migratedToSoftLight"
    }

    @Published private(set) var selected: ThemeChoice
    @Published private(set) var density: InterfaceDensity

    private init() {
        let stored = defaults
            .string(forKey: Keys.choice)
            .flatMap(ThemeChoice.init(rawValue:))
        let storedDensity = InterfaceDensity(rawValue: defaults.string(forKey: Keys.density) ?? "")
        let compact = defaults.bool(forKey: Keys.retiredCompact)

        defaults.removeObject(forKey: Keys.legacySoftGlass)
        defaults.removeObject(forKey: Keys.retiredCompact)

        if !defaults.bool(forKey: Keys.migratedToSoftLight) {
            selected = .softLight
            defaults.set(true, forKey: Keys.migratedToSoftLight)
        } else {
            // A value left by one of the themes this build no longer ships does
            // not parse, and falls back to the main theme.
            selected = stored ?? .softLight
        }
        density = storedDensity ?? (compact ? .compact : .regular)

        defaults.set(selected.rawValue, forKey: Keys.choice)
    }

    // MARK: Derived

    var isSoftLight: Bool { selected.isSoftLight }

    /// The compact density shortens the native controls as it tightens the rest.
    var compactControls: Bool { density == .compact }

    // MARK: Selection

    func select(_ choice: ThemeChoice) {
        guard choice != selected else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            selected = choice
        }
        defaults.set(choice.rawValue, forKey: Keys.choice)
        Haptics.impact(.light)
    }

    func setDensity(_ value: InterfaceDensity) {
        guard value != density else { return }
        density = value
        defaults.set(value.rawValue, forKey: Keys.density)
    }

    func reset() {
        defaults.removeObject(forKey: Keys.choice)
        defaults.removeObject(forKey: Keys.density)
        defaults.removeObject(forKey: Keys.legacySoftGlass)
        defaults.removeObject(forKey: Keys.retiredCompact)

        selected = .softLight
        density = .regular
    }
}
