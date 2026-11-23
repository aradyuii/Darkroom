//
//  SoftGlassComponents.swift
//  Darkroom
//
//  The pieces that give the soft-glass language its character: saturated
//  gradient tiles for figures, the dot-matrix numerals, and the small white
//  capsule actions. Everything else is built from the shared glass panel.
//

import SwiftUI

// MARK: - Gradient tile

/// A saturated panel that carries one figure: a tiny tracked label, a large
/// rounded value and an optional caption, floating on the ambient field.
struct SoftGlassTile: View {
    let label: String
    let value: String
    var caption: String?
    var gradient: LinearGradient
    var tint: Color
    var height: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 6)

            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: SoftGlassTheme.tileRadius, style: .continuous)
                    .fill(gradient)

                // The reference's cards are lit from one corner: a soft, wide
                // glow rather than an even shade across the ramp.
                RoundedRectangle(cornerRadius: SoftGlassTheme.tileRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.30), Color.clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 190
                        )
                    )
                    .blendMode(.softLight)

                RoundedRectangle(cornerRadius: SoftGlassTheme.tileRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .blendMode(.softLight)

                // The figure and its caption sit on the lower half of every
                // card, so the foot is deepened just enough to hold them at
                // contrast on the brightest ramps.
                RoundedRectangle(cornerRadius: SoftGlassTheme.tileRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.30)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: SoftGlassTheme.tileRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.28), radius: 20, x: 0, y: 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dot matrix numerals

/// A number set as a grid of round dots, the way the reference sets its hero
/// figure. Three columns by five rows per glyph, one column for a colon.
struct DotMatrixDigits: View {
    let text: String
    var dot: CGFloat = 6
    var spacing: CGFloat = 3
    var color: Color = .white

    private static let patterns: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"],
        "3": ["111", "001", "111", "001", "111"],
        "4": ["101", "101", "111", "001", "001"],
        "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"],
        "7": ["111", "001", "001", "001", "001"],
        "8": ["111", "101", "111", "101", "111"],
        "9": ["111", "101", "111", "001", "111"],
        ":": ["0", "1", "0", "1", "0"],
        "-": ["000", "000", "111", "000", "000"]
    ]

    var body: some View {
        let characters = Array(text)
        HStack(alignment: .center, spacing: spacing * 2) {
            ForEach(0..<characters.count, id: \.self) { index in
                glyph(characters[index])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func glyph(_ character: Character) -> some View {
        let rows = Self.patterns[character] ?? ["000", "000", "000", "000", "000"]
        return VStack(spacing: spacing) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                let cells = Array(rows[rowIndex])
                HStack(spacing: spacing) {
                    ForEach(0..<cells.count, id: \.self) { columnIndex in
                        Circle()
                            .fill(cells[columnIndex] == "1" ? color : Color.clear)
                            .frame(width: dot, height: dot)
                    }
                }
            }
        }
    }
}

// MARK: - Small circular action

/// The thin outlined circle the reference uses for back, close and secondary
/// actions. Drawn on its own so a navigation link can wear the same disc as a
/// button without either one copying the other's styling.
struct SoftGlassIconDisc: View {
    let systemImage: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.34, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: size, height: size)
            .background {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(Color.white.opacity(0.07))
            }
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
    }
}

struct SoftGlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 40
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SoftGlassIconDisc(systemImage: systemImage, size: size)
        }
        .buttonStyle(HapticButtonStyle())
    }
}

// MARK: - Caption

/// A tiny tracked caption, used above titles and inside cards.
struct SoftGlassCaption: View {
    let text: String
    var color: Color = SoftGlassTheme.inkSoft

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}


// MARK: - Primary capsule label

/// The white capsule action from the reference: the words at the leading edge
/// and a dark circular badge carrying the glyph at the trailing edge. Meant to
/// be used inside `AmberCapsuleStyle`, which supplies the white fill.
struct SoftGlassActionLabel: View {
    let title: String
    var symbol: String = "plus"

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            ZStack {
                Circle().fill(Color.black)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Glass row

/// A quiet row on the panel surface: white figure in a small disc, a title, an
/// optional detail line and an optional trailing value.
struct SoftGlassRow: View {
    let title: String
    var detail: String?
    var index: Int?
    var trailing: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let index {
                Text("\(index)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .frame(width: 26, height: 26)
                    .background { Circle().fill(Color.white) }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SoftGlassTheme.ink)
                if let detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(SoftGlassTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 6)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SoftGlassTheme.inkFaint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Weekday strip

/// The circle row across the top of the reference's dashboard: short weekday
/// letters in thin rings, today's filled white with black ink.
struct SoftGlassDayStrip: View {
    var body: some View {
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date())
        let symbols = calendar.veryShortWeekdaySymbols
        // Monday-first order, as the reference lays its week out.
        let order = [2, 3, 4, 5, 6, 7, 1]

        HStack(spacing: 10) {
            ForEach(order, id: \.self) { weekday in
                let isToday = weekday == today
                Text(symbols[weekday - 1])
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isToday ? Color.black : Color.white.opacity(0.85))
                    .frame(width: 42, height: 42)
                    .background {
                        Circle().fill(isToday ? Color.white : Color.white.opacity(0.03))
                    }
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(isToday ? 0 : 0.20), lineWidth: 1.5)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today is \(symbols[today - 1])")
    }
}

// MARK: - Wave line

/// The wave the reference draws under its hero figure, settling flat to the
/// right where a small triangle marker sits on the baseline. Decorative.
struct SoftGlassWaveLine: View {
    var stroke: Color = Preferences.shared.accent.base
    var markerAt: Double = 0.60

    var body: some View {
        Canvas { context, size in
            let midY = size.height * 0.5
            var wave = Path()
            let steps = 140
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let x = t * size.width
                let amplitude = size.height * 0.36 * (t < markerAt ? 1.0 : max(0, 1.0 - (t - markerAt) * 2.4))
                let y = midY + sin(t * 5.6 * .pi) * amplitude
                if step == 0 {
                    wave.move(to: CGPoint(x: x, y: y))
                } else {
                    wave.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                wave,
                with: .color(stroke.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
            )

            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: midY))
            baseline.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(baseline, with: .color(Color.white.opacity(0.30)), lineWidth: 1)

            let markerX = markerAt * size.width
            var triangle = Path()
            triangle.move(to: CGPoint(x: markerX - 6, y: midY - 11))
            triangle.addLine(to: CGPoint(x: markerX + 6, y: midY - 11))
            triangle.addLine(to: CGPoint(x: markerX, y: midY - 1))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(stroke))
        }
        .frame(height: 46)
        .accessibilityHidden(true)
    }
}

// MARK: - Ring gauge

/// The dotted ring the reference sets into its wide card, the value inside set
/// as dots as well. The arc fills clockwise from the top.
struct SoftGlassRingGauge: View {
    var fraction: Double
    var text: String
    var size: CGFloat = 92
    var dot: CGFloat = 3.0

    var body: some View {
        Canvas { context, canvasSize in
            let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - dot * 1.5
            let count = 56
            let clamped = min(max(fraction, 0), 1)
            for index in 0..<count {
                let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
                let position = CGPoint(
                    x: centre.x + cos(angle) * radius,
                    y: centre.y + sin(angle) * radius
                )
                let lit = Double(index) / Double(count) <= clamped
                let rect = CGRect(x: position.x - dot / 2, y: position.y - dot / 2, width: dot, height: dot)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(lit ? Color.white.opacity(0.92) : Color.white.opacity(0.20))
                )
            }
        }
        .frame(width: size, height: size)
        .overlay {
            DotMatrixDigits(text: text, dot: 2.6, spacing: 1.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text), \(Int(fraction * 100)) percent of the dial")
    }
}

// MARK: - Range bar

/// The gradient bar with a triangle riding on it, the way the reference shows
/// where a value sits in its range.
struct SoftGlassRangeBar: View {
    var fraction: Double
    var barHeight: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let markerX = min(max(fraction, 0), 1) * width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.30), Preferences.shared.accent.base],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: barHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                SoftGlassTriangle()
                    .frame(width: 13, height: 9)
                    .offset(x: markerX - 6.5)
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}

/// The small solid triangle the reference rides on its bars and waves.
struct SoftGlassTriangle: View {
    var color: Color = Preferences.shared.accent.base

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 13, y: 0))
            path.addLine(to: CGPoint(x: 6.5, y: 9))
            path.closeSubpath()
        }
        .fill(color)
    }
}

// MARK: - Dot row

/// The row of round marks the reference spreads across its variability card.
struct SoftGlassDotRow: View {
    var count: Int = 9
    var dot: CGFloat = 7

    private let pattern: [Double] = [0.45, 1.0, 1.0, 0.55, 0.35, 1.0, 1.0, 0.7, 1.0]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(pattern[index % pattern.count]))
                    .frame(width: dot, height: dot)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tick strip

/// The strip of fine ticks the reference sets into its blue card, with one
/// amber needle standing tall.
struct SoftGlassTickStrip: View {
    var count: Int = 22
    var needleAt: Double = 0.72

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let needleX = min(max(needleAt, 0), 1) * width
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let pitch = size.width / CGFloat(max(count - 1, 1))
                    for index in 0..<count {
                        let x = CGFloat(index) * pitch
                        var tick = Path()
                        tick.move(to: CGPoint(x: x, y: size.height))
                        tick.addLine(to: CGPoint(x: x, y: size.height - 11))
                        context.stroke(tick, with: .color(Color.white.opacity(0.28)), lineWidth: 1.4)
                    }
                }
                VStack(spacing: 2) {
                    SoftGlassTriangle()
                    Rectangle()
                        .fill(Preferences.shared.accent.base)
                        .frame(width: 1.6)
                }
                .offset(x: needleX - 6.5)
            }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}

// MARK: - Blurred blob

/// The soft coloured pool the reference drops into the corner of a card.
struct SoftGlassBlob: View {
    var color: Color = Preferences.shared.accent.bloom
    var size: CGFloat = 120

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.95), color.opacity(0.35), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size * 0.62)
            .blur(radius: 10)
            .accessibilityHidden(true)
    }
}

// MARK: - Page dots

/// The four-dot pagination the reference sets under its ruler.
struct SoftGlassPageDots: View {
    var count: Int = 4
    var active: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == active ? Color.white : Color.white.opacity(0.28))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Radial hero card

/// The "Complete setup" card from the reference: a field in the chosen palette
/// with a deep glow of the same lamp pooling behind the figure at its centre.
struct SoftGlassRadialCard<Content: View>: View {
    var cornerRadius: CGFloat = 36
    /// The lamp the card is lit with. Defaults to the palette the reader chose.
    var tint: Color = Preferences.shared.accent.base
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geometry in
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(SoftGlassTheme.ramp(for: tint))

                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.black.opacity(0.85),
                                        tint.opacity(0.72),
                                        tint.opacity(0.0)
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: geometry.size.width * 0.60
                                )
                            )
                            .frame(width: geometry.size.width * 1.15, height: geometry.size.width * 1.15)
                            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.50)
                            .blur(radius: 16)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Tick ruler

/// The ruler under the reference's figure: a row of fine ticks, the current
/// one amber and tall. Dragging across the ruler steps the bound value, with
/// a light tick haptic at every step so the hand feels the notches.
struct SoftGlassTickRuler: View {
    let range: ClosedRange<Double>
    let step: Double
    @Binding var value: Double
    var tickColor: Color = Preferences.shared.accent.base

    private var steps: Int {
        Int(((range.upperBound - range.lowerBound) / step).rounded())
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            let currentStep = Int(((value - range.lowerBound) / step).rounded())

            ZStack {
                HStack(alignment: .center, spacing: 0) {
                    ForEach(0...max(steps, 1), id: \.self) { index in
                        let isCurrent = index == currentStep
                        Capsule()
                            .fill(isCurrent ? tickColor : Color.white.opacity(0.26))
                            .frame(width: 1.6, height: isCurrent ? 26 : 13)
                        if index < steps {
                            Spacer(minLength: 0)
                        }
                    }
                }

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let raw = range.lowerBound
                                    + min(max(gesture.location.x / width, 0), 1)
                                    * (range.upperBound - range.lowerBound)
                                let stepped = (raw / step).rounded() * step
                                let clamped = min(max(range.lowerBound, stepped), range.upperBound)
                                if abs(clamped - value) >= step / 2 {
                                    value = clamped
                                    Haptics.impact(.light)
                                }
                            }
                    )
            }
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ruler")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            let adjusted = direction == .increment ? value + step : value - step
            value = min(max(range.lowerBound, adjusted), range.upperBound)
        }
    }
}

// MARK: - Row surface

/// List rows wear the reference's card language in this language: one of its
/// tile ramps, lit from a corner, instead of a frosted panel.
struct SoftGlassRowSurface: ViewModifier {
    let key: String
    @ObservedObject private var appearance = AppearanceStore.shared

    func body(content: Content) -> some View {
        if appearance.isSoftGlassActive {
            content
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(SoftGlassTheme.rowGradient(for: key))
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [Color.white.opacity(0.24), Color.clear],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 230
                                )
                            )
                            .blendMode(.softLight)
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear, Color.black.opacity(0.26)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
        } else {
            content
                .glassCard(radius: 20)
        }
    }
}

extension View {
    func softGlassRowSurface(key: String) -> some View {
        modifier(SoftGlassRowSurface(key: key))
    }
}