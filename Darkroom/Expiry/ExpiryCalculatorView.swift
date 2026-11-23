//
//  ExpiryCalculatorView.swift
//  Darkroom
//
//  The expired-film EI calculator: a film, the date printed on it, and how it has
//  been stored, answered with a recommended exposure index, a probabilistic
//  range, and an honest account of what the model does and does not know.
//
//  Exposure only. Nothing here recommends a developer or a time.
//

import SwiftUI

struct ExpiryCalculatorView: View {
    @ObservedObject private var store = LibraryStore.shared
    @ObservedObject private var calibration = ExpiryCalibrationStore.shared

    @State private var selection: ExpiryFilmSelection?
    @State private var expiryDate = ExpiryCalculatorView.defaultExpiry
    @State private var tier: ExpiryStorageTier = .roomTemperature
    @State private var usesTimeline = false
    /// Whether the "Where has it been?" disclosure is open. Only the reveal of
    /// the editor, never the storage the answer is computed from.
    @State private var timelineExpanded = false
    @State private var segments: [ExpiryStorageSegment] = []
    @State private var estimate: ExpiryEstimate?
    @State private var isRefining = false
    @State private var choosingFilm = false
    @State private var loggedOutcome: ExpiryRollOutcome?
    @State private var loggedQuality = 3
    /// The exposure index the reader typed for the roll they are logging. Kept as
    /// text so an empty field stays empty instead of quietly becoming a number.
    @State private var loggedEI = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingModelNotes = false

    private static let warningInk = Color(red: 1.0, green: 0.62, blue: 0.42)
    private static let severeInk = Color(red: 1.0, green: 0.42, blue: 0.34)

    static var defaultExpiry: Date {
        Calendar.current.date(byAdding: .year, value: -6, to: Date()) ?? Date()
    }

    private var dateRange: ClosedRange<Date> {
        let start = Calendar.current.date(from: DateComponents(year: 1950, month: 1, day: 1)) ?? Date.distantPast
        let end = Calendar.current.date(byAdding: .year, value: 8, to: Date()) ?? Date()
        return start...end
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                introduction
                disclaimerCard
                filmRow
                dateCard
                storageCard
                resultSection
                timelineDisclosure
                logRollDisclosure
                modelCard
                sourcesDisclosure
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background { LiquidBackdrop() }
        .navigationTitle("Expired film")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $choosingFilm) {
            ExpiryFilmPickerView(selection: resolvedSelection) { picked in
                selection = picked
                estimate = nil
            }
        }
        .task(id: requestKey) {
            await refresh()
        }
    }

    // MARK: - Model plumbing

    private var resolvedSelection: ExpiryFilmSelection {
        if let selection { return selection }
        if let preferred = store.films.first(where: { $0.key == "kodak-portra-400" }) {
            return .library(preferred.key)
        }
        if let first = store.films.first {
            return .library(first.key)
        }
        return .unlisted(name: "", iso: 400, process: .blackAndWhite)
    }

    private var profile: ExpiryFilmProfile {
        let model = ExpiryModel.standard
        switch resolvedSelection {
        case .library(let key):
            guard let film = store.film(key: key) else {
                return model.profile(forUnknown: key, iso: 400, process: .blackAndWhite)
            }
            return model.profile(for: film)
        case .unlisted(let name, let iso, let process):
            return model.profile(forUnknown: name, iso: iso, process: process)
        }
    }

    private var timeline: ExpiryStorageTimeline {
        if usesTimeline, !segments.isEmpty {
            return ExpiryStorageTimeline(segments: segments)
        }
        return .single(tier)
    }

    private var request: ExpiryRequest {
        ExpiryRequest(profile: profile, expiration: expiryDate, timeline: timeline, now: Date())
    }

    private var adjustment: ExpiryCalibrationAdjustment {
        calibration.adjustment(
            filmKey: profile.filmKey,
            group: profile.group,
            model: .standard,
            film: { store.film(key: $0) }
        )
    }

    /// Everything the answer depends on, so the task runs again when any of it
    /// changes and not on every redraw.
    private var requestKey: String {
        [
            profile.filmKey,
            "\(profile.iso)",
            profile.group.rawValue,
            "\(Int(expiryDate.timeIntervalSince1970 / 86_400))",
            timeline.normalised
                .map { "\($0.tier.rawValue):\(Int(($0.fraction * 1000).rounded()))" }
                .joined(separator: ","),
            "\(Int(adjustment.deltaStops * 1000))"
        ]
        .joined(separator: "|")
    }

    private func refresh() async {
        let request = self.request
        let adjustment = self.adjustment
        estimate = ExpiryCalculator.quick(request, calibration: adjustment)
        isRefining = true
        let full = await ExpiryCalculator.full(request, calibration: adjustment)
        estimate = full
        isRefining = false
    }

    // MARK: - Header

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverlineText(text: "Expired film", color: Theme.amber)
            Text("Date it.\nThen rate it.")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Film that has sat past its date has lost speed and gained fog. This works out how much extra exposure puts your shadows back where they were — and says how sure it is.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.top, 1)
            Text("Estimates. Expired film varies roll to roll. Bracket if you can.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 18)
    }

    // MARK: - Film

    private var filmRow: some View {
        Button {
            choosingFilm = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.amber)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("\(profile.manufacturer.isEmpty ? "Unlisted" : profile.manufacturer) · \(profile.process.label) · box speed ISO \(profile.iso)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticButtonStyle())
        .accessibilityLabel("Film stock, \(profile.displayName). Change.")
    }

    // MARK: - Date

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Printed expiration date")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                DatePicker(
                    "Expiration date",
                    selection: $expiryDate,
                    in: dateRange,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Theme.amber)
            }

            if let estimate {
                Text(estimate.isExpired
                     ? "About \(Self.yearsText(estimate.ageYears)) old — roughly \(Self.yearsText(max(0, estimate.ageYears - estimate.shelfLifeYears))) past its date."
                     : "Still inside its printed date.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    // MARK: - Storage

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage")
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExpiryStorageTier.allCases) { option in
                        storageChip(option)
                    }
                }
                .padding(.vertical, 1)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: tier.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 1)
                Text(tier.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if usesTimeline {
                Text(timeline.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    private func storageChip(_ option: ExpiryStorageTier) -> some View {
        let isOn = usesTimeline ? false : tier == option
        return Button {
            usesTimeline = false
            tier = option
            estimate = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(option.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Theme.amberInk : Theme.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(isOn ? Theme.amber : Theme.surfaceRaised)
            }
            .overlay {
                if !isOn {
                    Capsule().strokeBorder(Theme.border, lineWidth: 1)
                }
            }
        }
        .buttonStyle(HapticButtonStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Multi-period storage

    private var timelineDisclosure: some View {
        DisclosureGroup(isExpanded: $timelineExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Most rolls move. Give each stretch of the film's life its share, and the model integrates the temperature exposure across them instead of assuming one room.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach($segments) { $segment in
                    HStack(spacing: 10) {
                        Picker("Storage", selection: $segment.tier) {
                            ForEach(ExpiryStorageTier.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .tint(Theme.ink)

                        Spacer(minLength: 4)

                        Stepper(
                            "\(Int((segment.fraction * 100).rounded()))%",
                            value: $segment.fraction,
                            in: 0.05...1,
                            step: 0.05
                        )
                        .font(.figures(13))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize()
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        if segments.isEmpty {
                            // Start from what the reader has already chosen: one
                            // period covering the whole life at that tier.
                            // Nothing is invented, and the estimate does not
                            // move until a tier or a share is edited.
                            segments = [ExpiryStorageSegment(tier: tier, fraction: 1)]
                        } else {
                            segments.append(
                                ExpiryStorageSegment(tier: tier, fraction: 0.5)
                            )
                        }
                        usesTimeline = true
                        estimate = nil
                    } label: {
                        Label(
                            segments.isEmpty ? "Split the storage" : "Add a period",
                            systemImage: "plus"
                        )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.amber)
                    }
                    .buttonStyle(HapticButtonStyle())

                    Spacer(minLength: 4)

                    if segments.count > 1 {
                        Button {
                            segments.removeLast()
                            estimate = nil
                        } label: {
                            Text("Remove")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.inkFaint)
                        }
                        .buttonStyle(HapticButtonStyle())
                    }
                }

                Text("Shares are read as proportions, so they need not add to exactly 100%.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where has it been?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(usesTimeline ? "Several periods" : "One period assumed")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .tint(Theme.amber)
        .padding(16)
        .glassCard(radius: 20)
    }

    // MARK: - Result

    @ViewBuilder
    private var resultSection: some View {
        if let estimate {
            resultCard(estimate)

            ForEach(estimate.warnings) { warning in
                warningCard(warning)
            }

            if let bracketing = estimate.bracketing {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.amber)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bracket it")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(bracketing)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(radius: 20)
            }

            explainability(estimate)
        } else {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.amber)
                Text("Reading the film…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 20)
        }
    }

    private func resultCard(_ estimate: ExpiryEstimate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                OverlineText(
                    text: estimate.isExpired ? "Recommended exposure index" : "Rating",
                    color: Theme.amber
                )
                Spacer(minLength: 6)
                ExpiryConfidenceBadge(confidence: estimate.confidence)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("EI \(estimate.eiMedian)")
                    .font(.figures(48, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Recommended exposure index \(estimate.eiMedian)")

                if isRefining {
                    ProgressView()
                        .tint(Theme.inkFaint)
                        .scaleEffect(0.7)
                        .accessibilityLabel("Refining the estimate")
                }
            }

            Text("EI \(estimate.eiLow) – \(estimate.eiHigh) · best EI \(estimate.eiMedian)")
                .font(.figures(15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

            HStack(spacing: 8) {
                Text(compensationText(estimate))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if estimate.isSaturated {
                    Text("SATURATED")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.amberInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(Theme.amber) }
                }
            }

            Text(estimate.explanation)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if adjustment.isActive {
                Text("Adjusted by logged rolls: \(adjustment.summary)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 24, tint: Theme.amber)
    }

    private func compensationText(_ estimate: ExpiryEstimate) -> String {
        guard estimate.isExpired else { return "Box speed · no compensation" }
        if estimate.stops < 0.02 { return "Box speed · no compensation" }
        let stops = String(format: "%.1f", estimate.stops)
        return "+\(stops) stop\(estimate.stops >= 1.05 ? "s" : "") over box speed"
    }

    private func warningCard(_ warning: ExpiryWarning) -> some View {
        let ink = warning.isSevere ? Self.severeInk : Self.warningInk
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: warning.isSevere ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(warning.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(warning.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    // MARK: - Explainability

    private func explainability(_ estimate: ExpiryEstimate) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(estimate.contributions) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 6)
                            Text(row.value)
                                .font(.figures(12))
                                .foregroundStyle(Theme.amber)
                                .multilineTextAlignment(.trailing)
                        }
                        Text(row.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 2)
                }

                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("WHERE EACH PARAMETER COMES FROM")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkFaint)

                    ForEach(ExpiryParameterCatalogue.annotations) { annotation in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(annotation.field)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.ink.opacity(0.86))
                                Spacer(minLength: 4)
                                Text(annotation.classification.label.uppercased())
                                    .font(.system(size: 8, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(
                                        annotation.classification == .assumed ? Theme.amber : Theme.ink.opacity(0.7)
                                    )
                                    .multilineTextAlignment(.trailing)
                            }
                            Text(annotation.note)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 3)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("WHAT THIS MODEL ASSUMES")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkFaint)

                    ForEach(Self.assumptions, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Theme.inkFaint)
                                .frame(width: 4, height: 4)
                                .padding(.top, 5)
                            Text(line)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("Confidence: \(estimate.confidence.label.lowercased()) — \(estimate.confidence.detail)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)

                    Text("Film family: \(estimate.group.title). Evidence: \(profile.evidence.label.lowercased()). \(profile.groupReason).")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)

                    if let note = profile.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Why this number")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("Heat, radiation, fog and uncertainty")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .tint(Theme.amber)
        .padding(16)
        .glassCard(radius: 20)
    }

    private static let assumptions = [
        "The printed date is treated as an expiry, and manufacture as the printed date minus a shelf life drawn from a distribution — not a known coating date.",
        "Thermal ageing is an Arrhenius acceleration against a 17.5 °C reference. The activation energies are priors informed by how these families are described, not published rate constants.",
        "Radiation fog is modelled separately from heat, with a floor that cold storage cannot remove; the split between thermal and radiation fog is an assumption where the public record cannot separate them.",
        "The fresh characteristic curve is typical for the film's family, not a measured sensitometric trace of this box. Compensation is the difference between the aged and fresh curves, so both move together.",
        "Exposure compensation cannot repair chemical degradation, colour crossover, fog, contrast loss or physical base damage. It only moves the shadows away from the fog floor.",
        "Storage temperatures are distributions per band, with seasonal swing folded in. Humidity is not measured and is only implied by the storage tier.",
        "Logged rolls adjust the answer by at most half a stop and are weighted by evidence and quality; one roll never rewrites a film."
    ]

    // MARK: - Log a roll

    private var logRollDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Logging what a roll actually did is the only calibration that comes from measurements rather than assumptions. Outcomes are treated as ordinal — under, right, over — not as measured densities.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text("EI you shot at")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 4)
                    TextField("EI", text: $loggedEI)
                        .keyboardType(.numberPad)
                        .font(.figures(15, weight: .medium))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.ink)
                        .frame(width: 80)
                }

                Group {
                    if isUnlisted {
                        Text("Log this roll from a film in the library. An unlisted stock has no record to calibrate against, so its rolls are not kept.")
                    } else if let estimate, estimate.isExpired {
                        Text("This screen suggests EI \(estimate.eiMedian). Log the number you actually set on the meter, even when it is not that one — the record is only worth what it measures.")
                    } else {
                        Text("A roll that is still inside its date calibrates nothing: the maker's rating already covers it. Move the date into the past first.")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

                Text("How did the negatives come out?")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)

                HStack(spacing: 8) {
                    ForEach(ExpiryRollOutcome.allCases) { outcome in
                        Button {
                            loggedOutcome = outcome
                        } label: {
                            Text(outcome.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(loggedOutcome == outcome ? Theme.amberInk : Theme.inkSoft)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background {
                                    Capsule().fill(loggedOutcome == outcome ? Theme.amber : Theme.surfaceRaised)
                                }
                        }
                        .buttonStyle(HapticButtonStyle())
                        .accessibilityAddTraits(loggedOutcome == outcome ? .isSelected : [])
                    }
                }

                HStack(spacing: 10) {
                    Text("Negative quality")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 4)
                    Picker("Quality", selection: $loggedQuality) {
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                Button {
                    logRoll()
                } label: {
                    Text("Log this roll")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.amberInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background { Capsule().fill(Theme.amberGradient) }
                }
                .buttonStyle(HapticButtonStyle())
                .disabled(!canLogRoll)
                .opacity(canLogRoll ? 1 : 0.5)

                let validation = calibration.validation(
                    filmKey: profile.filmKey,
                    group: profile.group,
                    model: .standard,
                    film: { store.film(key: $0) }
                )
                Text(validationSummary(validation))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)

                if !isUnlisted, !calibration.points(forFilm: profile.filmKey).isEmpty {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Text("Delete my logged rolls for \(profile.displayName)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(HapticButtonStyle())
                    .confirmationDialog(
                        "Delete every roll logged for \(profile.displayName)?",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete these rolls", role: .destructive) {
                            calibration.removeAll(forFilm: profile.filmKey)
                            estimate = nil
                        }
                        Button("Keep them", role: .cancel) {}
                    } message: {
                        Text("Only the rolls for this film are removed. Rolls logged for other films stay.")
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log how this roll came out")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("\(calibration.points(forFilm: profile.filmKey).count) logged for this film")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .tint(Theme.amber)
        .padding(16)
        .glassCard(radius: 20)
    }

    /// An unlisted stock shares one key with every other unlisted stock, so its
    /// rolls cannot be told apart and are never stored.
    private var isUnlisted: Bool { profile.filmKey == "unlisted" }

    private var canLogRoll: Bool {
        guard !isUnlisted, loggedOutcome != nil, estimate?.isExpired == true else { return false }
        guard let shot = Int(loggedEI.trimmingCharacters(in: .whitespaces)), shot > 0 else { return false }
        return shot <= 100_000
    }

    /// Stores the roll against the exposure index the reader actually shot, and
    /// the model's prediction for the same film, age and storage with no
    /// adjustment applied. The residual is then measured against that
    /// prediction, so "good" at box speed on a film the model wanted half a
    /// stop more for is real evidence against the model, not a no-op.
    private func logRoll() {
        guard canLogRoll,
              let outcome = loggedOutcome,
              let shot = Int(loggedEI.trimmingCharacters(in: .whitespaces)),
              estimate != nil else { return }

        calibration.add(
            ExpiryCalibrationPoint(
                filmKey: profile.filmKey,
                group: profile.group,
                // The engine integrates from the printed date, so the age a
                // residual is measured at is years past date, not total age.
                ageYears: max(0, request.yearsPastExpiry),
                storage: timeline.summary,
                exposureIndex: shot,
                boxISO: profile.iso,
                predictedStops: ExpiryCalculator.baselineStops(request),
                quality: loggedQuality,
                evidence: .personal,
                source: "Logged in the expired-film calculator",
                notes: "",
                outcome: outcome
            )
        )
        loggedOutcome = nil
    }

    private func validationSummary(
        _ validation: (error: Double, count: Int, samples: Int, holdoutError: Double, holdoutCount: Int)
    ) -> String {
        var parts: [String] = []
        if validation.count > 0 {
            parts.append("leave-one-out error over \(validation.count) fitting roll\(validation.count == 1 ? "" : "s"): ±\(String(format: "%.2f", validation.error)) stops")
        }
        if validation.holdoutCount > 0 {
            parts.append("held-out error over \(validation.holdoutCount) later roll\(validation.holdoutCount == 1 ? "" : "s"): ±\(String(format: "%.2f", validation.holdoutError)) stops")
        }
        if parts.isEmpty {
            let older = calibration.unmeasuredCount
            let caveat = older > 0
                ? " \(older) older roll\(older == 1 ? " is" : "s are") kept but left out of the fit: it was logged before the box speed was recorded, so its compensation is unknown."
                : ""
            return "No rolls logged yet. Log five or more and the most recent fifth is held back, so the error is measured on rolls the fit has not seen." + caveat
        }
        return parts.joined(separator: " · ") + "."
    }

    // MARK: - Model card

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                Text("Exposure only")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                Button(showingModelNotes ? "Hide" : "Model") {
                    showingModelNotes.toggle()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.amber)
                .buttonStyle(HapticButtonStyle())
            }

            if showingModelNotes {
                Text("This calculator estimates an exposure index. It does not recommend a developer, a dilution or a development time, and it does not claim that exposure compensation recovers a film that has chemically degraded. Fog, colour crossover, contrast loss and a brittle acetate base are permanent changes; correct exposure only keeps what is left from being lost in the shadows.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Two thousand Monte Carlo samples per estimate, seeded from the inputs so the same film, date and storage always give the same answer. The parameters live in ExpiryParameters.swift and Resources/Library/expiry-overrides.json, every one of them labelled with how it is known.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    // MARK: - Sources

    private var sourcesDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.sources) { source in
                    if let url = URL(string: source.url) {
                        Link(destination: url) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.amber)
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(source.publisher)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.inkFaint)
                                    Text(source.usedFor)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.inkFaint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HapticButtonStyle())
                    }
                }

                Text("Read from the published documents while this model was built. Where a document was only available as a mirror or a search preview, it says so here: Kodak E-30 is quoted from a research-project mirror because Kodak's own copy no longer resolves, and the 1965 Air Force manual is read from a full-view scan.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "book.closed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sources")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("\(model.sources.count) published documents, with what each was used for")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.amber)
        .padding(16)
        .glassCard(radius: 20)
    }

    private var model: ExpiryModel { .standard }

    // MARK: - Formatting

    private static func yearsText(_ years: Double) -> String {
        if years < 1 { return String(format: "%.0f months", years * 12) }
        return String(format: "%.1f years", years)
    }
}

// MARK: - Confidence badge

struct ExpiryConfidenceBadge: View {
    let confidence: ExpiryConfidence

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(confidence.label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .lineLimit(1)
        }
        .foregroundStyle(confidence == .educatedGuess ? Theme.amber : Theme.ink.opacity(0.82))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(confidence == .educatedGuess ? Theme.accentWash : Theme.surfaceRaised)
        }
        .overlay {
            Capsule().strokeBorder(
                confidence == .educatedGuess ? Theme.amber.opacity(0.4) : Theme.border,
                lineWidth: 1
            )
        }
        .accessibilityLabel("Confidence: \(confidence.label)")
    }

    private var symbol: String {
        switch confidence {
        case .wellDocumented: return "checkmark.seal.fill"
        case .communityConsensus: return "person.2.fill"
        case .educatedGuess: return "questionmark.circle.fill"
        }
    }
}

#Preview {
    NavigationStack {
        ExpiryCalculatorView()
    }
}
