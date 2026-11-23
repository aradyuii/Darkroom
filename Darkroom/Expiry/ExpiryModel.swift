//
//  ExpiryModel.swift
//  Darkroom
//
//  The vocabulary of the expired-film exposure model: how a roll has been
//  stored, where each number came from, which family of emulsions it belongs
//  to, the characteristic curve the model works on, and what the engine hands
//  back to the screen.
//
//  Nothing here draws anything, and every structural constant says which kind
//  of knowledge it is. The whole point of the model is that it is honest about
//  the difference between a manufacturer's published figure and an engineering
//  prior someone had to choose.
//

import Foundation

// MARK: - Storage

/// A temperature band a roll has lived in. Each band is a *distribution* of
/// temperatures rather than one figure: a fridge cycles, an attic swings with
/// the season, and a cellar is not held at 17.5 °C to the decimal.
enum ExpiryStorageTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case frozen
    case refrigerator
    case coolRoom
    case roomTemperature
    case hot
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frozen: return "Frozen"
        case .refrigerator: return "Refrigerator"
        case .coolRoom: return "Cool room"
        case .roomTemperature: return "Room temperature"
        case .hot: return "Hot storage"
        case .unknown: return "Unknown"
        }
    }

    var detail: String {
        switch self {
        case .frozen: return "A freezer, about −18 °C"
        case .refrigerator: return "A domestic fridge, about 4 °C"
        case .coolRoom: return "A cellar or shaded room, about 15–20 °C"
        case .roomTemperature: return "A lived-in room, about 20–25 °C"
        case .hot: return "An attic, a car, or a tropical room"
        case .unknown: return "The roll's history is not known"
        }
    }

    var symbol: String {
        switch self {
        case .frozen: return "snowflake"
        case .refrigerator: return "thermometer.snowflake"
        case .coolRoom: return "house"
        case .roomTemperature: return "thermometer.medium"
        case .hot: return "sun.max"
        case .unknown: return "questionmark.circle"
        }
    }

    var isUnknown: Bool { self == .unknown }

    /// Mean, typical spread and seasonal swing, in Celsius. These are
    /// engineering priors chosen to describe the band, not measurements of any
    /// particular room. The bands themselves follow the storage conditions the
    /// manufacturers publish: Kodak E-30 gives 24 °C for two months, 16 °C for
    /// six and 10 °C for twelve (black-and-white), 13 °C for professional colour
    /// and −18 to −23 °C for long-term motion-picture stock; Kodak TIB5202 gives
    /// 13 °C general and −18 °C beyond six months at about 50% RH; the Library of
    /// Congress describes the best environment as 30–50% RH at 70 °F or below.
    var climate: ExpiryClimate {
        switch self {
        case .frozen:
            return ExpiryClimate(meanCelsius: -18, deviationCelsius: 4, seasonalAmplitudeCelsius: 0)
        case .refrigerator:
            return ExpiryClimate(meanCelsius: 4, deviationCelsius: 2.5, seasonalAmplitudeCelsius: 0.5)
        case .coolRoom:
            return ExpiryClimate(meanCelsius: 17.5, deviationCelsius: 2.5, seasonalAmplitudeCelsius: 2)
        case .roomTemperature:
            return ExpiryClimate(meanCelsius: 22.5, deviationCelsius: 3, seasonalAmplitudeCelsius: 3.5)
        case .hot:
            return ExpiryClimate(meanCelsius: 32, deviationCelsius: 6, seasonalAmplitudeCelsius: 5)
        case .unknown:
            return ExpiryClimate(meanCelsius: 21, deviationCelsius: 8, seasonalAmplitudeCelsius: 4)
        }
    }

    /// What an unknown history is drawn from. An unknown roll is uncertain, not
    /// assumed to have boiled in a car: the mixture keeps room temperature most
    /// likely and leaves the extremes possible.
    static let unknownMixture: [(tier: ExpiryStorageTier, weight: Double)] = [
        (.frozen, 0.04),
        (.refrigerator, 0.14),
        (.coolRoom, 0.26),
        (.roomTemperature, 0.36),
        (.hot, 0.20)
    ]
}

struct ExpiryClimate: Hashable, Sendable {
    var meanCelsius: Double
    var deviationCelsius: Double
    var seasonalAmplitudeCelsius: Double

    /// The swing across a year behaves like an extra spread of amplitude ÷ √2
    /// around the mean, so it folds into the same normal draw.
    var effectiveDeviation: Double {
        let seasonal = seasonalAmplitudeCelsius / 2.0.squareRoot()
        return (deviationCelsius * deviationCelsius + seasonal * seasonal).squareRoot()
    }
}

/// One stretch of a roll's life. The default interface uses a single segment;
/// the engine integrates a list of them.
struct ExpiryStorageSegment: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var tier: ExpiryStorageTier
    /// Share of the film's life spent here, 0…1.
    var fraction: Double

    init(id: String = UUID().uuidString, tier: ExpiryStorageTier, fraction: Double) {
        self.id = id
        self.tier = tier
        self.fraction = fraction
    }
}

struct ExpiryStorageTimeline: Codable, Hashable, Sendable {
    var segments: [ExpiryStorageSegment]

    static func single(_ tier: ExpiryStorageTier) -> ExpiryStorageTimeline {
        ExpiryStorageTimeline(segments: [ExpiryStorageSegment(id: "whole", tier: tier, fraction: 1)])
    }

    /// Fractions are renormalised, so a timeline that does not add to one is
    /// read as proportions rather than rejected. Periods in the same tier are
    /// merged, in the order the tiers first appear: two rows that both say
    /// "room temperature" are one period of the roll's life, and a reader who
    /// has just added a second period has not yet told the model anything.
    var normalised: [(tier: ExpiryStorageTier, fraction: Double)] {
        let kept = segments.filter { $0.fraction > 0 }
        let total = kept.reduce(0) { $0 + $1.fraction }
        guard total > 0 else { return [(.unknown, 1)] }

        var order: [ExpiryStorageTier] = []
        var sums: [ExpiryStorageTier: Double] = [:]
        for segment in kept {
            if sums[segment.tier] == nil { order.append(segment.tier) }
            sums[segment.tier, default: 0] += segment.fraction / total
        }
        return order.map { ($0, sums[$0] ?? 0) }
    }

    var isSingleTier: Bool { normalised.count == 1 }

    var containsUnknown: Bool { normalised.contains { $0.tier.isUnknown } }

    /// How sure the input is about storage, 0…1. Used by the confidence badge.
    var certainty: Double {
        let parts = normalised
        if parts.contains(where: { $0.tier.isUnknown }) { return 0.45 }
        if parts.count == 1 { return 1 }
        // Several known periods: the model integrates them, but the reader had
        // to approximate, so the answer is a little less sure.
        return max(0.7, 1 - 0.06 * Double(parts.count - 1))
    }

    var summary: String {
        let parts = normalised
        if parts.isEmpty { return "Unknown" }
        if parts.count == 1 { return parts[0].tier.title }
        return parts
            .map { "\(Int(($0.fraction * 100).rounded()))% \($0.tier.title.lowercased())" }
            .joined(separator: " · ")
    }
}

// MARK: - Evidence

/// How a number earned its place in the model. The badge the reader sees is
/// capped by this: a tight simulated range built on assumptions is still an
/// assumption.
enum ExpiryEvidenceClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case measured
    case manufacturerDocumented
    case literatureDerived
    case empiricallyObserved
    case assumed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .measured: return "Measured"
        case .manufacturerDocumented: return "Manufacturer documented"
        case .literatureDerived: return "Literature derived"
        case .empiricallyObserved: return "Empirically observed"
        case .assumed: return "Engineering assumption"
        }
    }

    /// The share of confidence a figure of this class can support.
    var weight: Double {
        switch self {
        case .measured: return 1.0
        case .manufacturerDocumented: return 0.9
        case .literatureDerived: return 0.72
        case .empiricallyObserved: return 0.55
        case .assumed: return 0.3
        }
    }

    /// The highest confidence score this class of evidence permits. A
    /// literature-derived ageing prior can never carry the "well documented"
    /// badge, however narrow its simulated range turns out.
    var confidenceCap: Double {
        switch self {
        case .measured: return 1.0
        case .manufacturerDocumented: return 0.96
        case .literatureDerived: return 0.72
        case .empiricallyObserved: return 0.68
        case .assumed: return 0.49
        }
    }
}

struct ExpiryEvidence: Codable, Hashable, Sendable {
    var classification: ExpiryEvidenceClass
    var source: String?
    var note: String?

    static func assumed(_ note: String? = nil) -> ExpiryEvidence {
        ExpiryEvidence(classification: .assumed, source: nil, note: note)
    }
}

/// A published document a parameter leans on. `key` matches the id an
/// annotation or a note cites, so the reader can follow a number back to the
/// page it came from.
struct ExpirySource: Codable, Identifiable, Hashable, Sendable {
    var key: String
    var title: String
    var publisher: String
    var url: String
    /// What this document was actually used for, in one sentence.
    var usedFor: String

    var id: String { key }
}

/// What kind of knowledge one parameter rests on. The evidence class is per
/// parameter, not per film, so a model can be documented in one place and
/// assumed in another without either claim hiding the other.
struct ExpiryParameterAnnotation: Identifiable, Hashable, Sendable {
    var id: String
    var field: String
    var classification: ExpiryEvidenceClass
    var sourceKey: String?
    var note: String
}

/// A value with the spread it is believed to have.
struct ExpiryDistribution: Codable, Hashable, Sendable {
    var mean: Double
    var deviation: Double
    var minimum: Double

    init(mean: Double, deviation: Double, minimum: Double = 0) {
        self.mean = mean
        self.deviation = deviation
        self.minimum = minimum
    }

    var clampedMean: Double { Swift.max(minimum, mean) }

    static func fixed(_ value: Double, minimum: Double = 0) -> ExpiryDistribution {
        ExpiryDistribution(mean: value, deviation: 0, minimum: minimum)
    }
}

// MARK: - Behaviour groups

/// Emulsions that age alike. Every film in the library is mapped to one of
/// these; nothing starts from a blank slate.
enum ExpiryBehaviourGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case slowModernBW
    case classicBW
    case fastBW
    case consumerColourNegative
    case professionalColourNegative
    case slide
    case cineECN2
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slowModernBW: return "Slow modern B&W"
        case .classicBW: return "Classic B&W"
        case .fastBW: return "Fast B&W"
        case .consumerColourNegative: return "Consumer colour negative"
        case .professionalColourNegative: return "Professional colour negative"
        case .slide: return "Slide / E-6"
        case .cineECN2: return "Cine / ECN-2"
        case .other: return "Other or unknown"
        }
    }

    var detail: String {
        switch self {
        case .slowModernBW:
            return "Tabular and fine-grain monochrome up to ISO 200: T-Max 100, Delta 100, Acros, Pan F."
        case .classicBW:
            return "Conventional and older monochrome around ISO 200–400: FP4, HP5, Tri-X, Foma, APX, Neopan."
        case .fastBW:
            return "Monochrome at ISO 400 and above, where crystals are largest and fog shows first."
        case .consumerColourNegative:
            return "Mass-market C-41: Gold, ColorPlus, C200, Superia, Pro Plus."
        case .professionalColourNegative:
            return "Pro-sheet C-41 with a shorter date and a cold chain: Portra, Ektar, Pro 400H, Reala."
        case .slide:
            return "E-6 reversal: Velvia, Provia, Ektachrome, Sensia, Astia. The strictest colour balance."
        case .cineECN2:
            return "Motion-picture negative and its respools: Vision3, Eterna, the Kodak F series."
        case .other:
            return "Anything the library cannot place with confidence. Conservative, wide, an educated guess."
        }
    }

    var isColour: Bool {
        switch self {
        case .consumerColourNegative, .professionalColourNegative, .slide, .cineECN2: return true
        case .slowModernBW, .classicBW, .fastBW, .other: return false
        }
    }

    /// The three layers of a colour film do not age at the same rate; slide film
    /// is the least forgiving because it has no printing stage to correct in.
    var layerCrossoverSensitivity: Double {
        switch self {
        case .slide: return 1.0
        case .professionalColourNegative: return 0.75
        case .consumerColourNegative: return 0.6
        case .cineECN2: return 0.7
        default: return 0
        }
    }
}

/// Everything a group says before any individual film has spoken. Every field
/// is a starting distribution the film may override.
struct ExpiryGroupParameters: Codable, Hashable, Sendable {
    /// Activation energy of the dominant degradation path, in eV.
    var activationEnergyEV: ExpiryDistribution
    /// Years between coating and the printed date.
    var shelfLifeYears: ExpiryDistribution

    // The fresh characteristic curve. Fog is base + fog density.
    var freshBaseFog: Double
    var freshGamma: Double
    var freshMaxDensity: Double
    var toeDecades: Double

    // How the curve moves with age. Each is an asymptote approached with a
    // saturating (non-linear) curve of its own time constant.
    var fogCeiling: Double
    var fogTimeConstantYears: Double
    var gammaLossFraction: Double
    var gammaTimeConstantYears: Double
    var densityLoss: Double
    var densityTimeConstantYears: Double
    var speedLossStops: Double
    var speedTimeConstantYears: Double

    /// Multiplier on the base radiation fog rate. That faster films are fogged
    /// more by ambient gamma radiation than slower ones is manufacturer
    /// documented (Kodak TIB5202, 2002: "Higher-speed films are affected more by
    /// gamma radiation than lower-speed films"); the magnitudes here are priors
    /// laid along that direction, not measurements of any emulsion.
    var radiationSensitivity: ExpiryDistribution

    /// Beyond this the answer is saturated: more exposure cannot help.
    var saturationStops: Double
    /// Published exposure latitude, for the summary line.
    var latitudeStops: Double

    var notes: String
    var evidence: ExpiryEvidence
}

// MARK: - Film overrides

/// Per-film adjustments to its group. Optional fields mean "the group's value
/// stands".
struct ExpiryParameterOverride: Codable, Hashable, Sendable {
    var activationEnergyEV: ExpiryDistribution?
    var shelfLifeYears: ExpiryDistribution?
    var freshBaseFog: Double?
    var freshGamma: Double?
    var freshMaxDensity: Double?
    var toeDecades: Double?
    var fogCeiling: Double?
    var fogTimeConstantYears: Double?
    var gammaLossFraction: Double?
    var gammaTimeConstantYears: Double?
    var densityLoss: Double?
    var densityTimeConstantYears: Double?
    var speedLossStops: Double?
    var speedTimeConstantYears: Double?
    var radiationSensitivity: ExpiryDistribution?
    var saturationStops: Double?

    /// 1 = the group's antifoggant reserve; below 1 the film fogs sooner.
    var antifoggantRobustness: Double?
    /// 1 = modern stabilisers. Below 1 shortens every time constant.
    var sensitizerEraFactor: Double?
    /// 1 = the group's thermal sensitivity; multiplies activation energy.
    var thermalSensitivity: Double?
}

/// The film as the engine sees it.
struct ExpiryFilmProfile: Hashable, Sendable {
    var filmKey: String
    var displayName: String
    var manufacturer: String
    var iso: Int
    var process: FilmProcess
    var status: FilmStatus
    var group: ExpiryBehaviourGroup
    var groupReason: String
    var baseMaterial: ExpiryBaseMaterial
    var baseMaterialIsAssumed: Bool
    var overrides: ExpiryParameterOverride
    var evidence: ExpiryEvidenceClass
    var note: String?

    /// Named stocks the library carries a curated reading for.
    var hasCuratedProfile: Bool
}

enum ExpiryBaseMaterial: String, Codable, CaseIterable, Identifiable, Sendable {
    case acetate
    case polyester
    case paper
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .acetate: return "Acetate"
        case .polyester: return "Polyester"
        case .paper: return "Paper"
        case .unknown: return "Not known"
        }
    }

    /// Acetate is the base that hydrolyses — vinegar syndrome. Polyester is the
    /// stable one, and paper is a different problem altogether.
    var canHydrolyse: Bool { self == .acetate }
}

// MARK: - The curve

/// A parametric Hurter–Driffield curve: toe, straight line and shoulder, with a
/// speed shift of its own.
///
/// The toe is a smooth maximum of the exposure axis, so the curve leaves fog
/// gradually instead of kinking; the shoulder is an exponential approach to the
/// film's maximum density, so highlights compress instead of clipping. Both are
/// monotone, which is what lets the engine invert the curve by bisection.
struct ExpiryCharacteristicCurve: Hashable, Sendable {
    var baseFog: Double
    var gamma: Double
    var maxDensity: Double
    var toeDecades: Double
    /// Extra exposure, in decades, the emulsion needs because it has slowed.
    var speedShiftDecades: Double

    /// Density at an exposure given in decades relative to the film's fresh
    /// speed point.
    func density(decades: Double) -> Double {
        let shifted = decades - speedShiftDecades
        let toe = Swift.max(toeDecades, 0.02)
        let toeResponse: Double
        if shifted <= 0 {
            toeResponse = toe * log10(1 + pow(10, Swift.max(shifted / toe, -30)))
        } else if shifted / toe > 12 {
            toeResponse = shifted
        } else {
            toeResponse = toe * log10(1 + pow(10, shifted / toe))
        }

        let increment = Swift.max(gamma * Swift.max(toeResponse, 0), 0)
        let headroom = Swift.max(maxDensity - baseFog, 0.001)
        return baseFog + headroom * (1 - exp(-increment / headroom))
    }

    /// The exposure (in decades) that reaches a density, by bisection. Nil when
    /// the density is out of reach — which is the saturation case.
    func decades(forDensity target: Double, range: ClosedRange<Double> = -2...16) -> Double? {
        guard target > baseFog + 0.0005 else { return nil }
        guard target < maxDensity - 0.0005 else { return nil }

        var low = range.lowerBound
        var high = range.upperBound
        guard density(decades: high) > target else { return nil }

        for _ in 0..<48 {
            let mid = (low + high) / 2
            if density(decades: mid) > target {
                high = mid
            } else {
                low = mid
            }
        }
        return (low + high) / 2
    }
}

// MARK: - Results

enum ExpiryConfidence: String, Codable, CaseIterable, Identifiable, Sendable {
    case wellDocumented
    case communityConsensus
    case educatedGuess

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wellDocumented: return "Well documented"
        case .communityConsensus: return "Community consensus"
        case .educatedGuess: return "Educated guess"
        }
    }

    var detail: String {
        switch self {
        case .wellDocumented:
            return "The inputs are documented and the storage history is known."
        case .communityConsensus:
            return "The film family is well understood, but the ageing rates are informed priors, not measurements."
        case .educatedGuess:
            return "The emulsion or its history is not documented well enough for more than a careful guess."
        }
    }
}

struct ExpiryContribution: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var value: String
    var detail: String
}

struct ExpiryWarning: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var detail: String
    var isSevere: Bool
}

/// What the calculator hands the screen.
struct ExpiryEstimate: Hashable, Sendable {
    var requestedISO: Int
    var eiLow: Int
    var eiMedian: Int
    var eiHigh: Int
    /// Stops of extra exposure relative to box speed, snapped to a third.
    var stops: Double
    var lowStops: Double
    var highStops: Double

    var confidence: ExpiryConfidence
    var confidenceScore: Double
    var explanation: String
    var warnings: [ExpiryWarning]
    var bracketing: String?
    var isSaturated: Bool
    var contributions: [ExpiryContribution]

    var ageYears: Double
    var shelfLifeYears: Double
    var manufactureYear: Int
    var equivalentThermalYears: Double
    var fogIncrease: Double
    var group: ExpiryBehaviourGroup
    var isExpired: Bool
    var calibrationDelta: Double
    var sampleCount: Int
}

// MARK: - The ladder

/// Exposure indices on standard third stops below the box speed. Every number
/// the screen shows comes from here, so a reading is always a setting a camera
/// or meter can actually take.
struct ExpiryEILadder: Hashable, Sendable {
    let iso: Int

    func stops(at index: Int) -> Double { Double(index) / 3 }

    func index(nearest stops: Double) -> Int { Int((stops * 3).rounded()) }

    func index(roundingUp stops: Double) -> Int { Int((stops * 3).rounded(.up)) }

    func index(roundingDown stops: Double) -> Int { Int((stops * 3).rounded(.down)) }

    /// Box speed is index 0; each index is a third of a stop less light on the
    /// film, so the index itself is the exposure index the meter should be set to.
    func ei(at index: Int) -> Int {
        let value = Double(iso) * pow(2, -Double(index) / 3)
        return Swift.max(1, Int(value.rounded()))
    }

    func label(at index: Int) -> String { "EI \(ei(at: index))" }
}

// MARK: - Requests

/// Everything the engine is told. Plain values, so a calculation can leave the
/// main thread and come back with no shared state.
struct ExpiryRequest: Hashable, Sendable {
    var profile: ExpiryFilmProfile
    var expiration: Date
    var timeline: ExpiryStorageTimeline
    var now: Date

    var iso: Int { profile.iso }

    var yearsPastExpiry: Double {
        ExpiryEngine.years(from: expiration, to: now)
    }

    /// Stable across launches, unlike `hashValue`, so a fixed input always gives
    /// a fixed answer.
    var deterministicSeed: UInt64 {
        var text = profile.filmKey
        text += "|\(Int(expiration.timeIntervalSince1970 / 86400))"
        text += "|\(iso)"
        text += timeline.normalised
            .map { "\($0.tier.rawValue):\(Int(($0.fraction * 1000).rounded()))" }
            .joined(separator: ",")
        return ExpiryEngine.stableHash(text)
    }
}
