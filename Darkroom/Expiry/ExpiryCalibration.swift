//
//  ExpiryCalibration.swift
//  Darkroom
//
//  Roll observations and the hierarchical calibration they feed: global → film
//  family → this film → this roll. A single roll is never allowed to rewrite a
//  film's behaviour, and the validation is kept separate from the fitting.
//

import Combine
import Foundation

// MARK: - Observations

/// How a roll actually came out. Deliberately ordinal: nobody knows by how
/// much a scan was under, and pretending otherwise would build false precision
/// into the calibration.
enum ExpiryRollOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case underexposed
    case good
    case overexposed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .underexposed: return "Underexposed"
        case .good: return "Good"
        case .overexposed: return "Overexposed"
        }
    }

    var detail: String {
        switch self {
        case .underexposed: return "Thin shadows, detail lost in the dark parts."
        case .good: return "Shadows and highlights both where they should be."
        case .overexposed: return "Dense, highlights blocked, shadows flat but present."
        }
    }

    /// The stops of *needed extra exposure* the roll wanted, relative to the
    /// exposure index it was actually shot at. Positive means the film wanted
    /// more light than that index gave it.
    ///
    /// "Good" is zero against the index that was shot. The residual is taken
    /// against the model's prediction for the same index, so a good roll rated
    /// at an adjusted EI is evidence that the adjusted EI was right, and pulls
    /// the adjustment toward it rather than back toward the baseline.
    var residualStops: Double {
        switch self {
        case .underexposed: return 0.5
        case .good: return 0
        case .overexposed: return -0.5
        }
    }
}

/// How much a reported outcome is trusted.
enum ExpiryCalibrationEvidence: String, Codable, CaseIterable, Identifiable, Sendable {
    case anecdotal
    case personal
    case controlled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anecdotal: return "Someone else's report"
        case .personal: return "My own result"
        case .controlled: return "Side-by-side test"
        }
    }

    var weight: Double {
        switch self {
        case .anecdotal: return 0.45
        case .personal: return 0.75
        case .controlled: return 1.0
        }
    }
}

/// One roll's outcome, with everything needed to weigh it.
struct ExpiryCalibrationPoint: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var filmKey: String
    var group: ExpiryBehaviourGroup
    /// Years between the printed date and the day the roll was shot. Not the
    /// film's total age: the model integrates from the printed date, so this is
    /// the quantity a residual is measured at.
    var ageYears: Double
    var storage: String
    /// The exposure index the roll was actually shot at, as the reader set it.
    /// Never the model's recommendation unless the reader chose that.
    var exposureIndex: Int
    /// The box speed of the stock the roll came from, so the exposure index can
    /// be read as stops of compensation. Zero on a record written before this
    /// was stored, which leaves the shot compensation unknown.
    var boxISO: Int
    /// The model's own prediction, in stops of compensation, for this roll's
    /// age and storage, before any logged roll adjusted it. The residual is
    /// measured against this, so a good roll at an adjusted EI is evidence
    /// about the adjustment and not about the baseline.
    var predictedStops: Double
    /// 1 = barely usable, 5 = a clean, well-scanned negative.
    var quality: Int
    var evidence: ExpiryCalibrationEvidence
    var source: String
    var notes: String
    var outcome: ExpiryRollOutcome
    var recorded: Date

    init(
        id: String = UUID().uuidString,
        filmKey: String,
        group: ExpiryBehaviourGroup,
        ageYears: Double,
        storage: String,
        exposureIndex: Int,
        boxISO: Int = 0,
        predictedStops: Double = 0,
        quality: Int,
        evidence: ExpiryCalibrationEvidence = .personal,
        source: String = "",
        notes: String = "",
        outcome: ExpiryRollOutcome,
        recorded: Date = Date()
    ) {
        self.id = id
        self.filmKey = filmKey
        self.group = group
        self.ageYears = ageYears
        self.storage = storage
        self.exposureIndex = exposureIndex
        self.boxISO = boxISO
        self.predictedStops = predictedStops
        self.quality = quality
        self.evidence = evidence
        self.source = source
        self.notes = notes
        self.outcome = outcome
        self.recorded = recorded
    }

    private enum CodingKeys: String, CodingKey {
        case id, filmKey, group, ageYears, storage, exposureIndex
        case boxISO, predictedStops, quality, evidence, source, notes, outcome, recorded
    }

    /// Two fields arrived once rolls could already have been logged, so they
    /// decode with a default rather than failing the whole array and quietly
    /// wiping the reader's history.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        filmKey = try container.decode(String.self, forKey: .filmKey)
        group = try container.decode(ExpiryBehaviourGroup.self, forKey: .group)
        ageYears = try container.decode(Double.self, forKey: .ageYears)
        storage = try container.decodeIfPresent(String.self, forKey: .storage) ?? ""
        exposureIndex = try container.decode(Int.self, forKey: .exposureIndex)
        boxISO = try container.decodeIfPresent(Int.self, forKey: .boxISO) ?? 0
        predictedStops = try container.decodeIfPresent(Double.self, forKey: .predictedStops) ?? 0
        quality = try container.decode(Int.self, forKey: .quality)
        evidence = try container.decode(ExpiryCalibrationEvidence.self, forKey: .evidence)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        outcome = try container.decode(ExpiryRollOutcome.self, forKey: .outcome)
        recorded = try container.decodeIfPresent(Date.self, forKey: .recorded) ?? Date(timeIntervalSince1970: 0)
    }

    var weight: Double {
        let qualityShare = Double(max(1, min(5, quality))) / 5
        return max(0.05, evidence.weight * qualityShare)
    }

    /// Observations from the public record, identified by their id prefix. They
    /// inform the fit and are never validated against.
    var isResearch: Bool { id.hasPrefix("research-") }

    /// The stops of extra exposure the reader actually gave the film by rating
    /// it slower than box speed. Positive is more light. Zero when the record
    /// does not carry a box speed, which is all a record written before box
    /// speed was stored can honestly claim.
    var shotStops: Double {
        guard boxISO > 0, exposureIndex > 0 else { return 0 }
        return log2(Double(boxISO) / Double(exposureIndex))
    }

    /// What this roll says the model got wrong, in stops. The compensation the
    /// roll actually needed is what the reader gave it plus whatever the
    /// negative still lacked; the residual is that, less the compensation the
    /// model predicted.
    ///
    /// So a good roll shot at box speed against a prediction of +0.5 is a
    /// residual of −0.5 — the model asked for half a stop the film did not
    /// want — and a good roll shot at the recommended EI is a residual of zero,
    /// which is what makes logging a roll move the answer at all.
    var residualStops: Double {
        shotStops + outcome.residualStops - predictedStops
    }
}


// MARK: - The adjustment

/// What the calibration does to a prediction. Everything is in stops and the
/// whole correction is hard-bounded, so no amount of logged rolls can turn the
/// model into something that contradicts its own physics.
struct ExpiryCalibrationAdjustment: Hashable, Sendable {
    var deltaStops: Double
    var filmDelta: Double
    var groupDelta: Double
    var filmObservations: Int
    var groupObservations: Int
    var leaveOneOutError: Double
    var leaveOneOutCount: Int

    static let none = ExpiryCalibrationAdjustment(
        deltaStops: 0,
        filmDelta: 0,
        groupDelta: 0,
        filmObservations: 0,
        groupObservations: 0,
        leaveOneOutError: 0,
        leaveOneOutCount: 0
    )

    /// The adjustment is capped well below a third of a stop until a film has a
    /// real sample behind it.
    static let maximumShiftStops = 0.5

    var isActive: Bool { abs(deltaStops) >= 0.02 }

    var summary: String {
        guard filmObservations > 0 || groupObservations > 0 else {
            return "No rolls logged yet, so nothing has been adjusted."
        }
        let direction = deltaStops > 0 ? "more exposure" : "less exposure"
        let amount = String(format: "%.2f", abs(deltaStops))
        return "\(filmObservations) roll\(filmObservations == 1 ? "" : "s") for this film and \(groupObservations) across the family shift the estimate \(amount) stop\(amount == "1.00" ? "" : "s") toward \(direction)."
    }
}

// MARK: - Analyser

/// Hierarchical shrinkage. Each level is pulled toward the one above it by a
/// prior strength expressed in effective observations, so a thin sample moves
/// almost nothing and a fat one moves the film, not the family.
struct ExpiryCalibrationAnalyser: Sendable {
    /// Pseudo-observations standing behind a film's own sample. Twenty is
    /// deliberately heavy: one roll, however well controlled, moves this film's
    /// prediction by only about a twentieth of a stop, while a few dozen move
    /// it most of the half-stop the clamp allows.
    var filmPriorStrength: Double = 20
    /// Pseudo-observations standing behind a family's sample.
    var groupPriorStrength: Double = 20

    /// The shrinkage itself, with no validation inside it. Every leave-one-out
    /// pass calls this, so fitting and validating cannot recurse into each other.
    struct Fit: Sendable {
        var deltaStops: Double
        var filmDelta: Double
        var groupDelta: Double
        var filmObservations: Int
        var groupObservations: Int
    }

    func fit(
        forFilm filmKey: String,
        group: ExpiryBehaviourGroup,
        points: [ExpiryCalibrationPoint]
    ) -> Fit? {
        guard !points.isEmpty else { return nil }

        let groupPoints = points.filter { $0.group == group }
        let filmPoints = points.filter { $0.filmKey == filmKey }

        let groupWeight = groupPoints.reduce(0) { $0 + $1.weight }
        let groupWeighted = groupPoints.reduce(0) { $0 + $1.weight * $1.residualStops }
        // Global prior is zero: with no evidence, films age as the group says.
        let groupDelta = groupWeight + groupPriorStrength > 0
            ? groupWeighted / (groupWeight + groupPriorStrength)
            : 0

        let filmWeight = filmPoints.reduce(0) { $0 + $1.weight }
        let filmResidual = filmPoints.reduce(0) { $0 + $1.weight * ($1.residualStops - groupDelta) }
        let filmDelta = groupDelta + (filmWeight + filmPriorStrength > 0
            ? filmResidual / (filmWeight + filmPriorStrength)
            : 0)

        let bounded = max(
            -ExpiryCalibrationAdjustment.maximumShiftStops,
            min(ExpiryCalibrationAdjustment.maximumShiftStops, filmDelta)
        )

        return Fit(
            deltaStops: bounded,
            filmDelta: filmDelta,
            groupDelta: groupDelta,
            filmObservations: filmPoints.count,
            groupObservations: groupPoints.count
        )
    }

    func adjustment(
        forFilm filmKey: String,
        group: ExpiryBehaviourGroup,
        points: [ExpiryCalibrationPoint]
    ) -> ExpiryCalibrationAdjustment {
        guard let fitted = fit(forFilm: filmKey, group: group, points: points) else {
            return .none
        }

        let loo = leaveOneOut(filmKey: filmKey, group: group, points: points)

        return ExpiryCalibrationAdjustment(
            deltaStops: fitted.deltaStops,
            filmDelta: fitted.filmDelta,
            groupDelta: fitted.groupDelta,
            filmObservations: fitted.filmObservations,
            groupObservations: fitted.groupObservations,
            leaveOneOutError: loo.error,
            leaveOneOutCount: loo.count
        )
    }

    /// Each of the reader's own rolls is predicted from the others, never from
    /// itself. Observations from the public record are never held out — they are
    /// not the reader's rolls and nobody is being told they predicted their own
    /// result — but they stay in the set that predicts, because they are part of
    /// the model the reader actually gets and holding them out would measure a
    /// different, thinner model. The held-out fits go through `fit` directly, so
    /// this is one pass over the rolls rather than a fit that re-validates
    /// inside every fold.
    func leaveOneOut(
        filmKey: String,
        group: ExpiryBehaviourGroup,
        points: [ExpiryCalibrationPoint]
    ) -> (error: Double, count: Int) {
        let own = points.filter { $0.filmKey == filmKey && !$0.isResearch }
        guard own.count >= 2 else { return (0, 0) }

        var total = 0.0
        var count = 0
        for point in own {
            let remaining = points.filter { $0.id != point.id }
            let prediction = fit(forFilm: filmKey, group: group, points: remaining)?.deltaStops ?? 0
            total += abs(point.residualStops - prediction)
            count += 1
        }
        guard count > 0 else { return (0, 0) }
        return (total / Double(count), count)
    }
}


// MARK: - Store

/// Logged rolls, persisted as JSON in the app's defaults beside the other
/// preferences. Nothing here reaches the network.
final class ExpiryCalibrationStore: ObservableObject {
    static let shared = ExpiryCalibrationStore()

    @Published private(set) var points: [ExpiryCalibrationPoint]

    private static let key = "expiry.calibration.points"
    private let defaults: UserDefaults
    private let analyser = ExpiryCalibrationAnalyser()

    /// Observations gathered from the public record while the model was built.
    /// They inform the fitted behaviour and are never used for validation:
    /// leave-one-out runs over the reader's own rolls only. The prediction is
    /// not typed in here: `researchPoints(model:)` fills it in from the running
    /// model, so the residual is measured against what the model says.
    static let researchObservations: [ExpiryCalibrationPoint] = [
        ExpiryCalibrationPoint(
            id: "research-tmax-100-2009",
            filmKey: "kodak-t-max-100",
            group: .slowModernBW,
            ageYears: 17,
            storage: "Room temperature, sealed in its canister",
            exposureIndex: 100,
            boxISO: 100,
            quality: 4,
            evidence: .anecdotal,
            source: "Reported by the app's owner: a roll dated 2009, stored at room temperature, gave solid results at box speed.",
            notes: "A single anecdote about a roll dated 2009, shot 17 years later at box speed. It is weighed as one anecdote, not as a measured series — and because it was shot at box speed while the model predicts compensation at that age, its residual is not zero.",
            outcome: .good,
            recorded: Date(timeIntervalSince1970: 1_770_000_000)
        )
    ]

    /// The research points with their prediction taken from the model, so the
    /// residual is measured against what the model actually says for that film,
    /// age and storage, and not against a number typed in by hand. The film is
    /// read from the library, the same path the calculator uses. A point whose
    /// film is not in the library keeps a prediction of zero and is not used.
    static func researchPoints(model: ExpiryModel, film: (String) -> LibraryFilm?) -> [ExpiryCalibrationPoint] {
        researchObservations.map { point in
            var filled = point
            guard let libraryFilm = film(point.filmKey) else { return filled }
            let profile = model.profile(for: libraryFilm)
            // The roll was shot on the day the observation was recorded, and
            // `ageYears` is how far past its printed date it already was.
            let anchor = point.recorded
            let expiration = ExpiryEngine.utcCalendar.date(
                byAdding: .year,
                value: -Int(point.ageYears.rounded()),
                to: anchor
            ) ?? anchor
            let request = ExpiryRequest(
                profile: profile,
                expiration: expiration,
                timeline: .single(.roomTemperature),
                now: anchor
            )
            filled.predictedStops = ExpiryCalculator.baselineStops(request, model: model)
            return filled
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([ExpiryCalibrationPoint].self, from: data) {
            points = decoded
        } else {
            points = []
        }
    }

    /// Rolls are split by date: the most recent fifth is held out and never used
    /// for fitting, so the reported hold-out error is measured on data the fit
    /// has not seen. Fewer than five rolls cannot be split usefully, so
    /// everything fits and the hold-out error stays unknown rather than being
    /// quietly computed on the training data.
    static func split(
        _ points: [ExpiryCalibrationPoint]
    ) -> (fitting: [ExpiryCalibrationPoint], validation: [ExpiryCalibrationPoint]) {
        let sorted = points.sorted { $0.recorded < $1.recorded }
        guard sorted.count >= 5 else { return (sorted, []) }
        let held = max(1, sorted.count / 5)
        return (Array(sorted.dropLast(held)), Array(sorted.suffix(held)))
    }

    /// Rolls that can be measured: those logged with the box speed they were
    /// shot against. A roll stored before box speed was recorded has no known
    /// compensation, so its residual would be a guess. It stays in the store and
    /// is counted, but it is never fitted or validated against.
    static func measurable(_ points: [ExpiryCalibrationPoint]) -> [ExpiryCalibrationPoint] {
        points.filter { $0.boxISO > 0 }
    }

    /// What the model is fitted on: the reader's older measurable rolls, plus
    /// the public observations with their predictions taken from the model.
    func fittingPoints(model: ExpiryModel, film: (String) -> LibraryFilm?) -> [ExpiryCalibrationPoint] {
        Self.split(Self.measurable(points)).fitting + Self.researchPoints(model: model, film: film)
    }

    /// What it is checked against, and never fitted on.
    var holdoutPoints: [ExpiryCalibrationPoint] {
        Self.split(Self.measurable(points)).validation
    }

    /// Logged rolls that cannot be used because they predate the box-speed field.
    var unmeasuredCount: Int {
        points.count - Self.measurable(points).count
    }

    func adjustment(
        filmKey: String,
        group: ExpiryBehaviourGroup,
        model: ExpiryModel = .standard,
        film: (String) -> LibraryFilm? = { _ in nil }
    ) -> ExpiryCalibrationAdjustment {
        analyser.adjustment(
            forFilm: filmKey,
            group: group,
            points: fittingPoints(model: model, film: film)
        )
    }

    func points(forFilm filmKey: String) -> [ExpiryCalibrationPoint] {
        points.filter { $0.filmKey == filmKey }
    }

    /// Per-film prediction error, how much data is behind it, and the error on
    /// the held-out rolls when there are enough of them to hold any back.
    func validation(
        filmKey: String,
        group: ExpiryBehaviourGroup,
        model: ExpiryModel = .standard,
        film: (String) -> LibraryFilm? = { _ in nil }
    ) -> (error: Double, count: Int, samples: Int, holdoutError: Double, holdoutCount: Int) {
        let fitSet = fittingPoints(model: model, film: film)
        let loo = analyser.leaveOneOut(filmKey: filmKey, group: group, points: fitSet)

        let held = holdoutPoints.filter { $0.filmKey == filmKey }
        var holdoutError = 0.0
        if !held.isEmpty,
           let base = analyser.fit(forFilm: filmKey, group: group, points: fitSet)?.deltaStops {
            let total = held.reduce(0) { $0 + abs($1.residualStops - base) }
            holdoutError = total / Double(held.count)
        }

        return (loo.error, loo.count, points(forFilm: filmKey).count, holdoutError, held.count)
    }

    /// An unlisted stock shares one key with every other unlisted stock, so a
    /// roll logged against it could never be told apart from any other. It is
    /// refused here as well as in the screen, so nothing can store one.
    static let unlistedFilmKey = "unlisted"

    @discardableResult
    func add(_ point: ExpiryCalibrationPoint) -> Bool {
        guard !point.filmKey.isEmpty, point.filmKey != Self.unlistedFilmKey else { return false }
        points.append(point)
        persist()
        return true
    }

    func remove(id: String) {
        points.removeAll { $0.id == id }
        persist()
    }

    /// Every roll logged for one film, and nothing for any other. A film with
    /// rolls logged has its own record to clear; "delete my rolls" must never
    /// take the rest of the library's with it.
    func removeAll(forFilm filmKey: String) {
        points.removeAll { $0.filmKey == filmKey }
        persist()
    }

    func removeAll() {
        points.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(points) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - Running a calculation off the main thread

/// The thin seam between a screen and the engine: a fast synchronous answer and
/// a background full one.
enum ExpiryCalculator {
    /// Kept small enough that the fast path is instant on the main thread.
    static let quickEngine = ExpiryEngine(sampleCount: 1)
    /// Two thousand samples, run on a background task.
    static let fullEngine = ExpiryEngine(sampleCount: 2000)

    static func quick(
        _ request: ExpiryRequest,
        calibration: ExpiryCalibrationAdjustment = .none
    ) -> ExpiryEstimate {
        quickEngine.quickEstimate(request, calibration: calibration)
    }

    static func full(
        _ request: ExpiryRequest,
        calibration: ExpiryCalibrationAdjustment = .none
    ) async -> ExpiryEstimate {
        await Task.detached(priority: .userInitiated) {
            fullEngine.estimate(request, calibration: calibration)
        }
        .value
    }

    /// The model's compensation at its mean parameters, in unrounded stops, with
    /// no logged roll adjusting it. A logged roll's residual is measured against
    /// this rather than against the number the screen shows, so the record keeps
    /// its footing when a later roll moves the answer.
    static func baselineStops(_ request: ExpiryRequest, model: ExpiryModel = .standard) -> Double {
        ExpiryEngine(model: model, sampleCount: 1).baselineStops(request)
    }
}
