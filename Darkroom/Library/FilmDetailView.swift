//
//  FilmDetailView.swift
//  Darkroom
//
//  One film, everything the library knows about it: the facts that were sourced,
//  the times at each dilution and temperature with the badge that says where they
//  came from, the cross-process options, and the sources themselves.
//

import SwiftUI

struct FilmDetailView: View {
    let filmKey: String

    @ObservedObject private var store = LibraryStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showingCrossProcess = false
    @State private var sessionSelection: SessionSelection?
    @State private var chartState: ChartSectionState = .idle
    @State private var showingAllChartTimes = false

    var body: some View {
        Group {
            if let film = store.film(key: filmKey) {
                content(film)
            } else {
                missing
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingCrossProcess) {
            CrossProcessSheet(filmKey: filmKey)
        }
        .sheet(item: $sessionSelection) { selection in
            NavigationStack {
                SessionSetupView(
                    film: selection.film,
                    developer: selection.developer,
                    dilution: selection.dilution
                )
            }
        }
    }

    // MARK: Content

    private func content(_ film: LibraryFilm) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar(film)
                header(film)
                chips(film)
                originCard(film)
                historyCard(film)
                factTiles(film)
                characteristicsSection(film)

                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)

                ForEach(temperatureGroups(film), id: \.temperature) { group in
                    timesSection(film, group: group)
                }

                chartSection(film)

                crossProcessSection(film)
                sourcesSection(film)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 20)
            // A vertical page, and only vertical. A row wider than the screen —
            // a long developer name, a chart line — used to widen the scroll
            // view's content, which let the whole page be dragged sideways.
            // Pinning the content to the viewport's width removes that axis.
            .containerRelativeFrame(.horizontal)
        }
        .background { LiquidBackdrop() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            startButton(film)
        }
        .task(id: filmKey) {
            await loadChart(film)
        }
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineText(text: "Library", color: Theme.amber)
            Text("This film is no longer in the library.")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Button("Go back") { dismiss() }
                .buttonStyle(AmberCapsuleStyle(height: 48))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { LiquidBackdrop() }
    }

    // MARK: Top bar and header

    private func topBar(_ film: LibraryFilm) -> some View {
        HStack {
            CircleIconButton(systemImage: "chevron.left", size: 42) {
                dismiss()
            }
            .accessibilityLabel("Back")

            Spacer(minLength: 8)

            CircleIconButton(
                systemImage: store.isFavourite(film.key) ? "star.fill" : "star",
                size: 42
            ) {
                store.toggleFavourite(film.key)
            }
            .accessibilityLabel(
                store.isFavourite(film.key) ? "Remove from favourites" : "Keep in favourites"
            )
        }
    }

    private func header(_ film: LibraryFilm) -> some View {
        VStack(spacing: 6) {
            Text("\(film.manufacturer) · \(film.process.label)".uppercased())
                .font(.system(size: 12, weight: .medium))
                .tracking(3)
                .foregroundStyle(Theme.inkSoft)

            Text(film.displayName)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let generationLabel = film.generationLabel {
                Text(generationLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chips(_ film: LibraryFilm) -> some View {
        LibraryFlowLayout(spacing: 6, lineSpacing: 6) {
            LibraryChip(text: "ISO \(film.iso)")
            ForEach(film.formats) { format in
                LibraryChip(text: format.label)
            }
            LibraryChip(text: film.status.label, emphasised: film.status == .current)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Origin and background

    /// A respool or a rebrand is only interesting when it says what it actually
    /// is, so the stock it came from comes before anything else on the page.
    @ViewBuilder
    private func originCard(_ film: LibraryFilm) -> some View {
        if let origin = film.origin {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(origin.kind.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.amberInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(Theme.amber) }

                    if let remjet = origin.remjetRemoved {
                        Text(remjet ? "REM-JET REMOVED" : "REM-JET INTACT")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.9)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background { Capsule().fill(Theme.surfaceRaised) }
                    }

                    Spacer(minLength: 4)
                }

                if let stock = origin.stock {
                    Text(stock)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(origin.kind.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)

                if let note = origin.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 20)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func historyCard(_ film: LibraryFilm) -> some View {
        if let history = film.history, !history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                OverlineText(text: "Background", color: Theme.amber)

                Text(history)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 20)
        }
    }

    // MARK: Facts

    private func factTiles(_ film: LibraryFilm) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                LibraryFactTile(symbol: "circle.lefthalf.filled", label: "Latitude", fact: film.latitude)
                LibraryFactTile(symbol: "circle.grid.3x3.fill", label: "Grain", fact: film.grain)
                LibraryFactTile(symbol: "circle.dotted", label: "Contrast", fact: film.contrast)
                LibraryFactTile(symbol: "minus", label: "Reciprocity", fact: film.reciprocity)
            }

            if let structure = film.grainStructure {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("GRAIN STRUCTURE")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(Theme.inkFaint)

                        Text(structure.value)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 6)

                    LibraryBadge(kind: structure.provenance.kind)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(radius: 18)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Characteristics

    @ViewBuilder
    private func characteristicsSection(_ film: LibraryFilm) -> some View {
        let items = film.characteristics ?? []
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                LibrarySectionTitle(text: "Characteristics")

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 10) {
                            Text(item.label)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkFaint)
                                .frame(width: 96, alignment: .leading)

                            Text(item.value)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.ink.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 4)

                            LibraryBadge(kind: item.provenance.kind)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)

                        if index < items.count - 1 {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .glassCard(radius: 22)
            }
        }
    }

    // MARK: Times

    private struct TimeRow: Identifiable {
        let entry: LibraryTimeEntry
        let developerName: String
        let dilutionLabel: String

        var id: String { entry.id }

        var timeText: String {
            guard let seconds = entry.seconds else { return "—" }
            return Clock.mmss(TimeInterval(seconds))
        }
    }

    private struct TemperatureGroup {
        let temperature: Double
        let rows: [TimeRow]
    }

    private func temperatureGroups(_ film: LibraryFilm) -> [TemperatureGroup] {
        let entries = store.times(forFilm: film.key)
        let primary = store.primaryTemperature(forFilm: film.key)
        let grouped = Dictionary(grouping: entries, by: \.celsius)

        return grouped
            .sorted { left, right in
                if left.key == primary { return true }
                if right.key == primary { return false }
                return left.key < right.key
            }
            .map { celsius, entries in
                let rows = entries
                    .map { entry in
                        TimeRow(
                            entry: entry,
                            developerName: store.developer(key: entry.developer)?.name ?? entry.developer,
                            dilutionLabel: store.dilutionLabel(
                                developerKey: entry.developer,
                                dilution: entry.dilution
                            )
                        )
                    }
                    .sorted { $0.developerName.localizedCaseInsensitiveCompare($1.developerName) == .orderedAscending }
                return TemperatureGroup(temperature: celsius, rows: rows)
            }
    }

    private func timesSection(_ film: LibraryFilm, group: TemperatureGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LibrarySectionTitle(text: "Development times · \(store.temperatureLabel(group.temperature))")

            VStack(spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    NavigationLink {
                        DeveloperDetailView(developerKey: row.entry.developer)
                    } label: {
                        timeRow(row)
                    }
                    .buttonStyle(HapticButtonStyle())

                    if index < group.rows.count - 1 {
                        Rectangle()
                            .fill(Theme.hairline)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .glassCard(radius: 22)
        }
    }

    private func timeRow(_ row: TimeRow) -> some View {
        HStack(spacing: 10) {
            Text(row.developerName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 88, alignment: .leading)

            Text(row.dilutionLabel)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 58, alignment: .leading)

            Spacer(minLength: 4)

            Text(row.timeText)
                .font(.figures(17, weight: .semibold))
                .foregroundStyle(row.entry.seconds == nil ? Theme.inkFaint : Theme.amber)

            LibraryBadge(kind: row.entry.provenance.kind)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Cross-processing

    /// Every film carries this section, whether or not a combination is known
    /// for it. An unsafe combination is called out here, before the sheet opens.
    private func crossProcessSection(_ film: LibraryFilm) -> some View {
        let entries = LibraryCrossProcess.sorted(store.crossProcess(forFilm: film.key))
        let classes = CrossProcessClass.allCases.filter { item in
            entries.contains { $0.classification == item }
        }
        let unsafe = entries.contains { $0.isUnsafe }

        return VStack(alignment: .leading, spacing: 10) {
            LibrarySectionTitle(text: "Cross-processing")

            if entries.isEmpty {
                Text("No cross-process is documented for this film yet. Combinations are added through the library import as documentation appears.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(radius: 20)
            } else {
                Button {
                    showingCrossProcess = true
                } label: {
                    HStack(spacing: 8) {
                        Text("\(entries.count) documented option\(entries.count == 1 ? "" : "s")")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 6)

                        ForEach(classes.prefix(3)) { item in
                            classificationPill(item)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(radius: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HapticButtonStyle())

                if unsafe {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.top, 1)

                        Text("One combination is chemically incompatible and unsafe. It is listed as a warning, never as a recipe.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Warning. One cross-processing combination is chemically incompatible and unsafe.")
                }
            }
        }
    }

    private func classificationPill(_ item: CrossProcessClass) -> some View {
        HStack(spacing: 4) {
            if item == .incompatible {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(colour(for: item))
            } else {
                Circle()
                    .fill(colour(for: item))
                    .frame(width: 6, height: 6)
            }
            Text(item == .incompatible ? "Unsafe" : item.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background { Capsule().fill(Theme.surfaceRaised) }
    }

    private func colour(for item: CrossProcessClass) -> Color {
        switch item {
        case .documentedAndTested: return .green
        case .communityTested: return .blue
        case .experimental: return Theme.amber
        case .notRecommended, .incompatible: return .red
        }
    }

    // MARK: Live chart

    @ViewBuilder
    private func chartSection(_ film: LibraryFilm) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LibrarySectionTitle(text: "Live chart · 35mm.org")

            switch chartState {
            case .idle, .loading:
                chartLoadingCard
            case .empty:
                chartMessageCard("35mm.org has no published times for this film yet.")
            case .failed(let message):
                chartFailureCard(message, film: film)
            case .loaded(let result):
                if result.times.isEmpty {
                    chartMessageCard("35mm.org has no published times for this film yet.")
                } else {
                    chartListCard(result)
                }
            }
        }
    }

    private var chartLoadingCard: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Theme.amber)
            Text("Reading the chart…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    private func chartMessageCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 20)
    }

    private func chartFailureCard(_ message: String, film: LibraryFilm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try again") {
                Task { await loadChart(film) }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.amber)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20)
    }

    private func chartListCard(_ result: ChartFilmTimes) -> some View {
        let sorted = sortedChartTimes(result.times)
        let shown = showingAllChartTimes ? sorted : Array(sorted.prefix(8))
        let hiddenCount = sorted.count - shown.count

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, time in
                chartRow(time)

                if index < shown.count - 1 {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                }
            }

            if hiddenCount > 0 {
                Button {
                    showingAllChartTimes = true
                } label: {
                    Text("Show \(hiddenCount) more")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HapticButtonStyle())
            }

            chartAttribution(result)
        }
        .padding(.horizontal, 16)
        .glassCard(radius: 22)
    }

    private func chartRow(_ time: ChartTime) -> some View {
        Button {
            if let url = time.url.flatMap(URL.init(string:)) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(time.developer.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(time.dilution.label)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(time.time)
                        .font(.figures(16, weight: .semibold))
                        .foregroundStyle(Theme.amber)

                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }

                HStack(spacing: 8) {
                    Text(chartSubtitle(time))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    chartBadge(time)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticButtonStyle())
    }

    private func chartSubtitle(_ time: ChartTime) -> String {
        var parts: [String] = []
        if let ei = time.ei { parts.append("EI \(ei)") }
        parts.append(store.temperatureLabel(time.temperatureC))
        if let format = time.format, format != "any" { parts.append(format) }
        return parts.joined(separator: " · ")
    }

    private func chartBadge(_ time: ChartTime) -> some View {
        let kind: LibraryProvenanceKind
        switch time.confidence {
        case "verified": kind = .datasheet
        case "community": kind = .community
        default: kind = .unverified
        }
        return LibraryBadge(kind: kind, text: time.confidenceLabel)
    }

    private func chartAttribution(_ result: ChartFilmTimes) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.attribution)

            if let url = result.filmURL {
                Button("Open this film on 35mm.org") {
                    openURL(url)
                }
                .foregroundStyle(Theme.amber)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Theme.inkFaint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
    }

    private func sortedChartTimes(_ times: [ChartTime]) -> [ChartTime] {
        times.sorted { left, right in
            if left.developer.name != right.developer.name {
                return left.developer.name.localizedCaseInsensitiveCompare(right.developer.name) == .orderedAscending
            }
            if left.dilution.label != right.dilution.label {
                return left.dilution.label < right.dilution.label
            }
            if (left.ei ?? 0) != (right.ei ?? 0) {
                return (left.ei ?? 0) < (right.ei ?? 0)
            }
            return left.temperatureC < right.temperatureC
        }
    }

    @MainActor
    private func loadChart(_ film: LibraryFilm) async {
        if case .loaded(_) = chartState { return }
        if case .loading = chartState { return }

        chartState = .loading
        do {
            let result = try await DevelopmentChartClient.shared.times(
                manufacturer: film.manufacturer,
                name: film.name,
                iso: film.iso
            )
            chartState = result.times.isEmpty ? .empty : .loaded(result)
        } catch {
            chartState = .failed(error.localizedDescription)
        }
    }

    // MARK: Sources

    @ViewBuilder
    private func sourcesSection(_ film: LibraryFilm) -> some View {
        let sources = store.sources(forFilm: film.key)
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                LibrarySectionTitle(text: "Sources")

                VStack(spacing: 0) {
                    ForEach(Array(sources.enumerated()), id: \.element.key) { index, source in
                        Button {
                            open(source)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundStyle(Theme.inkSoft)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.title)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading)
                                    if !source.retrieved.isEmpty {
                                        Text("Retrieved \(source.retrieved)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.inkFaint)
                                    }
                                }

                                Spacer(minLength: 6)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.inkFaint)
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HapticButtonStyle())

                        if index < sources.count - 1 {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .glassCard(radius: 22)
            }
        }
    }

    private func open(_ source: LibrarySource) {
        guard let url = URL(string: source.url), !source.url.isEmpty else { return }
        openURL(url)
    }

    // MARK: Action

    private func startButton(_ film: LibraryFilm) -> some View {
        Button {
            presentSession(film)
        } label: {
            Label("Start session with this film", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AmberCapsuleStyle(height: 54))
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func presentSession(_ film: LibraryFilm) {
        guard let legacyFilm = store.legacyFilm(key: film.key) else { return }

        var developer: Developer?
        var dilution: Dilution?
        if let record = store.times(forFilm: film.key).first(where: { $0.seconds != nil }),
           let match = store.legacyDevelopers.first(where: { $0.id == record.developer }) {
            developer = match
            dilution = match.dilution(id: record.dilution) ?? match.dilutions.first
        }

        sessionSelection = SessionSelection(film: legacyFilm, developer: developer, dilution: dilution)
    }
}

/// Carries a film into the session setup sheet.
struct SessionSelection: Identifiable {
    let id = UUID()
    let film: Film
    let developer: Developer?
    let dilution: Dilution?
}

/// What the live chart is doing for this film.
private enum ChartSectionState {
    case idle
    case loading
    case loaded(ChartFilmTimes)
    case empty
    case failed(String)
}

// MARK: - Cross-process sheet

private struct CrossProcessSheet: View {
    let filmKey: String

    @ObservedObject private var store = LibraryStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Each classification is decided by who tested it, not by how it looks. A chemically incompatible combination is shown as a warning, never as a recipe.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(LibraryCrossProcess.sorted(store.crossProcess(forFilm: filmKey))) { entry in
                        CrossProcessProfileCard(entry: entry)
                    }
                }
                .padding(20)
            }
            .background { LiquidBackdrop() }
            .navigationTitle("Cross-processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CrossProcessProfileCard: View {
    let entry: LibraryCrossProcess

    @Environment(\.openURL) private var openURL

    var body: some View {
        let fields = entry.profileFields

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(entry.fromProcess.label) → \(entry.toProcess.label)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Text(entry.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                LibraryBadge(kind: entry.provenance.kind)
            }

            if entry.isUnsafe {
                unsafeBanner
            } else {
                Text(entry.classification.safetyTitle.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(colour(for: entry.classification))
            }

            if !fields.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                        fieldRow(field)
                        if index < fields.count - 1 {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 1)
                        }
                    }
                }
            }

            if let examples = entry.examples, !examples.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SEEN IN")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.inkFaint)

                    ForEach(examples, id: \.self) { example in
                        Text("· \(example)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let references = entry.references, !references.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("REFERENCES")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.inkFaint)

                    ForEach(references, id: \.self) { reference in
                        Button {
                            open(reference)
                        } label: {
                            HStack(spacing: 5) {
                                Text(reference)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.inkSoft)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                if reference.contains("http") {
                                    Image(systemName: "arrow.up.forward")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Theme.inkFaint)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HapticButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 20, tint: entry.isUnsafe ? .red : nil)
    }

    private var unsafeBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 3) {
                Text("UNSAFE — CHEMICALLY INCOMPATIBLE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.ink)

                Text("Do not attempt this combination. The notes below say what goes wrong, not how to do it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.red.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unsafe. Chemically incompatible. Do not attempt this combination.")
    }

    private func fieldRow(_ field: (label: String, value: String, isWarning: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(field.label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(field.isWarning ? .red : Theme.inkFaint)

            HStack(alignment: .top, spacing: 5) {
                if field.isWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.top, 1)
                }

                Text(field.value)
                    .font(.system(size: 13))
                    .foregroundStyle(field.isWarning ? Theme.ink : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func colour(for item: CrossProcessClass) -> Color {
        switch item {
        case .documentedAndTested: return .green
        case .communityTested: return .blue
        case .experimental: return Theme.amber
        case .notRecommended, .incompatible: return .red
        }
    }

    private func open(_ reference: String) {
        guard let range = reference.range(of: "http") else { return }
        let text = String(reference[range.lowerBound...])
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        openURL(url)
    }
}
