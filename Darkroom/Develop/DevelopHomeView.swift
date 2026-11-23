//
//  DevelopHomeView.swift
//  Darkroom
//
//  The Develop tab: the entry to a new session and a short guide to the stages.
//

import SwiftUI

struct DevelopHomeView: View {
    @ObservedObject private var appearance = AppearanceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sections settle in once the first frame is laid out, so a tab switch or a
    /// launch arrives rather than snaps.
    @State private var revealed = false

    private let steps: [(title: String, detail: String)] = [
        ("Pre-soak", "Optional soak in water before the developer."),
        ("Developer", "Timed, with agitation prompts and a tap for bubbles."),
        ("Stop", "20 to 40 seconds with constant agitation."),
        ("Fix", "Set by your film leader's clearing time, times three."),
        ("Wash", "Running water, or fill and dump."),
        ("Final rinse", "A wetting agent, without a rinse.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if appearance.isSoftGlassActive {
                        softContent
                    } else {
                        hero
                        flow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background {
                LiquidBackdrop()
            }
            .appNavigationChrome(title: "Develop")
        }
    }

    // MARK: Soft glass

    private var softContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            softHeading
                .softReveal(revealed, delay: 0, reduceMotion: reduceMotion)
            SoftGlassDayStrip()
                .softReveal(revealed, delay: 0.04, reduceMotion: reduceMotion)
            softHero
                .softReveal(revealed, delay: 0.08, reduceMotion: reduceMotion)
            softWideCard
                .softReveal(revealed, delay: 0.12, reduceMotion: reduceMotion)
            softStatGrid
                .softReveal(revealed, delay: 0.16, reduceMotion: reduceMotion)
            softPlan
                .softReveal(revealed, delay: 0.20, reduceMotion: reduceMotion)
        }
        .task {
            guard !revealed else { return }
            try? await Task.sleep(for: .milliseconds(40))
            revealed = true
        }
    }

    private var softHeading: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SoftGlassCaption(text: "At the sink", color: SoftGlassTheme.accent)
                Text("Ready when\nthe tank is.")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(SoftGlassTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            NavigationLink {
                SettingsView()
            } label: {
                SoftGlassIconDisc(systemImage: "slider.horizontal.3")
            }
            .buttonStyle(HapticButtonStyle())
            .accessibilityLabel("Settings")
        }
    }

    // The reference's hero figure sits straight on the black field: the metric
    // name, the number in dots, its unit, and the wave with its marker.
    private var softHero: some View {
        let featured = featuredTime

        return VStack(spacing: 4) {
            Text(featured?.pair ?? "Development")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(SoftGlassTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            DotMatrixDigits(text: featured?.figure ?? "--:--", dot: 7, spacing: 3)
                .padding(.vertical, 10)

            Text("min")
                .font(.system(size: 16))
                .foregroundStyle(SoftGlassTheme.inkSoft)

            SoftGlassWaveLine()
                .padding(.top, 14)

            Text(featured?.note ?? "Add a film and a developer to the library and its published time appears here.")
                .font(.system(size: 13))
                .foregroundStyle(SoftGlassTheme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            NavigationLink {
                SessionSetupView()
            } label: {
                SoftGlassActionLabel(title: "Start a session")
            }
            .buttonStyle(AmberCapsuleStyle(height: 58))
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
    }

    // The wide salmon card: the featured time at its foot, the dotted ring
    // gauge riding at its top-right.
    private var softWideCard: some View {
        let featured = featuredTime

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Featured time")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.88))

                Spacer(minLength: 10)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(featured?.figure ?? "--:--")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(featured?.temperature ?? "—")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)

            SoftGlassRingGauge(
                fraction: ringFraction(featured),
                text: featured.map { String(Int((Double($0.seconds) / 60).rounded())) } ?? "--"
            )
            .padding(14)
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(SoftGlassTheme.ramp(for: Preferences.shared.accent.base))
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.26), Color.clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 240
                        )
                    )
                    .blendMode(.softLight)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.24)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }

    // The two-by-two grid, each tile wearing one of the reference's card
    // decorations: a range bar, a dot row, a tick strip, a blurred pool.
    private var softStatGrid: some View {
        let films = LibraryStore.shared.films.count
        let bottles = ChemistryStore.shared.batches.count
        let featured = featuredTime

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            SoftStatCard(
                label: "Films",
                value: "\(films)",
                unit: "in library",
                gradient: SoftGlassTheme.ramp(for: Preferences.shared.accent.soft)
            ) {
                SoftGlassRangeBar(fraction: 0.80)
            }

            SoftStatCard(
                label: "Chemicals",
                value: "\(bottles)",
                unit: bottles == 1 ? "bottle" : "bottles",
                gradient: SoftGlassTheme.ramp(for: Preferences.shared.accent.bloom)
            ) {
                SoftGlassDotRow()
            }

            SoftStatCard(
                label: "Published at",
                value: featured?.temperature ?? "—",
                unit: "",
                gradient: SoftGlassTheme.ramp(for: Preferences.shared.accent.base)
            ) {
                SoftGlassTickStrip()
            }

            SoftStatCard(
                label: "Stages",
                value: "\(steps.count)",
                unit: "in a session",
                gradient: SoftGlassTheme.ramp(for: Preferences.shared.accent.deep)
            ) {
                HStack {
                    Spacer()
                    SoftGlassBlob().offset(x: 12, y: 8)
                }
            }
        }
    }

    private func ringFraction(_ featured: FeaturedTime?) -> Double {
        guard let featured else { return 0 }
        return min(max(featured.seconds / (40 * 60), 0.05), 1)
    }

    private var softPlan: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SoftGlassCaption(text: "How a session runs")
                Spacer(minLength: 0)
                Text("\(steps.count) stages")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SoftGlassTheme.inkFaint)
            }

            VStack(spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    SoftGlassRow(title: step.title, detail: step.detail, index: index + 1)

                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(SoftGlassTheme.hairline)
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: SoftGlassTheme.cardRadius)
    }

    // MARK: Feature

    private struct FeaturedTime {
        let figure: String
        let pair: String
        let temperature: String
        let note: String
        let seconds: TimeInterval
    }

    /// The first film in the library that has a sourced development time, set as
    /// the screen's figure. Nothing is invented: with no documented time the hero
    /// says so rather than showing a plausible number.
    private var featuredTime: FeaturedTime? {
        let library = LibraryStore.shared

        for film in StarterLibrary.films {
            let entries = library.times(forFilm: film.id).filter { $0.seconds != nil }
            guard let entry = entries.first(where: { abs($0.celsius - 20) < 0.05 }) ?? entries.first,
                  let seconds = entry.seconds else { continue }

            let developerName = library.developer(key: entry.developer)?.name ?? entry.developer
            let dilution = library.dilutionLabel(developerKey: entry.developer, dilution: entry.dilution)
            let minutes = seconds / 60
            let remainder = seconds % 60
            let temperature = library.temperatureLabel(entry.celsius)

            let source = library.source(key: entry.provenance.source)?.publisher
            let note = source.map { "Published time at \(temperature), sourced from \($0)." }
                ?? "Published time at \(temperature)."

            return FeaturedTime(
                figure: String(format: "%02d:%02d", minutes, remainder),
                pair: "\(film.displayName) · \(developerName) \(dilution)",
                temperature: temperature,
                note: note,
                seconds: TimeInterval(seconds)
            )
        }

        return nil
    }

    // MARK: Darkroom

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "timer")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.amber)
                .frame(width: 68, height: 68)
                .glassCard(radius: 34)

            VStack(alignment: .leading, spacing: 8) {
                OverlineText(text: "Ready when the tank is", color: Theme.amber)
                Text("Develop a roll")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Timed stages, agitation prompts, a tap-anywhere start and a sound at every step.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NavigationLink {
                SessionSetupView()
            } label: {
                Label("New session", systemImage: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.amberInk)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.amber)
            .controlSize(.large)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 30)
    }

    private var flow: some View {
        VStack(alignment: .leading, spacing: 14) {
            OverlineText(text: "How a session runs")

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.amberInk)
                        .frame(width: 26, height: 26)
                        .background {
                            Circle().fill(Theme.amber)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(step.detail)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 30)
    }
}


// MARK: - Reveal

/// A short spring settle for a section: a little rise and scale, staggered by a
/// few tens of milliseconds per section. Collapses to a quick fade when the
/// reader has asked for reduced motion.
private struct SoftReveal: ViewModifier {
    let revealed: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(revealed || reduceMotion ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 16)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.97, anchor: .top)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.20)
                    : .spring(response: 0.62, dampingFraction: 0.86).delay(delay),
                value: revealed
            )
    }
}

extension View {
    fileprivate func softReveal(_ revealed: Bool, delay: Double, reduceMotion: Bool) -> some View {
        modifier(SoftReveal(revealed: revealed, delay: delay, reduceMotion: reduceMotion))
    }
}



// MARK: - Stat card

/// One of the reference's dashboard tiles: a sentence-case label, a decoration
/// in the middle, and the big figure with its unit at the foot.
private struct SoftStatCard<Decoration: View>: View {
    let label: String
    let value: String
    var unit: String? = nil
    let gradient: LinearGradient
    var minHeight: CGFloat = 150
    @ViewBuilder let decoration: () -> Decoration

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.88))

            decoration()
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(gradient)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.26), Color.clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 210
                        )
                    )
                    .blendMode(.softLight)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.28)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }
}
