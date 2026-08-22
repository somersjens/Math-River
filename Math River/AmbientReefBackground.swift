//
//  AmbientReefBackground.swift
//  Number Reef
//
//  A quiet menu version of the playing reef. It borrows the water column,
//  light shafts, bubbles and sea-floor silhouette from gameplay, while keeping
//  the contrast low enough for controls and longer translated copy.
//

import SwiftUI

struct AmbientReefBackground: View {
    let character: AnimalCharacter
    var showsSeaFloor = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: ReefPalette { ReefPalette.palette(for: character) }

    var body: some View {
        // The geometry sits outside the timeline: only the bubbles move from
        // frame to frame, and re-proposing the whole backdrop's layout 24 times
        // a second to learn a size that never changes is pure overhead.
        GeometryReader { proxy in
            ZStack {
                character.tintColor

                LinearGradient(
                    colors: [palette.waterTop.opacity(0.88), character.skyColor, character.tintColor],
                    startPoint: .top,
                    endPoint: .bottom
                )

                AmbientLightShafts(paused: reduceMotion)
                    .opacity(0.16)

                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
                    let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    AmbientBubbleField(phase: phase, size: proxy.size)
                }

                if showsSeaFloor {
                    AmbientSeaFloor(palette: palette)
                        .frame(height: min(150, proxy.size.height * 0.17))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }

                // A soft veil keeps dark theme colours and decoration from
                // reducing the contrast of text placed over the backdrop.
                Color.white.opacity(0.12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Two blurred shafts of light, drifting almost imperceptibly.
///
/// Their sway is deliberately *not* driven by the backdrop's timeline. A blur
/// this wide is an offscreen render pass, and recomputing two full-height ones
/// every frame was the single most expensive thing on an idle menu. A repeating
/// animation hands the same slow drift to Core Animation instead, which moves
/// them without waking SwiftUI at all.
private struct AmbientLightShafts: View {
    let paused: Bool

    @State private var drifted = false

    /// Half-periods of the sine waves this replaces, so the pace is unchanged.
    private static let leftSway = 31.4
    private static let rightSway = 39.3

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {
                shaft(width: width * 0.34)
                    .rotationEffect(.degrees(-12), anchor: .top)
                    .offset(x: width * (drifted ? 0.175 : 0.125))
                    .animation(sway(Self.leftSway), value: drifted)

                shaft(width: width * 0.22)
                    .rotationEffect(.degrees(-8), anchor: .top)
                    .offset(x: width * (drifted ? 0.71 : 0.65))
                    .animation(sway(Self.rightSway), value: drifted)
            }
        }
        .onAppear {
            guard !paused else { return }
            drifted = true
        }
    }

    private func sway(_ halfPeriod: Double) -> Animation {
        .easeInOut(duration: halfPeriod).repeatForever(autoreverses: true)
    }

    private func shaft(width: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.9), location: 0.18),
                .init(color: .white.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: width)
        .blur(radius: 28)
    }
}

private struct AmbientBubbleField: View {
    private struct Bubble: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let diameter: CGFloat
        let speed: CGFloat
    }

    let phase: Double
    let size: CGSize

    private static let bubbles: [Bubble] = [
        .init(id: 0, x: 0.06, y: 0.18, diameter: 12, speed: 3.2),
        .init(id: 1, x: 0.13, y: 0.66, diameter: 22, speed: 4.0),
        .init(id: 2, x: 0.22, y: 0.90, diameter: 8, speed: 2.7),
        .init(id: 3, x: 0.78, y: 0.30, diameter: 10, speed: 3.5),
        .init(id: 4, x: 0.88, y: 0.74, diameter: 18, speed: 3.0),
        .init(id: 5, x: 0.96, y: 0.48, diameter: 7, speed: 4.4),
        .init(id: 6, x: 0.68, y: 0.94, diameter: 13, speed: 3.8)
    ]

    var body: some View {
        ZStack {
            ForEach(Self.bubbles) { bubble in
                let travel = size.height + 100
                let shifted = bubble.y * travel - CGFloat(phase) * bubble.speed
                let wrapped = shifted.truncatingRemainder(dividingBy: travel)
                let y = wrapped >= 0 ? wrapped : wrapped + travel

                Circle()
                    .fill(.white.opacity(0.08))
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.32), lineWidth: max(1, bubble.diameter * 0.08))
                    }
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(.white.opacity(0.48))
                            .frame(width: bubble.diameter * 0.22, height: bubble.diameter * 0.22)
                            .padding(bubble.diameter * 0.2)
                    }
                    .frame(width: bubble.diameter, height: bubble.diameter)
                    .position(x: bubble.x * size.width, y: y)
            }
        }
        .opacity(0.78)
    }
}

private struct AmbientSeaFloor: View {
    let palette: ReefPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                AmbientSandShape()
                    .fill(
                        LinearGradient(
                            colors: [palette.sand.opacity(0.48), palette.sandDeep.opacity(0.38)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                HStack(alignment: .bottom, spacing: proxy.size.width * 0.035) {
                    plant(height: proxy.size.height * 0.34, rotation: 8)
                    plant(height: proxy.size.height * 0.50, rotation: -5)
                    plant(height: proxy.size.height * 0.28, rotation: 12)
                    Spacer()
                    plant(height: proxy.size.height * 0.42, rotation: -10)
                    plant(height: proxy.size.height * 0.58, rotation: 5)
                }
                .padding(.horizontal, max(18, proxy.size.width * 0.045))
                .padding(.bottom, proxy.size.height * 0.18)
                .opacity(0.22)
            }
        }
    }

    private func plant(height: CGFloat, rotation: Double) -> some View {
        Capsule()
            .fill(palette.plant)
            .frame(width: max(5, height * 0.12), height: height)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
    }
}

private struct AmbientSandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.48))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.38),
            control1: CGPoint(x: rect.width * 0.17, y: rect.height * 0.28),
            control2: CGPoint(x: rect.width * 0.34, y: rect.height * 0.58)
        )
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.44),
            control1: CGPoint(x: rect.width * 0.70, y: rect.height * 0.22),
            control2: CGPoint(x: rect.width * 0.84, y: rect.height * 0.60)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
