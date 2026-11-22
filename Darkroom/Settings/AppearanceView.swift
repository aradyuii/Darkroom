//
//  AppearanceView.swift
//  Darkroom
//
//  The Appearance section: the theme, the palette both themes are lit with, the
//  interface density, and a reset. Nothing here changes what the app does.
//

import SwiftUI

struct AppearanceView: View {
    @ObservedObject private var store = ThemeStore.shared
    @ObservedObject private var preferences = Preferences.shared

    var body: some View {
        SettingsScreen(
            index: "01",
            title: "Appearance",
            blurb: "Soft Light is the main theme and Darkroom the alternative. Both are lit by the palette you choose here."
        ) {
            themeSection
            paletteSection
            densitySection
            resetSection

            SettingsNote(text: "The theme, palette and density are remembered on this device and used by the next launch, every session and every calculation. A theme never changes what the app does, only how it is presented.")
        }
    }

    // MARK: Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(index: "01", title: "Theme")

            ForEach(ThemeChoice.allCases) { choice in
                themeCard(choice)
            }
        }
    }

    private func themeCard(_ choice: ThemeChoice) -> some View {
        let isSelected = store.selected == choice

        return Button {
            store.select(choice)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                specimen(choice)

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Image(systemName: choice.glyph)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? Theme.amber : Theme.inkFaint)

                            Text(choice.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                        }

                        Text(choice.role.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(isSelected ? Theme.amber : Theme.inkSoft)

                        Text(choice.tagline)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.amber)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard(radius: 22)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.amber.opacity(0.55), lineWidth: 1.4)
                }
            }
        }
        .buttonStyle(HapticButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.name), \(choice.role)")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint("Uses \(choice.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A small specimen of the theme: its field, one of its cards, and a control
    /// as it draws one. Decorative — the card's own label carries the meaning.
    private func specimen(_ choice: ThemeChoice) -> some View {
        let accent = preferences.accent
        let isSoft = choice.isSoftLight

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSoft ? SoftGlassTheme.background : DarkroomThemeDefaults.base)

            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSoft
                            ? AnyShapeStyle(SoftGlassTheme.ramp(for: accent.base))
                            : AnyShapeStyle(Color.white.opacity(0.075))
                    )
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 5) {
                            specimenBar(Color.white.opacity(0.92), width: 52)
                            specimenBar(Color.white.opacity(isSoft ? 0.55 : 0.40), width: 34)
                        }
                        .padding(10)
                    }
                    .frame(height: 48)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Capsule()
                        .fill(isSoft ? Color.white : accent.base)
                        .frame(width: 62, height: 20)
                        .overlay {
                            Capsule().strokeBorder(
                                isSoft ? Color.clear : Color.white.opacity(0.30),
                                lineWidth: 1
                            )
                        }

                    Capsule()
                        .fill(Color.white.opacity(isSoft ? 0.10 : 0.06))
                        .frame(width: 38, height: 20)

                    Spacer(minLength: 0)
                }
            }
            .padding(10)
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func specimenBar(_ color: Color, width: CGFloat) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: 5)
    }

    // MARK: Palette

    private var paletteSection: some View {
        SettingsCard {
            SettingsCardHeading(
                title: "Palette",
                detail: "The lamp both themes are lit with. It changes the field, the cards and the accent."
            )

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 10
            ) {
                ForEach(AccentChoice.allCases) { choice in
                    accentChip(choice)
                }
            }
        }
    }

    private func accentChip(_ choice: AccentChoice) -> some View {
        let isSelected = preferences.accent == choice

        return Button {
            preferences.setAccent(choice)
            Haptics.impact(.light)
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [choice.soft, choice.base, choice.deep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle().strokeBorder(
                            isSelected ? Theme.ink : Color.white.opacity(0.16),
                            lineWidth: isSelected ? 2 : 1
                        )
                    }
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(choice.ink)
                        }
                    }

                Text(choice.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticButtonStyle())
        .accessibilityLabel("\(choice.title) palette")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Density

    private var densitySection: some View {
        SettingsCard {
            SettingsCardHeading(
                title: "Interface density",
                detail: "How much room every row, panel and gap takes. Compact also shortens the native controls."
            )

            Picker("Density", selection: Binding(
                get: { store.density },
                set: { store.setDensity($0) }
            )) {
                ForEach(InterfaceDensity.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Reset

    private var resetSection: some View {
        Button {
            store.reset()
            preferences.setAccent(.safelight)
            Haptics.impact(.light)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                Text("Reset appearance")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassCard(radius: 20)
        }
        .buttonStyle(HapticButtonStyle())
        .accessibilityLabel("Reset appearance")
        .accessibilityHint("Returns to Soft Light, the safelight palette and regular density")
    }
}

#Preview {
    NavigationStack {
        AppearanceView()
    }
}
