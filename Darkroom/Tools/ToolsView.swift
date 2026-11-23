//
//  ToolsView.swift
//  Darkroom
//
//  The sink-side utility hub.
//

import SwiftUI

struct ToolsView: View {
    @ObservedObject private var preferences = Preferences.shared

    /// The four lights of the chosen palette. Every tool card takes one, so the
    /// cards follow the palette rather than a fixed set of hues.
    private var lamp: [Color] {
        let chosen = preferences.accent
        return [chosen.base, chosen.bloom, chosen.soft, chosen.deep]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    introduction

                    VStack(spacing: 10) {
                        ToolLaunchCard(
                            title: "Film troubleshooter",
                            subtitle: "What do your negatives show?",
                            systemImage: "exclamationmark.triangle",
                            accent: lamp[0],
                            destination: FilmTroubleshooterView()
                        )
                        ToolLaunchCard(
                            title: "Expired film EI",
                            subtitle: "Rate an out-of-date roll by its storage",
                            systemImage: "calendar.badge.clock",
                            accent: lamp[1],
                            destination: ExpiryCalculatorView()
                        )
                        ToolLaunchCard(
                            title: "Times & temperature",
                            subtitle: "Move a development time to another temperature",
                            systemImage: "hourglass",
                            accent: lamp[2],
                            destination: TimeTemperatureCalculatorView()
                        )
                        ToolLaunchCard(
                            title: "Temperature",
                            subtitle: "Convert °C and °F",
                            systemImage: "thermometer.medium",
                            accent: lamp[3],
                            destination: TemperatureConverterView()
                        )
                        ToolLaunchCard(
                            title: "Stopwatch",
                            subtitle: "Elapsed time with lap splits",
                            systemImage: "stopwatch",
                            accent: lamp[0],
                            destination: StopwatchToolView()
                        )
                        ToolLaunchCard(
                            title: "Interval timer",
                            subtitle: "Set work, rest, and rounds",
                            systemImage: "repeat",
                            accent: lamp[1],
                            destination: IntervalTimerView()
                        )
                        ToolLaunchCard(
                            title: "Wash & final rinse",
                            subtitle: "Fill-and-dump guide and timers",
                            systemImage: "drop",
                            accent: lamp[2],
                            destination: WashRinseTimerView()
                        )
                        ToolLaunchCard(
                            title: "Tank visualizer",
                            subtitle: "See how far a pour reaches",
                            systemImage: "cylinder.fill",
                            accent: lamp[3],
                            destination: TankVisualizerView()
                        )
                        ToolLaunchCard(
                            title: "Development simulator",
                            subtitle: "See a choice before the chemistry is mixed",
                            systemImage: "slider.horizontal.3",
                            accent: lamp[0],
                            destination: DevelopmentSimulatorView()
                        )
                    }

                    OverlineText(text: "Reference", color: Theme.amber)
                        .padding(.top, 2)

                    VStack(spacing: 10) {
                        ToolLaunchCard(
                            title: "Film leader retrieval",
                            subtitle: "A documented 35 mm retriever method",
                            systemImage: "film",
                            accent: lamp[0],
                            destination: FilmLeaderGuideView()
                        )
                        ToolLaunchCard(
                            title: "Tank capacities",
                            subtitle: "Film load and reference volumes",
                            systemImage: "cylinder.split.1x2",
                            accent: lamp[1],
                            destination: TankCapacityReferenceView()
                        )
                        ToolLaunchCard(
                            title: "Chemical safety",
                            subtitle: "Handling, ventilation, and disposal",
                            systemImage: "hand.raised",
                            accent: lamp[2],
                            destination: ChemicalSafetyView()
                        )
                    }

                    ToolLaunchCard(
                        title: "Settings",
                        subtitle: "Theme, palette and appearance",
                        systemImage: "slider.horizontal.3",
                        accent: lamp[3],
                        destination: SettingsView()
                    )
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background {
                LiquidBackdrop()
            }
            .appNavigationChrome(title: "Tools")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            OverlineText(text: "At the sink", color: Theme.amber)
            Text("Small tools.\nSteady hands.")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Quick conversions, dependable timing, and references for the work in front of you.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct ToolLaunchCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            ToolCardBody(title: title, subtitle: subtitle, systemImage: systemImage, accent: accent)
        }
        .buttonStyle(HapticButtonStyle())
    }
}

private struct ToolCardBody: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        if appearance.isSoftGlassActive {
            softBody
        } else {
            glassBody
        }
    }

    // The reference's tile: one of its card ramps, lit from a corner, the
    // tool's name and its promise set in white on the gradient.
    private var softBody: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 46, height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.80))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(SoftGlassTheme.ramp(for: accent))

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.24), Color.clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 220
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
        .contentShape(Rectangle())
    }

    private var glassBody: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(accent.opacity(0.13))
                    .frame(width: 48, height: 48)
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                    .frame(width: 48, height: 48)
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 21, tint: accent)
        .contentShape(Rectangle())
    }
}
