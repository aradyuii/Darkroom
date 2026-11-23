import Foundation

// A standalone check of the calibration arithmetic, compiled against the app's
// own model files. XCTest cannot run on this machine, so this exercises the
// same assertions the test target makes.

var failures: [String] = []

func check(_ condition: Bool, _ label: String) {
    if condition { print("ok   \(label)") } else { failures.append(label); print("FAIL \(label)") }
}

let model = ExpiryModel(groups: ExpiryModel.defaultGroups, curated: [:])

func profile(iso: Int, evidence: ExpiryEvidenceClass = .literatureDerived, key: String = "film-a") -> ExpiryFilmProfile {
    ExpiryFilmProfile(
        filmKey: key,
        displayName: "Test \(iso)",
        manufacturer: "Test",
        iso: iso,
        process: .colourNegative,
        status: .current,
        group: .consumerColourNegative,
        groupReason: "harness",
        baseMaterial: .acetate,
        baseMaterialIsAssumed: true,
        overrides: ExpiryParameterOverride(),
        evidence: evidence,
        note: nil,
        hasCuratedProfile: false
    )
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
func request(iso: Int = 400, years: Double, tier: ExpiryStorageTier, evidence: ExpiryEvidenceClass = .literatureDerived) -> ExpiryRequest {
    ExpiryRequest(
        profile: profile(iso: iso, evidence: evidence),
        expiration: now.addingTimeInterval(-years * ExpiryEngine.secondsPerYear),
        timeline: .single(tier),
        now: now
    )
}

func rolled(outcome: ExpiryRollOutcome, box: Int, shot: Int, predicted: Double) -> ExpiryCalibrationPoint {
    ExpiryCalibrationPoint(
        filmKey: "film-a",
        group: .consumerColourNegative,
        ageYears: 12,
        storage: "Cool room",
        exposureIndex: shot,
        boxISO: box,
        predictedStops: predicted,
        quality: 5,
        evidence: .controlled,
        source: "harness",
        notes: "",
        outcome: outcome
    )
}

// 1. The residual uses the exposure index actually shot.
let boxSpeed = rolled(outcome: .good, box: 400, shot: 400, predicted: 0.5)
check(abs(boxSpeed.shotStops) < 1e-12, "box speed is zero stops of compensation")
check(abs(boxSpeed.residualStops + 0.5) < 1e-12, "a good roll at box speed is -0.5 against a +0.5 prediction")

let recommended = rolled(outcome: .good, box: 400, shot: 283, predicted: 0.5)
check(abs(recommended.shotStops - 0.5) < 0.01, "EI 283 on a 400 box is +0.5 stops")
check(abs(recommended.residualStops) < 0.01, "a good roll at the recommended index is a zero residual")

let short = rolled(outcome: .underexposed, box: 400, shot: 283, predicted: 0.5)
check(abs(short.residualStops - 0.5) < 0.01, "an underexposed roll at +0.5 is half a stop short of the model")

// 2. A "good" result at box speed pulls an over-prediction down, not toward zero only.
let analyser = ExpiryCalibrationAnalyser()
let many = (0..<30).map { _ in rolled(outcome: .good, box: 400, shot: 400, predicted: 0.5) }
let adjustment = analyser.adjustment(forFilm: "film-a", group: .consumerColourNegative, points: many)
check(adjustment.deltaStops < -0.1, "thirty good rolls at box speed pull the answer down (got \(String(format: "%.3f", adjustment.deltaStops)))")
check(abs(adjustment.deltaStops) <= ExpiryCalibrationAdjustment.maximumShiftStops, "the adjustment stays inside its clamp")

// 3. A single roll still barely moves anything.
let single = analyser.adjustment(
    forFilm: "film-a",
    group: .consumerColourNegative,
    points: [rolled(outcome: .underexposed, box: 400, shot: 400, predicted: 0.5)]
)
check(abs(single.deltaStops) < 0.15, "one roll does not rewrite the film")

// 4. Leave-one-out never validates the research observation.
let research = ExpiryCalibrationPoint(
    id: "research-x",
    filmKey: "film-a",
    group: .consumerColourNegative,
    ageYears: 12,
    storage: "Room",
    exposureIndex: 400,
    boxISO: 400,
    predictedStops: 0.5,
    quality: 4,
    evidence: .anecdotal,
    source: "public record",
    notes: "",
    outcome: .good,
    recorded: Date(timeIntervalSince1970: 1_600_000_000)
)
let own = (0..<3).map { _ in rolled(outcome: .good, box: 400, shot: 400, predicted: 0.5) }
let loo = analyser.leaveOneOut(filmKey: "film-a", group: .consumerColourNegative, points: own + [research])
check(loo.count == 3, "leave-one-out runs over the three own rolls only (got \(loo.count))")

// 5. An in-date film with unknown storage is not "well documented".
let engine = ExpiryEngine(model: model, sampleCount: 400)
let known = engine.estimate(request(years: -1, tier: .coolRoom))
let unknown = engine.estimate(request(years: -1, tier: .unknown))
check(!known.isExpired && known.eiMedian == 400, "an in-date film rates at box speed")
check(known.confidence == .wellDocumented, "known storage in date is well documented")
check(unknown.confidence != .wellDocumented, "unknown storage in date is not well documented (got \(unknown.confidence.rawValue))")
check(unknown.confidenceScore < known.confidenceScore, "unknown storage scores lower")

let unlisted = engine.estimate(request(years: -1, tier: .coolRoom, evidence: .assumed))
check(unlisted.confidence == .educatedGuess, "an assumed stock in date is only a guess")

// 6. Splitting one period into two of the same tier cannot move the answer.
let whole = request(years: 12, tier: .roomTemperature)
let split = ExpiryRequest(
    profile: profile(iso: 400),
    expiration: now.addingTimeInterval(-12 * ExpiryEngine.secondsPerYear),
    timeline: ExpiryStorageTimeline(segments: [
        ExpiryStorageSegment(tier: .roomTemperature, fraction: 0.5),
        ExpiryStorageSegment(tier: .roomTemperature, fraction: 0.5)
    ]),
    now: now
)
check(split.timeline.normalised.count == 1, "two periods in one tier are one period")
check(split.timeline.certainty == 1, "splitting a period adds no storage uncertainty")
check(engine.estimate(whole).eiMedian == engine.estimate(split).eiMedian, "the estimate is unchanged by the split")

// 7. The baseline is the model's own unrounded figure.
let baseline = engine.baselineStops(request(years: 12, tier: .roomTemperature))
check(baseline > 0, "an aged film in warm storage needs compensation (got \(String(format: "%.3f", baseline)))")

// 8. The in-app note quotes the constants the engine uses.
let rate = String(format: "%.4f", ExpiryEngine.baseRadiationFogPerYear)
let floor = String(format: "%.4f", ExpiryEngine.minimumRadiationFogPerYear)
let note = ExpiryParameterCatalogue.annotation(id: "radiation-magnitude")?.note ?? ""
check(note.contains(rate) && note.contains(floor), "the radiation note quotes \(rate) and \(floor)")

print("")
print(failures.isEmpty ? "all checks passed" : "\(failures.count) FAILED: \(failures.joined(separator: "; "))")
exit(failures.isEmpty ? 0 : 1)
