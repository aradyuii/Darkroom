//
//  LiquidBackdrop.swift
//  Darkroom
//
//  The default bench-light backdrop, with the soft-glass field while that
//  language is active.
//

import SwiftUI

struct LiquidBackdrop: View {
    var tint: Color = Theme.amber
    var intensity: Double = 1.0
    @ObservedObject private var appearance = AppearanceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The backdrop drifts continuously, so it is the one thing in the app that
    /// would keep redrawing while the screen is covered or in the background.
    /// Tracked here so the liquid can stop when nobody is looking at it.
    @State private var isVisible = true

    /// Reduce Motion asks for no movement at all; a covered screen and a
    /// backgrounded app have nothing to animate. In every one of those cases the
    /// liquid is drawn once and held, which looks the same and costs nothing.
    /// The liquid moves a couple of points a second under a 24-44 pt blur, so a
    /// few frames a second look the same as 24. It matters beyond the backdrop:
    /// every frosted card above it re-blurs whatever is behind it each time this
    /// layer changes, so each redraw saved here is saved once per visible card.
    private static let driftInterval: TimeInterval = 1.0 / 6.0

    private var isDrifting: Bool {
        isVisible && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        // A flexible filler reports the size it is offered; the blooms and the
        // bleeding liquid layers are drawn in an overlay, which never takes part
        // in layout. Hosted as ordinary children they reported their own canvas
        // — roughly 940 × 1330 pt — and every screen that hosts the backdrop as
        // a child laid its content out on it and was cut off on all four edges.
        Color.clear
            .overlay {
                Group {
                    if appearance.isSoftGlassActive {
                        SoftGlassTheme.backdrop(intensity: intensity)
                    } else {
                        darkroomBackdrop
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }

    private var darkroomBackdrop: some View {
        ZStack {
            DarkroomThemeDefaults.base

            // Two lights in the room, not one: the chosen lamp and its
            // companion, wide enough and soft enough to read as light falling
            // across the bench rather than as a shape on the screen.
            let lamp = Preferences.shared.accent
            bloom(color: tint, opacity: 0.46 * intensity, size: 620, blur: 66)
                .offset(x: 140, y: -300)
            bloom(color: lamp.bloom, opacity: 0.32 * intensity, size: 560, blur: 74)
                .offset(x: -160, y: 30)
            bloom(color: lamp.deep, opacity: 0.24 * intensity, size: 520, blur: 64)
                .offset(x: 70, y: 340)

            liquidLayers(tint: tint)

            LinearGradient(
                colors: [
                    DarkroomThemeDefaults.base.opacity(0.40),
                    Color.clear,
                    DarkroomThemeDefaults.base.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func bloom(color: Color, opacity: Double, size: CGFloat, blur: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(opacity),
                        color.opacity(opacity * 0.32),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .blur(radius: blur)
    }

    private func liquidLayers(tint: Color) -> some View {
        TimelineView(.animation(minimumInterval: Self.driftInterval, paused: !isDrifting)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = Double(size.width)
                let height = Double(size.height)

                for band in 0..<3 {
                    let progress = Double(band)
                    let baseY = height * (0.87 + 0.045 * progress)
                    let amplitude = height * (0.016 + 0.006 * progress)
                    let wavelength = width * (0.92 - 0.16 * progress)
                    let speed = 0.16 + 0.07 * progress

                    var path = Path()
                    var x = 0.0
                    var first = true
                    while x <= width + 8 {
                        let y = baseY + sin((x / wavelength) * Double.pi * 2 + time * speed + progress) * amplitude
                        if first {
                            path.move(to: CGPoint(x: x, y: y))
                            first = false
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        x += 6
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()

                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 24 + 10 * progress))
                        layer.fill(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [
                                    tint.opacity(max(0, 0.16 * intensity - 0.04 * progress)),
                                    tint.opacity(0.03 * intensity)
                                ]),
                                startPoint: CGPoint(x: 0, y: baseY - amplitude),
                                endPoint: CGPoint(x: 0, y: height)
                            )
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
