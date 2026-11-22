//
//  Appearance.swift
//  Darkroom
//
//  The app-wide visual state that is not a choice of its own: whether the tab
//  stack must be rebuilt, and whether Settings is on screen. The theme lives in
//  ThemeStore, the palette and the other preferences in Preferences; this store
//  reads them and tells the root when they change.
//

import SwiftUI

/// Publishes the revision the app root re-dresses itself on. Writes that the
/// native tab stack reads bump it, so the stack is rebuilt with the new look.
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    @Published private(set) var revision: Int = 0

    /// Set by the Tools hub and the Develop header; the app root presents
    /// Settings as a sheet so the tabs behind it can be rebuilt without tearing
    /// down the screen.
    @Published var isShowingSettings = false {
        didSet {
            guard oldValue != isShowingSettings else { return }
            if !isShowingSettings {
                if skipNextRevision {
                    skipNextRevision = false
                } else {
                    bumpRevision()
                }
            }
        }
    }

    /// Set while a stale presentation flag is being cleared, so the reset is not
    /// mistaken for the reader closing Settings.
    private var skipNextRevision = false

    /// The one way to open Settings. A reader can only tap an entry while no
    /// sheet covers the screen, so if the flag still says Settings is showing it
    /// is stale; clear it, then raise it again on the next turn so the sheet is
    /// presented rather than the tap doing nothing.
    func presentSettings() {
        guard isShowingSettings else {
            isShowingSettings = true
            return
        }
        skipNextRevision = true
        isShowingSettings = false
        DispatchQueue.main.async { [weak self] in
            self?.isShowingSettings = true
        }
    }

    private init() {}

    // MARK: Derived

    /// True while Soft Light, the main theme, owns the interface.
    var isSoftGlassActive: Bool { ThemeStore.shared.isSoftLight }

    /// The compact density shortens the native controls as it tightens the rest.
    var compactControls: Bool { ThemeStore.shared.compactControls }

    /// Re-dresses the app root. Called by every write the native screens read.
    func bumpRevision() {
        revision &+= 1
    }
}
