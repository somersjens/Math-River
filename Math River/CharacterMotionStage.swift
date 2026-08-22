//
//  CharacterMotionStage.swift
//  Number Reef
//
//  A reusable, image-independent trail for character artwork. The stage takes
//  its proportions from the frame supplied by its caller, so future portrait,
//  landscape and square character assets all receive the same composition.
//

import SwiftUI

/// Places themed motion wisps and bubbles behind arbitrary character artwork.
///
/// The content is intentionally generic: no character image is coupled to this
/// effect. Give the stage the size/aspect ratio of the artwork that will be
/// inserted later and the decoration adapts with it.
struct CharacterMotionStage<Content: View>: View {
    let character: AnimalCharacter
    var trailEdge: HorizontalEdge = .leading
    var intensity: CGFloat = 1
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            CharacterMotionBackdrop(
                character: character,
                trailEdge: trailEdge,
                intensity: intensity
            )

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The decoration-only layer used by `CharacterMotionStage`.
///
/// It can also be placed directly in an existing ZStack. Its drawing uses
/// normalized coordinates, rather than screen points, so the visual density
/// follows the size and aspect ratio of its container.
struct CharacterMotionBackdrop: View {
    let character: AnimalCharacter
    var trailEdge: HorizontalEdge = .leading
    var intensity: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let renderer = CharacterTrailRenderer(
                    size: size,
                    time: time,
                    trailEdge: trailEdge,
                    intensity: min(max(intensity, 0), 1.5),
                    brightColor: character.color,
                    deepColor: character.deepColor
                )
                renderer.draw(in: &context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CharacterTrailRenderer {
    struct Wisp {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
        let width: CGFloat
        let phase: Double
        let opacity: Double
    }

    struct Bubble {
        let origin: CGPoint
        let diameter: CGFloat
        let speed: Double
        let phase: Double
    }

    let size: CGSize
    let time: Double
    let trailEdge: HorizontalEdge
    let intensity: CGFloat
    let brightColor: Color
    let deepColor: Color

    // Uneven vertical spacing and varied lengths preserve the hand-drawn,
    // organic rhythm of the reference instead of creating a mechanical fan.
    private static let wisps: [Wisp] = [
        .init(start: .init(x: 0.05, y: 0.29), control1: .init(x: 0.24, y: 0.25), control2: .init(x: 0.47, y: 0.34), end: .init(x: 0.76, y: 0.31), width: 0.012, phase: 0.2, opacity: 0.76),
        .init(start: .init(x: 0.16, y: 0.38), control1: .init(x: 0.34, y: 0.35), control2: .init(x: 0.51, y: 0.43), end: .init(x: 0.82, y: 0.40), width: 0.007, phase: 1.7, opacity: 0.52),
        .init(start: .init(x: 0.02, y: 0.52), control1: .init(x: 0.21, y: 0.49), control2: .init(x: 0.43, y: 0.59), end: .init(x: 0.73, y: 0.55), width: 0.014, phase: 3.1, opacity: 0.82),
        .init(start: .init(x: 0.13, y: 0.65), control1: .init(x: 0.30, y: 0.60), control2: .init(x: 0.49, y: 0.72), end: .init(x: 0.79, y: 0.66), width: 0.009, phase: 4.4, opacity: 0.61),
        .init(start: .init(x: 0.04, y: 0.76), control1: .init(x: 0.23, y: 0.73), control2: .init(x: 0.43, y: 0.82), end: .init(x: 0.68, y: 0.78), width: 0.005, phase: 5.6, opacity: 0.44)
    ]

    // Bubbles intentionally form three loose clusters, with empty space in
    // between. That distribution is an important part of the reference image.
    private static let bubbles: [Bubble] = [
        .init(origin: .init(x: 0.18, y: 0.22), diameter: 0.064, speed: 0.030, phase: 0.10),
        .init(origin: .init(x: 0.27, y: 0.29), diameter: 0.027, speed: 0.042, phase: 0.56),
        .init(origin: .init(x: 0.12, y: 0.48), diameter: 0.042, speed: 0.035, phase: 0.31),
        .init(origin: .init(x: 0.21, y: 0.55), diameter: 0.018, speed: 0.048, phase: 0.78),
        .init(origin: .init(x: 0.15, y: 0.79), diameter: 0.052, speed: 0.028, phase: 0.67),
        .init(origin: .init(x: 0.29, y: 0.73), diameter: 0.022, speed: 0.044, phase: 0.18)
    ]

    func draw(in context: inout GraphicsContext) {
        guard size.width > 0, size.height > 0, intensity > 0 else { return }

        for (index, wisp) in Self.wisps.enumerated() {
            draw(wisp: wisp, index: index, in: &context)
        }

        for bubble in Self.bubbles {
            draw(bubble: bubble, in: &context)
        }
    }

    private func draw(wisp: Wisp, index: Int, in context: inout GraphicsContext) {
        let wave = CGFloat(sin(time * 1.05 + wisp.phase)) * size.height * 0.012
        let breathe = 1 + CGFloat(sin(time * 0.72 + wisp.phase * 1.4)) * 0.025

        var path = Path()
        path.move(to: point(wisp.start, yOffset: -wave * 0.35))
        path.addCurve(
            to: point(CGPoint(x: wisp.end.x * breathe, y: wisp.end.y), yOffset: wave * 0.2),
            control1: point(wisp.control1, yOffset: wave),
            control2: point(wisp.control2, yOffset: -wave * 0.6)
        )

        let lineWidth = max(1, min(size.width, size.height) * wisp.width)
        let opacity = wisp.opacity * Double(intensity)
        let start = point(.init(x: 0.02, y: 0.5))
        let end = point(.init(x: 0.82, y: 0.5))

        context.stroke(
            path,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: deepColor.opacity(0), location: 0),
                    .init(color: deepColor.opacity(opacity * 0.76), location: 0.20),
                    .init(color: brightColor.opacity(opacity), location: 0.72),
                    .init(color: brightColor.opacity(0), location: 1)
                ]),
                startPoint: start,
                endPoint: end
            ),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: index.isMultiple(of: 2) ? .round : .butt
            )
        )
    }

    private func draw(bubble: Bubble, in context: inout GraphicsContext) {
        let cycle = positiveRemainder(bubble.phase + time * bubble.speed, 1)
        let drift = CGFloat(cycle) - 0.5
        let position = CGPoint(
            x: bubble.origin.x - drift * 0.10,
            y: bubble.origin.y - drift * 0.09 + CGFloat(sin(time * 0.9 + bubble.phase * 8)) * 0.008
        )
        let diameter = max(4, min(size.width, size.height) * bubble.diameter)
        let center = point(position)
        let rect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let edgeFade = min(1, min(cycle * 8, (1 - cycle) * 8))
        let opacity = Double(intensity) * edgeFade

        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.34 * opacity),
                    brightColor.opacity(0.20 * opacity),
                    deepColor.opacity(0.08 * opacity)
                ]),
                center: CGPoint(x: rect.midX - diameter * 0.16, y: rect.midY - diameter * 0.18),
                startRadius: 0,
                endRadius: diameter * 0.62
            )
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(brightColor.opacity(0.78 * opacity)),
            lineWidth: max(1, diameter * 0.075)
        )

        let highlightSize = diameter * 0.22
        let highlight = CGRect(
            x: rect.minX + diameter * 0.22,
            y: rect.minY + diameter * 0.18,
            width: highlightSize,
            height: highlightSize
        )
        context.fill(Path(ellipseIn: highlight), with: .color(.white.opacity(0.82 * opacity)))
    }

    private func point(_ normalized: CGPoint, yOffset: CGFloat = 0) -> CGPoint {
        let x = trailEdge == .leading ? normalized.x : 1 - normalized.x
        return CGPoint(x: x * size.width, y: normalized.y * size.height + yOffset)
    }

    private func positiveRemainder(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
