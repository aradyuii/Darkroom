//
//  Preferences.swift
//  Darkroom
//
//  The app-wide settings behind Settings: what the bench reads in, how reuse and
//  extrapolation are counted, what each prompt sounds and feels like, and what a
//  new session starts from. Every write persists immediately; nothing here knows
//  how it is drawn.
//

import SwiftUI

// MARK: - Units

enum TemperatureScale: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        }
    }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    func value(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9 / 5 + 32
        }
    }

    /// A reading typed on the bench, back in Celsius — the scale every
    /// calculation is worked in.
    func celsius(from value: Double) -> Double {
        switch self {
        case .celsius: return value
        case .fahrenheit: return (value - 32) * 5 / 9
        }
    }
}

enum VolumeUnit: String, CaseIterable, Identifiable {
    case millilitres
    case fluidOunces

    /// A US fluid ounce. The app's volumes are all metric; this is a reading.
    static let millilitresPerFluidOunce = 29.5735

    var id: String { rawValue }

    var title: String {
        switch self {
        case .millilitres: return "Millilitres"
        case .fluidOunces: return "Fluid ounces"
        }
    }

    func value(fromMillilitres millilitres: Double) -> Double {
        switch self {
        case .millilitres: return millilitres
        case .fluidOunces: return millilitres / Self.millilitresPerFluidOunce
        }
    }
}

/// Turns a stored number into the units the bench reads in. Times are never
/// converted; temperatures and volumes are.
enum Units {
    static func temperature(_ celsius: Double, decimals: Int = 1) -> String {
        let scale = Preferences.shared.temperatureScale
        let value = scale.value(fromCelsius: celsius)
        return String(format: "%.\(decimals)f %@", value, scale.symbol)
    }

    /// A temperature with no decimal place when the figure is whole — the form
    /// published times use.
    static func shortTemperature(_ celsius: Double) -> String {
        if abs(celsius - celsius.rounded()) < 0.05 {
            return temperature(celsius, decimals: 0)
        }
        return temperature(celsius)
    }

    static func volume(millilitres: Double) -> String {
        switch Preferences.shared.volumeUnit {
        case .millilitres:
            if millilitres < 10 && abs(millilitres - millilitres.rounded()) > 0.05 {
                return String(format: "%.1f ml", millilitres)
            }
            return "\(Int(millilitres.rounded())) ml"
        case .fluidOunces:
            let ounces = VolumeUnit.fluidOunces.value(fromMillilitres: millilitres)
            let decimals = ounces >= 10 ? 1 : 2
            return String(format: "%.\(decimals)f fl oz", ounces)
        }
    }

    /// The same figure spelled out, for a spoken or screen-reader label.
    static func volumePhrase(millilitres: Double) -> String {
        switch Preferences.shared.volumeUnit {
        case .millilitres:
            return "\(Int(millilitres.rounded())) millilitres"
        case .fluidOunces:
            let ounces = VolumeUnit.fluidOunces.value(fromMillilitres: millilitres)
            return String(format: "%.1f fluid ounces", ounces)
        }
    }

    static func litres(_ litres: Double) -> String {
        guard Preferences.shared.volumeUnit == .fluidOunces else {
            if abs(litres - litres.rounded()) < 0.001 {
                return "\(Int(litres.rounded())) L"
            }
            return String(format: "%.2f L", litres)
        }
        return volume(millilitres: litres * 1000)
    }
}

// MARK: - Accent

/// The app's lamp, in the nine lights the bench can be lit with. Both themes are
/// lit by it.
enum AccentChoice: String, CaseIterable, Identifiable {
    case safelight
    case ruby
    case ember
    case rose
    case violet
    case sky
    case ice
    case mint
    case lime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safelight: return "Safelight"
        case .ruby: return "Ruby"
        case .ember: return "Ember"
        case .rose: return "Rose"
        case .violet: return "Violet"
        case .sky: return "Sky"
        case .ice: return "Ice"
        case .mint: return "Mint"
        case .lime: return "Lime"
        }
    }

    var base: Color {
        switch self {
        case .safelight: return Color(red: 0.976, green: 0.667, blue: 0.196)
        case .ruby: return Color(red: 0.949, green: 0.353, blue: 0.298)
        case .ember: return Color(red: 0.980, green: 0.490, blue: 0.200)
        case .rose: return Color(red: 0.960, green: 0.450, blue: 0.700)
        case .violet: return Color(red: 0.706, green: 0.549, blue: 0.961)
        case .sky: return Color(red: 0.349, green: 0.706, blue: 0.941)
        case .ice: return Color(red: 0.400, green: 0.880, blue: 0.880)
        case .mint: return Color(red: 0.373, green: 0.827, blue: 0.651)
        case .lime: return Color(red: 0.776, green: 0.941, blue: 0.000)
        }
    }

    var soft: Color {
        switch self {
        case .safelight: return Color(red: 1.0, green: 0.812, blue: 0.494)
        case .ruby: return Color(red: 0.976, green: 0.553, blue: 0.506)
        case .ember: return Color(red: 1.0, green: 0.680, blue: 0.420)
        case .rose: return Color(red: 1.0, green: 0.660, blue: 0.830)
        case .violet: return Color(red: 0.816, green: 0.710, blue: 0.984)
        case .sky: return Color(red: 0.588, green: 0.824, blue: 0.973)
        case .ice: return Color(red: 0.660, green: 0.950, blue: 0.950)
        case .mint: return Color(red: 0.592, green: 0.914, blue: 0.784)
        case .lime: return Color(red: 0.880, green: 0.980, blue: 0.450)
        }
    }

    var deep: Color {
        switch self {
        case .safelight: return Color(red: 0.839, green: 0.463, blue: 0.098)
        case .ruby: return Color(red: 0.761, green: 0.227, blue: 0.180)
        case .ember: return Color(red: 0.800, green: 0.300, blue: 0.100)
        case .rose: return Color(red: 0.800, green: 0.240, blue: 0.520)
        case .violet: return Color(red: 0.494, green: 0.345, blue: 0.769)
        case .sky: return Color(red: 0.180, green: 0.498, blue: 0.710)
        case .ice: return Color(red: 0.160, green: 0.600, blue: 0.640)
        case .mint: return Color(red: 0.180, green: 0.612, blue: 0.455)
        case .lime: return Color(red: 0.550, green: 0.720, blue: 0.000)
        }
    }

    /// Ink that sits on top of the accent block.
    var ink: Color {
        switch self {
        case .safelight: return Color(red: 0.106, green: 0.075, blue: 0.020)
        case .ruby: return Color(red: 0.110, green: 0.035, blue: 0.030)
        case .ember: return Color(red: 0.140, green: 0.060, blue: 0.020)
        case .rose: return Color(red: 0.130, green: 0.030, blue: 0.090)
        case .violet: return Color(red: 0.070, green: 0.040, blue: 0.140)
        case .sky: return Color(red: 0.015, green: 0.080, blue: 0.130)
        case .ice: return Color(red: 0.010, green: 0.090, blue: 0.095)
        case .mint: return Color(red: 0.020, green: 0.110, blue: 0.080)
        case .lime: return Color(red: 0.050, green: 0.090, blue: 0.000)
        }
    }

    /// The second light in the room. Every screen is lit by the accent and this,
    /// so the field carries a gradient instead of one flat wash.
    var bloom: Color {
        switch self {
        case .safelight: return Color(red: 0.950, green: 0.360, blue: 0.100)
        case .ruby: return Color(red: 0.980, green: 0.550, blue: 0.250)
        case .ember: return Color(red: 0.940, green: 0.220, blue: 0.420)
        case .rose: return Color(red: 0.720, green: 0.350, blue: 0.980)
        case .violet: return Color(red: 0.360, green: 0.530, blue: 0.990)
        case .sky: return Color(red: 0.300, green: 0.900, blue: 0.850)
        case .ice: return Color(red: 0.300, green: 0.600, blue: 0.980)
        case .mint: return Color(red: 0.360, green: 0.700, blue: 0.950)
        case .lime: return Color(red: 0.300, green: 0.850, blue: 0.600)
        }
    }
}

// MARK: - Agitation

/// The default pattern for the developer stage. The stop and the fixer keep the
/// agitation their own instructions give.
enum AgitationScheme: String, CaseIterable, Identifiable {
    case interval
    case continuous
    case stand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interval: return "Every minute"
        case .continuous: return "Continuous"
        case .stand: return "Stand"
        }
    }

    var blurb: String {
        switch self {
        case .interval:
            return "Thirty seconds of continuous agitation, then an inversion each minute with a tap on the bench."
        case .continuous:
            return "The reels keep moving for the whole stage."
        case .stand:
            return "No agitation at all: the developer stands, and the time carries the contrast."
        }
    }

    var style: AgitationStyle {
        switch self {
        case .interval: return .interval
        case .continuous: return .continuous
        case .stand: return .off
        }
    }
}

// MARK: - Alerts

/// The moments the bench is told about, each with a sound and a haptic of its own.
enum FeedbackEvent: String, CaseIterable, Identifiable {
    case agitate
    case tap
    case rest
    case stageComplete
    case finished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agitate: return "Agitate now"
        case .tap: return "Tap the tank"
        case .rest: return "Rest"
        case .stageComplete: return "Stage complete"
        case .finished: return "Session finished"
        }
    }

    var detail: String {
        switch self {
        case .agitate: return "The inversion prompt during the developer and the fixer."
        case .tap: return "After each inversion, when the tank goes down on the bench."
        case .rest: return "The settle after a tap, and the start of a still stage."
        case .stageComplete: return "One stage has ended and the next is waiting for GO."
        case .finished: return "The last stage is done."
        }
    }
}

enum FeedbackSound: String, CaseIterable, Identifiable {
    case bright
    case soft
    case stage
    case fanfare
    case tick
    case silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bright: return "Bright double"
        case .soft: return "Soft single"
        case .stage: return "Stage chime"
        case .fanfare: return "Finish fanfare"
        case .tick: return "Short tick"
        case .silent: return "None"
        }
    }

    var chime: Chime? {
        switch self {
        case .bright: return .agitate
        case .soft: return .settle
        case .stage: return .stageComplete
        case .fanfare: return .finished
        case .tick: return .tick
        case .silent: return nil
        }
    }
}

enum FeedbackHaptic: String, CaseIterable, Identifiable {
    case none
    case light
    case medium
    case heavy
    case success
    case warning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .light: return "Light tap"
        case .medium: return "Medium tap"
        case .heavy: return "Heavy tap"
        case .success: return "Success"
        case .warning: return "Warning"
        }
    }

    func fire() {
        switch self {
        case .none: break
        case .light: Haptics.impact(.light)
        case .medium: Haptics.impact(.medium)
        case .heavy: Haptics.impact(.heavy)
        case .success: Haptics.success()
        case .warning: Haptics.warning()
        }
    }
}

// MARK: - Store

/// One source of truth for every preference the Settings screen owns. The theme
/// and its palettes stay with the theme store; everything else is here.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Keys {
        static let prefix = "prefs."
        static let temperatureScale = "prefs.temperatureScale"
        static let volumeUnit = "prefs.volumeUnit"
        static let agitationScheme = "prefs.agitationScheme"
        static let agitationIntensity = "prefs.agitationIntensity"
        static let reuseStep = "prefs.reuseStep"
        static let extrapolation = "prefs.extrapolationFactor"
        static let spokenPrompts = "prefs.spokenPrompts"
        static let voiceCommands = "prefs.voiceCommands"
        static let keepAwake = "prefs.keepAwake"
        static let stop = "prefs.stopSeconds"
        static let fix = "prefs.fixSeconds"
        static let wash = "prefs.washSeconds"
        static let rinse = "prefs.finalRinseSeconds"
        static let accent = "prefs.accent"

        static func sound(_ event: FeedbackEvent) -> String { "prefs.sound.\(event.rawValue)" }
        static func haptic(_ event: FeedbackEvent) -> String { "prefs.haptic.\(event.rawValue)" }
    }

    /// The ranges the screen offers, kept here so the store and the controls
    /// cannot drift apart.
    static let reuseStepRange: ClosedRange<Double> = 0.05...0.25
    static let extrapolationRange: ClosedRange<Double> = 0.5...2.0
    static let stopRange: ClosedRange<TimeInterval> = 20...40
    static let fixRange: ClosedRange<TimeInterval> = 120...900
    static let washRange: ClosedRange<TimeInterval> = 60...1800
    static let rinseRange: ClosedRange<TimeInterval> = 15...300

    private let defaults = UserDefaults.standard

    @Published private(set) var temperatureScale: TemperatureScale
    @Published private(set) var volumeUnit: VolumeUnit
    @Published private(set) var agitationScheme: AgitationScheme
    @Published private(set) var agitationIntensity: AgitationIntensity
    @Published private(set) var reuseStep: Double
    @Published private(set) var extrapolationFactor: Double
    @Published private(set) var spokenPrompts: Bool
    @Published private(set) var voiceCommands: Bool
    @Published private(set) var keepAwake: Bool
    @Published private(set) var stopSeconds: TimeInterval
    @Published private(set) var fixSeconds: TimeInterval
    @Published private(set) var washSeconds: TimeInterval
    @Published private(set) var finalRinseSeconds: TimeInterval
    @Published private(set) var accent: AccentChoice
    @Published private(set) var sounds: [FeedbackEvent: FeedbackSound]
    @Published private(set) var haptics: [FeedbackEvent: FeedbackHaptic]

    private init() {
        temperatureScale = TemperatureScale(rawValue: defaults.string(forKey: Keys.temperatureScale) ?? "") ?? .celsius
        volumeUnit = VolumeUnit(rawValue: defaults.string(forKey: Keys.volumeUnit) ?? "") ?? .millilitres
        agitationScheme = AgitationScheme(rawValue: defaults.string(forKey: Keys.agitationScheme) ?? "") ?? .interval
        agitationIntensity = AgitationIntensity(rawValue: defaults.string(forKey: Keys.agitationIntensity) ?? "") ?? .normal

        let storedStep = defaults.object(forKey: Keys.reuseStep) as? Double ?? CompensationRules.defaultReuseStep
        reuseStep = min(Self.reuseStepRange.upperBound, max(Self.reuseStepRange.lowerBound, storedStep))
        let storedExtrapolation = defaults.object(forKey: Keys.extrapolation) as? Double ?? 1
        extrapolationFactor = min(Self.extrapolationRange.upperBound, max(Self.extrapolationRange.lowerBound, storedExtrapolation))

        spokenPrompts = defaults.bool(forKey: Keys.spokenPrompts)
        voiceCommands = defaults.object(forKey: Keys.voiceCommands) as? Bool ?? true
        keepAwake = defaults.object(forKey: Keys.keepAwake) as? Bool ?? true
        stopSeconds = Self.read(defaults, Keys.stop, fallback: 30, range: Self.stopRange)
        fixSeconds = Self.read(defaults, Keys.fix, fallback: 300, range: Self.fixRange)
        washSeconds = Self.read(defaults, Keys.wash, fallback: 300, range: Self.washRange)
        finalRinseSeconds = Self.read(defaults, Keys.rinse, fallback: 30, range: Self.rinseRange)
        accent = AccentChoice(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .safelight

        var storedSounds: [FeedbackEvent: FeedbackSound] = [:]
        var storedHaptics: [FeedbackEvent: FeedbackHaptic] = [:]
        for event in FeedbackEvent.allCases {
            storedSounds[event] = FeedbackSound(rawValue: defaults.string(forKey: Keys.sound(event)) ?? "")
                ?? Self.defaultSound(for: event)
            storedHaptics[event] = FeedbackHaptic(rawValue: defaults.string(forKey: Keys.haptic(event)) ?? "")
                ?? Self.defaultHaptic(for: event)
        }
        sounds = storedSounds
        haptics = storedHaptics
    }

    // MARK: Reading and writing

    func sound(for event: FeedbackEvent) -> FeedbackSound {
        sounds[event] ?? Self.defaultSound(for: event)
    }

    func haptic(for event: FeedbackEvent) -> FeedbackHaptic {
        haptics[event] ?? Self.defaultHaptic(for: event)
    }

    func setSound(_ sound: FeedbackSound, for event: FeedbackEvent) {
        var updated = sounds
        updated[event] = sound
        sounds = updated
        defaults.set(sound.rawValue, forKey: Keys.sound(event))
    }

    func setHaptic(_ haptic: FeedbackHaptic, for event: FeedbackEvent) {
        var updated = haptics
        updated[event] = haptic
        haptics = updated
        defaults.set(haptic.rawValue, forKey: Keys.haptic(event))
    }

    func setTemperatureScale(_ scale: TemperatureScale) {
        temperatureScale = scale
        defaults.set(scale.rawValue, forKey: Keys.temperatureScale)
    }

    func setVolumeUnit(_ unit: VolumeUnit) {
        volumeUnit = unit
        defaults.set(unit.rawValue, forKey: Keys.volumeUnit)
    }

    func setAgitationScheme(_ scheme: AgitationScheme) {
        agitationScheme = scheme
        defaults.set(scheme.rawValue, forKey: Keys.agitationScheme)
    }

    func setAgitationIntensity(_ intensity: AgitationIntensity) {
        agitationIntensity = intensity
        defaults.set(intensity.rawValue, forKey: Keys.agitationIntensity)
    }

    func setReuseStep(_ step: Double) {
        let clamped = min(Self.reuseStepRange.upperBound, max(Self.reuseStepRange.lowerBound, step))
        reuseStep = clamped
        defaults.set(clamped, forKey: Keys.reuseStep)
    }

    func setExtrapolationFactor(_ factor: Double) {
        let clamped = min(Self.extrapolationRange.upperBound, max(Self.extrapolationRange.lowerBound, factor))
        extrapolationFactor = clamped
        defaults.set(clamped, forKey: Keys.extrapolation)
    }

    func setSpokenPrompts(_ value: Bool) {
        spokenPrompts = value
        defaults.set(value, forKey: Keys.spokenPrompts)
    }

    func setVoiceCommands(_ value: Bool) {
        voiceCommands = value
        defaults.set(value, forKey: Keys.voiceCommands)
    }

    func setKeepAwake(_ value: Bool) {
        keepAwake = value
        defaults.set(value, forKey: Keys.keepAwake)
    }

    func setStopSeconds(_ value: TimeInterval) {
        stopSeconds = min(Self.stopRange.upperBound, max(Self.stopRange.lowerBound, value))
        defaults.set(stopSeconds, forKey: Keys.stop)
    }

    func setFixSeconds(_ value: TimeInterval) {
        fixSeconds = min(Self.fixRange.upperBound, max(Self.fixRange.lowerBound, value))
        defaults.set(fixSeconds, forKey: Keys.fix)
    }

    func setWashSeconds(_ value: TimeInterval) {
        washSeconds = min(Self.washRange.upperBound, max(Self.washRange.lowerBound, value))
        defaults.set(washSeconds, forKey: Keys.wash)
    }

    func setFinalRinseSeconds(_ value: TimeInterval) {
        finalRinseSeconds = min(Self.rinseRange.upperBound, max(Self.rinseRange.lowerBound, value))
        defaults.set(finalRinseSeconds, forKey: Keys.rinse)
    }

    func setAccent(_ choice: AccentChoice) {
        accent = choice
        defaults.set(choice.rawValue, forKey: Keys.accent)
    }

    // MARK: Events

    /// Sounds and feels one moment, as its two preferences say.
    func play(_ event: FeedbackEvent) {
        if let chime = sound(for: event).chime {
            FeedbackCenter.shared.play(chime)
        }
        haptic(for: event).fire()
    }

    // MARK: Reset

    /// Puts every preference back to the value it had before the first change.
    func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Keys.prefix) {
            defaults.removeObject(forKey: key)
        }

        temperatureScale = .celsius
        volumeUnit = .millilitres
        agitationScheme = .interval
        agitationIntensity = .normal
        reuseStep = CompensationRules.defaultReuseStep
        extrapolationFactor = 1
        spokenPrompts = false
        voiceCommands = true
        keepAwake = true
        stopSeconds = 30
        fixSeconds = 300
        washSeconds = 300
        finalRinseSeconds = 30
        accent = .safelight

        var soundValues: [FeedbackEvent: FeedbackSound] = [:]
        var hapticValues: [FeedbackEvent: FeedbackHaptic] = [:]
        for event in FeedbackEvent.allCases {
            soundValues[event] = Self.defaultSound(for: event)
            hapticValues[event] = Self.defaultHaptic(for: event)
        }
        sounds = soundValues
        haptics = hapticValues
    }

    // MARK: Defaults

    static func defaultSound(for event: FeedbackEvent) -> FeedbackSound {
        switch event {
        case .agitate: return .bright
        case .tap, .rest: return .soft
        case .stageComplete: return .stage
        case .finished: return .fanfare
        }
    }

    static func defaultHaptic(for event: FeedbackEvent) -> FeedbackHaptic {
        switch event {
        case .agitate: return .heavy
        case .tap: return .medium
        case .rest: return .light
        case .stageComplete, .finished: return .success
        }
    }

    private static func read(
        _ defaults: UserDefaults,
        _ key: String,
        fallback: TimeInterval,
        range: ClosedRange<TimeInterval>
    ) -> TimeInterval {
        guard let stored = defaults.object(forKey: key) as? Double else { return fallback }
        return min(range.upperBound, max(range.lowerBound, stored))
    }
}
