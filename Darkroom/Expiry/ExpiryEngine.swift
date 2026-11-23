//
//  ExpiryEngine.swift
//  Darkroom
//
//  The ageing engine behind the expired-film calculator. Pure arithmetic: no
//  SwiftUI, no clock reading, no storage. It takes a request and a parameter
//  table and returns an estimate, so the same inputs always give the same
//  answer and a test can call it directly.
//
//  Two modelling ideas carry the whole thing:
//
//  1. Storage is integrated, not assumed. Every segment of the roll's life has
//     a temperature band, a sample is drawn from that band's distribution, and
//     the Arrhenius rate for that draw is weighted by the segment's share of
//     the life. Averaging rates rather than temperatures is what makes a hot
//     summer in an attic cost more than a warm average would.
//
//  2. Compensation comes out of the characteristic curve, not out of a rule.
//     The engine asks how much more exposure is needed to place a fixed
//     shadow density above the fog the film has now, compared with the same
//     film fresh. Saturation is not a special case bolted on: it appears when
//     the shoulder can no longer deliver the density at all.
//

import Foundation

// MARK: - Randomness

/// SplitMix64. Deterministic, seedable, and free of the standard library's
/// per-process seeding, so a fixed input gives a byte-identical result.
struct ExpirySeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform in the open interval (0, 1).
    mutating func unit() -> Double {
        let value = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return min(max(value, 1e-12), 1 - 1e-12)
    }

    /// Box–Muller. Two draws, one used and one discarded: a simpler exchange
    /// than carrying a spare, and this is not a hot path.
    mutating func normal() -> Double {
        let u1 = unit()
        let u2 = unit()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
}

// MARK: - Engine

struct ExpiryEngine: Sendable {
    var model: ExpiryModel
    var sampleCount: Int

    init(model: ExpiryModel = .standard, sampleCount: Int = 2000) {
        self.model = model
        self.sampleCount = sampleCount
    }

    // MARK: Constants

    /// Boltzmann's constant in electron-volt per kelvin.
    static let gasConstantEV = 8.617_333_262e-5
    /// The temperature every relative rate is quoted against.
    static let referenceCelsius = 17.5
    /// Best-estimate radiation fog for a typical emulsion, log D per year.
    /// The split between thermal and radiation fog cannot be separated in the
    /// public record, so this is a prior (see the documentation). Kodak TIB5202
    /// documents that the effect exists, that it continues in cold storage and
    /// that faster films are hit harder; it gives no rate.
    static let baseRadiationFogPerYear = 0.0028
    /// Radiation fog does not stop. This is the floor that keeps it honest.
    static let minimumRadiationFogPerYear = 0.0012
    /// Density separation a shadow needs above base fog, in log D.
    static let shadowSeparation = 0.12
    /// Fog is not a flat pedestal: it carries granularity, so a foggier film is
    /// treated as needing a wider separation for the shadow to read. Assumed.
    static let fogGranularityCoefficient = 0.35
    /// Cold slows radiation damage a little, never stops it.
    static let frozenRadiationFactor = 0.8

    static let secondsPerYear = 365.2425 * 24 * 60 * 60

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static func years(from start: Date, to end: Date) -> Double {
        end.timeIntervalSince(start) / secondsPerYear
    }

    static func year(of date: Date) -> Int {
        utcCalendar.component(.year, from: date)
    }

    /// FNV-1a over the request's text, so a seed is stable across launches.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    // MARK: - Public entry points

    /// The full Monte Carlo answer. Roughly two thousand samples, a few
    /// milliseconds, and no dependence on the main thread.
    func estimate(_ request: ExpiryRequest, calibration: ExpiryCalibrationAdjustment = .none) -> ExpiryEstimate {
        let expiryYear = Self.year(of: request.expiration)
        let parameters = model.parameters(for: request.profile, expiryYear: expiryYear)
        let ladder = ExpiryEILadder(iso: request.iso)

        guard request.yearsPastExpiry > 0 else {
            return notExpired(request, parameters: parameters, ladder: ladder, expiryYear: expiryYear)
        }

        var generator = ExpirySeededGenerator(seed: request.deterministicSeed)
        let count = max(1, sampleCount)
        var samples: [ExpirySample] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            samples.append(
                sample(
                    request: request,
                    parameters: parameters,
                    calibration: calibration,
                    variation: .everything,
                    generator: &generator
                )
            )
        }

        let sensitivity = sensitivityBreakdown(
            request: request,
            parameters: parameters,
            calibration: calibration,
            seed: request.deterministicSeed ^ 0x5DEE_CE66_D1CE_4E5B
        )

        return assemble(
            samples: samples,
            request: request,
            parameters: parameters,
            calibration: calibration,
            ladder: ladder,
            expiryYear: expiryYear,
            sensitivity: sensitivity
        )
    }

    /// The closed-form answer used the instant a control moves: the model at its
    /// mean parameters, with an uncertainty assembled from the sizes of the
    /// unknowns rather than simulated. The full estimate replaces it within a
    /// frame or two, but the screen never waits.
    func quickEstimate(
        _ request: ExpiryRequest,
        calibration: ExpiryCalibrationAdjustment = .none
    ) -> ExpiryEstimate {
        let expiryYear = Self.year(of: request.expiration)
        let parameters = model.parameters(for: request.profile, expiryYear: expiryYear)
        let ladder = ExpiryEILadder(iso: request.iso)

        guard request.yearsPastExpiry > 0 else {
            return notExpired(request, parameters: parameters, ladder: ladder, expiryYear: expiryYear)
        }

        var generator = ExpirySeededGenerator(seed: request.deterministicSeed)
        let single = sample(
            request: request,
            parameters: parameters,
            calibration: calibration,
            variation: .nothing,
            generator: &generator
        )

        let unknownStorage = request.timeline.containsUnknown
        let segmentPenalty: Double = unknownStorage
            ? 0.45
            : 0.10 * Double(max(0, request.timeline.segments.count - 1))
        let evidencePenalty: Double = parameters.evidence == .assumed ? 0.30 : 0
        let uncertainty: Double = 0.22 + 0.10 * single.stops + segmentPenalty + evidencePenalty

        let samples = [
            single,
            single.with(stops: max(0, single.stops - uncertainty)),
            single.with(stops: single.stops + uncertainty)
        ]

        return assemble(
            samples: samples,
            request: request,
            parameters: parameters,
            calibration: calibration,
            ladder: ladder,
            expiryYear: expiryYear,
            sensitivity: [],
            isQuick: true
        )
    }

    // MARK: - Sampling

    private enum Variation {
        case everything
        case storageOnly
        case shelfOnly
        case materialOnly
        case nothing

        var variesShelf: Bool { self == .everything || self == .shelfOnly }
        var variesStorage: Bool { self == .everything || self == .storageOnly }
        var variesMaterial: Bool { self == .everything || self == .materialOnly }
    }

    private struct ExpirySample: Sendable {
        var stops: Double
        var fogIncrease: Double
        var thermalFog: Double
        var radiationFog: Double
        var thermalYears: Double
        var radiationYears: Double
        var shelfLife: Double
        var saturated: Bool

        func with(stops newStops: Double) -> ExpirySample {
            var copy = self
            copy.stops = max(0, newStops)
            return copy
        }
    }

    private func sample(
        request: ExpiryRequest,
        parameters: ExpiryResolvedParameters,
        calibration: ExpiryCalibrationAdjustment,
        variation: Variation,
        generator: inout ExpirySeededGenerator
    ) -> ExpirySample {
        let parts = request.timeline.normalised
        let expiredYears = min(200, max(0, request.yearsPastExpiry))

        // 1. The printed date is a point on a distribution, not a fact about
        //    manufacture: dating conventions vary by maker, family and era.
        let shelfLife: Double
        if variation.variesShelf {
            let draw = parameters.shelfLifeYears.clampedMean
                + parameters.shelfLifeYears.deviation * generator.normal()
            shelfLife = min(20, max(parameters.shelfLifeYears.minimum, draw))
        } else {
            shelfLife = parameters.shelfLifeYears.clampedMean
        }

        // 2. Activation energy.
        let activationEnergy: Double
        if variation.variesMaterial {
            let draw = parameters.activationEnergyEV.clampedMean
                + parameters.activationEnergyEV.deviation * generator.normal()
            activationEnergy = min(1.4, max(0.15, draw))
        } else {
            activationEnergy = parameters.activationEnergyEV.clampedMean
        }

        // 3. Integrate storage. Rates are averaged, not temperatures, so the
        //    convexity of the Arrhenius curve does the work of making a spike
        //    cost more than the same warmth spread evenly.
        var weightedRate = 0.0
        var radiationWeight = 0.0
        for part in parts {
            var tier = part.tier
            if tier.isUnknown {
                tier = variation.variesStorage ? Self.drawUnknownTier(generator: &generator) : .roomTemperature
            }

            let climate = tier.climate
            let deviation = variation.variesStorage ? climate.effectiveDeviation : 0
            let celsius = climate.meanCelsius + (deviation > 0 ? deviation * generator.normal() : 0)
            let rate = Self.thermalRate(celsius: celsius, activationEnergyEV: activationEnergy)

            weightedRate += part.fraction * rate
            radiationWeight += part.fraction * (tier == .frozen ? Self.frozenRadiationFactor : 1)
        }
        weightedRate = min(60, max(0.02, weightedRate))

        // 4. Damage accrued by the printed date is the manufacturer's own
        //    tolerance. Compensation is the change beyond it, which is why a
        //    film a few months past its date barely moves.
        let thermalAtExpiry = shelfLife * weightedRate
        let thermalTotal = (shelfLife + expiredYears) * weightedRate
        let thermalYears = max(0, thermalTotal - thermalAtExpiry)
        let radiationYears = expiredYears * radiationWeight

        func progress(_ timeConstant: Double) -> Double {
            let constant = max(1, timeConstant)
            let total = 1 - exp(-thermalTotal / constant)
            let atExpiry = 1 - exp(-thermalAtExpiry / constant)
            return max(0, min(1, total - atExpiry))
        }

        // 5. Fog. Thermal fog saturates against the antifoggant reserve;
        //    radiation fog does not, but it is slow and bounded in practice.
        let thermalFog = parameters.fogCeiling * progress(parameters.fogTimeConstantYears)
        let radiationSensitivity: Double
        if variation.variesMaterial {
            let draw = parameters.radiationSensitivity.clampedMean
                + parameters.radiationSensitivity.deviation * generator.normal()
            radiationSensitivity = min(4, max(0.05, draw))
        } else {
            radiationSensitivity = parameters.radiationSensitivity.clampedMean
        }
        let radiationRate = max(
            Self.minimumRadiationFogPerYear,
            Self.baseRadiationFogPerYear * radiationSensitivity
        )
        let radiationFog = min(0.4, radiationRate * radiationYears)
        let fogIncrease = thermalFog + radiationFog

        // 6. Contrast, shoulder and speed.
        let gammaAged = max(
            0.12,
            parameters.freshGamma * (1 - parameters.gammaLossFraction * progress(parameters.gammaTimeConstantYears))
        )
        // Fog is developed silver like any other density, so it eats into the
        // density the shoulder can still deliver. That is what makes saturation
        // arrive on its own at the extreme end: once fog has taken most of the
        // maximum density, no exposure can put a shadow above it.
        let densityLost = parameters.densityLoss * progress(parameters.densityTimeConstantYears)
        let maxDensity = max(
            parameters.freshBaseFog + 0.12,
            parameters.freshMaxDensity - densityLost - 0.9 * thermalFog - 0.6 * radiationFog
        )
        let speedStops = min(
            4,
            max(0, parameters.speedLossStops * progress(parameters.speedTimeConstantYears))
        )

        // 7. Invert both curves for the same shadow criterion. Compensation is
        //    the difference: what the aged film needs that the fresh one did
        //    not.
        let freshCurve = ExpiryCharacteristicCurve(
            baseFog: parameters.freshBaseFog,
            gamma: parameters.freshGamma,
            maxDensity: parameters.freshMaxDensity,
            toeDecades: parameters.toeDecades,
            speedShiftDecades: 0
        )
        let agedCurve = ExpiryCharacteristicCurve(
            baseFog: parameters.freshBaseFog + fogIncrease,
            gamma: gammaAged,
            maxDensity: maxDensity,
            toeDecades: parameters.toeDecades,
            speedShiftDecades: speedStops * log10(2)
        )

        let separation = Self.shadowSeparation + Self.fogGranularityCoefficient * fogIncrease
        let freshExposure = freshCurve.decades(forDensity: freshCurve.baseFog + Self.shadowSeparation) ?? 0

        var saturated = false
        var stops: Double
        if let agedExposure = agedCurve.decades(forDensity: agedCurve.baseFog + separation) {
            stops = max(0, (agedExposure - freshExposure) / log10(2))
        } else {
            saturated = true
            stops = parameters.saturationStops
        }

        stops += calibration.deltaStops
        if stops >= parameters.saturationStops {
            stops = parameters.saturationStops
            saturated = true
        }
        if !stops.isFinite || stops < 0 { stops = 0 }

        return ExpirySample(
            stops: stops,
            fogIncrease: fogIncrease,
            thermalFog: thermalFog,
            radiationFog: radiationFog,
            thermalYears: thermalYears,
            radiationYears: radiationYears,
            shelfLife: shelfLife,
            saturated: saturated
        )
    }

    static func drawUnknownTier(generator: inout ExpirySeededGenerator) -> ExpiryStorageTier {
        let draw = generator.unit()
        var accumulated = 0.0
        for entry in ExpiryStorageTier.unknownMixture {
            accumulated += entry.weight
            if draw <= accumulated { return entry.tier }
        }
        return .roomTemperature
    }

    /// Arrhenius acceleration relative to the cool-room reference. The default
    /// activation energies were chosen so this reproduces the relative rates
    /// the model documents: roughly 0.3× in a fridge, 1.5× in a warm room and
    /// 3× in an attic. That is a calibration choice, not a measurement.
    static func thermalRate(celsius: Double, activationEnergyEV: Double) -> Double {
        let kelvin = max(55, celsius + 273.15)
        let reference = referenceCelsius + 273.15
        let exponent = (activationEnergyEV / gasConstantEV) * (1 / reference - 1 / kelvin)
        let rate = exp(min(8, max(-20, exponent)))
        return min(50, max(0.02, rate))
    }

    // MARK: - Sensitivity

    /// One factor varied at a time, so the explainability section can say which
    /// unknown is actually driving the spread instead of guessing at it.
    private func sensitivityBreakdown(
        request: ExpiryRequest,
        parameters: ExpiryResolvedParameters,
        calibration: ExpiryCalibrationAdjustment,
        seed: UInt64
    ) -> [(title: String, deviation: Double)] {
        let count = 240
        var results: [(String, Double)] = []

        for (title, variation) in [
            ("Storage temperature", Variation.storageOnly),
            ("Shelf-life convention", Variation.shelfOnly),
            ("Emulsion parameters", Variation.materialOnly)
        ] {
            var generator = ExpirySeededGenerator(seed: seed &+ UInt64(results.count &+ 1) &* 0x9E37_79B9)
            var values: [Double] = []
            values.reserveCapacity(count)
            for _ in 0..<count {
                values.append(
                    sample(
                        request: request,
                        parameters: parameters,
                        calibration: calibration,
                        variation: variation,
                        generator: &generator
                    ).stops
                )
            }
            results.append((title, Self.deviation(of: values)))
        }

        return results
    }

    // MARK: - Assembly

    private func assemble(
        samples: [ExpirySample],
        request: ExpiryRequest,
        parameters: ExpiryResolvedParameters,
        calibration: ExpiryCalibrationAdjustment,
        ladder: ExpiryEILadder,
        expiryYear: Int,
        sensitivity: [(title: String, deviation: Double)],
        isQuick: Bool = false
    ) -> ExpiryEstimate {
        let clamped = samples.map { $0.stops.isFinite ? max(0, min(12, $0.stops)) : parameters.saturationStops }
        let sorted = clamped.sorted()
        let p10 = Self.percentile(sorted, 0.10)
        let p50 = Self.percentile(sorted, 0.50)
        let p90 = Self.percentile(sorted, 0.90)

        // Every figure the screen shows is snapped to a third of a stop, and a
        // range is widened to the step it contains rather than narrowed.
        let medianIndex = max(-12, min(60, ladder.index(nearest: p50)))
        let lowIndex = max(-12, min(60, ladder.index(roundingUp: p90)))
        let highIndex = max(-12, min(60, ladder.index(roundingDown: p10)))
        let eiLow = ladder.ei(at: max(lowIndex, medianIndex))
        let eiHigh = ladder.ei(at: min(highIndex, medianIndex))

        let saturatedShare = Double(samples.filter(\.saturated).count) / Double(max(1, samples.count))
        let isSaturated = saturatedShare >= 0.4

        let medianSample = samples.min { abs($0.stops - p50) < abs($1.stops - p50) }
        let fogIncrease = medianSample?.fogIncrease ?? 0
        let thermalFog = medianSample?.thermalFog ?? 0
        let radiationFog = medianSample?.radiationFog ?? 0
        let thermalYears = medianSample?.thermalYears ?? 0
        let shelfLife = medianSample?.shelfLife ?? parameters.shelfLifeYears.clampedMean
        let ageYears = shelfLife + max(0, request.yearsPastExpiry)

        let bag = ConfidenceInputs(
            parameters: parameters,
            request: request,
            spread: p90 - p10,
            hasShelfData: !isQuick
        )
        let confidenceScore = bag.score
        let confidence = Self.confidence(for: confidenceScore)

        let explanation = Self.explanation(
            request: request,
            parameters: parameters,
            so: ExpirySummary(
                eiMedian: ladder.ei(at: medianIndex),
                stops: p50,
                fogIncrease: fogIncrease,
                thermalYears: thermalYears,
                shelfLife: shelfLife,
                ageYears: ageYears
            )
        )

        let warnings = Self.warnings(
            request: request,
            parameters: parameters,
            fogIncrease: fogIncrease,
            thermalFog: thermalFog,
            radiationFog: radiationFog,
            ageYears: ageYears,
            isSaturated: isSaturated
        )

        let bracketing = Self.bracketing(
            request: request,
            ladder: ladder,
            medianIndex: medianIndex,
            lowStops: p10,
            highStops: p90,
            confidence: confidence,
            isSaturated: isSaturated
        )

        let contributions = Self.contributions(
            parameters: parameters,
            ladder: ladder,
            medianIndex: medianIndex,
            p10: p10,
            p90: p90,
            fogIncrease: fogIncrease,
            thermalFog: thermalFog,
            radiationFog: radiationFog,
            thermalYears: thermalYears,
            shelfLife: shelfLife,
            sensitivity: sensitivity
        )

        return ExpiryEstimate(
            requestedISO: request.iso,
            eiLow: eiLow,
            eiMedian: ladder.ei(at: medianIndex),
            eiHigh: eiHigh,
            stops: ladder.stops(at: medianIndex),
            lowStops: ladder.stops(at: highIndex),
            highStops: ladder.stops(at: lowIndex),
            confidence: confidence,
            confidenceScore: confidenceScore,
            explanation: explanation,
            warnings: warnings,
            bracketing: bracketing,
            isSaturated: isSaturated,
            contributions: contributions,
            ageYears: ageYears,
            shelfLifeYears: shelfLife,
            manufactureYear: expiryYear - Int(shelfLife.rounded()),
            equivalentThermalYears: thermalYears,
            fogIncrease: fogIncrease,
            group: parameters.group,
            isExpired: true,
            calibrationDelta: calibration.deltaStops,
            sampleCount: samples.count
        )
    }

    /// The model's compensation at its mean parameters, in unrounded stops and
    /// before any logged roll has adjusted it. A logged roll's residual is
    /// measured against this, so the baseline is never rounded to a third of a
    /// stop and never carries an earlier roll's correction.
    func baselineStops(_ request: ExpiryRequest) -> Double {
        guard request.yearsPastExpiry > 0 else { return 0 }
        let parameters = model.parameters(for: request.profile, expiryYear: Self.year(of: request.expiration))
        var generator = ExpirySeededGenerator(seed: request.deterministicSeed)
        return sample(
            request: request,
            parameters: parameters,
            calibration: .none,
            variation: .nothing,
            generator: &generator
        ).stops
    }

    private func notExpired(
        _ request: ExpiryRequest,
        parameters: ExpiryResolvedParameters,
        ladder: ExpiryEILadder,
        expiryYear: Int
    ) -> ExpiryEstimate {
        let box = ladder.ei(at: 0)
        let months = max(0, Int((-request.yearsPastExpiry * 12).rounded()))
        let shelfLife = parameters.shelfLifeYears.clampedMean
        let ageYears = shelfLife + request.yearsPastExpiry

        var warnings: [ExpiryWarning] = []
        if request.timeline.containsUnknown {
            warnings.append(
                ExpiryWarning(
                    id: "storage-unknown",
                    title: "Storage is unknown",
                    detail: "Within its date the rating holds, but a roll of unknown history is still worth a second frame.",
                    isSevere: false
                )
            )
        }

        // The maker's rating is documented, but it is a rating for storage the
        // maker expected. Unknown storage lowers the score, and an unlisted stock
        // with no evidence behind its rating cannot claim documentation at all.
        var score = ExpiryEvidenceClass.manufacturerDocumented.confidenceCap
            * (0.5 + 0.5 * request.timeline.certainty)
        if request.profile.evidence == .assumed {
            score = Swift.min(score, 0.47)
        }

        return ExpiryEstimate(
            requestedISO: request.iso,
            eiLow: box,
            eiMedian: box,
            eiHigh: box,
            stops: 0,
            lowStops: 0,
            highStops: 0,
            confidence: Self.confidence(for: score),
            confidenceScore: score,
            explanation: months > 0
                ? "Not expired: the printed date is about \(months) month\(months == 1 ? "" : "s") away, so the film is still inside the range its maker rates it for. Rate it at box speed, EI \(box)."
                : "Not expired, so the film is still rated as its maker specifies. Rate it at box speed, EI \(box).",
            warnings: warnings,
            bracketing: nil,
            isSaturated: false,
            contributions: [
                ExpiryContribution(
                    id: "status",
                    title: "Inside its date",
                    value: "0 stops",
                    detail: "No compensation is applied until the printed date has passed; the manufacturer's rating covers this period."
                ),
                ExpiryContribution(
                    id: "shelf",
                    title: "Assumed shelf life",
                    value: String(format: "%.1f ± %.1f years", shelfLife, parameters.shelfLifeYears.deviation),
                    detail: "The interval between coating and the printed date, used to date the film's manufacture."
                ),
                ExpiryContribution(
                    id: "family",
                    title: "Film family",
                    value: parameters.group.title,
                    detail: parameters.group.detail
                )
            ],
            ageYears: ageYears,
            shelfLifeYears: shelfLife,
            manufactureYear: expiryYear - Int(shelfLife.rounded()),
            equivalentThermalYears: 0,
            fogIncrease: 0,
            group: parameters.group,
            isExpired: false,
            calibrationDelta: 0,
            sampleCount: 1
        )
    }

    // MARK: - Confidence

    private struct ConfidenceInputs {
        var parameters: ExpiryResolvedParameters
        var request: ExpiryRequest
        var spread: Double
        var hasShelfData: Bool

        /// A narrow simulated range is not on its own evidence of anything, so
        /// the evidence class sets a ceiling the number cannot pass.
        var score: Double {
            let storage = request.timeline.certainty
            let spreadScore = max(0, min(1, 1 - spread / 3.0))
            let baseEvidence = parameters.evidence.weight * 0.5
            var score = baseEvidence + 0.2 * storage + 0.3 * spreadScore
            if request.profile.hasCuratedProfile { score += 0.04 }
            if !request.profile.baseMaterialIsAssumed { score += 0.02 }
            if !hasShelfData { score -= 0.08 }

            return max(0, min(parameters.evidence.confidenceCap, score))
        }
    }

    static func confidence(for score: Double) -> ExpiryConfidence {
        if score >= 0.74 { return .wellDocumented }
        if score >= 0.48 { return .communityConsensus }
        return .educatedGuess
    }

    // MARK: - Wording

    private struct ExpirySummary {
        var eiMedian: Int
        var stops: Double
        var fogIncrease: Double
        var thermalYears: Double
        var shelfLife: Double
        var ageYears: Double
    }

    private static func explanation(
        request: ExpiryRequest,
        parameters: ExpiryResolvedParameters,
        so summary: ExpirySummary
    ) -> String {
        let years = max(0, request.yearsPastExpiry)
        let yearsText = years < 1
            ? String(format: "%.0f months", years * 12)
            : String(format: "%.1f years", years)

        if summary.stops < 0.34 {
            return "About \(yearsText) past its date, in \(request.timeline.summary.lowercased()) storage. The model finds almost no change to the film's speed, so box speed is still the right place to stand: EI \(request.iso)."
        }

        let stopsText = String(format: "%.1f", summary.stops)
        let fogText = String(format: "%.2f", summary.fogIncrease)

        return "About \(yearsText) past its date, in \(request.timeline.summary.lowercased()) storage, the film is estimated to have gained \(fogText) of base fog and to need \(stopsText) stop\(summary.stops >= 1.05 ? "s" : "") more light to put your shadows back where they sat when it was fresh. That is EI \(summary.eiMedian)."
    }

    private static func warnings(
        request: ExpiryRequest,
        parameters: ExpiryResolvedParameters,
        fogIncrease: Double,
        thermalFog: Double,
        radiationFog: Double,
        ageYears: Double,
        isSaturated: Bool
    ) -> [ExpiryWarning] {
        var warnings: [ExpiryWarning] = []

        if isSaturated {
            warnings.append(
                ExpiryWarning(
                    id: "saturated",
                    title: "Compensation has run out",
                    detail: "More exposure will not bring back useful shadow detail: the film's maximum density has fallen too close to its fog for a shadow to separate from it. Exposure is not the limiting factor any more.",
                    isSevere: true
                )
            )
        }

        if parameters.isColour, fogIncrease >= 0.09 + 0.05 * (1 - parameters.layerCrossoverSensitivity) {
            warnings.append(
                ExpiryWarning(
                    id: "crossover",
                    title: "Colour crossover likely",
                    detail: "The three colour layers age at different rates, so the casts that appear in the shadows, midtones and highlights will not agree. No exposure setting corrects that; it can only be graded, and imperfectly.",
                    isSevere: false
                )
            )
        }

        if request.profile.baseMaterial.canHydrolyse, ageYears >= 25 {
            warnings.append(
                ExpiryWarning(
                    id: "acetate",
                    title: "Acetate base may be deteriorating",
                    detail: "An acetate base has been reacting with moisture for a long time. Vinegar syndrome — the sharp acidic smell, buckling, and finally brittleness — is a physical change, and no exposure or processing choice reverses it.",
                    isSevere: false
                )
            )
        } else if request.profile.baseMaterial == .unknown, ageYears >= 30 {
            warnings.append(
                ExpiryWarning(
                    id: "base-unrecorded",
                    title: "Base material not recorded",
                    detail: "This film's base is not documented in the library, so whether it is acetate or polyester is unknown. Polyester keeps far better; acetate can hydrolyse.",
                    isSevere: false
                )
            )
        }

        if radiationFog > thermalFog * 1.5, radiationFog > 0.05 {
            warnings.append(
                ExpiryWarning(
                    id: "radiation",
                    title: "Fog is mostly from radiation, not heat",
                    detail: "Cold storage has slowed the thermal side, but background radiation fog keeps accumulating at any temperature. It shows as an even veil rather than a colour shift.",
                    isSevere: false
                )
            )
        }

        if ageYears > 45 {
            warnings.append(
                ExpiryWarning(
                    id: "extrapolation",
                    title: "Beyond the model's footing",
                    detail: "Past about four decades, none of these ageing curves has been checked against anything. The number is an extrapolation, and a wide one.",
                    isSevere: false
                )
            )
        }

        return warnings
    }

    private static func bracketing(
        request: ExpiryRequest,
        ladder: ExpiryEILadder,
        medianIndex: Int,
        lowStops: Double,
        highStops: Double,
        confidence: ExpiryConfidence,
        isSaturated: Bool
    ) -> String? {
        guard !isSaturated else { return nil }
        let spread = highStops - lowStops
        guard spread >= 0.9 || confidence == .educatedGuess else { return nil }

        let median = ladder.label(at: medianIndex)
        let under = ladder.label(at: medianIndex + 1)
        let over = ladder.label(at: medianIndex - 1)
        return "The range is wide enough that bracketing is worth the frames: shoot one at \(over) (a third over), one at \(median), and one at \(under) (a third under), and keep the one that scans best."
    }

    private static func contributions(
        parameters: ExpiryResolvedParameters,
        ladder: ExpiryEILadder,
        medianIndex: Int,
        p10: Double,
        p90: Double,
        fogIncrease: Double,
        thermalFog: Double,
        radiationFog: Double,
        thermalYears: Double,
        shelfLife: Double,
        sensitivity: [(title: String, deviation: Double)]
    ) -> [ExpiryContribution] {
        var rows: [ExpiryContribution] = []

        rows.append(
            ExpiryContribution(
                id: "thermal",
                title: "Thermal ageing",
                value: String(format: "%.1f equivalent years", thermalYears),
                detail: "The storage timeline integrated at the cool-room reference temperature, using an Arrhenius rate with an activation energy of about \(String(format: "%.2f", parameters.activationEnergyEV.mean)) eV. It accounts for \(String(format: "%.2f", thermalFog)) of the fog."
            )
        )

        rows.append(
            ExpiryContribution(
                id: "radiation",
                title: "Radiation ageing",
                value: String(format: "%.2f log D", radiationFog),
                detail: "Counted separately from heat and never switched off by cold storage, with a floor of \(String(format: "%.4f", minimumRadiationFogPerYear)) per year so freezing cannot pretend the clock stopped."
            )
        )

        rows.append(
            ExpiryContribution(
                id: "fog",
                title: "Base fog",
                value: String(format: "%.2f log D above fresh", fogIncrease),
                detail: "Raising fog narrows the density a shadow can separate from, and the model treats a foggier film as needing a wider gap for detail to read."
            )
        )

        rows.append(
            ExpiryContribution(
                id: "shelf",
                title: "Shelf-life uncertainty",
                value: String(format: "%.1f ± %.1f years", shelfLife, parameters.shelfLifeYears.deviation),
                detail: "The printed date is not a manufacture date. The interval between coating and dating is a distribution, so the film's true age is uncertain by that much either way."
            )
        )

        if let top = sensitivity.max(by: { $0.deviation < $1.deviation }), top.deviation > 0 {
            let share = sensitivity.reduce(0) { $0 + $1.deviation * $1.deviation }
            let percent = share > 0 ? Int((top.deviation * top.deviation / share * 100).rounded()) : 0
            rows.append(
                ExpiryContribution(
                    id: "uncertainty",
                    title: "Top uncertainty",
                    value: top.title,
                    detail: "Varying that one input alone moves the answer by about ±\(String(format: "%.2f", top.deviation)) stops, around \(percent)% of the modelled spread. It is the first thing worth pinning down."
                )
            )
        }

        rows.append(
            ExpiryContribution(
                id: "curve",
                title: "Curve assumption",
                value: String(format: "γ %.2f, Dmax %.1f", parameters.freshGamma, parameters.freshMaxDensity),
                detail: "The fresh curve is a typical one for this family, not a measured sensitometric trace of this box. The compensation is the difference between the aged and fresh curves, so a different curve would move both together."
            )
        )

        rows.append(
            ExpiryContribution(
                id: "range",
                title: "Simulated range",
                value: "\(ladder.label(at: ladder.index(roundingDown: p10))) – \(ladder.label(at: ladder.index(roundingUp: p90)))",
                detail: "The 10th to 90th percentile of the simulated exposure indices. Wide is not the same as wrong: it is the model saying how much it does not know."
            )
        )

        return rows
    }

    // MARK: - Statistics

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = max(0, min(1, fraction)) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let blend = position - Double(lower)
        return sorted[lower] * (1 - blend) + sorted[upper] * blend
    }

    static func deviation(of values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    static func mean(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
