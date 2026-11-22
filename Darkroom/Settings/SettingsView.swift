//
//  SettingsView.swift
//  Darkroom
//
//  The Settings sheet: one Appearance entry, where the theme, the palette and the
//  density are chosen, and the screens behind units, development defaults and
//  alerts.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var preferences = Preferences.shared
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    designSection
                    preferencesSection
                    notesSection
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .background { LiquidBackdrop() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.amber)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverlineText(text: "Bench preferences", color: Theme.amber)
            Text("Settings")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("How the bench reads, moves and remembers.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: Appearance

    /// One entry for the whole look: the theme, the palette both themes are lit
    /// with and the interface density.
    private var designSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(index: "01", title: "Appearance")

            NavigationLink {
                AppearanceView()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: theme.selected.glyph)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.amber)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Theme and palette")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(theme.selected.name) · \(preferences.accent.title) palette")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .glassCard(radius: 20)
            }
            .buttonStyle(HapticButtonStyle())
            .accessibilityLabel("Theme and palette")
            .accessibilityHint("Opens the appearance section")
        }
    }

    // MARK: Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(index: "02", title: "Preferences")

            SettingsHubRow(
                index: "03",
                title: "Units",
                detail: "\(preferences.temperatureScale.title) · \(preferences.volumeUnit.title)",
                systemImage: "ruler"
            ) {
                UnitsSettingsView()
            }

            SettingsHubRow(
                index: "04",
                title: "Development defaults",
                detail: developmentDetail,
                systemImage: "slider.horizontal.below.rectangle"
            ) {
                DevelopmentDefaultsView()
            }

            SettingsHubRow(
                index: "05",
                title: "Alerts",
                detail: "Sound and haptic for each prompt",
                systemImage: "bell.badge"
            ) {
                AlertSettingsView()
            }

            resetRow
        }
    }

    private var developmentDetail: String {
        let step = Int((preferences.reuseStep * 100).rounded())
        return "\(preferences.agitationScheme.title) · \(step)% reuse · \(Clock.mmss(preferences.washSeconds)) wash"
    }

    private var resetRow: some View {
        Button {
            confirmingReset = true
        } label: {
            HStack(spacing: 14) {
                Text("06")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.amber)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Reset preferences")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Every stored preference returns to its default.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.8))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard(radius: 20)
        }
        .buttonStyle(HapticButtonStyle())
        .accessibilityLabel("Reset preferences")
        .accessibilityHint("Every stored preference returns to its default")
        .confirmationDialog(
            "Reset every preference?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                resetPreferences()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Units, development defaults, alerts, the theme, the palette and the density return to their defaults.")
        }
    }

    private func resetPreferences() {
        preferences.resetAll()
        // The theme and density live in their own store, so the promise on the
        // reset row is only kept if that store is reset too.
        ThemeStore.shared.reset()
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(index: "07", title: "Notes")
            Text("Every choice here is remembered on this device and used by the next session, calculation and prompt.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    SettingsView()
}
