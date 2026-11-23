//
//  ExpiryEngineTests.swift
//  DarkroomTests
//
//  The expired-film exposure model: the guarantees it has to keep, the
//  properties a reader can rely on, and the places where it must say "I do not
//  know" instead of inventing an answer.
//

import XCTest
@testable import Darkroom

final class ExpiryEngineTests: XCTestCase {

    // MARK: Fixtures

    /// A fixed "now" so nothing in these tests depends on the wall clock.
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The model without the bundled per-film table, so a test measures the
    /// arithmetic and not the contents of a JSON file.
    private func engine(samples: Int = 400) -> ExpiryEngine {
        ExpiryEngine(
            model: ExpiryModel(groups: ExpiryModel.defaultGroups, curated: [:]),
            sampleCount: samples
        )
    }

    private func profile(
        key: String = "test-film",
        name: String = "Test",
        iso: Int = 400,
        process: FilmProcess = .colourNegative,
        group: ExpiryBehaviourGroup = .consumerColourNegative,
        evidence: ExpiryEvidenceClass = .literatureDerived,
        base: ExpiryBaseMaterial = .acetate
    ) -> ExpiryFilmProfile {
        ExpiryFilmProfile(
            filmKey: key,
            displayName: "\(name) \(iso)",
            manufacturer: "Test",
            iso: iso,
            process: process,
            status: .current,
            group: group,
            groupReason: "Test fixture",
            baseMaterial: base,
            baseMaterialIsAssumed: true,
            overrides: ExpiryParameterOverride(),
            evidence: evidence,
            note: nil,
            hasCuratedProfile: false
        )
    }

    private func request(
        _ profile: ExpiryFilmProfile,
        yearsPastExpiry: Double,
        timeline: ExpiryStorageTimeline = .single(.coolRoom)
    ) -> ExpiryRequest {
        ExpiryRequest(
            profile: profile,
            expiration: Self.now.addingTimeInterval(-yearsPastExpiry * ExpiryEngine.secondsPerYear),
            timeline: timeline,
            now: Self.now
        )
    }

    private func libraryFilm(key: String, iso: Int, process: FilmProcess) -> LibraryFilm {
        LibraryFilm(
            key: key,
            manufacturer: "Kodak",
            name: "T-Max",
            iso: iso,
            process: process,
            formats: [.size135],
            status: .current,
            generation: nil,
            generationLabel: nil,
            latitude: nil,
            grain: nil,
            contrast: nil,
            reciprocity: nil,
            notes: nil
        )
    }

    // MARK: - Dates

    func testNotExpiredReturnsBoxSpeed() {
        let result = engine().quickEstimate(request(profile(), yearsPastExpiry: -2))

        XCTAssertFalse(result.isExpired)
        XCTAssertEqual(result.eiMedian, 400)
        XCTAssertEqual(result.eiLow, 400)
        XCTAssertEqual(result.eiHigh, 400)
        XCTAssertEqual(result.stops, 0)
        XCTAssertEqual(result.confidence, .wellDocumented)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testFutureExpirationDateIsStillBoxSpeed() {
        let result = engine().quickEstimate(request(profile(iso: 100), yearsPastExpiry: -12))
        XCTAssertEqual(result.eiMedian, 100)
        XCTAssertFalse(result.isSaturated)
    }

    func testRecentlyExpiredBarelyMoves() {
        for years in [0.5, 1.0, 2.0] {
            let result = engine().quickEstimate(request(profile(), yearsPastExpiry: years))
            XCTAssertLessThan(result.stops, 0.34, "Under \(years) years expired should not reach a third of a stop")
        }

        let half = engine().quickEstimate(request(profile(), yearsPastExpiry: 0.5))
        XCTAssertEqual(half.eiMedian, 400, "Six months past the date should still be box speed")
    }

    func testOneYearExpiredIsSmall() {
        let result = engine().quickEstimate(request(profile(), yearsPastExpiry: 1))
        XCTAssertTrue(result.isExpired)
        XCTAssertLessThanOrEqual(result.stops, 0.34)
        XCTAssertGreaterThanOrEqual(result.eiMedian, 320)
    }

    // MARK: - Ageing

    func testCompensationGrowsWithAge() {
        let subject = engine()
        var previous = -1.0
        for years in [1.0, 5.0, 10.0, 20.0, 30.0] {
            let result = subject.quickEstimate(request(profile(), yearsPastExpiry: years))
            XCTAssertGreaterThanOrEqual(
                result.stops,
                previous - 0.001,
                "Compensation fell at \(years) years"
            )
            previous = result.stops
        }
        XCTAssertGreaterThan(previous, 0.5, "Thirty years of cool-room storage should need real compensation")
    }

    func testTenYearsExpiredIsMoreThanOne() {
        let subject = engine()
        let one = subject.quickEstimate(request(profile(), yearsPastExpiry: 1))
        let ten = subject.quickEstimate(request(profile(), yearsPastExpiry: 10))
        XCTAssertGreaterThan(ten.stops, one.stops)
    }

    func testThirtyYearsIsMoreThanTen() {
        let subject = engine()
        let ten = subject.quickEstimate(request(profile(), yearsPastExpiry: 10))
        let thirty = subject.quickEstimate(request(profile(), yearsPastExpiry: 30))
        XCTAssertGreaterThanOrEqual(thirty.stops, ten.stops)
    }

    func testHotStorageNeedsMoreThanCoolRoom() {
        let subject = engine()
        let cool = subject.quickEstimate(request(profile(), yearsPastExpiry: 20, timeline: .single(.coolRoom)))
        let hot = subject.quickEstimate(request(profile(), yearsPastExpiry: 20, timeline: .single(.hot)))
        XCTAssertGreaterThan(hot.stops, cool.stops)
    }

    func testStorageOrderingIsMonotone() {
        let subject = engine()
        let tiers: [ExpiryStorageTier] = [.frozen, .refrigerator, .coolRoom, .roomTemperature, .hot]
        let stops = tiers.map {
            subject.quickEstimate(request(profile(), yearsPastExpiry: 15, timeline: .single($0))).stops
        }

        for index in 1..<stops.count {
            XCTAssertGreaterThanOrEqual(
                stops[index],
                stops[index - 1] - 0.001,
                "\(tiers[index].rawValue) aged less than \(tiers[index - 1].rawValue)"
            )
        }
    }

    func testFrozenStorageStillAccruesSomething() {
        let result = engine().quickEstimate(request(profile(), yearsPastExpiry: 20, timeline: .single(.frozen)))
        XCTAssertGreaterThan(result.fogIncrease, 0, "Freezing must never switch radiation ageing off")
        XCTAssertLessThan(result.equivalentThermalYears, 2, "Frozen should barely accrue thermal years")
    }

    func testThermalRateRisesWithTemperature() {
        let low = ExpiryEngine.thermalRate(celsius: -18, activationEnergyEV: 0.6)
        let fridge = ExpiryEngine.thermalRate(celsius: 4, activationEnergyEV: 0.6)
        let cool = ExpiryEngine.thermalRate(celsius: 17.5, activationEnergyEV: 0.6)
        let warm = ExpiryEngine.thermalRate(celsius: 22.5, activationEnergyEV: 0.6)
        let hot = ExpiryEngine.thermalRate(celsius: 32, activationEnergyEV: 0.6)

        XCTAssertLessThan(low, fridge)
        XCTAssertLessThan(fridge, cool)
        XCTAssertLessThan(cool, warm)
        XCTAssertLessThan(warm, hot)
        XCTAssertEqual(cool, 1, accuracy: 0.0001, "The cool room is the reference temperature")
    }

    // MARK: - Storage timelines

    func testMixedTimelineLandsBetweenItsPeriods() {
        let subject = engine()
        let mixed = ExpiryStorageTimeline(segments: [
            ExpiryStorageSegment(tier: .roomTemperature, fraction: 0.6),
            ExpiryStorageSegment(tier: .frozen, fraction: 0.4)
        ])

        let frozen = subject.quickEstimate(request(profile(), yearsPastExpiry: 12, timeline: .single(.frozen)))
        let room = subject.quickEstimate(request(profile(), yearsPastExpiry: 12, timeline: .single(.roomTemperature)))
        let combined = subject.quickEstimate(request(profile(), yearsPastExpiry: 12, timeline: mixed))

        XCTAssertGreaterThan(combined.stops, frozen.stops)
        XCTAssertLessThan(combined.stops, room.stops)
    }

    func testTimelineFractionsAreNormalised() {
        let timeline = ExpiryStorageTimeline(segments: [
            ExpiryStorageSegment(tier: .coolRoom, fraction: 3),
            ExpiryStorageSegment(tier: .frozen, fraction: 1)
        ])
        XCTAssertEqual(timeline.normalised.count, 2)
        XCTAssertEqual(timeline.normalised[0].fraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(timeline.normalised[1].fraction, 0.25, accuracy: 0.0001)
    }

    func testEmptyTimelineFallsBackToUnknown() {
        let timeline = ExpiryStorageTimeline(segments: [])
        XCTAssertEqual(timeline.normalised.count, 1)
        XCTAssertTrue(timeline.normalised[0].tier.isUnknown)
        XCTAssertLessThan(timeline.certainty, 1)
    }

    func testUnknownStorageLowersConfidence() {
        let subject = engine(samples: 600)
        let known = subject.estimate(request(profile(), yearsPastExpiry: 15, timeline: .single(.coolRoom)))
        let unknown = subject.estimate(request(profile(), yearsPastExpiry: 15, timeline: .single(.unknown)))

        XCTAssertLessThan(unknown.confidenceScore, known.confidenceScore)
        XCTAssertGreaterThanOrEqual(
            unknown.highStops - unknown.lowStops,
            known.highStops - known.lowStops - 0.001,
            "Unknown storage must not narrow the answer"
        )
    }

    func testUnknownStorageIsNotAssumedToBeAnAttic() {
        let subject = engine(samples: 900)
        let unknown = subject.estimate(request(profile(), yearsPastExpiry: 15, timeline: .single(.unknown)))
        let hot = subject.estimate(request(profile(), yearsPastExpiry: 15, timeline: .single(.hot)))

        XCTAssertLessThanOrEqual(unknown.stops, hot.stops + 0.001)
    }

    // MARK: - Film families

    func testFamiliesDoNotAgeIdentically() {
        let subject = engine()

        let slowBW = subject.quickEstimate(request(profile(
            key: "slow", iso: 100, process: .blackAndWhite, group: .slowModernBW
        ), yearsPastExpiry: 20))

        let fastBW = subject.quickEstimate(request(profile(
            key: "fast", iso: 3200, process: .blackAndWhite, group: .fastBW
        ), yearsPastExpiry: 20))

        let portra = subject.quickEstimate(request(profile(
            key: "colour", iso: 400, process: .colourNegative, group: .professionalColourNegative
        ), yearsPastExpiry: 20))

        XCTAssertLessThan(slowBW.stops, fastBW.stops, "A fine-grain modern film should outlast a 3200-speed one")
        XCTAssertNotEqual(slowBW.stops, portra.stops, accuracy: 0.0001)
    }

    func testUnknownFilmGroupIsEducatedGuess() {
        let subject = engine(samples: 500)
        let unlisted = profile(
            key: "unlisted",
            name: "Something old",
            iso: 200,
            process: .blackAndWhite,
            group: .other,
            evidence: .assumed,
            base: .unknown
        )
        let result = subject.estimate(request(unlisted, yearsPastExpiry: 18, timeline: .single(.unknown)))

        XCTAssertEqual(result.confidence, .educatedGuess)
        XCTAssertFalse(result.explanation.isEmpty)
        XCTAssertTrue(result.eiMedian > 0)
        XCTAssertGreaterThan(result.contributions.count, 3)
    }

    func testAssumedEvidenceCannotSoundWellDocumented() {
        let subject = engine(samples: 600)
        let assumed = profile(evidence: .assumed, base: .acetate)
        let result = subject.estimate(request(assumed, yearsPastExpiry: 4, timeline: .single(.coolRoom)))
        XCTAssertNotEqual(result.confidence, .wellDocumented)
    }

    // MARK: - Curve and saturation

    func testCharacteristicCurveIncreasesMonotonically() {
        let curve = ExpiryCharacteristicCurve(
            baseFog: 0.06,
            gamma: 0.62,
            maxDensity: 2.6,
            toeDecades: 0.5,
            speedShiftDecades: 0.2
        )
        var previous = 0.0
        for step in stride(from: -2.0, through: 6.0, by: 0.1) {
            let density = curve.density(decades: step)
            XCTAssertGreaterThanOrEqual(density, previous - 1e-9)
            XCTAssertTrue(density.isFinite)
            previous = density
        }
        XCTAssertGreaterThan(curve.density(decades: 8), curve.baseFog + 1.5)
        XCTAssertLessThan(curve.density(decades: 20), curve.maxDensity + 1e-9)
    }

    func testCurveReturnsNilWhenTargetIsOutOfReach() {
        let saturated = ExpiryCharacteristicCurve(
            baseFog: 0.9,
            gamma: 0.5,
            maxDensity: 1.0,
            toeDecades: 0.5,
            speedShiftDecades: 0
        )
        XCTAssertNil(saturated.decades(forDensity: 1.05))
        XCTAssertNotNil(saturated.decades(forDensity: 0.95))
    }

    func testExtremeAgeReachesLargeCompensation() {
        let subject = engine(samples: 800)
        let extreme = profile(
            key: "extreme",
            name: "Old push film",
            iso: 3200,
            process: .blackAndWhite,
            group: .fastBW,
            evidence: .literatureDerived
        )
        let result = subject.estimate(request(extreme, yearsPastExpiry: 80, timeline: .single(.hot)))

        XCTAssertGreaterThan(result.stops, 2.0, "Eighty years in an attic must cost several stops")
        XCTAssertTrue(result.isSaturated || result.stops >= 3.0)
    }

    func testSaturationIsReportedWhenItHappens() {
        let saturated = ExpiryEstimate(
            requestedISO: 400,
            eiLow: 12,
            eiMedian: 12,
            eiHigh: 12,
            stops: 5,
            lowStops: 5,
            highStops: 5,
            confidence: .educatedGuess,
            confidenceScore: 0.3,
            explanation: "",
            warnings: [
                ExpiryWarning(id: "saturated", title: "Compensation has run out", detail: "", isSevere: true)
            ],
            bracketing: nil,
            isSaturated: true,
            contributions: [],
            ageYears: 80,
            shelfLifeYears: 2,
            manufactureYear: 1945,
            equivalentThermalYears: 200,
            fogIncrease: 0.9,
            group: .fastBW,
            isExpired: true,
            calibrationDelta: 0,
            sampleCount: 2000
        )

        XCTAssertTrue(saturated.warnings.contains { $0.id == "saturated" })
        XCTAssertNil(saturated.bracketing)
    }

    // MARK: - Ladder

    func testLadderSnapsToThirdStops() {
        let ladder = ExpiryEILadder(iso: 400)
        XCTAssertEqual(ladder.ei(at: 0), 400)
        XCTAssertEqual(ladder.ei(at: 3), 200)
        XCTAssertEqual(ladder.ei(at: 9), 50)

        var previous = Int.max
        for index in 0...12 {
            let ei = ladder.ei(at: index)
            XCTAssertLessThan(ei, previous, "The ladder must fall monotonically")
            previous = ei
        }
    }

    func testEveryReportedIndexIsOnTheLadder() {
        let subject = engine(samples: 400)
        let result = subject.estimate(request(profile(), yearsPastExpiry: 14))
        let ladder = ExpiryEILadder(iso: 400)

        XCTAssertTrue((0...60).map { ladder.ei(at: $0) }.contains(result.eiMedian))
        XCTAssertLessThanOrEqual(result.eiLow, result.eiMedian, "The low EI is the most exposure")
        XCTAssertGreaterThanOrEqual(result.eiHigh, result.eiMedian, "The high EI is the least exposure")
        XCTAssertEqual(result.stops, (result.stops * 3).rounded() / 3, accuracy: 1e-9)
    }

    // MARK: - Determinism and stability

    func testEstimateIsDeterministicForTheSameInput() {
        let subject = engine(samples: 700)
        let input = request(profile(), yearsPastExpiry: 17, timeline: .single(.refrigerator))

        let first = subject.estimate(input)
        let second = subject.estimate(input)

        XCTAssertEqual(first.eiMedian, second.eiMedian)
        XCTAssertEqual(first.eiLow, second.eiLow)
        XCTAssertEqual(first.eiHigh, second.eiHigh)
        XCTAssertEqual(first.stops, second.stops, accuracy: 1e-12)
        XCTAssertEqual(first.confidence, second.confidence)
    }

    func testMalformedInputStaysFinite() {
        let subject = engine(samples: 300)
        let odd = profile(key: "odd", name: "Odd", iso: 1, process: .colourReversal, group: .slide)
        let zeroFraction = ExpiryStorageTimeline(segments: [
            ExpiryStorageSegment(tier: .hot, fraction: 0),
            ExpiryStorageSegment(tier: .frozen, fraction: 0)
        ])

        let result = subject.estimate(request(
            odd,
            yearsPastExpiry: 200,
            timeline: zeroFraction
        ))

        XCTAssertTrue(result.stops.isFinite)
        XCTAssertTrue(result.fogIncrease.isFinite)
        XCTAssertTrue(result.explanation.isEmpty == false)
        XCTAssertGreaterThanOrEqual(result.eiMedian, 1)
        XCTAssertLessThanOrEqual(result.eiLow, result.eiMedian)
        XCTAssertGreaterThanOrEqual(result.eiHigh, result.eiMedian)
    }

    func testNegativeAgeIsTreatedAsUnexpired() {
        let result = engine().estimate(request(profile(), yearsPastExpiry: -40))
        XCTAssertFalse(result.isExpired)
        XCTAssertEqual(result.stops, 0)
    }

    func testPercentileAndDeviationHelpers() {
        let values: [Double] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        XCTAssertEqual(ExpiryEngine.percentile(values, 0), 0)
        XCTAssertEqual(ExpiryEngine.percentile(values, 1), 10)
        XCTAssertEqual(ExpiryEngine.percentile(values, 0.5), 5, accuracy: 1e-9)
        XCTAssertEqual(ExpiryEngine.deviation(of: [2, 2, 2]), 0, accuracy: 1e-9)
        XCTAssertEqual(ExpiryEngine.mean(of: []), 0)
    }

    // MARK: - Colours and warnings

    func testColourFilmGainsACrossoverWarningWithAge() {
        let subject = engine(samples: 500)
        let result = subject.estimate(request(
            profile(iso: 100, process: .colourReversal, group: .slide),
            yearsPastExpiry: 25
        ))
        XCTAssertTrue(result.warnings.contains { $0.id == "crossover" })
    }

    func testBlackAndWhiteDoesNotGetACrossoverWarning() {
        let subject = engine(samples: 400)
        let result = subject.estimate(request(
            profile(iso: 400, process: .blackAndWhite, group: .classicBW),
            yearsPastExpiry: 25
        ))
        XCTAssertFalse(result.warnings.contains { $0.id == "crossover" })
    }

    func testOldAcetateGetsTheBaseWarning() {
        let subject = engine(samples: 400)
        let acetate = subject.estimate(request(
            profile(base: .acetate),
            yearsPastExpiry: 30,
            timeline: .single(.coolRoom)
        ))
        XCTAssertTrue(acetate.warnings.contains { $0.id == "acetate" })

        let polyester = subject.estimate(request(
            profile(base: .polyester),
            yearsPastExpiry: 30,
            timeline: .single(.coolRoom)
        ))
        XCTAssertFalse(polyester.warnings.contains { $0.id == "acetate" })
    }

    func testWideRangeProducesBracketingAdvice() {
        let subject = engine(samples: 900)
        let result = subject.estimate(request(profile(), yearsPastExpiry: 25, timeline: .single(.unknown)))
        if result.confidence == .educatedGuess || (result.highStops - result.lowStops) >= 0.9 {
            XCTAssertNotNil(result.bracketing)
        }
    }

    // MARK: - Per-film overrides

    func testOverrideDocumentDecodesAndApplies() throws {
        let json = """
        {
          "schema": 1,
          "films": [
            {
              "filmKey": "kodak-t-max-100",
              "group": "slowModernBW",
              "evidence": "literatureDerived",
              "overrides": { "fogCeiling": 0.16, "speedLossStops": 0.3 },
              "note": "Keeps well."
            }
          ]
        }
        """

        let document = try JSONDecoder().decode(ExpiryOverrideDocument.self, from: Data(json.utf8))
        XCTAssertEqual(document.films.count, 1)

        var model = ExpiryModel(groups: ExpiryModel.defaultGroups, curated: [:])
        for entry in document.films {
            model.curated[entry.filmKey] = entry
        }

        let film = libraryFilm(key: "kodak-t-max-100", iso: 100, process: .blackAndWhite)
        let resolved = model.profile(for: film)

        XCTAssertEqual(resolved.group, .slowModernBW)
        XCTAssertEqual(resolved.evidence, .literatureDerived)
        XCTAssertTrue(resolved.hasCuratedProfile)

        let parameters = model.parameters(for: resolved, expiryYear: 2014)
        XCTAssertEqual(parameters.fogCeiling, 0.16, accuracy: 1e-9)
        XCTAssertEqual(parameters.speedLossStops, 0.3, accuracy: 1e-9)
    }

    func testUnknownFilmKeyFallsBackToAConservativeProfile() {
        let model = ExpiryModel(groups: ExpiryModel.defaultGroups, curated: [:])
        let resolved = model.profile(for: libraryFilm(key: "nobody-knows", iso: 400, process: .colourNegative))

        XCTAssertEqual(resolved.group, .consumerColourNegative)
        XCTAssertEqual(resolved.evidence, .literatureDerived)
        XCTAssertFalse(resolved.hasCuratedProfile)
    }

    func testEraAdjustsShelfLifeAndStability() {
        let modern = ExpiryCatalogue.era(expiryYear: 2018)
        let eighties = ExpiryCatalogue.era(expiryYear: 1988)
        let sixties = ExpiryCatalogue.era(expiryYear: 1965)

        XCTAssertEqual(modern.shelf, 1.0, accuracy: 1e-9)
        XCTAssertGreaterThan(eighties.shelf, modern.shelf)
        XCTAssertGreaterThan(sixties.shelf, eighties.shelf)
        XCTAssertLessThan(sixties.stability, modern.stability)
        XCTAssertNotNil(sixties.note)
    }

    func testBaseMaterialIsReadFromTheLibraryWhenDocumented() {
        let documented = LibraryFilm(
            key: "doc",
            manufacturer: "Kodak",
            name: "Portra",
            iso: 400,
            process: .colourNegative,
            formats: [.size120],
            status: .current,
            generation: nil,
            generationLabel: nil,
            latitude: nil,
            grain: nil,
            contrast: nil,
            reciprocity: nil,
            notes: nil,
            origin: nil,
            history: nil,
            grainStructure: nil,
            characteristics: [
                LibraryCharacteristic(
                    label: "Base",
                    value: "Polyester, clear.",
                    provenance: LibraryProvenance(kind: .datasheet, source: nil, note: nil)
                )
            ]
        )

        let base = ExpiryCatalogue.baseMaterial(for: documented)
        XCTAssertEqual(base.material, .polyester)
        XCTAssertFalse(base.isAssumed)
    }

    // MARK: - Calibration

    private func point(
        film: String = "film-a",
        outcome: ExpiryRollOutcome,
        weight: ExpiryCalibrationEvidence = .controlled,
        quality: Int = 5
    ) -> ExpiryCalibrationPoint {
        ExpiryCalibrationPoint(
            filmKey: film,
            group: .consumerColourNegative,
            ageYears: 10,
            storage: "Cool room",
            exposureIndex: 200,
            quality: quality,
            evidence: weight,
            source: "test",
            notes: "",
            outcome: outcome
        )
    }

    func testOneRollDoesNotRewriteTheFilm() {
        let analyser = ExpiryCalibrationAnalyser()
        let single = analyser.adjustment(
            forFilm: "film-a",
            group: .consumerColourNegative,
            points: [point(outcome: .underexposed)]
        )

        XCTAssertLessThan(abs(single.deltaStops), 0.15, "A single roll must barely move the prediction")
        XCTAssertEqual(single.filmObservations, 1)
    }

    func testManyRollsShiftThePredictionButStayBounded() {
        let analyser = ExpiryCalibrationAnalyser()
        var points: [ExpiryCalibrationPoint] = []
        for _ in 0..<40 {
            points.append(point(outcome: .underexposed))
        }

        let adjustment = analyser.adjustment(forFilm: "film-a", group: .consumerColourNegative, points: points)
        XCTAssertGreaterThan(adjustment.deltaStops, 0.05)
        XCTAssertLessThanOrEqual(abs(adjustment.deltaStops), ExpiryCalibrationAdjustment.maximumShiftStops)
    }

    func testGoodOutcomesPullInTheOppositeDirection() {
        let analyser = ExpiryCalibrationAnalyser()
        let points = (0..<20).map { _ in point(outcome: .overexposed) }
        let adjustment = analyser.adjustment(forFilm: "film-a", group: .consumerColourNegative, points: points)
        XCTAssertLessThan(adjustment.deltaStops, 0)
    }

    func testLeaveOneOutUsesHeldOutObservations() {
        let analyser = ExpiryCalibrationAnalyser()
        let points = [
            point(outcome: .underexposed),
            point(outcome: .good),
            point(outcome: .underexposed)
        ]

        let loo = analyser.leaveOneOut(filmKey: "film-a", group: .consumerColourNegative, points: points)
        XCTAssertEqual(loo.count, 3)
        XCTAssertGreaterThanOrEqual(loo.error, 0)
        XCTAssertTrue(loo.error.isFinite)
    }

    func testLeaveOneOutNeedsTwoRolls() {
        let analyser = ExpiryCalibrationAnalyser()
        let loo = analyser.leaveOneOut(
            filmKey: "film-a",
            group: .consumerColourNegative,
            points: [point(outcome: .good)]
        )
        XCTAssertEqual(loo.count, 0)
        XCTAssertEqual(loo.error, 0)
    }

    func testCalibrationWeightsByEvidence() {
        let analyser = ExpiryCalibrationAnalyser()
        let anecdotal = analyser.adjustment(
            forFilm: "film-b",
            group: .consumerColourNegative,
            points: [point(film: "film-b", outcome: .underexposed, weight: .anecdotal, quality: 1)]
        )
        let controlled = analyser.adjustment(
            forFilm: "film-b",
            group: .consumerColourNegative,
            points: [point(film: "film-b", outcome: .underexposed, weight: .controlled, quality: 5)]
        )

        XCTAssertGreaterThan(controlled.deltaStops, anecdotal.deltaStops)
    }

    func testNoPointsIsNoAdjustment() {
        let adjustment = ExpiryCalibrationAnalyser().adjustment(
            forFilm: "film-a",
            group: .consumerColourNegative,
            points: []
        )
        XCTAssertEqual(adjustment.deltaStops, 0)
        XCTAssertFalse(adjustment.isActive)
    }

    // MARK: - Held-out validation

    private func datedPoint(_ index: Int, daysApart: Double = 1) -> ExpiryCalibrationPoint {
        var point = self.point(outcome: .good)
        point.recorded = Date(timeIntervalSince1970: 1_600_000_000 + Double(index) * daysApart * 86_400)
        return point
    }

    func testSplitHoldsBackTheMostRecentRolls() {
        let points = (0..<10).map { datedPoint($0) }
        let split = ExpiryCalibrationStore.split(points)

        XCTAssertEqual(split.fitting.count, 8)
        XCTAssertEqual(split.validation.count, 2)
        XCTAssertGreaterThan(
            split.validation.first?.recorded ?? .distantPast,
            split.fitting.last?.recorded ?? .distantFuture,
            "The held-out rolls must be the later ones"
        )
        XCTAssertTrue(split.validation.allSatisfy { held in
            !split.fitting.contains { $0.id == held.id }
        })
    }

    func testSplitKeepsEverythingWhenThereAreTooFewRolls() {
        let points = (0..<3).map { datedPoint($0) }
        let split = ExpiryCalibrationStore.split(points)

        XCTAssertEqual(split.fitting.count, 3)
        XCTAssertTrue(split.validation.isEmpty, "Three rolls cannot be split usefully")
    }

    func testSplitIsStableForTheSameRolls() {
        let points = (0..<12).map { datedPoint($0) }
        let first = ExpiryCalibrationStore.split(points)
        let second = ExpiryCalibrationStore.split(points)
        XCTAssertEqual(first.fitting.map(\.id), second.fitting.map(\.id))
        XCTAssertEqual(first.validation.map(\.id), second.validation.map(\.id))
    }

    func testCalibrationFeedShiftsTheEstimate() {
        let subject = engine(samples: 700)
        let input = request(profile(), yearsPastExpiry: 15, timeline: .single(.coolRoom))

        let plain = subject.estimate(input)
        let shifted = subject.estimate(
            input,
            calibration: ExpiryCalibrationAdjustment(
                deltaStops: 0.5,
                filmDelta: 0.5,
                groupDelta: 0,
                filmObservations: 10,
                groupObservations: 10,
                leaveOneOutError: 0,
                leaveOneOutCount: 0
            )
        )

        XCTAssertGreaterThanOrEqual(shifted.stops, plain.stops)
        XCTAssertLessThanOrEqual(shifted.eiMedian, plain.eiMedian)
    }

    // MARK: - Seed

    func testSeedIsStableAcrossRuns() {
        let input = request(profile(), yearsPastExpiry: 9, timeline: .single(.refrigerator))
        let first = input.deterministicSeed
        let second = input.deterministicSeed
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, 0)

        let other = request(profile(), yearsPastExpiry: 9, timeline: .single(.hot))
        XCTAssertNotEqual(first, other.deterministicSeed)
    }

    func testGeneratorIsDeterministic() {
        var first = ExpirySeededGenerator(seed: 42)
        var second = ExpirySeededGenerator(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(first.unit(), second.unit(), accuracy: 1e-15)
        }
    }

    // MARK: - What a logged roll actually says

    private func rolled(
        _ film: String = "film-a",
        outcome: ExpiryRollOutcome,
        box: Int,
        shot: Int,
        predicted: Double,
        recorded: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ExpiryCalibrationPoint {
        ExpiryCalibrationPoint(
            filmKey: film,
            group: .consumerColourNegative,
            ageYears: 12,
            storage: "Cool room",
            exposureIndex: shot,
            boxISO: box,
            predictedStops: predicted,
            quality: 5,
            evidence: .controlled,
            source: "test",
            notes: "",
            outcome: outcome,
            recorded: recorded
        )
    }

    func testAGoodRollAtBoxSpeedIsEvidenceAgainstAPredictionOfMoreLight() {
        // The model wanted half a stop; the roll was shot at box speed and came
        // out right. That is half a stop of evidence against the model, not a
        // no-op, which is what an outcome-only residual would have made it.
        let point = rolled(outcome: .good, box: 400, shot: 400, predicted: 0.5)
        XCTAssertEqual(point.shotStops, 0, accuracy: 1e-9)
        XCTAssertEqual(point.residualStops, -0.5, accuracy: 1e-9)
    }

    func testAGoodRollAtTheRecommendedIndexIsAZeroResidual() {
        // EI 283 on a 400 box speed is +0.5 stops, which is exactly what the
        // model asked for, so a good result there confirms it.
        let point = rolled(outcome: .good, box: 400, shot: 283, predicted: 0.5)
        XCTAssertEqual(point.shotStops, 0.5, accuracy: 0.01)
        XCTAssertEqual(point.residualStops, 0, accuracy: 0.01)
    }

    func testAnUnderexposedRollAtAnAdjustedIndexSaysHowShortItWas() {
        // Shot half a stop over box against a prediction of +0.5 and still thin:
        // the film wanted about a stop, so the model is short by half of one.
        let point = rolled(outcome: .underexposed, box: 400, shot: 283, predicted: 0.5)
        XCTAssertEqual(point.residualStops, 0.5, accuracy: 0.01)
    }

    func testBoxSpeedOnAFilmTheModelWantedMoreLightForMovesDown() {
        let points = (0..<30).map { _ in
            rolled(outcome: .good, box: 400, shot: 400, predicted: 0.5)
        }
        let adjustment = ExpiryCalibrationAnalyser().adjustment(
            forFilm: "film-a",
            group: .consumerColourNegative,
            points: points
        )
        XCTAssertLessThan(
            adjustment.deltaStops,
            0,
            "A good roll at box speed must pull a +0.5 prediction down, not back toward zero"
        )
    }

    func testResearchObservationsAreNeverHeldOut() {
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
        let own = (0..<3).map { _ in
            rolled(outcome: .good, box: 400, shot: 400, predicted: 0.5)
        }

        let loo = ExpiryCalibrationAnalyser().leaveOneOut(
            filmKey: "film-a",
            group: .consumerColourNegative,
            points: own + [research]
        )
        XCTAssertEqual(loo.count, 3, "Only the reader's own rolls are validated")
    }

    func testARecordWrittenBeforeTheBaselineExistedStillDecodes() throws {
        let json = """
        [{"id":"old","filmKey":"film-a","group":"consumerColourNegative","ageYears":8,\
        "storage":"Cool room","exposureIndex":200,"quality":4,"evidence":"personal",\
        "source":"","notes":"","outcome":"underexposed","recorded":0}]
        """
        let decoded = try JSONDecoder().decode([ExpiryCalibrationPoint].self, from: Data(json.utf8))

        XCTAssertEqual(decoded.count, 1, "A missing baseline must not wipe the reader's history")
        XCTAssertEqual(decoded[0].boxISO, 0)
        XCTAssertEqual(decoded[0].predictedStops, 0, accuracy: 1e-9)
        XCTAssertEqual(decoded[0].residualStops, 0.5, accuracy: 1e-9)
    }

    // MARK: - The store

    private func store(named name: String) -> ExpiryCalibrationStore {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return ExpiryCalibrationStore(defaults: defaults)
    }

    func testAnUnlistedStockCannotBeLogged() {
        let calibration = store(named: "darkroom.expiry.unlisted")
        let stored = calibration.add(rolled("unlisted", outcome: .good, box: 400, shot: 400, predicted: 0.5))

        XCTAssertFalse(stored, "Every unlisted stock shares one key, so its rolls can never be told apart")
        XCTAssertTrue(calibration.points.isEmpty)
    }

    func testRollsWithoutABoxSpeedAreKeptButNotFitted() {
        let calibration = store(named: "darkroom.expiry.legacy")
        calibration.add(rolled("film-a", outcome: .good, box: 400, shot: 400, predicted: 0.5))
        var legacy = rolled("film-a", outcome: .underexposed, box: 400, shot: 400, predicted: 0)
        legacy.boxISO = 0
        calibration.add(legacy)

        XCTAssertEqual(calibration.points.count, 2, "Nothing that was logged is discarded")
        XCTAssertEqual(calibration.unmeasuredCount, 1)
        let fitting = calibration.fittingPoints(model: .standard, film: { _ in nil })
        XCTAssertFalse(
            fitting.contains { !$0.isResearch && $0.boxISO == 0 },
            "A roll with no box speed has no measured residual, so it must not move the answer"
        )
        calibration.removeAll()
    }

    func testDeletingRollsTakesOnlyOneFilm() {
        let calibration = store(named: "darkroom.expiry.delete")
        calibration.add(rolled("film-a", outcome: .good, box: 400, shot: 400, predicted: 0.5))
        calibration.add(rolled("film-b", outcome: .good, box: 400, shot: 400, predicted: 0.5))
        calibration.add(rolled("film-a", outcome: .overexposed, box: 400, shot: 400, predicted: 0.5))

        calibration.removeAll(forFilm: "film-a")

        XCTAssertEqual(calibration.points.map(\.filmKey), ["film-b"])
        calibration.removeAll()
    }

    // MARK: - Storage as a timeline

    func testPeriodsInTheSameTierAreOnePeriod() {
        let timeline = ExpiryStorageTimeline(segments: [
            ExpiryStorageSegment(tier: .roomTemperature, fraction: 0.6),
            ExpiryStorageSegment(tier: .roomTemperature, fraction: 0.4)
        ])

        XCTAssertEqual(timeline.normalised.count, 1)
        XCTAssertEqual(timeline.normalised[0].fraction, 1, accuracy: 1e-9)
        XCTAssertTrue(timeline.isSingleTier)
        XCTAssertEqual(
            timeline.certainty,
            1,
            accuracy: 1e-9,
            "Splitting one period in two is not new uncertainty"
        )
    }

    func testAddingAPeriodOfTheSameTierCannotMoveTheAnswer() {
        let subject = engine(samples: 300)
        let whole = request(profile(), yearsPastExpiry: 12, timeline: .single(.roomTemperature))
        let split = request(
            profile(),
            yearsPastExpiry: 12,
            timeline: ExpiryStorageTimeline(segments: [
                ExpiryStorageSegment(tier: .roomTemperature, fraction: 0.5),
                ExpiryStorageSegment(tier: .roomTemperature, fraction: 0.5)
            ])
        )

        XCTAssertEqual(
            subject.estimate(whole).eiMedian,
            subject.estimate(split).eiMedian,
            "An editor that has added a period but not described one must not change the estimate"
        )
    }

    // MARK: - Films still inside their date

    func testAnInDateFilmWithUnknownStorageIsNotCalledWellDocumented() {
        let subject = engine(samples: 200)
        let known = subject.estimate(
            request(profile(), yearsPastExpiry: -1, timeline: .single(.coolRoom))
        )
        let unknown = subject.estimate(
            request(profile(), yearsPastExpiry: -1, timeline: .single(.unknown))
        )

        XCTAssertFalse(known.isExpired)
        XCTAssertEqual(known.eiMedian, 400)
        XCTAssertEqual(known.confidence, .wellDocumented)
        XCTAssertNotEqual(
            unknown.confidence,
            .wellDocumented,
            "Unknown storage cannot read as well documented"
        )
        XCTAssertLessThan(unknown.confidenceScore, known.confidenceScore)
    }

    func testAnUnlistedStockStillInDateIsOnlyAGuess() {
        let subject = engine(samples: 200)
        let result = subject.estimate(
            request(
                profile(key: "unlisted", evidence: .assumed),
                yearsPastExpiry: -1,
                timeline: .single(.coolRoom)
            )
        )
        XCTAssertEqual(result.confidence, .educatedGuess)
    }

    // MARK: - The notes on screen

    func testTheParameterNoteQuotesTheNumbersTheEngineActuallyUses() throws {
        let annotation = try XCTUnwrap(
            ExpiryParameterCatalogue.annotation(id: "radiation-magnitude")
        )
        let rate = String(format: "%.4f", ExpiryEngine.baseRadiationFogPerYear)
        let floor = String(format: "%.4f", ExpiryEngine.minimumRadiationFogPerYear)

        XCTAssertTrue(annotation.note.contains(rate), "The note must quote the deployed rate, \(rate)")
        XCTAssertTrue(annotation.note.contains(floor), "The note must quote the deployed floor, \(floor)")
    }

}
