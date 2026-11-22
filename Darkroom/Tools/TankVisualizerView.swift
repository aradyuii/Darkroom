//
//  TankVisualizerView.swift
//  Darkroom
//
//  The tank liquid visualizer: a tank drawn to scale with its reels, showing
//  exactly how far a poured volume of chemistry reaches. The liquid is not a
//  fixed rectangle — it finds its level with weight, sloshing and damping
//  through a damped oscillator whenever the pour or the tilt changes, and the
//  tank can be dragged to spin its reels. Colour follows the chemistry and the
//  coverage is reported in reels and millilitres, with a warning whenever a
//  reel sits above the liquid.
//

import SwiftUI

// MARK: - Chemistry

/// What is in the tank. The colours are chemistry colours, not theme accents —
/// they stay the same in both themes so the liquid always reads as the
/// chemical it is.
enum PourChemistry: CaseIterable, Identifiable {
    case developer
    case stopBath
    case fixer
    case wash

    var id: Self { self }

    var label: String {
        switch self {
        case .developer: return "Developer"
        case .stopBath: return "Stop"
        case .fixer: return "Fixer"
        case .wash: return "Wash"
        }
    }

    var shortLabel: String {
        switch self {
        case .developer: return "Dev"
        case .stopBath: return "Stop"
        case .fixer: return "Fix"
        case .wash: return "Wash"
        }
    }

    var color: Color {
        switch self {
        case .developer: return Color(red: 0.98, green: 0.66, blue: 0.18)
        case .stopBath: return Color(red: 0.36, green: 0.85, blue: 0.72)
        case .fixer: return Color(red: 0.62, green: 0.50, blue: 0.96)
        case .wash: return Color(red: 0.36, green: 0.55, blue: 0.98)
        }
    }

    /// The water part of mixing this pour from stock, at the dilution each
    /// chemistry is most commonly used at: developer 1+1, stop 1+19, fixer 1+4,
    /// wash is water. The screen states the assumption under the summary.
    var waterFractionOfPour: Double {
        switch self {
        case .developer: return 1.0 / 2.0
        case .stopBath: return 19.0 / 20.0
        case .fixer: return 4.0 / 5.0
        case .wash: return 1.0
        }
    }
}

// MARK: - Film format

enum ReelFormat: String, CaseIterable, Identifiable {
    case mm35 = "35 mm"
    case mm120 = "120"

    var id: String { rawValue }

    /// Reel drum thickness as a fraction of the tank's usable height. 120 film
    /// needs taller drums, so the reels stack higher and the same pour covers
    /// less — the reason the format picker changes the coverage maths.
    var reelThicknessFraction: Double {
        self == .mm35 ? 0.12 : 0.20
    }
}

// MARK: - Screen

struct TankVisualizerView: View {
    /// Paterson Super System 4, two reels, 35 mm or 120. The tank picker itself
    /// belongs to the tank calculator, not this screen.
    private static let capacity: Double = 500
    private static let reelCount = 2

    @State private var fillML: Double = 290
    @State private var tiltDegrees: Double = 0
    @State private var chemistry: PourChemistry = .developer
    @State private var format: ReelFormat = .mm35
    @State private var spin: Double = 0
    @State private var lastDragX: CGFloat = 0
    @State private var lastDragY: CGFloat = 0
    @State private var disturbance = PourDisturbance(magnitude: 0, at: .distantPast)
    @State private var pourConfirmed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                tankAndCoverage
                if let warning = coverageWarning {
                    warningCard(warning)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                slidersCard
                rotateHint
                summaryCard
                dilutionFootnote
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: coverageWarning)
        }
        .background { LiquidBackdrop() }
        .navigationTitle("Tank")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: fillML) { oldValue, newValue in
            disturb(abs(newValue - oldValue) * 0.5)
        }
        .onChange(of: tiltDegrees) { oldValue, newValue in
            disturb(abs(newValue - oldValue) * 1.3)
        }
        .onChange(of: format) { _, _ in
            Haptics.impact(.light)
            disturb(3)
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("Paterson Super System 4")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text("\(Units.volume(millilitres: Self.capacity)) · \(Self.reelCount) reels")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
            }
            HStack {
                Spacer(minLength: 0)
                formatMenu
            }
        }
        .padding(.top, 2)
    }

    private var formatMenu: some View {
        Menu {
            Picker("Film format", selection: $format) {
                ForEach(ReelFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(format.rawValue)
                    .font(.figures(14, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.leading, 14)
            .glassCard(radius: 99)
            .padding(.trailing, 5)
        }
    }

    // MARK: Tank

    private var tankAndCoverage: some View {
        HStack(alignment: .bottom, spacing: 4) {
            tankCanvas
                .frame(maxWidth: .infinity)

            VStack(spacing: 26) {
                chemistryColumn
                coverageBlock
            }
            .frame(width: 74)
        }
    }

    private var tankCanvas: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                draw(
                    context: context,
                    size: size,
                    now: timeline.date,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .frame(height: 336)
        .contentShape(Rectangle())
        .gesture(rotateGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Tank with \(Self.reelCount) reels. \(Units.volumePhrase(millilitres: fillML)) of "
                + "\(chemistry.label.lowercased()); \(coveredCount) of \(Self.reelCount) reels covered."
        )
    }

    private var rotateGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let dx = value.translation.width - lastDragX
                let dy = value.translation.height - lastDragY
                lastDragX = value.translation.width
                lastDragY = value.translation.height
                guard abs(dx) >= abs(dy) else { return }
                spin = (spin + Double(dx) * 0.014)
                    .truncatingRemainder(dividingBy: 2 * Double.pi)
                disturb(min(6, abs(Double(dx)) * 0.12))
            }
            .onEnded { value in
                if abs(value.translation.width) >= 24,
                   abs(value.translation.width) >= abs(value.translation.height) {
                    Haptics.impact(.light)
                }
                lastDragX = 0
                lastDragY = 0
            }
    }

    private var chemistryColumn: some View {
        VStack(spacing: 13) {
            ForEach(PourChemistry.allCases) { chem in
                let selected = chemistry == chem
                Button {
                    guard chemistry != chem else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        chemistry = chem
                    }
                    disturb(2)
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .strokeBorder(Theme.inkFaint.opacity(0.55), lineWidth: 1.6)
                                .frame(width: 44, height: 44)
                            if selected {
                                Circle()
                                    .fill(chem.color)
                                    .frame(width: 44, height: 44)
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                                    .frame(width: 9, height: 9)
                            }
                        }
                        Text(chem.shortLabel)
                            .font(.system(size: 11, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Theme.ink : Theme.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(HapticButtonStyle())
                .accessibilityLabel("\(chem.label) chemistry")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    private var coverageBlock: some View {
        VStack(spacing: 2) {
            Text("\(coveredCount) of \(Self.reelCount)")
                .font(.figures(19, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("reels covered")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
        }
    }

    // MARK: Coverage and warnings

    /// How high each reel's top face sits above the tank bottom, as a fraction
    /// of the usable height. The same fractions drive the drawing, so the label
    /// and the picture never disagree.
    private var reelTopFractions: [Double] {
        let t = format.reelThicknessFraction
        let lowerCenter = 0.34 + t / 2
        let upperCenter = lowerCenter + t + 0.06
        return [lowerCenter + t / 2, upperCenter + t / 2]
    }

    private func neededVolume(forReel index: Int) -> Double {
        Self.capacity * reelTopFractions[index] * 1.04
    }

    private var coveredReels: [Bool] {
        reelTopFractions.map { fillML >= Self.capacity * $0 * 1.04 }
    }

    private var coveredCount: Int {
        coveredReels.filter(\.self).count
    }

    private var coverageWarning: String? {
        guard let uncovered = coveredReels.firstIndex(of: false) else { return nil }
        let shortfall = Int((neededVolume(forReel: uncovered) - fillML).rounded(.up))
        return "Reel \(uncovered + 1) sits above the liquid. \(Units.volume(millilitres: Double(shortfall))) more covers it."
    }

    private func warningCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.38))
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 16, tint: Color(red: 1.0, green: 0.45, blue: 0.22))
    }

    // MARK: Sliders

    private var slidersCard: some View {
        VStack(spacing: 2) {
            HStack(spacing: 12) {
                Text("Fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, alignment: .leading)
                Slider(value: $fillML, in: 0...Self.capacity, step: 5)
                    .tint(chemistry.color)
                    .accessibilityLabel("Fill volume")
                fillValueText
                    .frame(minWidth: 88, alignment: .trailing)
            }
            .padding(.vertical, 10)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

            HStack(spacing: 12) {
                Text("Tilt")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, alignment: .leading)
                Slider(value: $tiltDegrees, in: -25...25, step: 1)
                    .tint(Color(white: 0.55))
                    .accessibilityLabel("Tilt")
                Text("\(Int(tiltDegrees))°")
                    .font(.figures(15, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .frame(minWidth: 88, alignment: .trailing)
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .glassCard(radius: 22)
    }

    private var fillValueText: Text {
        Text(Units.volume(millilitres: fillML))
            .font(.figures(15, weight: .semibold))
            .foregroundColor(chemistry.color)
        + Text(" / \(Units.volume(millilitres: Self.capacity))")
            .font(.figures(15, weight: .medium))
            .foregroundColor(Theme.inkSoft)
    }

    private var rotateHint: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
            Text("Drag the tank to rotate.")
                .font(.system(size: 13))
        }
        .foregroundStyle(Theme.inkFaint)
        .frame(maxWidth: .infinity)
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                summaryColumn(
                    label: chemistry.label,
                    value: Units.volume(millilitres: fillML),
                    valueColor: chemistry.color
                )
                verticalDivider
                summaryColumn(label: "Water to make", value: waterToMake, valueColor: Theme.ink)
                verticalDivider
                summaryColumn(
                    label: "Covers",
                    value: "\(coveredCount) of \(Self.reelCount)",
                    valueColor: Theme.ink,
                    caption: "reels"
                )
            }

            Button {
                Haptics.success()
                disturb(7)
                pourConfirmed = true
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    pourConfirmed = false
                }
            } label: {
                if pourConfirmed {
                    Label(
                        "\(Units.volume(millilitres: fillML)) of \(chemistry.label.lowercased()) — ready to pour",
                        systemImage: "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Use this volume")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(AmberCapsuleStyle(height: 52))
        }
        .padding(16)
        .glassCard(radius: 22)
    }

    private func summaryColumn(
        label: String,
        value: String,
        valueColor: Color,
        caption: String? = nil
    ) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
            Text(value)
                .font(.figures(21, weight: .semibold))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 46)
    }

    private var waterToMake: String {
        Units.volume(millilitres: (fillML * chemistry.waterFractionOfPour).rounded())
    }

    private var dilutionFootnote: some View {
        Text("Water to make assumes common stock dilutions — developer 1+1, stop 1+19, fixer 1+4. Wash is water.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Slosh physics
    //
    // A damped oscillator driven toward the new tilt or level: on every change
    // the surface swings past its mark and settles with weight, instead of
    // snapping like a fixed rectangle. Fully deterministic from the disturbance
    // time, so a redraw never jumps.

    private struct PourDisturbance {
        let magnitude: Double
        let at: Date
    }

    private func disturb(_ magnitude: Double) {
        let now = Date()
        let elapsed = now.timeIntervalSince(disturbance.at)
        let carry = elapsed >= 0 && elapsed < 3
            ? disturbance.magnitude * exp(-1.8 * elapsed)
            : 0
        disturbance = PourDisturbance(magnitude: min(9, max(magnitude, carry)), at: now)
    }

    /// Degrees the liquid surface still swings away from level, in screen terms.
    private func sloshAngleOffset(now: Date) -> Double {
        let elapsed = now.timeIntervalSince(disturbance.at)
        guard elapsed >= 0, elapsed < 5 else { return 0 }
        return disturbance.magnitude * exp(-2.6 * elapsed) * cos(9.0 * elapsed)
    }

    /// Height of the surface ripple, in points, decaying with the slosh.
    private func rippleAmplitude(now: Date) -> CGFloat {
        let elapsed = now.timeIntervalSince(disturbance.at)
        guard elapsed >= 0, elapsed < 5 else { return 0 }
        return CGFloat(disturbance.magnitude * 1.15 * exp(-2.3 * elapsed))
    }

    // MARK: Drawing

    private struct TankCanvasGeometry {
        let bodyFrame: CGRect
        let interior: CGRect
        let lidHeight: CGFloat
        let reelCenters: [CGPoint]
        let reelRadius: CGFloat
        let reelThickness: CGFloat
    }

    private static func geometry(for size: CGSize, format: ReelFormat) -> TankCanvasGeometry {
        let bodyWidth = min(size.width * 0.46, 205)
        let bodyHeight = bodyWidth * 1.42
        let bodyFrame = CGRect(
            x: size.width * 0.44 - bodyWidth / 2,
            y: size.height - bodyHeight - size.height * 0.11,
            width: bodyWidth,
            height: bodyHeight
        )
        let wall = bodyWidth * 0.052
        let lidHeight = bodyHeight * 0.135
        let interiorTop = bodyFrame.minY + lidHeight + wall * 0.7
        let interior = CGRect(
            x: bodyFrame.minX + wall,
            y: interiorTop,
            width: bodyFrame.width - wall * 2,
            height: bodyFrame.maxY - wall - interiorTop
        )
        let usable = interior.height
        let thickness = usable * CGFloat(format.reelThicknessFraction)
        let radius = interior.width * 0.43
        let lowerCenter = usable * 0.34 + thickness / 2
        let upperCenter = lowerCenter + thickness + usable * 0.06
        let centers = [
            CGPoint(x: interior.midX, y: interior.maxY - lowerCenter),
            CGPoint(x: interior.midX, y: interior.maxY - upperCenter)
        ]
        return TankCanvasGeometry(
            bodyFrame: bodyFrame,
            interior: interior,
            lidHeight: lidHeight,
            reelCenters: centers,
            reelRadius: radius,
            reelThickness: thickness
        )
    }

    private func draw(
        context ctx: GraphicsContext,
        size: CGSize,
        now: Date,
        time: Double
    ) {
        let geo = Self.geometry(for: size, format: format)
        let color = chemistry.color

        // Puddle of shadow under the tank, in screen space so it stays put
        // while the tank tilts.
        let pivot = CGPoint(x: geo.bodyFrame.midX, y: geo.bodyFrame.maxY)
        let shadowRect = CGRect(
            x: pivot.x - geo.bodyFrame.width * 0.68,
            y: pivot.y - 8,
            width: geo.bodyFrame.width * 1.36,
            height: 24
        )
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            layer.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.55)))
        }

        let tiltRadians = Angle(degrees: tiltDegrees).radians
        let sloshRadians = Angle(degrees: sloshAngleOffset(now: now)).radians
        let ripple = rippleAmplitude(now: now)

        let fillFraction = max(0, min(1, fillML / Self.capacity))
        let fillHeight = fillFraction * geo.interior.height
        let surfacePoint = CGPoint(x: geo.interior.midX, y: geo.interior.maxY - fillHeight)
        // The liquid stays level in the world: in the tilted tank's own frame
        // the surface runs opposite to the tilt, plus the slosh still settling.
        let surfaceAngle = -tiltRadians + sloshRadians
        let covered = coveredReels

        var tank = ctx
        tank.translateBy(x: pivot.x, y: pivot.y)
        tank.rotate(by: .radians(tiltRadians))
        tank.translateBy(x: -pivot.x, y: -pivot.y)

        drawBaseRim(&tank, geo)
        drawGlassBody(&tank, geo)

        tank.drawLayer { interior in
            interior.clip(
                to: Path(roundedRect: geo.interior, cornerRadius: min(16, geo.interior.width * 0.10))
            )
            drawLiquid(
                &interior, geo, color: color, surfacePoint: surfacePoint,
                surfaceAngle: surfaceAngle, ripple: ripple, time: time
            )
            if fillHeight > 42 {
                let label = Text(Units.volume(millilitres: fillML))
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(color)
                interior.draw(label, at: CGPoint(x: surfacePoint.x, y: surfacePoint.y + 24), anchor: .center)
            }
            drawBubbles(
                &interior, geo, color: color, surfacePoint: surfacePoint,
                surfaceAngle: surfaceAngle, ripple: ripple, time: time
            )
            for (index, center) in geo.reelCenters.enumerated() {
                drawReel(
                    &interior, geo, center: center, spin: spin,
                    submerged: covered.indices.contains(index) ? covered[index] : false,
                    color: color
                )
            }
            drawCentreColumn(&interior, geo, spin: spin)
        }

        drawBodyEdges(&tank, geo)
        drawLid(&tank, geo)
    }

    private func drawLiquid(
        _ layer: inout GraphicsContext,
        _ geo: TankCanvasGeometry,
        color: Color,
        surfacePoint: CGPoint,
        surfaceAngle: Double,
        ripple: CGFloat,
        time: Double
    ) {
        layer.drawLayer { water in
            water.translateBy(x: surfacePoint.x, y: surfacePoint.y)
            water.rotate(by: .radians(surfaceAngle))

            let depth = geo.interior.height * 1.8
            var body = Path()
            body.addRect(CGRect(x: -700, y: 0, width: 1400, height: depth))
            water.fill(body, with: .linearGradient(
                Gradient(colors: [
                    color.opacity(0.40),
                    color.opacity(0.30),
                    color.opacity(0.88)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: depth)
            ))

            // The surface itself: two crossing sine waves scaled by the slosh.
            var crest = Path()
            crest.move(to: CGPoint(x: -700, y: 0))
            var x: Double = -700
            while x <= 700 {
                let y = sin(x * 0.045 + time * 7.0) * Double(ripple) * 0.5
                    + sin(x * 0.019 - time * 4.3) * Double(ripple) * 0.4
                crest.addLine(to: CGPoint(x: x, y: y))
                x += 6
            }
            water.stroke(
                crest,
                with: .color(.white.opacity(0.50)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
        }
    }

    private func surfaceY(
        at x: CGFloat,
        surfacePoint: CGPoint,
        surfaceAngle: Double
    ) -> CGFloat {
        surfacePoint.y - CGFloat(tan(surfaceAngle)) * (x - surfacePoint.x)
    }

    private func drawBubbles(
        _ layer: inout GraphicsContext,
        _ geo: TankCanvasGeometry,
        color: Color,
        surfacePoint: CGPoint,
        surfaceAngle: Double,
        ripple: CGFloat,
        time: Double
    ) {
        layer.drawLayer { bubbles in
            for index in 0..<6 {
                let lane = geo.interior.midX + (CGFloat(index) - 2.5) * geo.interior.width * 0.11
                let speed = 0.26 + Double(index) * 0.045
                var progress = (time * speed + Double(index) * 0.37)
                    .truncatingRemainder(dividingBy: 1)
                if progress < 0 { progress += 1 }
                let lineY = surfaceY(at: lane, surfacePoint: surfacePoint, surfaceAngle: surfaceAngle)
                let bottomY = geo.interior.maxY - 4
                guard bottomY > lineY + 6 else { continue }
                let y = lineY + (bottomY - lineY) * CGFloat(progress) * 0.92
                let radius = 1.4 + CGFloat(index % 3) * 0.7
                let strength = 0.06 + 0.26 * min(1, Double(ripple) / 6.0) * (1 - progress)
                bubbles.fill(
                    Path(ellipseIn: CGRect(x: lane - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(strength))
                )
            }
        }
    }

    private func drawReel(
        _ layer: inout GraphicsContext,
        _ geo: TankCanvasGeometry,
        center: CGPoint,
        spin: Double,
        submerged: Bool,
        color: Color
    ) {
        let r = geo.reelRadius
        let t = geo.reelThickness
        let ratio: CGFloat = 0.30
        let topY = center.y - t / 2
        let sideRect = CGRect(x: center.x - r, y: topY, width: r * 2, height: t)
        let sidePath = Path(roundedRect: sideRect, cornerRadius: min(5, t * 0.3))
        let faceRect = CGRect(x: center.x - r, y: topY - r * ratio, width: r * 2, height: r * 2 * ratio)
        let face = Path(ellipseIn: faceRect)

        // Drum side
        layer.fill(sidePath, with: .linearGradient(
            Gradient(colors: [Color(white: 0.13), Color(white: 0.27)]),
            startPoint: CGPoint(x: center.x, y: topY),
            endPoint: CGPoint(x: center.x, y: topY + t)
        ))
        // Top face
        layer.fill(face, with: .linearGradient(
            Gradient(colors: [Color(white: 0.34), Color(white: 0.18)]),
            startPoint: CGPoint(x: center.x, y: faceRect.minY),
            endPoint: CGPoint(x: center.x, y: faceRect.maxY)
        ))

        // Grooves and spiral. Rotation is applied before the foreshortening
        // scale, so the pattern spins inside its own ellipse footprint.
        layer.drawLayer { grooves in
            grooves.translateBy(x: center.x, y: topY)
            for index in 1...5 {
                let rr = r * CGFloat(index) / 5.5
                let rect = CGRect(x: -rr, y: -rr * ratio, width: rr * 2, height: rr * 2 * ratio)
                grooves.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(index.isMultiple(of: 2) ? 0.13 : 0.06)),
                    lineWidth: 1.1
                )
            }
            var spiral = Path()
            spiral.move(to: CGPoint(x: 0, y: 0))
            let total = 2.6 * 2 * Double.pi
            var a = 0.0
            while a < total {
                let rr = r * 0.92 * CGFloat(a / total)
                let angle = a + spin
                spiral.addLine(to: CGPoint(
                    x: CGFloat(cos(angle)) * rr,
                    y: CGFloat(sin(angle)) * rr * ratio
                ))
                a += 0.22
            }
            grooves.stroke(
                spiral,
                with: .color(.white.opacity(0.22)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
            )
            for tick in 0..<6 {
                let angle = spin + Double(tick) / 6.0 * 2 * Double.pi
                let from = CGPoint(
                    x: CGFloat(cos(angle)) * r * 0.55,
                    y: CGFloat(sin(angle)) * r * 0.55 * ratio
                )
                let to = CGPoint(
                    x: CGFloat(cos(angle)) * r * 0.68,
                    y: CGFloat(sin(angle)) * r * 0.68 * ratio
                )
                var line = Path()
                line.move(to: from)
                line.addLine(to: to)
                grooves.stroke(line, with: .color(.white.opacity(0.16)), lineWidth: 1.2)
            }
            let hub = CGRect(x: -7, y: -7 * ratio, width: 14, height: 14 * ratio)
            grooves.fill(Path(ellipseIn: hub), with: .color(Color(white: 0.07)))
        }

        // Chemistry reaching the reel: a tint of the liquid over the plastic.
        if submerged {
            layer.fill(face, with: .color(color.opacity(0.15)))
            layer.fill(sidePath, with: .color(color.opacity(0.10)))
        }
    }

    private func drawCentreColumn(
        _ layer: inout GraphicsContext,
        _ geo: TankCanvasGeometry,
        spin: Double
    ) {
        let width = max(16, geo.bodyFrame.width * 0.085)
        let rect = CGRect(
            x: geo.interior.midX - width / 2,
            y: geo.interior.minY - geo.lidHeight * 0.35,
            width: width,
            height: geo.interior.height + geo.lidHeight * 0.35
        )
        layer.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .linearGradient(
            Gradient(colors: [Color(white: 0.02), Color(white: 0.10), Color(white: 0.02)]),
            startPoint: CGPoint(x: rect.minX, y: rect.midY),
            endPoint: CGPoint(x: rect.maxX, y: rect.midY)
        ))
        // A highlight that slides along the column as the tank is spun.
        let highlightX = rect.minX + 2 + (CGFloat(sin(spin)) * 0.5 + 0.5) * (width - 6)
        let highlight = CGRect(x: highlightX, y: rect.minY + 6, width: 2.2, height: rect.height - 14)
        layer.fill(Path(roundedRect: highlight, cornerRadius: 1), with: .color(.white.opacity(0.30)))
    }

    private func drawGlassBody(
        _ layer: inout GraphicsContext,
        _ geo: TankCanvasGeometry
    ) {
        layer.fill(Path(roundedRect: geo.bodyFrame, cornerRadius: 20), with: .linearGradient(
            Gradient(colors: [
                Color.white.opacity(0.085),
                Color.white.opacity(0.015),
                Color.white.opacity(0.05)
            ]),
            startPoint: CGPoint(x: geo.bodyFrame.midX, y: geo.bodyFrame.minY),
            endPoint: CGPoint(x: geo.bodyFrame.midX, y: geo.bodyFrame.maxY)
        ))
    }

    private func drawBodyEdges(
        _ layer: inout GraphicsContext,
        _ geo: TankCanvasGeometry
    ) {
        let frame = geo.bodyFrame
        let leftRect = CGRect(
            x: frame.minX + frame.width * 0.045,
            y: frame.minY + geo.lidHeight,
            width: 5,
            height: frame.height * 0.62
        )
        layer.fill(Path(roundedRect: leftRect, cornerRadius: 2.5), with: .linearGradient(
            Gradient(colors: [.white.opacity(0.0), .white.opacity(0.30), .white.opacity(0.0)]),
            startPoint: CGPoint(x: leftRect.midX, y: leftRect.minY),
            endPoint: CGPoint(x: leftRect.midX, y: leftRect.maxY)
        ))
        let rightRect = CGRect(
            x: frame.maxX - frame.width * 0.045 - 4,
            y: frame.minY + geo.lidHeight * 1.3,
            width: 4,
            height: frame.height * 0.52
        )
        layer.fill(Path(roundedRect: rightRect, cornerRadius: 2), with: .linearGradient(
            Gradient(colors: [.white.opacity(0.0), .white.opacity(0.17), .white.opacity(0.0)]),
            startPoint: CGPoint(x: rightRect.midX, y: rightRect.minY),
            endPoint: CGPoint(x: rightRect.midX, y: rightRect.maxY)
        ))
        layer.stroke(
            Path(roundedRect: frame, cornerRadius: 20),
            with: .color(.white.opacity(0.20)),
            lineWidth: 1.4
        )
        layer.stroke(
            Path(roundedRect: geo.interior, cornerRadius: min(16, geo.interior.width * 0.10)),
            with: .color(.white.opacity(0.07)),
            lineWidth: 1
        )
    }

    private func drawBaseRim(
        _ layer: inout GraphicsContext,
        _ geo: TankCanvasGeometry
    ) {
        let frame = geo.bodyFrame
        let baseRect = CGRect(x: frame.minX - 4, y: frame.maxY - 9, width: frame.width + 8, height: 13)
        layer.fill(Path(roundedRect: baseRect, cornerRadius: 6.5), with: .color(Color(white: 0.04)))
        layer.stroke(
            Path(roundedRect: baseRect, cornerRadius: 6.5),
            with: .color(.white.opacity(0.10)),
            lineWidth: 1
        )
    }

    private func drawLid(
        _ layer: inout GraphicsContext,
        _ geo: TankCanvasGeometry
    ) {
        let frame = geo.bodyFrame
        let lidRect = CGRect(
            x: frame.minX - 5,
            y: frame.minY - geo.lidHeight * 0.30,
            width: frame.width + 10,
            height: geo.lidHeight
        )
        layer.fill(Path(roundedRect: lidRect, cornerRadius: 9), with: .linearGradient(
            Gradient(colors: [Color(white: 0.115), Color(white: 0.045)]),
            startPoint: CGPoint(x: frame.midX, y: lidRect.minY),
            endPoint: CGPoint(x: frame.midX, y: lidRect.maxY)
        ))
        var x = lidRect.minX + 9
        while x < lidRect.maxX - 9 {
            let ridge = CGRect(x: x, y: lidRect.minY + 4, width: 1.6, height: lidRect.height - 8)
            layer.fill(Path(roundedRect: ridge, cornerRadius: 0.8), with: .color(.white.opacity(0.09)))
            x += 8
        }
        layer.stroke(
            Path(roundedRect: lidRect, cornerRadius: 9),
            with: .color(.white.opacity(0.10)),
            lineWidth: 1
        )
        // Cap lip and opening under the lid
        let lipRect = CGRect(
            x: frame.minX + frame.width * 0.05,
            y: frame.minY + geo.lidHeight * 0.62,
            width: frame.width * 0.90,
            height: 13
        )
        layer.fill(Path(ellipseIn: lipRect), with: .color(Color(white: 0.03)))
        layer.stroke(Path(ellipseIn: lipRect), with: .color(.white.opacity(0.08)), lineWidth: 1)
        // Centre-column cap
        let capWidth = max(16, frame.width * 0.085) * 1.9
        let capRect = CGRect(
            x: geo.interior.midX - capWidth / 2,
            y: lipRect.maxY - 3,
            width: capWidth,
            height: 9
        )
        layer.fill(Path(roundedRect: capRect, cornerRadius: 4), with: .color(Color(white: 0.06)))
    }
}

#Preview {
    NavigationStack {
        TankVisualizerView()
    }
}
