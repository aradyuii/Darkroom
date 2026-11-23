//
//  Appearance.swift
//  Darkroom
//
//  The app-wide visual state that is not a choice of its own: the one object
//  every screen observes to be redrawn when the theme or the palette changes.
//  The theme lives in ThemeStore, the palette and the other preferences in
//  Preferences; this store listens to both and passes their changes on, so
//  nothing has to be rebuilt to be re-dressed.
//

import Combine
import SwiftUI

final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    private var forwarding: Set<AnyCancellable> = []

    private init() {
        // Every screen reads its colours through `Theme`, which resolves the
        // theme and the palette from these two stores. Forwarding their changes
        // here is what redraws the app when either is written. It replaces the
        // old `revision` counter, which was applied to the tab stack as an
        // `.id`: that re-identified the whole hierarchy on every accent, unit,
        // theme and density write, throwing every tab back to its root screen
        // and cancelling any touch already in flight.
        ThemeStore.shared.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &forwarding)

        Preferences.shared.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &forwarding)
    }

    // MARK: Derived

    /// True while Soft Light, the main theme, owns the interface.
    var isSoftGlassActive: Bool { ThemeStore.shared.isSoftLight }

    /// The compact density shortens the native controls as it tightens the rest.
    var compactControls: Bool { ThemeStore.shared.compactControls }
}
