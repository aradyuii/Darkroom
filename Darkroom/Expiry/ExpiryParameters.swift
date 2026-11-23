//
//  ExpiryParameters.swift
//  Darkroom
//
//  The parameter table behind the expired-film model: one entry per behaviour
//  group, the named films that depart from their group, the era adjustment, and
//  the rules that place every film in the library somewhere sensible.
//
//  What is documented and what is chosen is marked field by field. The
//  manufacturers publish storage guidance and dated stock; they do not publish
//  Arrhenius coefficients for a given emulsion. Everything that is a chosen
//  number says so, and the JSON table beside this file can replace any of it
//  without touching this code.
//

import Foundation

// MARK: - A named film's departures from its group

struct ExpiryFilmOverride: Codable, Hashable, Sendable {
    var filmKey: String
    var group: ExpiryBehaviourGroup?
    var overrides: ExpiryParameterOverride?
    var evidence: ExpiryEvidenceClass
    var note: String?

    init(
        filmKey: String,
        group: ExpiryBehaviourGroup? = nil,
        overrides: ExpiryParameterOverride? = nil,
        evidence: ExpiryEvidenceClass = .assumed,
        note: String? = nil
    ) {
        self.filmKey = filmKey
        self.group = group
        self.overrides = overrides
        self.evidence = evidence
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filmKey = try container.decode(String.self, forKey: .filmKey)
        group = try container.decodeIfPresent(ExpiryBehaviourGroup.self, forKey: .group)
        overrides = try container.decodeIfPresent(ExpiryParameterOverride.self, forKey: .overrides)
        evidence = try container.decodeIfPresent(ExpiryEvidenceClass.self, forKey: .evidence) ?? .assumed
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

/// The JSON table that carries the named-film departures. Internal so a test can
/// decode a table and check it lands on the film it names.
struct ExpiryOverrideDocument: Decodable {
    var schema: Int?
    var sources: [ExpirySource]?
    var films: [ExpiryFilmOverride]
}

// MARK: - Resolved parameters

/// A group's parameters after the film's overrides and the era adjustment have
/// been folded in. Plain values, so it can cross a task boundary.
struct ExpiryResolvedParameters: Sendable {
    var group: ExpiryBehaviourGroup
    var isColour: Bool
    var layerCrossoverSensitivity: Double

    var activationEnergyEV: ExpiryDistribution
    var shelfLifeYears: ExpiryDistribution

    var freshBaseFog: Double
    var freshGamma: Double
    var freshMaxDensity: Double
    var toeDecades: Double

    var fogCeiling: Double
    var fogTimeConstantYears: Double
    var gammaLossFraction: Double
    var gammaTimeConstantYears: Double
    var densityLoss: Double
    var densityTimeConstantYears: Double
    var speedLossStops: Double
    var speedTimeConstantYears: Double
    var radiationSensitivity: ExpiryDistribution
    var saturationStops: Double
    var latitudeStops: Double

    var evidence: ExpiryEvidenceClass
    var eraNote: String?
}

// MARK: - The table

struct ExpiryModel: Sendable {
    var groups: [ExpiryBehaviourGroup: ExpiryGroupParameters]
    var curated: [String: ExpiryFilmOverride]
    /// Every published document a parameter in this model leans on, carried
    /// beside the numbers rather than in a separate essay.
    var sources: [ExpirySource] = []

    /// The table the app runs with: the group priors in this file, plus the
    /// named-film departures from `expiry-overrides.json` when it is present.
    static let standard: ExpiryModel = load(bundle: .main)

    // MARK: Loading

    static func load(bundle: Bundle) -> ExpiryModel {
        var model = ExpiryModel(groups: defaultGroups, curated: [:])
        let document = loadOverrides(bundle: bundle)
        for entry in document.films {
            model.curated[entry.filmKey] = entry
        }
        model.sources = document.sources ?? []
        return model
    }

    private static func loadOverrides(bundle: Bundle) -> ExpiryOverrideDocument {
        var urls: [URL] = []
        for subdirectory in ["Library", "Resources/Library", nil] {
            let found = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? []
            for url in found where url.lastPathComponent == "expiry-overrides.json" {
                urls.append(url)
            }
        }
        guard let url = urls.first,
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(ExpiryOverrideDocument.self, from: data) else {
            return ExpiryOverrideDocument(schema: nil, sources: [], films: [])
        }
        return document
    }

    func source(key: String?) -> ExpirySource? {
        guard let key else { return nil }
        return sources.first { $0.key == key }
    }

    // MARK: Placement

    /// Places a library film in a behaviour group, preferring a curated reading
    /// and falling back to the rules.
    func profile(for film: LibraryFilm) -> ExpiryFilmProfile {
        let curated = curated[film.key]
        let rule = ExpiryCatalogue.ruleGroup(for: film)
        let group = curated?.group ?? rule.group
        let base = ExpiryCatalogue.baseMaterial(for: film)

        return ExpiryFilmProfile(
            filmKey: film.key,
            displayName: film.displayName,
            manufacturer: film.manufacturer,
            iso: film.iso,
            process: film.process,
            status: film.status,
            group: group,
            groupReason: curated?.group != nil ? "Named profile" : rule.reason,
            baseMaterial: base.material,
            baseMaterialIsAssumed: base.isAssumed,
            overrides: curated?.overrides ?? ExpiryParameterOverride(),
            evidence: curated?.evidence ?? ExpiryCatalogue.evidence(for: film, group: group),
            note: curated?.note,
            hasCuratedProfile: curated != nil
        )
    }

    /// A profile for an emulsion the library does not hold, so nothing the
    /// reader types can fail to produce an answer.
    func profile(forUnknown name: String, iso: Int, process: FilmProcess) -> ExpiryFilmProfile {
        ExpiryFilmProfile(
            filmKey: "unlisted",
            displayName: name.isEmpty ? "Unlisted film \(iso)" : "\(name) \(iso)",
            manufacturer: "",
            iso: max(1, iso),
            process: process,
            status: .current,
            group: .other,
            groupReason: "Not in the library",
            baseMaterial: .unknown,
            baseMaterialIsAssumed: true,
            overrides: ExpiryParameterOverride(),
            evidence: .assumed,
            note: nil,
            hasCuratedProfile: false
        )
    }

    // MARK: Resolution

    func parameters(for profile: ExpiryFilmProfile, expiryYear: Int) -> ExpiryResolvedParameters {
        let group = groups[profile.group] ?? Self.fallbackGroup
        let era = ExpiryCatalogue.era(expiryYear: expiryYear)
        let overrides = profile.overrides

        let thermal = overrides.thermalSensitivity ?? 1
        let antifog = overrides.antifoggantRobustness ?? 1
        let eraStability = overrides.sensitizerEraFactor ?? era.stability

        let activationBase = overrides.activationEnergyEV ?? group.activationEnergyEV
        let activation = ExpiryDistribution(
            mean: max(0.2, activationBase.mean * thermal),
            deviation: max(0, activationBase.deviation * abs(thermal)),
            minimum: 0.2
        )

        let shelfBase = overrides.shelfLifeYears ?? group.shelfLifeYears
        let shelf = ExpiryDistribution(
            mean: max(0.4, shelfBase.mean * era.shelf),
            deviation: max(0.05, shelfBase.deviation * era.shelf),
            minimum: 0.25
        )

        func time(_ groupValue: Double, _ override: Double?) -> Double {
            max(4, (override ?? groupValue) * eraStability)
        }

        return ExpiryResolvedParameters(
            group: profile.group,
            isColour: profile.group.isColour,
            layerCrossoverSensitivity: profile.group.layerCrossoverSensitivity,
            activationEnergyEV: activation,
            shelfLifeYears: shelf,
            freshBaseFog: overrides.freshBaseFog ?? group.freshBaseFog,
            freshGamma: overrides.freshGamma ?? group.freshGamma,
            freshMaxDensity: overrides.freshMaxDensity ?? group.freshMaxDensity,
            toeDecades: overrides.toeDecades ?? group.toeDecades,
            fogCeiling: max(0.02, (overrides.fogCeiling ?? group.fogCeiling) * antifog),
            fogTimeConstantYears: time(group.fogTimeConstantYears, overrides.fogTimeConstantYears),
            gammaLossFraction: min(0.8, overrides.gammaLossFraction ?? group.gammaLossFraction),
            gammaTimeConstantYears: time(group.gammaTimeConstantYears, overrides.gammaTimeConstantYears),
            densityLoss: min(1.5, overrides.densityLoss ?? group.densityLoss),
            densityTimeConstantYears: time(group.densityTimeConstantYears, overrides.densityTimeConstantYears),
            speedLossStops: min(4, overrides.speedLossStops ?? group.speedLossStops),
            speedTimeConstantYears: time(group.speedTimeConstantYears, overrides.speedTimeConstantYears),
            radiationSensitivity: overrides.radiationSensitivity ?? group.radiationSensitivity,
            saturationStops: max(2, overrides.saturationStops ?? group.saturationStops),
            latitudeStops: group.latitudeStops,
            evidence: profile.evidence,
            eraNote: era.note
        )
    }

    static let fallbackGroup = ExpiryGroupParameters(
        activationEnergyEV: ExpiryDistribution(mean: 0.62, deviation: 0.15, minimum: 0.2),
        shelfLifeYears: ExpiryDistribution(mean: 2.0, deviation: 1.2, minimum: 0.25),
        freshBaseFog: 0.10,
        freshGamma: 0.60,
        freshMaxDensity: 2.4,
        toeDecades: 0.55,
        fogCeiling: 0.50,
        fogTimeConstantYears: 50,
        gammaLossFraction: 0.28,
        gammaTimeConstantYears: 50,
        densityLoss: 0.50,
        densityTimeConstantYears: 55,
        speedLossStops: 1.0,
        speedTimeConstantYears: 45,
        radiationSensitivity: ExpiryDistribution(mean: 1.2, deviation: 0.5, minimum: 0.2),
        saturationStops: 5,
        latitudeStops: 2,
        notes: "The conservative fallback used when a group is somehow missing.",
        evidence: .assumed("Fallback parameters")
    )

    // MARK: Group priors

    /// The eight behaviour groups. Every coefficient here is an engineering
    /// prior informed by how these families are described to behave; none of
    /// them is a published measurement of an ageing rate.
    static let defaultGroups: [ExpiryBehaviourGroup: ExpiryGroupParameters] = [
        .slowModernBW: ExpiryGroupParameters(
            activationEnergyEV: ExpiryDistribution(mean: 0.65, deviation: 0.10, minimum: 0.2),
            shelfLifeYears: ExpiryDistribution(mean: 2.5, deviation: 0.9, minimum: 0.25),
            freshBaseFog: 0.06,
            freshGamma: 0.62,
            freshMaxDensity: 2.60,
            toeDecades: 0.50,
            fogCeiling: 0.28,
            fogTimeConstantYears: 70,
            gammaLossFraction: 0.15,
            gammaTimeConstantYears: 75,
            densityLoss: 0.30,
            densityTimeConstantYears: 80,
            speedLossStops: 0.45,
            speedTimeConstantYears: 65,
            radiationSensitivity: ExpiryDistribution(mean: 0.80, deviation: 0.25, minimum: 0.1),
            saturationStops: 6.0,
            latitudeStops: 2.0,
            notes: "Fine-grain tabular and epitaxial monochrome. The best-keeping family: small crystals, heavy stabiliser load, and a long reputation for surviving storage.",
            evidence: .assumed("Group coefficients are priors; shelf-life convention is manufacturer practice.")
        ),
        .classicBW: ExpiryGroupParameters(
            activationEnergyEV: ExpiryDistribution(mean: 0.62, deviation: 0.10, minimum: 0.2),
            shelfLifeYears: ExpiryDistribution(mean: 2.5, deviation: 0.9, minimum: 0.25),
            freshBaseFog: 0.08,
            freshGamma: 0.60,
            freshMaxDensity: 2.50,
            toeDecades: 0.55,
            fogCeiling: 0.36,
            fogTimeConstantYears: 60,
            gammaLossFraction: 0.18,
            gammaTimeConstantYears: 60,
            densityLoss: 0.40,
            densityTimeConstantYears: 65,
            speedLossStops: 0.62,
            speedTimeConstantYears: 52,
            radiationSensitivity: ExpiryDistribution(mean: 1.00, deviation: 0.30, minimum: 0.1),
            saturationStops: 5.5,
            latitudeStops: 2.0,
            notes: "Conventional cubic monochrome around ISO 200–400. Ages more gracefully than colour, and none of it is catastrophic in the first decade.",
            evidence: .assumed("Group coefficients are priors.")
        ),
        .fastBW: ExpiryGroupParameters(
            activationEnergyEV: ExpiryDistribution(mean: 0.60, deviation: 0.10, minimum: 0.2),
            shelfLifeYears: ExpiryDistribution(mean: 2.5, deviation: 1.0, minimum: 0.25),
            freshBaseFog: 0.10,
            freshGamma: 0.58,
            freshMaxDensity: 2.40,
            toeDecades: 0.60,
            fogCeiling: 0.50,
            fogTimeConstantYears: 38,
            gammaLossFraction: 0.24,
            gammaTimeConstantYears: 45,
            densityLoss: 0.48,
            densityTimeConstantYears: 48,
            speedLossStops: 0.85,
            speedTimeConstantYears: 38,
            radiationSensitivity: ExpiryDistribution(mean: 1.25, deviation: 0.35, minimum: 0.1),
            saturationStops: 5.0,
            latitudeStops: 2.5,
            notes: "ISO 400 and above. Large crystals and a thin stabiliser margin: fog arrives sooner and speed goes sooner.",
            evidence: .assumed("Group coefficients are priors.")
        ),
        .consumerColourNegative: ExpiryGroupParameters(
            activationEnergyEV: ExpiryDistribution(mean: 0.60, deviation: 0.12, minimum: 0.2),
            shelfLifeYears: ExpiryDistribution(mean: 2.0, deviation: 0.6, minimum: 0.25),
            freshBaseFog: 0.20,
            freshGamma: 0.55,
            freshMaxDensity: 2.30,
            toeDecades: 0.45,
            fogCeiling: 0.55,
            fogTimeConstantYears: 42,
            gammaLossFraction: 0.28,
            gammaTimeConstantYears: 40,
            densityLoss: 0.45,
            densityTimeConstantYears: 45,
            speedLossStops: 0.90,
            speedTimeConstantYears: 34,
            radiationSensitivity: ExpiryDistribution(mean: 1.30, deviation: 0.40, minimum: 0.1),
            saturationStops: 4.5,
            latitudeStops: 2.5,
            notes: "Mass-market C-41. Three dye layers plus a mask, dated for roughly two years, and famously forgiving for a decade of mild overexposure.",
            evidence: .assumed("Group coefficients are priors; the two-year date is manufacturer practice.")
        ),
        .professionalColourNegative: ExpiryGroupParameters(
            activationEnergyEV: ExpiryDistribution(mean: 0.62, deviation: 0.12, minimum: 0.2),
            shelfLifeYears: ExpiryDistribution(mean: 1.75, deviation: 0.75, minimum: 0.25),
            freshBaseFog: 0.22,
            freshGamma: 0.56,
            freshMaxDensity: 2.40,
            toeDecades: 0.45,
            fogCeiling: 0.52,
            fogTimeConstantYears: 45,
            gammaLossFraction: 0.24,
            gammaTimeConstantYears: 44,
            densityLoss: 0.40,
            densityTimeConstantYears: 48,
            speedLossStops: 0.75,
            speedTimeConstantYears: 38,
            radiationSensitivity: ExpiryDistribution(mean: 1.15, deviation: 0.35, minimum: 0.1),
            saturationStops: 4.5,
            latitudeStops: 2.5,
            notes: "Pro-sheet C-41 with a shorter printed date and a cold chain expected of the reseller. Better-kept in practice, worse-kept if it sat warm in a shop.",
            evidence: .assumed("Group coefficients are priors; the shorter date is manufacturer practice.")
        ),
        .slide: ExpiryGroupParameters(
            activationEnergyEV: ExpiryDistribution(mean: 0.58, deviation: 0.12, minimum: 0.2),
            shelfLifeYears: ExpiryDistribution(mean: 2.0, deviation: 0.6, minimum: 0.25),
            freshBaseFog: 0.05,
            freshGamma: 1.35,
            freshMaxDensity: 3.40,
            toeDecades: 0.35,
            fogCeiling: 0.45,
            fogTimeConstantYears: 30,
            gammaLossFraction: 0.22,
            gammaTimeConstantYears: 34,
            densityLoss: 0.55,
            densityTimeConstantYears: 32,
            speedLossStops: 1.00,
            speedTimeConstantYears: 28,
            radiationSensitivity: ExpiryDistribution(mean: 1.10, deviation: 0.35, minimum: 0.1),
            saturationStops: 4.0,
            latitudeStops: 1.0,
            notes: "E-6 reversal. Three layers that must stay balanced with no printing stage to rescue them, so crossover comes early and exposure cannot fix it.",
            evidence: .assumed("Group coefficients are priors; the two-year date is manufacturer practice.")
        ),
        .cineECN2: ExpiryGroupParameters(
            activationEnergyEV: ExpiryDistribution(mean: 0.62, deviation: 0.12, minimum: 0.2),
            shelfLifeYears: ExpiryDistribution(mean: 2.0, deviation: 0.7, minimum: 0.25),
            freshBaseFog: 0.18,
            freshGamma: 0.55,
            freshMaxDensity: 2.50,
            toeDecades: 0.45,
            fogCeiling: 0.55,
            fogTimeConstantYears: 42,
            gammaLossFraction: 0.26,
            gammaTimeConstantYears: 40,
            densityLoss: 0.45,
            densityTimeConstantYears: 44,
            speedLossStops: 0.85,
            speedTimeConstantYears: 36,
            radiationSensitivity: ExpiryDistribution(mean: 1.20, deviation: 0.40, minimum: 0.1),
            saturationStops: 4.5,
            latitudeStops: 2.5,
            notes: "Motion-picture negative, its Vision generations and the respools cut from them. Made to be exposed within weeks of coating, so the dating is short and the keeping is good only when cold.",
            evidence: .assumed("Group coefficients are priors; cinema dating practice is manufacturer documented.")
        ),
        .other: ExpiryGroupParameters(
            activationEnergyEV: ExpiryDistribution(mean: 0.62, deviation: 0.15, minimum: 0.2),
            shelfLifeYears: ExpiryDistribution(mean: 2.0, deviation: 1.2, minimum: 0.25),
            freshBaseFog: 0.10,
            freshGamma: 0.60,
            freshMaxDensity: 2.40,
            toeDecades: 0.55,
            fogCeiling: 0.50,
            fogTimeConstantYears: 50,
            gammaLossFraction: 0.28,
            gammaTimeConstantYears: 50,
            densityLoss: 0.50,
            densityTimeConstantYears: 55,
            speedLossStops: 1.00,
            speedTimeConstantYears: 45,
            radiationSensitivity: ExpiryDistribution(mean: 1.20, deviation: 0.50, minimum: 0.1),
            saturationStops: 5.0,
            latitudeStops: 2.0,
            notes: "The honest catch-all: wide distributions, conservative coefficients, and an answer labelled as a guess.",
            evidence: .assumed("No group could be established for this film.")
        )
    ]
}

// MARK: - Catalogue rules

enum ExpiryCatalogue {
    /// Films whose name says they are a modern tabular or epitaxial emulsion.
    static let modernMarkers = [
        "t-max", "tmax", "delta", "acros", "pan f", "retro 80", "p30", "cms 20", "silvermax", "ortho"
    ]

    /// Colour stocks sold as professional rather than mass market.
    static let professionalMarkers = [
        "portra", "ektar", "pro 160", "pro 400", "pro 800", "400h", "reala", "vericolor",
        "vps", "vpl", "nps", "nph", "npz", "ultra color"
    ]

    static func ruleGroup(for film: LibraryFilm) -> (group: ExpiryBehaviourGroup, reason: String) {
        let name = film.name.lowercased()

        switch film.process {
        case .colourReversal:
            return (.slide, "E-6 reversal stock")
        case .cinemaNegative:
            return (.cineECN2, "Cinema negative")

        case .colourNegative:
            if professionalMarkers.contains(where: { name.contains($0) }) {
                return (.professionalColourNegative, "Professional colour negative")
            }
            return (.consumerColourNegative, "Consumer colour negative")

        case .blackAndWhite:
            if film.iso >= 400 {
                return (.fastBW, "Monochrome at ISO 400 or above")
            }
            if film.iso < 200, modernMarkers.contains(where: { name.contains($0) }) {
                return (.slowModernBW, "Fine-grain modern monochrome")
            }
            return (.classicBW, "Conventional monochrome")
        }
    }

    /// Evidence for a film that has no curated entry. A film whose family is
    /// well described earns literature-derived priors; anything else is a guess.
    static func evidence(for film: LibraryFilm, group: ExpiryBehaviourGroup) -> ExpiryEvidenceClass {
        if group == .other { return .assumed }
        switch film.status {
        case .current, .cinema:
            return .literatureDerived
        case .discontinued, .specialty:
            return .empiricallyObserved
        }
    }

    // MARK: Base

    static func baseMaterial(for film: LibraryFilm) -> (material: ExpiryBaseMaterial, isAssumed: Bool) {
        if let entry = film.characteristics?.first(where: { $0.label.lowercased() == "base" }) {
            let text = entry.value.lowercased()
            if text.contains("paper") {
                return (.paper, entry.provenance.kind == .unverified)
            }
            if text.contains("polyester") || text.contains("estar") || text.contains("pet ") {
                return (.polyester, entry.provenance.kind == .unverified)
            }
            if text.contains("acetate") {
                return (.acetate, entry.provenance.kind == .unverified)
            }
        }

        // Nothing documented: sheet stock in the modern trade is nearly all
        // polyester and 35 mm is nearly all acetate. Both are assumptions.
        if film.formats.contains(.sheet4x5) || film.formats.contains(.sheet8x10) {
            return (.polyester, true)
        }
        if film.formats.contains(.size135) || film.formats.contains(.size120) {
            return (.acetate, true)
        }
        return (.unknown, true)
    }

    // MARK: Era

    /// Older coatings were dated longer and stabilised less well. The era is
    /// read from the printed date the reader typed, which is a fact rather than
    /// an estimate.
    static func era(expiryYear: Int) -> (shelf: Double, stability: Double, note: String?) {
        if expiryYear < 1985 {
            return (
                1.55,
                0.85,
                "Dated before 1985: coatings of that era carried longer dates and far less effective stabilisers."
            )
        }
        if expiryYear < 2000 {
            return (
                1.25,
                0.92,
                "Dated in the 1980s or 1990s: longer dating conventions and an earlier generation of stabilisers."
            )
        }
        return (1.0, 1.0, nil)
    }
}



// MARK: - Per-parameter provenance

/// What each part of the model rests on, in one place. The class here is about
/// the *kind* of knowledge, not the film: it is what lets the screen say that
/// the storage bands are transcribed from manufacturer guidance while the
/// thermal multipliers are a chosen calibration.
///
/// `sourceKey` matches a source in `expiry-overrides.json`, so a reader can
/// follow the claim back to the page.
enum ExpiryParameterCatalogue {
    static let annotations: [ExpiryParameterAnnotation] = [
        ExpiryParameterAnnotation(
            id: "climates",
            field: "Storage temperature bands",
            classification: .manufacturerDocumented,
            sourceKey: "kodak-e30",
            note: "The bands describe the conditions Kodak, Ilford and the Library of Congress publish: room, cool, refrigerated, frozen and the attic or car they all warn against. The means and spreads inside each band are chosen."
        ),
        ExpiryParameterAnnotation(
            id: "thermal-multipliers",
            field: "Thermal acceleration",
            classification: .assumed,
            sourceKey: "ipi-acetate",
            note: "The relative multipliers — roughly 0.3× refrigerated, 1× cool, 1.5× warm, 3× hot — are a calibration choice. The activation energies were picked so the Arrhenius curve lands there, not fitted to measurements. The IPI's 17× life at 30 °F against 70 °F is for acetate hydrolysis, not for emulsion speed loss, and is quoted as context rather than as a constant used here."
        ),
        ExpiryParameterAnnotation(
            id: "activation-energy",
            field: "Activation energy",
            classification: .assumed,
            sourceKey: "kodak-tib5202",
            note: "0.58–0.65 eV across the families, which reproduces roughly a doubling of the rate per 10 °C — the rule of thumb both the chemistry and the storage advice imply. No manufacturer publishes an Arrhenius coefficient for an emulsion."
        ),
        ExpiryParameterAnnotation(
            id: "radiation-direction",
            field: "Radiation fog: speed dependence",
            classification: .manufacturerDocumented,
            sourceKey: "kodak-tib5202",
            note: "\"Higher-speed films are affected more by gamma radiation than lower-speed films.\" Kodak also states that neither cooling nor lead-foil bags prevents it, which is why the model keeps a radiation floor under frozen storage."
        ),
        ExpiryParameterAnnotation(
            id: "radiation-magnitude",
            field: "Radiation fog: rate and floor",
            classification: .assumed,
            sourceKey: "kodak-tib5202",
            note: "\(String(format: "%.4f", ExpiryEngine.baseRadiationFogPerYear)) log D per year at unit sensitivity, floored at \(String(format: "%.4f", ExpiryEngine.minimumRadiationFogPerYear)), with a frozen multiplier of \(String(format: "%.1f", ExpiryEngine.frozenRadiationFactor)). The direction is documented; the size is a prior, because the published record does not separate thermal from radiation fog. These figures are read from the engine's own constants, so the note cannot drift from the arithmetic."
        ),
        ExpiryParameterAnnotation(
            id: "speed-loss",
            field: "Speed loss with age",
            classification: .empiricallyObserved,
            sourceKey: "usaf-afm160-30",
            note: "\"As films age, they lose speed and contrast.\" Kodak E-30 likewise lists speed among the characteristics that change gradually after manufacture. The size and shape of the loss per family is an engineering prior."
        ),
        ExpiryParameterAnnotation(
            id: "contrast-loss",
            field: "Contrast and gamma loss",
            classification: .empiricallyObserved,
            sourceKey: "usaf-afm160-30",
            note: "The direction is both documented and widely observed. The time constants and the fraction lost are chosen."
        ),
        ExpiryParameterAnnotation(
            id: "shelf-life",
            field: "Shelf-life distribution",
            classification: .assumed,
            sourceKey: "ilford-faq",
            note: "Manufacturers publish a \"develop before\" date and no interval: Ilford answers only that the date is a useful guide when film has not been refrigerated. The 1.5–2.5 year centres come from the dates actually seen on stock, and the era adjustment is a prior about older dating conventions."
        ),
        ExpiryParameterAnnotation(
            id: "curve",
            field: "Characteristic curve shape",
            classification: .assumed,
            sourceKey: nil,
            note: "A parametric H&D curve with a smooth toe, a gamma-scaled straight line and an exponential shoulder. The fresh base fog, gamma and maximum density are typical of each family, not a sensitometric trace of the box in the reader's hand."
        ),
        ExpiryParameterAnnotation(
            id: "fog-granularity",
            field: "Shadow criterion and fog granularity",
            classification: .assumed,
            sourceKey: nil,
            note: "A shadow must sit 0.12 log D above fog, widened by 0.35 × the fog growth because fog carries granularity. Both figures are modelling choices; they set how quickly compensation grows."
        ),
        ExpiryParameterAnnotation(
            id: "saturation",
            field: "Saturation",
            classification: .literatureDerived,
            sourceKey: nil,
            note: "Fog is developed silver, so it subtracts from the density the shoulder can still deliver. Saturation is what falls out when the aged curve can no longer reach the shadow criterion, or when compensation passes the family's limit."
        ),
        ExpiryParameterAnnotation(
            id: "crossover",
            field: "Colour layer crossover",
            classification: .assumed,
            sourceKey: "kodak-e30",
            note: "One sensitivity number per family. Kodak states that adverse conditions usually affect the colour layers to different degrees; nothing public quantifies that per stock, so the model reports crossover as a warning rather than trying to correct it."
        ),
        ExpiryParameterAnnotation(
            id: "acetate",
            field: "Acetate degradation warning",
            classification: .literatureDerived,
            sourceKey: "ipi-acetate",
            note: "The IPI puts fresh acetate at about 50 years to the onset of vinegar syndrome at 65 °F/50% RH, about 150 years at 55 °F/40%, and roughly 17× longer at 30 °F than at 70 °F. The warning threshold in this model is a simplification of those contours."
        ),
        ExpiryParameterAnnotation(
            id: "film-overrides",
            field: "Named-film departures",
            classification: .literatureDerived,
            sourceKey: nil,
            note: "Each entry in expiry-overrides.json carries its own evidence class and a note saying why it departs from its family. They are curated readings, not measurements."
        ),
        ExpiryParameterAnnotation(
            id: "calibration",
            field: "Roll calibration",
            classification: .empiricallyObserved,
            sourceKey: nil,
            note: "Ordinal outcomes logged by the reader, shrunk toward the family and clamped to ±0.5 stops. Ordinal, not densitometric: a scan judged under or over is not a measurement of sensitivity."
        )
    ]

    static func annotation(id: String) -> ExpiryParameterAnnotation? {
        annotations.first { $0.id == id }
    }
}
