//
//  MathRiverPlayfield.swift
//  Math River
//
//  What Honey Slide looks like: a flowing golden track curls through a high
//  forest valley while the honey-ring rider and existing answer art approach.
//  The simulation lives in `MathRiverArena`.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MathRiverPlayfield: View {
    let round: GameRound?
    var missedSum: MissedSum?
    let maximumRounds: Int
    let character: AnimalCharacter
    let isPad: Bool
    let isLive: Bool
    let isRunning: Bool
    let playsEntrance: Bool
    let playsLevelCompletion: Bool
    let reduceMotion: Bool
    var tutorialPlan = CrabTutorialPlan()
    var reservesTutorialMessage = false
    let topReserve: CGFloat
    let bottomReserve: CGFloat
    let scoreTarget: CGPoint?
    let onAnswer: (UUID) -> Bool
    let onRewardArrived: () -> Void
    let onEntranceComplete: () -> Void
    var onLevelCompletionStarted: () -> Void = {}
    let onLevelCompletionFinished: () -> Void
    var onTutorialEvent: (CrabTutorialEvent) -> Void = { _ in }
    let onWaveComplete: () -> Void

    @StateObject private var arena = MathRiverArena()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let projection = RiverProjection(size: size,
                                             phase: arena.scroll,
                                             speed: arena.currentSlideSpeed,
                                             focusLateral: arena.cameraLateral)

            ZStack(alignment: .topLeading) {
                RiverWorld(character: character,
                           arena: arena,
                           projection: projection,
                           isPad: isPad)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(riverGesture)
            .allowsHitTesting(!playsLevelCompletion)
            .environment(\.layoutDirection, .leftToRight)
            .onAppear {
                bindArena()
                _ = (maximumRounds, reservesTutorialMessage, topReserve, missedSum, tutorialPlan)
                arena.layout(size: size, isPad: isPad)
                arena.setReduceMotion(reduceMotion)
                arena.setScoreTarget(scoreTarget)
                arena.setLive(isLive)
                arena.load(round: round)
                arena.setRunning(isRunning)
                if playsEntrance {
                    arena.beginEntrance(completion: onEntranceComplete)
                }
                if playsLevelCompletion {
                    arena.beginCalm(reduceMotion: reduceMotion,
                                    started: onLevelCompletionStarted,
                                    completion: onLevelCompletionFinished)
                }
            }
            .onChange(of: size) { _, newSize in
                arena.layout(size: newSize, isPad: isPad)
            }
        }
        .onChange(of: round) { _, newRound in
            arena.load(round: newRound)
        }
        .onChange(of: isLive) { _, live in
            arena.setLive(live)
        }
        .onChange(of: isRunning) { _, running in
            arena.setRunning(running)
        }
        .onChange(of: scoreTarget) { _, target in
            arena.setScoreTarget(target)
        }
        .onChange(of: playsEntrance) { _, shouldPlay in
            if shouldPlay { arena.beginEntrance(completion: onEntranceComplete) }
        }
        .onChange(of: playsLevelCompletion) { _, shouldPlay in
            if shouldPlay {
                arena.beginCalm(reduceMotion: reduceMotion,
                                started: onLevelCompletionStarted,
                                completion: onLevelCompletionFinished)
            } else {
                arena.endCalm()
            }
        }
        .onDisappear { arena.stop() }
        .accessibilityElement(children: .contain)
    }

    private func bindArena() {
        arena.onAnswer = onAnswer
        arena.onRewardArrived = onRewardArrived
        arena.onWaveComplete = onWaveComplete
        arena.onTutorialEvent = onTutorialEvent
    }

    private var riverGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                arena.beginSteering(at: value.startLocation)
                arena.updateSteering(to: value.location)
            }
            .onEnded { _ in arena.endSteering() }
    }
}

// MARK: - World

private struct RiverWorld: View {
    let character: AnimalCharacter
    @ObservedObject var arena: MathRiverArena
    let projection: RiverProjection
    let isPad: Bool

    var body: some View {
        ZStack {
            HoneyWorldBackdrop(projection: projection)
            water
            ForEach(arena.pots) { pot in
                RiverAnswerStoneView(pot: pot,
                                     projection: projection,
                                     isPad: isPad,
                                     clock: arena.clock,
                                     groupDismissal: arena.reelLift)
                    .zIndex(pot.travel > 0.08 ? Double(4 - pot.travel) : Double(16 - pot.travel))
            }
            playerContactUnderlay
            boatLayer
            playerContactLip
            splashes
                .zIndex(31)
            rewards
                .zIndex(32)
#if DEBUG
            if HoneySlideDebugState.enabled {
                HoneySlidePerformanceOverlay(text: arena.debugPerformanceText)
                    .zIndex(100)
            }
            if HoneySlideDebugState.contactEnabled {
                HoneySlideContactDebugLayer(projection: projection,
                                            lateral: arena.displayLateral,
                                            spriteSize: playerSize,
                                            visualBounce: -arena.boatBob * playerSize)
                    .zIndex(101)
            }
#endif
        }
        .clipped()
    }

    private var water: some View {
            RiverWater(clock: arena.clock,
                   scroll: arena.scroll,
                   calmness: arena.calmness,
                   current: arena.current,
                   boatLateral: arena.displayLateral,
                   entrance: arena.entrance,
                   pots: arena.pots,
                   reelLift: arena.reelLift,
                   quality: arena.visualQuality,
                   projection: projection)
    }

    private var banks: some View {
        RiverBanks(scroll: arena.scroll,
                   decor: arena.decor,
                   projection: projection,
                   calmness: arena.calmness)
    }

    private var playerSize: CGFloat {
        RiverConfig.boatSize(isPad: isPad) * 1.13
    }

    private var playerContactUnderlay: some View {
        let surface = projection.playerSurface(lateral: arena.displayLateral)
        let size = playerSize
        let presence = max(0, 1 - arena.entrance)
        return ZStack {
            Ellipse()
                .fill(Color(red: 0.30, green: 0.10, blue: 0.015).opacity(0.34))
                .blur(radius: 1.2)
            Ellipse()
                .stroke(Color(red: 1.00, green: 0.75, blue: 0.08).opacity(0.78),
                        lineWidth: max(2, size * 0.027))
        }
        .frame(width: size * 0.78, height: size * 0.17)
        .rotationEffect(.degrees(surface.surfaceRollDegrees))
        .position(surface.contactPoint)
        .opacity(surface.trackWidth > 0 && projection.sample(for: 0).hasSurface
                 ? Double(presence * (1 - arena.jumpLift * 5)) : 0)
        .allowsHitTesting(false)
        .zIndex(9)
    }

    private var boatLayer: some View {
        let surface = projection.playerSurface(lateral: arena.displayLateral)
        // The rider is the foreground anchor in the mock-up. A slightly
        // larger silhouette also makes steering readable against the rich
        // honey surface without changing the collision model.
        let size = playerSize
        let rideHeight = size * HoneySlideTuning.playerRideHeightFraction
        let point = surface.visualPoint(rideHeight: rideHeight,
                                        bounce: -arena.boatBob * size)
        return Image("1_main_honey")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size * 1.15)
            .rotation3DEffect(.degrees(arena.boatPitch), axis: (x: 1, y: 0, z: 0),
                              perspective: 0.28)
            .rotationEffect(.degrees(surface.surfaceRollDegrees + arena.boatRoll))
            .scaleEffect(1 + arena.jumpLift * 0.55 + arena.landingImpact * 0.025)
            .position(x: point.x,
                      y: point.y + arena.entrance * size * 1.6)
            .zIndex(10)
    }

    private var playerContactLip: some View {
        let surface = projection.playerSurface(lateral: arena.displayLateral)
        let size = playerSize
        let presence = max(0, 1 - arena.entrance)
        return Path { path in
            path.move(to: CGPoint(x: 0, y: size * 0.005))
            path.addQuadCurve(to: CGPoint(x: size * 0.76, y: size * 0.005),
                              control: CGPoint(x: size * 0.38, y: size * 0.13))
        }
        .stroke(
            LinearGradient(colors: [
                Color(red: 0.90, green: 0.42, blue: 0.015),
                Color(red: 1.00, green: 0.76, blue: 0.08),
                Color(red: 0.90, green: 0.42, blue: 0.015)
            ], startPoint: .leading, endPoint: .trailing),
            style: StrokeStyle(lineWidth: size * HoneySlideTuning.playerImmersionFraction,
                               lineCap: .round)
        )
        .frame(width: size * 0.76, height: size * 0.15)
        .rotationEffect(.degrees(surface.surfaceRollDegrees))
        .position(x: surface.contactPoint.x,
                  y: surface.contactPoint.y + size * 0.015)
        .opacity(projection.sample(for: 0).hasSurface
                 ? Double(presence * (1 - arena.jumpLift * 5)) : 0)
        .allowsHitTesting(false)
        .zIndex(11)
    }

    private var splashes: some View {
        ForEach(arena.splashes) { splash in
            if splash.isActive {
                let fade = max(0, 1 - splash.age / splash.life)
                let stretch = 1 + min(0.45, abs(splash.vy) / 900)
                Ellipse()
                    .fill(
                        RadialGradient(colors: [
                            splash.honey
                                ? Color(red: 1, green: 0.86, blue: 0.40).opacity(0.95 * fade)
                                : Color.white.opacity(0.92 * fade),
                            splash.honey
                                ? Color(red: 1, green: 0.78, blue: 0.22).opacity(0.0)
                                : Color(red: 0.55, green: 0.88, blue: 1.0).opacity(0.0)
                        ], center: .center, startRadius: 0, endRadius: 8 * splash.scale)
                    )
                    .frame(width: 9 * splash.scale,
                           height: 11 * splash.scale * stretch)
                    .rotationEffect(.degrees(Double(splash.vx) * 0.04))
                    .position(x: splash.x, y: splash.y)
                    .allowsHitTesting(false)
            }
        }
    }

    private var rewards: some View {
        ForEach(arena.rewards) { reward in
            let t = min(1, reward.age / RiverConfig.rewardFlight)
            let ease = 1 - pow(1 - t, 3)
            let x = reward.start.x + (reward.target.x - reward.start.x) * ease
            let y = reward.start.y + (reward.target.y - reward.start.y) * ease
                - CGFloat(sin(t * .pi)) * 40
            CurrencyIcon(size: isPad ? 28 : 22)
                .foregroundStyle(character.deepColor)
                .position(x: x, y: y)
                .opacity(1 - Double(max(0, t - 0.82) / 0.18))
                .allowsHitTesting(false)
        }
    }
}

#if DEBUG
private struct HoneySlidePerformanceOverlay: View {
    let text: String

    var body: some View {
        VStack {
            HStack {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 46)
        .padding(.horizontal, 10)
        .allowsHitTesting(false)
    }
}

private struct HoneySlideContactDebugLayer: View {
    let projection: RiverProjection
    let lateral: CGFloat
    let spriteSize: CGFloat
    let visualBounce: CGFloat

    private var surface: RiverProjection.ProjectedPlayerSurface {
        projection.playerSurface(lateral: lateral)
    }

    private var visualPoint: CGPoint {
        surface.visualPoint(
            rideHeight: spriteSize * HoneySlideTuning.playerRideHeightFraction,
            bounce: visualBounce
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Canvas { context, _ in
                let contact = surface.contactPoint
                let visual = visualPoint
                var normal = Path()
                normal.move(to: contact)
                normal.addLine(to: CGPoint(x: contact.x + surface.screenNormal.dx * 64,
                                           y: contact.y + surface.screenNormal.dy * 64))
                context.stroke(normal, with: .color(.cyan),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                var tangent = Path()
                tangent.move(to: CGPoint(x: contact.x - surface.screenTangent.dx * 44,
                                         y: contact.y - surface.screenTangent.dy * 44))
                tangent.addLine(to: CGPoint(x: contact.x + surface.screenTangent.dx * 44,
                                            y: contact.y + surface.screenTangent.dy * 44))
                context.stroke(tangent, with: .color(.purple),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))

                var offset = Path()
                offset.move(to: contact)
                offset.addLine(to: visual)
                context.stroke(offset, with: .color(.yellow),
                               style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                context.fill(Path(ellipseIn: CGRect(x: contact.x - 5, y: contact.y - 5,
                                                    width: 10, height: 10)),
                             with: .color(.green))
                context.fill(Path(ellipseIn: CGRect(x: visual.x - 5, y: visual.y - 5,
                                                    width: 10, height: 10)),
                             with: .color(.yellow))
            }
            Text(debugText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
                .padding(.leading, 10)
                .padding(.bottom, 18)
        }
        .allowsHitTesting(false)
    }

    private var debugText: String {
        let p = surface.worldPosition
        let n = surface.worldNormal
        let t = surface.worldTangent
        return String(format:
            "CONTACT  green=surface yellow=visual\nP (%.2f, %.2f, %.2f)  lateral %.3f\nN (%.2f, %.2f, %.2f)  T (%.2f, %.2f, %.2f)\nride %.1f px (%.0f%%)  width %.2f m  allowed ±%.3f",
            p.x, p.y, p.z, surface.lateral,
            n.x, n.y, n.z, t.x, t.y, t.z,
            spriteSize * HoneySlideTuning.playerRideHeightFraction,
            HoneySlideTuning.playerRideHeightFraction * 100,
            surface.trackWidth, surface.allowedLateral)
    }
}
#endif

// MARK: - Water & banks

private enum RiverPaint {
    static let far = Color(red: 1.00, green: 0.73, blue: 0.16)
    static let body = Color(red: 0.96, green: 0.50, blue: 0.045)
    static let near = Color(red: 0.82, green: 0.30, blue: 0.018)
    static let trough = Color(red: 0.58, green: 0.19, blue: 0.015)
    static let gloss = Color(red: 1.00, green: 0.94, blue: 0.52)
    static let edge = Color(red: 0.35, green: 0.13, blue: 0.025)
    static let foam = Color(red: 1.00, green: 0.86, blue: 0.26)
    static let wood = Color(red: 0.38, green: 0.18, blue: 0.07)
    static let lightWood = Color(red: 0.68, green: 0.36, blue: 0.12)
}

/// A painterly environment plate provides the material richness that is
/// expensive to fake with dozens of Canvas primitives. The center was authored
/// as an open valley so every live track segment can still curve, split and
/// jump independently above it.
private struct HoneyWorldBackdrop: View {
    let projection: RiverProjection

    var body: some View {
        let curveParallax = -projection.meander(for: 0.96) * 0.055
        let verticalParallax = CGFloat(sin(Double(projection.phase) * 0.012))
            * projection.size.height * 0.004
        Image("HoneyWorldBackground")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: projection.size.width, height: projection.size.height)
            .scaleEffect(1.055)
            .offset(x: curveParallax, y: verticalParallax)
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.44),
                        .init(color: Color(red: 0.04, green: 0.13, blue: 0.055).opacity(0.08),
                              location: 0.78),
                        .init(color: Color.black.opacity(0.20), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
    }
}

/// Sky, a soft rainbow and two ridges of mountains, so the river can vanish
/// into a valley instead of filling the screen as a blue wall.
private struct RiverSky: View {
    let projection: RiverProjection

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.55, green: 0.82, blue: 0.98),
                        Color(red: 0.72, green: 0.90, blue: 1.0),
                        Color(red: 0.40, green: 0.78, blue: 0.96)
                    ]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: projection.horizonY + size.height * 0.12)
                )
            )

            let horizon = projection.horizonY
            let cx = size.width * 0.5

            // Soft cloud banks break up the flat sky without competing with
            // the track. Repeated overlapping ellipses are cheap and retain
            // the rounded illustrated language of the reference art.
            for cloud in 0..<5 {
                let baseX = size.width * (0.08 + CGFloat(cloud) * 0.22)
                let baseY = size.height * (0.035 + CGFloat(cloud % 2) * 0.035)
                let cloudScale = 0.72 + CGFloat((cloud * 7) % 4) * 0.12
                for puff in 0..<4 {
                    let w = (48 + CGFloat(puff % 2) * 22) * cloudScale
                    let h = w * 0.48
                    let rect = CGRect(x: baseX + CGFloat(puff) * 24 * cloudScale - w / 2,
                                      y: baseY + CGFloat(puff % 2) * 8 - h / 2,
                                      width: w, height: h)
                    context.fill(Path(ellipseIn: rect),
                                 with: .color(Color.white.opacity(0.34 - Double(puff) * 0.035)))
                }
            }

            // Rainbow sits in the sky, behind the ridges.
            for (i, alpha) in [0.22, 0.16, 0.12, 0.10, 0.08].enumerated() {
                let inset = CGFloat(i) * 7
                var bow = Path()
                bow.addArc(center: CGPoint(x: cx, y: horizon + size.height * 0.18),
                           radius: size.width * 0.42 - inset,
                           startAngle: .degrees(200),
                           endAngle: .degrees(340),
                           clockwise: false)
                let hues: [Color] = [
                    Color(red: 1, green: 0.45, blue: 0.45),
                    Color(red: 1, green: 0.72, blue: 0.28),
                    Color(red: 0.98, green: 0.92, blue: 0.35),
                    Color(red: 0.45, green: 0.85, blue: 0.45),
                    Color(red: 0.40, green: 0.65, blue: 1.0)
                ]
                context.stroke(bow,
                               with: .color(hues[i].opacity(alpha)),
                               style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }

            var far = Path()
            far.move(to: CGPoint(x: 0, y: horizon + 8))
            far.addLine(to: CGPoint(x: size.width * 0.12, y: horizon - size.height * 0.07))
            far.addLine(to: CGPoint(x: size.width * 0.28, y: horizon + 4))
            far.addLine(to: CGPoint(x: size.width * 0.48, y: horizon - size.height * 0.11))
            far.addLine(to: CGPoint(x: size.width * 0.66, y: horizon + 2))
            far.addLine(to: CGPoint(x: size.width * 0.84, y: horizon - size.height * 0.08))
            far.addLine(to: CGPoint(x: size.width, y: horizon + 6))
            far.addLine(to: CGPoint(x: size.width, y: horizon + size.height * 0.08))
            far.addLine(to: CGPoint(x: 0, y: horizon + size.height * 0.08))
            far.closeSubpath()
            context.fill(far, with: .color(Color(red: 0.42, green: 0.62, blue: 0.78).opacity(0.85)))

            var near = Path()
            near.move(to: CGPoint(x: 0, y: horizon + 18))
            near.addLine(to: CGPoint(x: size.width * 0.18, y: horizon - size.height * 0.03))
            near.addLine(to: CGPoint(x: size.width * 0.38, y: horizon + 14))
            near.addLine(to: CGPoint(x: size.width * 0.62, y: horizon + 10))
            near.addLine(to: CGPoint(x: size.width * 0.82, y: horizon - size.height * 0.02))
            near.addLine(to: CGPoint(x: size.width, y: horizon + 16))
            near.addLine(to: CGPoint(x: size.width, y: horizon + size.height * 0.10))
            near.addLine(to: CGPoint(x: 0, y: horizon + size.height * 0.10))
            near.closeSubpath()
            context.fill(near, with: .color(Color(red: 0.30, green: 0.50, blue: 0.62).opacity(0.70)))

            for cluster in 0..<9 {
                let x = CGFloat(cluster) / 8 * size.width
                let y = horizon + size.height * (0.055 + CGFloat(cluster % 3) * 0.012)
                let radius = size.width * (0.035 + CGFloat((cluster * 5) % 3) * 0.008)
                context.fill(Path(ellipseIn: CGRect(x: x - radius,
                                                    y: y - radius * 0.75,
                                                    width: radius * 2,
                                                    height: radius * 1.45)),
                             with: .color(Color(red: 0.23, green: 0.48, blue: 0.29).opacity(0.70)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct RiverWater: View {
    let clock: Double
    let scroll: CGFloat
    let calmness: CGFloat
    let current: CGFloat
    let boatLateral: CGFloat
    let entrance: CGFloat
    let pots: [RiverPot]
    let reelLift: CGFloat
    let quality: HoneySlideVisualQuality
    let projection: RiverProjection

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, _ in
#if DEBUG
            let generationMeasurement = HoneySlideProfiler.beginTrackGeneration()
#endif
            let slices = makeTrackSlices(quality: quality)
            let geometry = makeTrackGeometry(slices: slices)
#if DEBUG
            HoneySlideProfiler.endTrackGeneration(generationMeasurement)
            if HoneySlideDebugState.solidOpaqueTrack {
                drawSolidOpaqueDiagnostic(in: &context, slices: slices)
                if HoneySlideDebugState.enabled { drawDebug(in: &context) }
                return
            }
#endif
            drawBase(in: &context, quality: quality, geometry: geometry, slices: slices)
            drawFlowingMaterial(in: &context, quality: quality,
                                floorMask: geometry.honeyFloor)
            drawFinish(in: &context, quality: quality, slices: slices)
        }
        .frame(width: projection.size.width, height: projection.size.height)
        .clipped()
    }

    private func drawBase(in context: inout GraphicsContext,
                          quality: HoneySlideVisualQuality,
                          geometry: TrackGeometry,
                          slices: [TrackSlice]) {
        drawWoodenSupports(in: &context, quality: quality)
        drawGuaranteedOpaqueStructure(in: &context, slices: slices)
        drawTrackBody(in: &context, geometry: geometry)
        drawGuaranteedOpaqueFloor(in: &context, slices: slices)
        drawCenterGlow(in: &context, path: geometry.centerGlow)
    }

    /// Every body quad gets an un-antialiased alpha-1 base before its decorative
    /// gradient. This prevents sub-pixel scenery seams between adjacent slices.
    private func drawGuaranteedOpaqueStructure(in context: inout GraphicsContext,
                                               slices: [TrackSlice]) {
        guard slices.count > 1 else { return }
        let noSeams = FillStyle(eoFill: false, antialiased: false)
        for index in 0..<(slices.count - 1) {
            let aSlice = slices[index]
            let bSlice = slices[index + 1]
            if aSlice.projected.track.hasSurface
                != bSlice.projected.track.hasSurface {
                let surfaceBands = aSlice.projected.track.hasSurface
                    ? aSlice.bands : bSlice.bands
                for band in surfaceBands {
                    context.fill(endCap(band),
                                 with: .color(Color(red: 0.55, green: 0.18, blue: 0.01)),
                                 style: noSeams)
                }
                continue
            }
            guard aSlice.projected.track.hasSurface,
                  bSlice.projected.track.hasSurface else { continue }
            let matched = matchedSections(aSlice.bands, bSlice.bands)
            for bandIndex in 0..<min(matched.0.count, matched.1.count) {
                let a = matched.0[bandIndex]
                let b = matched.1[bandIndex]
                context.fill(quad(a.undersideLeft, a.undersideRight,
                                  b.undersideRight, b.undersideLeft),
                             with: .color(Color(red: 0.31, green: 0.09, blue: 0.01)),
                             style: noSeams)
                context.fill(quad(a.outerLeft, a.floorLeft,
                                  b.floorLeft, b.outerLeft),
                             with: .color(Color(red: 0.88, green: 0.35, blue: 0.01)),
                             style: noSeams)
                context.fill(quad(a.floorRight, a.outerRight,
                                  b.outerRight, b.floorRight),
                             with: .color(Color(red: 0.88, green: 0.35, blue: 0.01)),
                             style: noSeams)
            }
        }
    }

    /// Closed floor quads are submitted independently after the body. A single
    /// compound path can cancel/self-intersect when a projected curve folds
    /// over itself; drawing this alpha-1 pass last also guarantees the underbody
    /// can never bleed through the playable surface.
    private func drawGuaranteedOpaqueFloor(in context: inout GraphicsContext,
                                           slices: [TrackSlice]) {
        guard slices.count > 1 else { return }
        let floorPaint = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 1.00, green: 0.78, blue: 0.12), location: 0),
                .init(color: Color(red: 1.00, green: 0.61, blue: 0.035), location: 0.52),
                .init(color: Color(red: 0.91, green: 0.39, blue: 0.015), location: 1)
            ]),
            startPoint: CGPoint(x: projection.centerX, y: projection.horizonY),
            endPoint: CGPoint(x: projection.centerX, y: projection.size.height)
        )
        let noSeams = FillStyle(eoFill: false, antialiased: false)
        for index in 0..<(slices.count - 1) {
            let aSlice = slices[index]
            let bSlice = slices[index + 1]
            guard aSlice.projected.track.hasSurface,
                  bSlice.projected.track.hasSurface else { continue }
            let matched = matchedSections(aSlice.bands, bSlice.bands)
            for bandIndex in 0..<min(matched.0.count, matched.1.count) {
                let a = matched.0[bandIndex]
                let b = matched.1[bandIndex]
                context.fill(quad(a.floorLeft, a.floorRight,
                                  b.floorRight, b.floorLeft),
                             with: floorPaint,
                             style: noSeams)
            }
        }
    }

#if DEBUG
    /// Intentionally plain diagnostic: every structural quad is submitted
    /// individually at alpha 1, with no texture, highlight or blend layer.
    /// If scenery is visible here, the fault is topology/range—not material.
    private func drawSolidOpaqueDiagnostic(in context: inout GraphicsContext,
                                           slices: [TrackSlice]) {
        guard slices.count > 1 else { return }
        let noSeams = FillStyle(eoFill: false, antialiased: false)
        for index in 0..<(slices.count - 1) {
            let aSlice = slices[index]
            let bSlice = slices[index + 1]
            if aSlice.projected.track.hasSurface
                != bSlice.projected.track.hasSurface {
                let surfaceBands = aSlice.projected.track.hasSurface
                    ? aSlice.bands : bSlice.bands
                for band in surfaceBands {
                    context.fill(endCap(band),
                                 with: .color(Color(red: 0.55, green: 0.18, blue: 0.01)),
                                 style: noSeams)
                }
                continue
            }
            guard aSlice.projected.track.hasSurface,
                  bSlice.projected.track.hasSurface else { continue }
            let matched = matchedSections(aSlice.bands, bSlice.bands)
            for bandIndex in 0..<min(matched.0.count, matched.1.count) {
                let a = matched.0[bandIndex]
                let b = matched.1[bandIndex]
                context.fill(quad(a.undersideLeft, a.undersideRight,
                                  b.undersideRight, b.undersideLeft),
                             with: .color(Color(red: 0.31, green: 0.09, blue: 0.01)),
                             style: noSeams)
                context.fill(quad(a.outerLeft, a.floorLeft,
                                  b.floorLeft, b.outerLeft),
                             with: .color(Color(red: 0.88, green: 0.35, blue: 0.01)),
                             style: noSeams)
                context.fill(quad(a.floorRight, a.outerRight,
                                  b.outerRight, b.floorRight),
                             with: .color(Color(red: 0.88, green: 0.35, blue: 0.01)),
                             style: noSeams)
                context.fill(quad(a.floorLeft, a.floorRight,
                                  b.floorRight, b.floorLeft),
                             with: .color(Color(red: 1.00, green: 0.68, blue: 0.02)),
                             style: noSeams)
            }
        }
    }
#endif

    private func drawFinish(in context: inout GraphicsContext,
                            quality: HoneySlideVisualQuality,
                            slices: [TrackSlice]) {
        let wild = 1 - calmness
        drawFlowHighlights(in: &context, wild: wild, quality: quality)
        drawRailings(in: &context, slices: slices)
        drawSplitNoses(in: &context, slices: slices)
        drawHoneyfalls(in: &context, slices: slices)
        drawHangingShadows(in: &context)
        drawBoatWake(in: &context, wild: wild)
        drawHorizonMist(in: &context)
#if DEBUG
        if HoneySlideDebugState.enabled { drawDebug(in: &context) }
#endif
    }

    private func drawHorizonMist(in context: inout GraphicsContext) {
        let height = projection.size.height * 0.12
        let rect = CGRect(x: 0,
                          y: projection.horizonY - height * 0.52,
                          width: projection.size.width,
                          height: height)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.11), location: 0),
                .init(color: Color(red: 0.72, green: 0.90, blue: 0.96).opacity(0.07),
                      location: 0.48),
                .init(color: .clear, location: 1)
            ]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
    }

    private func drawFlowingMaterial(in context: inout GraphicsContext,
                                     quality: HoneySlideVisualQuality,
                                     floorMask: Path) {
        // Keep the generated square material square in screen space; stretching
        // it to portrait made bubbles and swirls look artificially elongated.
        let tile = max(280, projection.size.width * 1.06,
                       quality == .constrained ? projection.size.height * 0.51 : 0)
        let flow = cycle(scroll * 4.2 + CGFloat(clock) * 7.0, tile)
        let x = (projection.size.width - tile) * 0.5
        var materialContext = context
        materialContext.clip(to: floorMask)
        materialContext.opacity = quality.materialOpacity
        materialContext.blendMode = .softLight
        let texture = materialContext.resolve(Image("HoneySurfaceMaterial"))
        for index in 0..<quality.materialTileCount {
            let y = -tile + flow + CGFloat(index) * tile
            materialContext.draw(texture, in: CGRect(x: x, y: y, width: tile, height: tile))
        }
    }

    private struct TrackBandSection {
        let outerLeft: CGPoint
        let floorLeft: CGPoint
        let floorRight: CGPoint
        let outerRight: CGPoint
        let undersideLeft: CGPoint
        let undersideRight: CGPoint
    }

    private struct TrackSlice {
        let travel: CGFloat
        let projected: RiverProjection.ProjectedTrackSample
        let bands: [TrackBandSection]
    }

    private struct TrackGeometry {
        var underbody = Path()
        var endCaps = Path()
        var leftWalls = Path()
        var rightWalls = Path()
        var honeyFloor = Path()
        var centerGlow = Path()
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }

    /// When a normal channel becomes two branches (or two merge back into
    /// one), map each branch to the corresponding half of the single channel.
    /// Repeating the whole single section for both branches produced the old
    /// X-shaped overlap and visible crossbar at the transition.
    private func splitSection(_ section: TrackBandSection) -> [TrackBandSection] {
        let outerCenter = midpoint(section.outerLeft, section.outerRight)
        let floorCenter = midpoint(section.floorLeft, section.floorRight)
        let undersideCenter = midpoint(section.undersideLeft, section.undersideRight)
        return [
            TrackBandSection(outerLeft: section.outerLeft,
                             floorLeft: section.floorLeft,
                             floorRight: floorCenter,
                             outerRight: outerCenter,
                             undersideLeft: section.undersideLeft,
                             undersideRight: undersideCenter),
            TrackBandSection(outerLeft: outerCenter,
                             floorLeft: floorCenter,
                             floorRight: section.floorRight,
                             outerRight: section.outerRight,
                             undersideLeft: undersideCenter,
                             undersideRight: section.undersideRight)
        ]
    }

    private func matchedSections(_ a: [TrackBandSection],
                                 _ b: [TrackBandSection])
    -> ([TrackBandSection], [TrackBandSection]) {
        if a.count == b.count { return (a, b) }
        if a.count == 1, b.count == 2 { return (splitSection(a[0]), b) }
        if a.count == 2, b.count == 1 { return (a, splitSection(b[0])) }
        return (a, b)
    }

    private func trackSlice(at travel: CGFloat) -> TrackSlice {
        let projected = projection.projectedSample(for: travel)
        let sample = projected.track
        let near = projected.nearness
        let perspective = projected.scale
        let bands = projected.bandEdges.map { band in
            let span = max(1, band.right - band.left)
            let inset = span * (0.090 + 0.030 * near)
            let depth = (7 + 20 * near) * perspective
                * (sample.troughDepth / 0.10)
            let fullLeft = projected.center - projected.halfWidth
            let fullSpan = max(1, projected.halfWidth * 2)
            let leftT = min(1, max(0, (band.left - fullLeft) / fullSpan))
            let rightT = min(1, max(0, (band.right - fullLeft) / fullSpan))
            let leftY = projected.leftEdgeY
                + (projected.rightEdgeY - projected.leftEdgeY) * leftT
            let rightY = projected.leftEdgeY
                + (projected.rightEdgeY - projected.leftEdgeY) * rightT
            let thickness = (3 + 7 * near) * perspective
            return TrackBandSection(
                outerLeft: CGPoint(x: band.left, y: leftY),
                floorLeft: CGPoint(x: band.left + inset, y: leftY + depth),
                floorRight: CGPoint(x: band.right - inset, y: rightY + depth),
                outerRight: CGPoint(x: band.right, y: rightY),
                undersideLeft: CGPoint(x: band.left, y: leftY + depth + thickness),
                undersideRight: CGPoint(x: band.right, y: rightY + depth + thickness)
            )
        }
        return TrackSlice(travel: travel, projected: projected, bands: bands)
    }

    private func sections(at travel: CGFloat) -> [TrackBandSection] {
        trackSlice(at: travel).bands
    }

    private func makeTrackSlices(quality: HoneySlideVisualQuality) -> [TrackSlice] {
        let steps = quality.floorSteps
        let far = projection.renderFarTravel
        let near = projection.renderNearTravel
        return (0...steps).map { index in
            // Quadratic spacing spends most topology close to the camera,
            // where seams and silhouette changes have the most screen area.
            // The analytical route is already ready 15 seconds ahead, so this
            // is projection only—no synchronous segment creation occurs here.
            let progress = CGFloat(index) / CGFloat(steps)
            let distanceShare = pow(1 - progress, 2.15)
            let travel = near + (far - near) * distanceShare
            return trackSlice(at: travel)
        }
    }

    private func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        path.addLine(to: c)
        path.addLine(to: d)
        path.closeSubpath()
        return path
    }

    /// A real cross-section at a surface/gap boundary. Without this face the
    /// slide ended as four unrelated strips, so the scenery could be seen
    /// through the trough and the jump read as a stack of thin rectangles.
    private func endCap(_ band: TrackBandSection) -> Path {
        quad(band.outerLeft, band.outerRight,
             band.undersideRight, band.undersideLeft)
    }

    private func makeTrackGeometry(slices: [TrackSlice]) -> TrackGeometry {
        var geometry = TrackGeometry()
        guard slices.count > 1 else { return geometry }
        for index in 0..<(slices.count - 1) {
            let aSlice = slices[index]
            let bSlice = slices[index + 1]
            if aSlice.projected.track.hasSurface
                != bSlice.projected.track.hasSurface {
                let surfaceBands = aSlice.projected.track.hasSurface
                    ? aSlice.bands : bSlice.bands
                for band in surfaceBands {
                    geometry.endCaps.addPath(endCap(band))
                }
                continue
            }
            guard aSlice.projected.track.hasSurface,
                  bSlice.projected.track.hasSurface else { continue }
            let matched = matchedSections(aSlice.bands, bSlice.bands)
            let aBands = matched.0
            let bBands = matched.1
            let count = min(aBands.count, bBands.count)
            for bandIndex in 0..<count {
                let a = aBands[bandIndex]
                let b = bBands[bandIndex]
                geometry.underbody.addPath(quad(a.undersideLeft, a.undersideRight,
                                                b.undersideRight, b.undersideLeft))
                geometry.leftWalls.addPath(quad(a.outerLeft, a.floorLeft,
                                                b.floorLeft, b.outerLeft))
                geometry.rightWalls.addPath(quad(a.floorRight, a.outerRight,
                                                 b.outerRight, b.floorRight))
                geometry.honeyFloor.addPath(quad(a.floorLeft, a.floorRight,
                                                 b.floorRight, b.floorLeft))

                let aLeft = a.floorLeft.x + (a.floorRight.x - a.floorLeft.x) * 0.30
                let aRight = a.floorLeft.x + (a.floorRight.x - a.floorLeft.x) * 0.70
                let bLeft = b.floorLeft.x + (b.floorRight.x - b.floorLeft.x) * 0.30
                let bRight = b.floorLeft.x + (b.floorRight.x - b.floorLeft.x) * 0.70
                geometry.centerGlow.addPath(quad(
                    CGPoint(x: aLeft, y: (a.floorLeft.y + a.floorRight.y) * 0.5),
                    CGPoint(x: aRight, y: (a.floorLeft.y + a.floorRight.y) * 0.5),
                    CGPoint(x: bRight, y: (b.floorLeft.y + b.floorRight.y) * 0.5),
                    CGPoint(x: bLeft, y: (b.floorLeft.y + b.floorRight.y) * 0.5)
                ))
            }
        }
        return geometry
    }

    private func drawTrackBody(in context: inout GraphicsContext,
                               geometry: TrackGeometry) {
        context.fill(geometry.underbody, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.50, green: 0.22, blue: 0.045),
                Color(red: 0.31, green: 0.095, blue: 0.018)
            ]),
            startPoint: CGPoint(x: projection.centerX, y: projection.horizonY),
            endPoint: CGPoint(x: projection.centerX, y: projection.size.height)
        ))
        context.fill(geometry.endCaps, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.92, green: 0.39, blue: 0.018),
                Color(red: 0.39, green: 0.12, blue: 0.014)
            ]),
            startPoint: CGPoint(x: projection.centerX, y: projection.horizonY),
            endPoint: CGPoint(x: projection.centerX, y: projection.size.height)
        ))
        context.fill(geometry.leftWalls, with: .linearGradient(
            Gradient(colors: [RiverPaint.body, RiverPaint.trough]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: projection.size.width, y: 0)
        ))
        context.fill(geometry.rightWalls, with: .linearGradient(
            Gradient(colors: [RiverPaint.trough, RiverPaint.body]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: projection.size.width, y: 0)
        ))
    }

    private func drawCenterGlow(in context: inout GraphicsContext, path: Path) {
        context.fill(path, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.10), RiverPaint.gloss.opacity(0.28),
                              Color.white.opacity(0.06)]),
            startPoint: CGPoint(x: projection.size.width * 0.22, y: 0),
            endPoint: CGPoint(x: projection.size.width * 0.78, y: 0)
        ))
    }

    private func drawFlowHighlights(in context: inout GraphicsContext,
                                    wild: CGFloat,
                                    quality: HoneySlideVisualQuality) {
        let count = quality.highlightCount
        for index in 0..<count {
            let seed = hash(index, 211)
            let moving = cycle(scroll / HoneySlideTuning.cameraLookAheadDistance(
                for: HoneySlideTuning.nominalSlideSpeed) * 1.42
                               + seed * 1.45, 1.48)
            let travel = 1.20 - moving
            let sample = projection.sample(for: travel)
            guard sample.hasSurface else { continue }
            let across = 0.14 + hash(index, 212) * 0.72
            let bands = sections(at: travel)
            let band = bands[index % bands.count]
            let x = band.floorLeft.x + (band.floorRight.x - band.floorLeft.x) * across
            let y = band.floorLeft.y + (band.floorRight.y - band.floorLeft.y) * across
            let near = projection.nearness(for: travel)
            let scale = projection.scale(for: travel)
            let width = (18 + 42 * near) * scale * (0.7 + hash(index, 213) * 0.7)
            let height = max(2, width * (0.11 + near * 0.08))
            let pulse = 0.72 + 0.28 * CGFloat(sin(clock * 2.2 + Double(index))) * wild
            let rect = CGRect(x: x - width / 2, y: y - height / 2,
                              width: width, height: height * pulse)
            context.fill(Path(ellipseIn: rect),
                         with: .color(RiverPaint.gloss.opacity(0.22 + 0.30 * Double(near))))
            if index % 5 == 0, near > 0.28 {
                let bubble = CGRect(x: x + width * 0.22, y: y - height * 0.9,
                                    width: height * 0.65, height: height * 0.48)
                context.stroke(Path(ellipseIn: bubble),
                               with: .color(Color.white.opacity(0.38)),
                               style: StrokeStyle(lineWidth: max(0.8, scale)))
            }
        }
    }

    private func drawFlowRibbons(in context: inout GraphicsContext, tight: Bool) {
        let count = tight ? 10 : 16
        for index in 0..<count {
            let seed = hash(index, 330)
            let head = 1.20 - cycle(scroll / HoneySlideTuning.cameraLookAheadDistance(
                for: HoneySlideTuning.nominalSlideSpeed) * 1.22
                                    + seed * 1.48, 1.52)
            let length = 0.09 + hash(index, 331) * 0.16
            let across = 0.12 + hash(index, 332) * 0.76
            var ribbon = Path()
            var started = false
            for step in 0...7 {
                let travel = head + CGFloat(step) / 7 * length
                let sample = projection.sample(for: travel)
                guard sample.hasSurface else {
                    started = false
                    continue
                }
                let bands = sections(at: travel)
                guard !bands.isEmpty else { continue }
                let band = bands[index % bands.count]
                let wave = CGFloat(sin(Double(step) * 0.65 + Double(index))) * 0.018
                let t = min(0.9, max(0.1, across + wave))
                let point = CGPoint(
                    x: band.floorLeft.x + (band.floorRight.x - band.floorLeft.x) * t,
                    y: band.floorLeft.y + (band.floorRight.y - band.floorLeft.y) * t
                )
                if started { ribbon.addLine(to: point) }
                else {
                    ribbon.move(to: point)
                    started = true
                }
            }
            let near = projection.nearness(for: head)
            let width = max(1, (1.2 + 3.8 * near) * projection.scale(for: head))
            context.stroke(ribbon, with: .color(Color(red: 0.70, green: 0.25, blue: 0.01).opacity(0.20)),
                           style: StrokeStyle(lineWidth: width * 2.8, lineCap: .round))
            context.stroke(ribbon, with: .color(RiverPaint.gloss.opacity(0.56)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    private func drawRailings(in context: inout GraphicsContext,
                              slices: [TrackSlice]) {
        guard slices.count > 1 else { return }
        for index in 0..<(slices.count - 1) {
            let aSlice = slices[index]
            let bSlice = slices[index + 1]
            let aSample = aSlice.projected.track
            let bSample = bSlice.projected.track
            guard aSample.hasSurface, bSample.hasSurface else { continue }
            let detailScale = min(aSlice.projected.scale, bSlice.projected.scale)
            guard detailScale > 0.105 else { continue }
            let railPresence = (aSample.railVisibility + bSample.railVisibility) * 0.5
            guard railPresence > 0.015 else { continue }
            let matched = matchedSections(aSlice.bands, bSlice.bands)
            let aBands = matched.0
            let bBands = matched.1
            let count = min(aBands.count, bBands.count)
            for bandIndex in 0..<count {
                let a = aBands[bandIndex]
                let b = bBands[bandIndex]
                for side in 0...1 {
                    var start = side == 0 ? a.outerLeft : a.outerRight
                    var end = side == 0 ? b.outerLeft : b.outerRight
                    let isInnerRail = count == 2
                        && ((bandIndex == 0 && side == 1) || (bandIndex == 1 && side == 0))
                    let innerFactorA: CGFloat = isInnerRail
                        ? pow(aSample.splitAmount, 0.85) : 1
                    let innerFactorB: CGFloat = isInnerRail
                        ? pow(bSample.splitAmount, 0.85) : 1
                    let liftA = (2 + 9 * aSlice.projected.nearness)
                        * aSlice.projected.scale * (aSample.railHeight / 0.13)
                        * innerFactorA * aSample.railVisibility
                    let liftB = (2 + 9 * bSlice.projected.nearness)
                        * bSlice.projected.scale * (bSample.railHeight / 0.13)
                        * innerFactorB * bSample.railVisibility
                    start.y -= liftA
                    end.y -= liftB
                    var rail = Path()
                    rail.move(to: start)
                    rail.addLine(to: end)
                    let dividerWidth = isInnerRail ? max(0.12, innerFactorB) : 1
                    let width = max(isInnerRail ? 0.22 : 0.48,
                                    (3 + 7 * bSlice.projected.nearness)
                                    * bSlice.projected.scale * dividerWidth
                                    * max(0.16, railPresence))
                    context.stroke(rail, with: .color(Color.black.opacity(0.34 * Double(railPresence))),
                                   style: StrokeStyle(lineWidth: width * 1.72,
                                                      lineCap: .round, lineJoin: .round))
                    context.stroke(rail, with: .color(Color(red: 0.72, green: 0.28, blue: 0.015)
                        .opacity(Double(railPresence))),
                                   style: StrokeStyle(lineWidth: width * 1.42,
                                                      lineCap: .round, lineJoin: .round))
                    context.stroke(rail, with: .color(Color(red: 1.00, green: 0.64, blue: 0.035)
                        .opacity(Double(railPresence))),
                                   style: StrokeStyle(lineWidth: width,
                                                      lineCap: .round, lineJoin: .round))
                    let shine = rail.applying(CGAffineTransform(translationX: 0,
                                                                y: -width * 0.20))
                    context.stroke(shine, with: .color(Color(red: 1.0, green: 0.94, blue: 0.48)
                        .opacity(0.82 * Double(railPresence))),
                                   style: StrokeStyle(lineWidth: max(0.8, width * 0.28),
                                                      lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func drawWoodenSupports(in context: inout GraphicsContext,
                                    quality: HoneySlideVisualQuality) {
        let count = quality.supportCount
        for index in 0..<count {
            let share = CGFloat(index) / CGFloat(max(1, count - 1))
            let travel = 1.34 - share * 1.40
            let slice = trackSlice(at: travel)
            let sample = slice.projected.track
            guard sample.hasSurface, sample.kind != .landing,
                  slice.projected.scale > 0.15 else { continue }
            let y = slice.projected.y
            let drop = (24 + 54 * slice.projected.nearness) * slice.projected.scale
            let inset = max(2, 5 * slice.projected.scale)
            for band in slice.bands {
                let left = band.outerLeft.x + inset
                let right = band.outerRight.x - inset
                for x in [left, right] {
                    var post = Path()
                    post.move(to: CGPoint(x: x, y: y + 3))
                    post.addLine(to: CGPoint(x: x, y: y + drop))
                    context.stroke(post, with: .color(Color.black.opacity(0.30)),
                                   style: StrokeStyle(lineWidth: max(0.7, 6 * slice.projected.scale),
                                                      lineCap: .round))
                    context.stroke(post, with: .color(RiverPaint.wood.opacity(0.70)),
                                   style: StrokeStyle(lineWidth: max(0.45, 4 * slice.projected.scale),
                                                      lineCap: .round))
                }
                var crossBeam = Path()
                crossBeam.move(to: CGPoint(x: left, y: y + drop * 0.45))
                crossBeam.addLine(to: CGPoint(x: right, y: y + drop * 0.45))
                context.stroke(crossBeam, with: .color(Color.black.opacity(0.24)),
                               style: StrokeStyle(lineWidth: max(0.6, 5 * slice.projected.scale),
                                                  lineCap: .round))
                context.stroke(crossBeam, with: .color(RiverPaint.wood.opacity(0.62)),
                               style: StrokeStyle(lineWidth: max(0.4, 3 * slice.projected.scale),
                                                  lineCap: .round))
                var brace = Path()
                brace.move(to: CGPoint(x: left, y: y + drop))
                brace.addLine(to: CGPoint(x: right, y: y + 4))
                context.stroke(brace, with: .color(RiverPaint.lightWood.opacity(0.52)),
                               style: StrokeStyle(lineWidth: max(1, 2.5 * slice.projected.scale)))
            }
        }
    }

    private func drawSplitNoses(in context: inout GraphicsContext,
                                slices: [TrackSlice]) {
        guard slices.count > 1 else { return }
        for index in 0..<(slices.count - 1) {
            let aSections = slices[index].bands
            let bSections = slices[index + 1].bands
            guard aSections.count != bSections.count else { continue }
            let splitSlice = aSections.count == 2 ? slices[index] : slices[index + 1]
            let branches = aSections.count == 2 ? aSections : bSections
            guard branches.count == 2 else { continue }
            let leftTip = branches[0].outerRight
            let rightTip = branches[1].outerLeft
            let center = midpoint(leftTip, rightTip)
            let scale = splitSlice.projected.scale
            let radius = max(1.8, (3.4 + 5 * splitSlice.projected.nearness) * scale)
            let shadowRect = CGRect(x: center.x - radius * 1.22,
                                    y: center.y - radius * 0.72,
                                    width: radius * 2.44,
                                    height: radius * 1.70)
            context.fill(Path(ellipseIn: shadowRect),
                         with: .color(Color(red: 0.34, green: 0.09, blue: 0.01).opacity(0.88)))
            let capRect = shadowRect.insetBy(dx: radius * 0.28, dy: radius * 0.24)
            context.fill(Path(ellipseIn: capRect),
                         with: .color(Color(red: 0.98, green: 0.54, blue: 0.02)))
            let glint = CGRect(x: capRect.minX + capRect.width * 0.20,
                               y: capRect.minY + capRect.height * 0.12,
                               width: capRect.width * 0.42,
                               height: max(0.8, capRect.height * 0.18))
            context.fill(Path(ellipseIn: glint),
                         with: .color(Color(red: 1.0, green: 0.91, blue: 0.35).opacity(0.84)))
        }
    }

    private func drawHoneyfalls(in context: inout GraphicsContext,
                                slices: [TrackSlice]) {
        guard slices.count > 1 else { return }
        for index in 0..<(slices.count - 1) {
            let here = slices[index]
            let there = slices[index + 1]
            guard here.projected.track.hasSurface != there.projected.track.hasSurface else { continue }
            let edge = here.projected.track.hasSurface ? here : there
            guard edge.projected.scale > 0.14 else { continue }
            for band in edge.bands {
                let left = band.outerLeft
                let right = band.outerRight
                let y = (left.y + right.y) * 0.5
                let drip = 14 + 48 * edge.projected.nearness
                for strand in 0..<5 {
                    let t = CGFloat(strand) / 4
                    let x = left.x + (right.x - left.x) * t
                    var fall = Path()
                    fall.move(to: CGPoint(x: x, y: y))
                    fall.addCurve(to: CGPoint(x: x + CGFloat(strand - 2) * 1.5, y: y + drip),
                                  control1: CGPoint(x: x + 3, y: y + drip * 0.35),
                                  control2: CGPoint(x: x - 2, y: y + drip * 0.72))
                    context.stroke(fall, with: .color(RiverPaint.body.opacity(0.72)),
                                   style: StrokeStyle(lineWidth: max(1.2, 3 * edge.projected.scale),
                                                      lineCap: .round))
                }

                // A layered rounded lip hides the polygon edge and makes the
                // take-off and landing read like one thick, viscous material.
                let scale = edge.projected.scale
                let width = max(1.5, (2.4 + 4.4 * edge.projected.nearness) * scale)
                let bulge = max(1.5, width * 0.34)
                var lip = Path()
                lip.move(to: left)
                lip.addQuadCurve(to: right,
                                 control: CGPoint(x: (left.x + right.x) * 0.5,
                                                  y: y + bulge))
                context.stroke(lip, with: .color(Color(red: 0.27, green: 0.075, blue: 0.015)
                    .opacity(0.88)),
                               style: StrokeStyle(lineWidth: width * 1.55,
                                                  lineCap: .round, lineJoin: .round))
                context.stroke(lip, with: .color(Color(red: 0.88, green: 0.35, blue: 0.01)),
                               style: StrokeStyle(lineWidth: width * 1.14,
                                                  lineCap: .round, lineJoin: .round))
                let highlight = lip.applying(CGAffineTransform(translationX: 0,
                                                               y: -width * 0.22))
                context.stroke(highlight,
                               with: .color(Color(red: 1.0, green: 0.84, blue: 0.22).opacity(0.92)),
                               style: StrokeStyle(lineWidth: max(0.9, width * 0.34),
                                                  lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func mix(_ a: Color, _ b: Color, amount: Double) -> Color {
        // Explicit RGB values keep this hot drawing loop away from UIColor
        // conversion and make the interpolation deterministic on every target.
        let t = min(max(amount, 0), 1)
        return Color(red: 1.00 + (0.82 - 1.00) * t,
                     green: 0.73 + (0.30 - 0.73) * t,
                     blue: 0.16 + (0.018 - 0.16) * t)
    }

#if DEBUG
    private func drawDebug(in context: inout GraphicsContext) {
        var center = Path()
        var previousSegment: String?
        for index in 0...120 {
            let progress = CGFloat(index) / 120
            let travel = projection.renderFarTravel
                + (projection.renderNearTravel - projection.renderFarTravel) * progress
            let point = projection.point(lateral: 0, travel: travel)
            if index == 0 { center.move(to: point) } else { center.addLine(to: point) }
            let sample = projection.sample(for: travel)
            if let previousSegment, previousSegment != sample.segmentID,
               point.x > -20, point.x < projection.size.width + 20,
               point.y > -20, point.y < projection.size.height + 20 {
                let marker = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: marker),
                             with: .color(Color(red: 1, green: 0.12, blue: 0.72).opacity(0.90)))
            }
            previousSegment = sample.segmentID
        }
        context.stroke(center, with: .color(.cyan.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        let player = projection.point(lateral: 0, travel: 0)
        context.stroke(Path(ellipseIn: CGRect(x: player.x - 6, y: player.y - 6,
                                              width: 12, height: 12)),
                       with: .color(.green.opacity(0.95)),
                       style: StrokeStyle(lineWidth: 2))
    }
#endif

    /// A sheet of sky lying on the far water, so the surface reads as liquid
    /// rather than as a painted floor.
    private func drawSkyReflection(in context: inout GraphicsContext, size: CGSize) {
        let height = max(1, projection.boatY - projection.horizonY)
        let sheen = Path(CGRect(x: 0, y: projection.horizonY, width: size.width, height: height * 0.55))
        context.fill(sheen, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)]),
            startPoint: CGPoint(x: size.width / 2, y: projection.horizonY),
            endPoint: CGPoint(x: size.width / 2, y: projection.horizonY + height * 0.55)
        ))
    }

    private func drawBankShadow(in context: inout GraphicsContext) {
        for side in [0, 1] {
            var strip = Path()
            let inner: CGFloat = side == 0 ? 0.16 : 0.84
            let outer: CGFloat = side == 0 ? 0.0 : 1.0
            let steps = 14
            for i in 0...steps {
                let travel = 1.16 - CGFloat(i) / CGFloat(steps) * 1.60
                let p = projection.pointAcross(outer, travel: travel)
                if i == 0 { strip.move(to: p) } else { strip.addLine(to: p) }
            }
            for i in (0...steps).reversed() {
                let travel = 1.16 - CGFloat(i) / CGFloat(steps) * 1.60
                strip.addLine(to: projection.pointAcross(inner, travel: travel))
            }
            strip.closeSubpath()
            context.fill(strip, with: .color(RiverPaint.edge.opacity(0.42)))
        }
    }

    /// Water is a ground plane. A ripple on that plane is a wide, flat oval
    /// that grows as it comes toward the boat — not a stripe, not a line
    /// aimed at the horizon. Overlapping ovals are the surface; their drift
    /// is the current.
    private func drawSurface(in context: inout GraphicsContext,
                             wild: CGFloat,
                             flow: CGFloat,
                             tight: Bool) {
        drawRipples(in: &context, count: tight ? 28 : 42, speed: 0.40 * flow,
                    wild: wild, foamChance: 0.18)
        drawRipples(in: &context, count: tight ? 18 : 28, speed: 0.62 * flow,
                    wild: wild, foamChance: 0.32, salt: 91)
    }

    private func drawRipples(in context: inout GraphicsContext,
                             count: Int,
                             speed: CGFloat,
                             wild: CGFloat,
                             foamChance: CGFloat,
                             salt: Int = 0) {
        for i in 0..<count {
            let along = cycle(scroll * speed + hash(i, 1 + salt) * 1.55, 1.58)
            let travel = 1.18 - along
            guard travel > -0.18, travel < 1.22 else { continue }
            let across = 0.11 + hash(i, 2 + salt) * 0.78
            let near = projection.nearness(for: travel)
            let s = projection.scale(for: travel)
            var p = projection.pointAcross(across, travel: travel)
            p.y += CGFloat(sin(clock * 1.35 + Double(i) * 0.6)) * 2.4 * s * wild

            // Foreshortening: a round patch on the water is much wider than
            // it is tall, and only opens up a little as it reaches the boat.
            let w = (22 + 48 * near) * s * (0.80 + hash(i, 3 + salt) * 0.55)
            let h = w * (0.18 + 0.16 * near)
            let trough = CGRect(x: p.x - w / 2, y: p.y - h * 0.35, width: w, height: h)
            context.fill(Path(ellipseIn: trough),
                         with: .color(RiverPaint.trough.opacity(0.10 + 0.12 * Double(near))))

            let face = CGRect(x: p.x - w * 0.42, y: p.y + h * 0.05, width: w * 0.84, height: h * 0.55)
            context.fill(Path(ellipseIn: face),
                         with: .color(RiverPaint.gloss.opacity(0.10 + 0.16 * Double(near) * Double(0.5 + 0.5 * wild))))

            if hash(i, 4 + salt) < foamChance, near > 0.22 {
                let lip = CGRect(x: p.x - w * 0.28, y: p.y + h * 0.22, width: w * 0.56, height: h * 0.38)
                context.fill(Path(ellipseIn: lip),
                             with: .color(RiverPaint.foam.opacity(0.14 + 0.22 * Double(near) * Double(wild))))
            }
        }
    }

    private func hash(_ i: Int, _ salt: Int) -> CGFloat {
        let x = sin(Double(i * 19 + salt * 47) * 12.9898) * 43758.5453
        return CGFloat(x - floor(x))
    }

    /// Whitewater where the current chews the rocks — clumps on the surface,
    /// not streaks flying inland.
    private func drawBankFoam(in context: inout GraphicsContext,
                              wild: CGFloat,
                              flow: CGFloat,
                              tight: Bool) {
        let clumps = tight ? 8 : 12
        for side in [0, 1] {
            for i in 0..<clumps {
                let along = cycle(scroll * 0.8 * flow + CGFloat(i) * 0.15 + CGFloat(side) * 0.06, 1.55)
                let travel = 1.16 - along
                guard travel > -0.12, travel < 1.18 else { continue }
                let inward: CGFloat = side == 0 ? 1 : -1
                let edge = side == 0
                    ? projection.riverLeft(travel: travel)
                    : projection.riverRight(travel: travel)
                let s = projection.scale(for: travel)
                let near = projection.nearness(for: travel)
                let pulse = 0.82 + 0.18 * CGFloat(sin(clock * 2.8 + Double(i)))
                let w = (16 + 20 * near) * s * pulse
                let h = (7 + 8 * near) * s
                let p = CGPoint(x: edge + inward * (8 * s + w * 0.15), y: projection.y(for: travel))
                let rect = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
                context.fill(Path(ellipseIn: rect),
                             with: .color(RiverPaint.foam.opacity(0.22 + 0.32 * Double(wild) * Double(near))))
            }
        }
    }

    /// A flat ripple under each answer stone seats it on the water surface.
    private func drawHangingShadows(in context: inout GraphicsContext) {
        for pot in pots where !pot.hit {
            let liftFade = max(0, 1 - max(reelLift, pot.reel))
            guard liftFade > 0.04, pot.travel > -0.08, pot.travel < 1.05 else { continue }
            let p = projection.point(lateral: pot.lateral, travel: pot.travel)
            let s = projection.scale(for: pot.travel)
            let w = 26 * s * liftFade
            let h = 9 * s * liftFade
            let rect = CGRect(x: p.x - w / 2, y: p.y - h * 0.15, width: w, height: h)
            context.fill(Path(ellipseIn: rect),
                         with: .color(RiverPaint.edge.opacity(0.22 * Double(liftFade))))
        }
    }

    private func drawBoatWake(in context: inout GraphicsContext, wild: CGFloat) {
        let presence = max(0, 1 - entrance)
        guard presence > 0.04 else { return }
        let alpha = Double(presence) * (0.40 + 0.12 * Double(current) + 0.08 * Double(wild))
        for i in 0..<4 {
            let travel = -CGFloat(i) * 0.045
            let p = projection.playerSurface(lateral: boatLateral,
                                             travel: travel).contactPoint
            let s = projection.scale(for: travel)
            let w = (48 + CGFloat(i) * 22) * s
            let h = (12 + CGFloat(i) * 5) * s
            let rect = CGRect(x: p.x - w / 2, y: p.y + 4 * s, width: w, height: h)
            context.fill(Path(ellipseIn: rect),
                         with: .color(RiverPaint.foam.opacity(alpha * (0.50 - Double(i) * 0.09))))
        }

        // Two curved lips make the wake feel displaced by a heavy tube,
        // rather than four unrelated flat rings.
        let origin = projection.playerSurface(lateral: boatLateral,
                                              travel: -0.018).contactPoint
        for side: CGFloat in [-1, 1] {
            var lip = Path()
            lip.move(to: CGPoint(x: origin.x + side * 18, y: origin.y + 7))
            lip.addCurve(to: CGPoint(x: origin.x + side * 70, y: origin.y + 42),
                         control1: CGPoint(x: origin.x + side * 30, y: origin.y + 9),
                         control2: CGPoint(x: origin.x + side * 52, y: origin.y + 26))
            context.stroke(lip, with: .color(Color.white.opacity(alpha * 0.44)),
                           style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            let goldLip = lip.applying(CGAffineTransform(translationX: 0, y: 3))
            context.stroke(goldLip, with: .color(RiverPaint.foam.opacity(alpha * 0.48)),
                           style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
        }
    }

    private func cycle(_ value: CGFloat, _ span: CGFloat) -> CGFloat {
        guard span > 0 else { return 0 }
        let r = value.truncatingRemainder(dividingBy: span)
        return r >= 0 ? r : r + span
    }
}

/// Dense near foliage frames the playable lane and creates the same
/// foreground/midground separation as the painted reference. It deliberately
/// stays at the extreme sides so the steering surface remains unobstructed.
private struct HoneyWorldForeground: View {
    let clock: Double
    let projection: RiverProjection

    var body: some View {
        Canvas { context, size in
            for side in 0...1 {
                let sign: CGFloat = side == 0 ? 1 : -1
                let edgeX: CGFloat = side == 0 ? 0 : size.width

                // Warm, chunky branches beneath the leaves.
                for branch in 0..<4 {
                    let y = size.height * (0.66 + CGFloat(branch) * 0.105)
                    var path = Path()
                    path.move(to: CGPoint(x: edgeX, y: y + 52))
                    path.addCurve(to: CGPoint(x: edgeX + sign * size.width * 0.13, y: y - 12),
                                  control1: CGPoint(x: edgeX + sign * 28, y: y + 25),
                                  control2: CGPoint(x: edgeX + sign * size.width * 0.075, y: y - 4))
                    context.stroke(path, with: .color(Color(red: 0.26, green: 0.12, blue: 0.045).opacity(0.72)),
                                   style: StrokeStyle(lineWidth: 13 + CGFloat(branch) * 2,
                                                      lineCap: .round))
                    let barkLight = path.applying(CGAffineTransform(translationX: sign * 2, y: -2))
                    context.stroke(barkLight, with: .color(Color(red: 0.55, green: 0.28, blue: 0.08).opacity(0.58)),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }

                for cluster in 0..<13 {
                    let row = cluster / 4
                    let column = cluster % 4
                    let baseY = size.height * (0.57 + CGFloat(row) * 0.145)
                        + CGFloat(column % 2) * 19
                    let inset = size.width * (0.015 + CGFloat(column) * 0.035)
                    let centerX = edgeX + sign * inset
                    let radius = size.width * (0.045 + CGFloat((cluster * 7) % 4) * 0.009)
                    let sway = CGFloat(sin(clock * 0.6 + Double(cluster + side * 9))) * 1.8
                    let shadow = CGRect(x: centerX - radius * 1.12,
                                        y: baseY - radius * 0.70 + sway,
                                        width: radius * 2.24,
                                        height: radius * 1.60)
                    context.fill(Path(ellipseIn: shadow.offsetBy(dx: sign * -3, dy: 5)),
                                 with: .color(Color(red: 0.055, green: 0.16, blue: 0.055).opacity(0.88)))
                    context.fill(Path(ellipseIn: shadow), with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.37, green: 0.68, blue: 0.18),
                            Color(red: 0.10, green: 0.34, blue: 0.085)
                        ]), center: CGPoint(x: centerX - sign * radius * 0.28,
                                           y: baseY - radius * 0.30),
                        startRadius: 2, endRadius: radius * 1.25))

                    for leaf in 0..<3 {
                        let angle = Double(leaf) * 2.1 + Double(cluster) * 0.7
                        let lx = centerX + CGFloat(cos(angle)) * radius * 0.48
                        let ly = baseY + sway + CGFloat(sin(angle)) * radius * 0.32
                        let leafRect = CGRect(x: lx - radius * 0.22, y: ly - radius * 0.12,
                                              width: radius * 0.44, height: radius * 0.24)
                        context.fill(Path(ellipseIn: leafRect),
                                     with: .color(Color(red: 0.55, green: 0.79, blue: 0.23).opacity(0.66)))
                    }
                }

                // Tiny flowers and honeycomb cues give the frame the same
                // friendly crafted language as the main slide.
                for item in 0..<7 {
                    let x = edgeX + sign * size.width * (0.035 + CGFloat(item % 3) * 0.048)
                    let y = size.height * (0.71 + CGFloat(item) * 0.043)
                    let r: CGFloat = 3.2 + CGFloat(item % 2)
                    for petal in 0..<5 {
                        let angle = Double(petal) * .pi * 0.4
                        let px = x + CGFloat(cos(angle)) * r
                        let py = y + CGFloat(sin(angle)) * r
                        context.fill(Path(ellipseIn: CGRect(x: px - r * 0.58, y: py - r * 0.58,
                                                            width: r * 1.16, height: r * 1.16)),
                                     with: .color(Color.white.opacity(0.90)))
                    }
                    context.fill(Path(ellipseIn: CGRect(x: x - r * 0.55, y: y - r * 0.55,
                                                        width: r * 1.1, height: r * 1.1)),
                                 with: .color(Color(red: 1.0, green: 0.67, blue: 0.08)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct RiverBanks: View {
    let scroll: CGFloat
    let decor: [RiverDecor]
    let projection: RiverProjection
    let calmness: CGFloat

    var body: some View {
        Canvas { context, size in
            // Only the track-contact layer remains procedural. The authored
            // backdrop owns the valley, trees and landmark cliffs, eliminating
            // the visibly repetitive placeholder foliage from the previous
            // pass while the small edge rocks still scroll with gameplay.
            drawShore(side: 0, in: &context, size: size)
            drawShore(side: 1, in: &context, size: size)
            drawFalls(in: &context)
        }
    }

    /// Layered sandstone ledges and one large honey cascade establish an
    /// elevated fantasy valley instead of a flat green strip around the lane.
    private func drawMidgroundCliffs(in context: inout GraphicsContext, size: CGSize) {
        let ledges: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.00, 0.30, 0.24, 0.24),
            (0.77, 0.27, 0.23, 0.31),
            (0.00, 0.51, 0.18, 0.21),
            (0.84, 0.56, 0.16, 0.19)
        ]
        for (index, ledge) in ledges.enumerated() {
            let rect = CGRect(x: ledge.0 * size.width,
                              y: ledge.1 * size.height,
                              width: ledge.2 * size.width,
                              height: ledge.3 * size.height)
            var cliff = Path()
            cliff.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.16))
            cliff.addLine(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY))
            cliff.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.06))
            cliff.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.22))
            cliff.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY))
            cliff.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.07))
            cliff.closeSubpath()
            context.fill(cliff, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.77, green: 0.48, blue: 0.22),
                    Color(red: 0.46, green: 0.25, blue: 0.105)
                ]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

            for facet in 0..<4 {
                let x = rect.minX + rect.width * (0.18 + CGFloat(facet) * 0.20)
                var crack = Path()
                crack.move(to: CGPoint(x: x, y: rect.minY + rect.height * 0.18))
                crack.addLine(to: CGPoint(x: x - 4 + CGFloat(facet % 2) * 8,
                                          y: rect.maxY - rect.height * 0.10))
                context.stroke(crack,
                               with: .color(Color(red: 0.31, green: 0.15, blue: 0.06).opacity(0.31)),
                               style: StrokeStyle(lineWidth: 2.2 + CGFloat(index % 2),
                                                  lineCap: .round))
            }
            let cap = CGRect(x: rect.minX - 4, y: rect.minY - 5,
                             width: rect.width + 8, height: rect.height * 0.19)
            context.fill(Path(ellipseIn: cap), with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.55, green: 0.76, blue: 0.24),
                    Color(red: 0.19, green: 0.45, blue: 0.12)
                ]), startPoint: CGPoint(x: cap.midX, y: cap.minY),
                endPoint: CGPoint(x: cap.midX, y: cap.maxY)))
        }

        // Broad background honeyfall on the right, modeled as layered viscous
        // ribbons with a soft pool at its foot.
        let fallX = size.width * 0.865
        let topY = size.height * 0.31
        let bottomY = size.height * 0.54
        for strand in 0..<7 {
            let offset = CGFloat(strand - 3) * size.width * 0.012
            let width = size.width * (0.015 + CGFloat((strand + 1) % 3) * 0.006)
            var fall = Path()
            fall.move(to: CGPoint(x: fallX + offset, y: topY + CGFloat(strand % 2) * 7))
            fall.addCurve(to: CGPoint(x: fallX + offset * 0.65, y: bottomY),
                          control1: CGPoint(x: fallX + offset + 8, y: topY + (bottomY - topY) * 0.32),
                          control2: CGPoint(x: fallX + offset - 7, y: topY + (bottomY - topY) * 0.73))
            context.stroke(fall, with: .color(Color(red: 0.84, green: 0.34, blue: 0.01).opacity(0.72)),
                           style: StrokeStyle(lineWidth: width * 1.45, lineCap: .round))
            context.stroke(fall, with: .color(Color(red: 1.00, green: 0.69, blue: 0.055).opacity(0.93)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
            let shine = fall.applying(CGAffineTransform(translationX: -width * 0.18, y: 0))
            context.stroke(shine, with: .color(Color(red: 1.0, green: 0.94, blue: 0.48).opacity(0.55)),
                           style: StrokeStyle(lineWidth: max(1, width * 0.18), lineCap: .round))
        }
        context.fill(Path(ellipseIn: CGRect(x: fallX - size.width * 0.095,
                                            y: bottomY - size.height * 0.014,
                                            width: size.width * 0.19,
                                            height: size.height * 0.035)),
                     with: .color(Color(red: 1.0, green: 0.58, blue: 0.025).opacity(0.80)))
    }

    private func drawForestCanopies(in context: inout GraphicsContext, size: CGSize) {
        for side in 0...1 {
            let sign: CGFloat = side == 0 ? 1 : -1
            let edge: CGFloat = side == 0 ? 0 : size.width
            for tree in 0..<11 {
                let row = tree / 4
                let x = edge + sign * size.width * (0.025 + CGFloat(tree % 4) * 0.05)
                let y = size.height * (0.22 + CGFloat(row) * 0.15)
                    + CGFloat(tree % 3) * 12
                let r = size.width * (0.030 + CGFloat((tree * 3) % 4) * 0.006)
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.64,
                                                    width: r * 2, height: r * 1.52)),
                             with: .radialGradient(
                                Gradient(colors: [
                                    Color(red: 0.43, green: 0.67, blue: 0.20),
                                    Color(red: 0.10, green: 0.34, blue: 0.10)
                                ]), center: CGPoint(x: x - sign * r * 0.25, y: y - r * 0.28),
                                startRadius: 1, endRadius: r * 1.18))
            }
        }
    }

    /// Wet grey boulders along the waterline, with moss on their crowns — the
    /// river meets stone, not a green paper edge.
    private func drawShore(side: Int, in context: inout GraphicsContext, size: CGSize) {
        let steps = 16
        var strip = Path()
        for i in 0...steps {
            let travel = 1.16 - CGFloat(i) / CGFloat(steps) * 1.60
            let edge = side == 0
                ? projection.riverLeft(travel: travel)
                : projection.riverRight(travel: travel)
            let p = CGPoint(x: edge, y: projection.y(for: travel))
            if i == 0 { strip.move(to: p) } else { strip.addLine(to: p) }
        }
        for i in (0...steps).reversed() {
            let travel = 1.16 - CGFloat(i) / CGFloat(steps) * 1.60
            let edge = side == 0
                ? projection.riverLeft(travel: travel)
                : projection.riverRight(travel: travel)
            let outward = size.width * (0.055 + 0.025 * projection.nearness(for: travel))
            let x = side == 0 ? edge - outward : edge + outward
            strip.addLine(to: CGPoint(x: x, y: projection.y(for: travel)))
        }
        strip.closeSubpath()
        context.fill(strip, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.55, green: 0.39, blue: 0.20),
                Color(red: 0.31, green: 0.23, blue: 0.13)
            ]),
            startPoint: CGPoint(x: size.width * 0.5, y: projection.horizonY),
            endPoint: CGPoint(x: size.width * 0.5, y: size.height)))

        for i in 0..<14 {
            let along = shoreCycle(scroll * 0.55 + CGFloat(i) * 0.16 + CGFloat(side) * 0.07, 1.80)
            let travel = 1.30 - along
            guard travel > -0.08, travel < 1.28 else { continue }
            let s = projection.scale(for: travel) * (0.85 + CGFloat(i % 3) * 0.18)
            let edge = side == 0
                ? projection.riverLeft(travel: travel)
                : projection.riverRight(travel: travel)
            let outward: CGFloat = side == 0 ? -1 : 1
            let x = edge + outward * (10 + CGFloat(i % 4) * 7) * s
            let y = projection.y(for: travel)
            let w = (22 + CGFloat(i % 3) * 10) * s
            let h = (14 + CGFloat(i % 2) * 8) * s
            let rock = CGRect(x: x - w / 2, y: y - h * 0.72, width: w, height: h)
            context.fill(Path(ellipseIn: rock.offsetBy(dx: 0, dy: 2 * s)),
                         with: .color(.black.opacity(0.22)))
            context.fill(Path(ellipseIn: rock),
                         with: .color(Color(red: 0.46, green: 0.48, blue: 0.44)))
            context.fill(Path(ellipseIn: rock.insetBy(dx: w * 0.18, dy: h * 0.28).offsetBy(dx: 0, dy: -h * 0.12)),
                         with: .color(Color(red: 0.32, green: 0.58, blue: 0.22).opacity(0.9)))
            context.fill(Path(ellipseIn: rock.insetBy(dx: w * 0.28, dy: h * 0.38).offsetBy(dx: -w * 0.08, dy: h * 0.16)),
                         with: .color(Color(red: 0.28, green: 0.30, blue: 0.32).opacity(0.7)))
        }
    }

    /// Landmark honeyfalls: layered strokes fake viscous flow cheaply.
    private func drawFalls(in context: inout GraphicsContext) {
        for i in 0..<2 {
            let along = shoreCycle(scroll * 0.35 + CGFloat(i) * 0.85 + 0.2, 2.0)
            let travel = 1.15 - along
            guard travel > 0.12, travel < 0.95 else { continue }
            let s = projection.scale(for: travel)
            let edge = projection.riverLeft(travel: travel)
            let y = projection.y(for: travel)
            for k in 0..<4 {
                var fall = Path()
                let top = CGPoint(x: edge - (22 - CGFloat(k) * 4) * s,
                                  y: y - (36 + CGFloat(k) * 4) * s)
                let bot = CGPoint(x: edge + (6 + CGFloat(k) * 3) * s,
                                  y: y + 4 * s)
                fall.move(to: top)
                fall.addLine(to: bot)
                context.stroke(fall,
                               with: .color(RiverPaint.gloss.opacity(0.70 - Double(k) * 0.08)),
                               style: StrokeStyle(lineWidth: (5 + CGFloat(k)) * s * 0.55, lineCap: .round))
            }
            let splash = CGRect(x: edge - 4 * s, y: y - 4 * s, width: 28 * s, height: 12 * s)
            context.fill(Path(ellipseIn: splash), with: .color(RiverPaint.body.opacity(0.72)))
        }
    }

    private func shoreCycle(_ value: CGFloat, _ span: CGFloat) -> CGFloat {
        guard span > 0 else { return 0 }
        let r = value.truncatingRemainder(dividingBy: span)
        return r >= 0 ? r : r + span
    }

    private func drawDecor(_ kind: Int, at p: CGPoint, scale: CGFloat, in context: inout GraphicsContext) {
        switch kind {
        case 0, 1:
            context.fill(Path(CGRect(x: p.x - 3 * scale, y: p.y - 10 * scale,
                                     width: 6 * scale, height: 14 * scale)),
                         with: .color(Color(red: 0.40, green: 0.24, blue: 0.12)))
            for crown in 0..<5 {
                let angle = Double(crown) * .pi * 0.4
                let x = p.x + CGFloat(cos(angle)) * 10 * scale
                let y = p.y - 34 * scale + CGFloat(sin(angle)) * 12 * scale
                let rect = CGRect(x: x - 15 * scale, y: y - 13 * scale,
                                  width: 30 * scale, height: 26 * scale)
                context.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 2 * scale)),
                             with: .color(Color(red: 0.06, green: 0.25, blue: 0.07).opacity(0.72)))
                context.fill(Path(ellipseIn: rect),
                             with: .color(Color(red: 0.18 + Double(crown % 2) * 0.06,
                                                green: 0.47 + Double(crown % 3) * 0.035,
                                                blue: 0.10)))
            }
        case 2:
            context.fill(Path(ellipseIn: CGRect(x: p.x - 16 * scale, y: p.y - 18 * scale,
                                                width: 32 * scale, height: 20 * scale)),
                         with: .color(Color(red: 0.45, green: 0.42, blue: 0.38)))
        case 3:
            context.fill(Path(ellipseIn: CGRect(x: p.x - 8 * scale, y: p.y - 16 * scale,
                                                width: 16 * scale, height: 16 * scale)),
                         with: .color(Color(red: 0.86, green: 0.16, blue: 0.16)))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 5 * scale, y: p.y - 12 * scale,
                                                width: 4 * scale, height: 4 * scale)),
                         with: .color(.white))
        case 4:
            let colors: [Color] = [
                Color(red: 1, green: 0.45, blue: 0.72),
                Color(red: 0.95, green: 0.82, blue: 0.2),
                Color(red: 0.72, green: 0.42, blue: 0.95)
            ]
            context.fill(Path(ellipseIn: CGRect(x: p.x - 6 * scale, y: p.y - 12 * scale,
                                                width: 12 * scale, height: 12 * scale)),
                         with: .color(colors[positiveMod(Int(p.x.rounded()), colors.count)]))
        case 5:
            let cabin = Path(CGRect(x: p.x - 14 * scale, y: p.y - 28 * scale,
                                    width: 28 * scale, height: 20 * scale))
            context.fill(cabin, with: .color(Color(red: 0.55, green: 0.32, blue: 0.16)))
            var roof = Path()
            roof.move(to: CGPoint(x: p.x - 16 * scale, y: p.y - 28 * scale))
            roof.addLine(to: CGPoint(x: p.x, y: p.y - 40 * scale))
            roof.addLine(to: CGPoint(x: p.x + 16 * scale, y: p.y - 28 * scale))
            context.fill(roof, with: .color(Color(red: 0.72, green: 0.22, blue: 0.16)))
        default:
            context.fill(Path(ellipseIn: CGRect(x: p.x - 10 * scale, y: p.y - 14 * scale,
                                                width: 20 * scale, height: 12 * scale)),
                         with: .color(Color(red: 0.38, green: 0.36, blue: 0.32)))
        }
    }

    private func positiveMod(_ value: Int, _ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        let remainder = value % bound
        return remainder >= 0 ? remainder : remainder + bound
    }
}

// MARK: - Legacy fishing artwork

/// Landmarks on the 1711×1024 bank-bear exports, as a share of the canvas.
/// The three pictures are registered to each other: stacking the empty cub
/// and the loose jar rebuilds the loaded pose, and mirroring puts the stick
/// over the other bank.
private enum BankBearArt {
    static let aspect: CGFloat = 1711 / 1024
    static let potWidth: CGFloat = 301 / 1711
    static let feet = CGPoint(x: 0.172, y: 0.942)
    static let headY: CGFloat = 0.216
    /// Where both paws hold the stick — the joint the pole turns around.
    static let grip = CGPoint(x: 0.365, y: 0.410)
    /// Empty rope loop on the unloaded drawing.
    static let loop = CGPoint(x: 0.840, y: 0.436)
    /// Knot where the rope is lashed to the wood.
    static let knot = CGPoint(x: 0.808, y: 0.352)
    static let pot = CGPoint(x: 0.855, y: 0.498)
    static let number = CGPoint(x: 0.853, y: 0.540)
    static let retract = CGPoint(x: 0.455, y: 0.205)
    /// Sitting cub, paws included, stick left out.
    static let body = CGRect(x: 0.010, y: 0.195, width: 0.385, height: 0.760)
    /// Painted pole through the knot — the dangling loop is drawn separately
    /// so stretching the wood cannot smear the rope.
    static let stick = CGRect(x: 0.305, y: 0.000, width: 0.515, height: 0.50)
}

/// Places one cub on a stable bank seat next to its own jar. Size follows
/// perspective only. The painted pole is aimed as a single piece so the wood
/// and rope stay whole.
private struct FisherLayout {
    let playfield: CGSize
    let spriteOrigin: CGPoint
    let spriteSize: CGSize
    let artCanvas: CGSize
    let pad: CGFloat
    let mirrored: Bool
    let hangPoint: CGPoint
    let jarPoint: CGPoint
    let loopPoint: CGPoint
    let poleWidth: CGFloat
    let gripPx: CGPoint
    let restTipPx: CGPoint
    let targetTipPx: CGPoint
    let stillOnRod: Bool
    let isOnScreen: Bool
    let jarCanvas: CGSize

    init(pot: RiverPot, projection: RiverProjection, isPad: Bool, reelLift: CGFloat, clock: Double) {
        playfield = projection.size
        let lift = 1 - pow(1 - min(max(max(reelLift, pot.reel), 0), 1), 3)
        stillOnRod = !pot.hit || pot.grabFlight < RiverConfig.grabDetach
        mirrored = pot.fisherSide == 1
        let towardRiver: CGFloat = mirrored ? -1 : 1
        let travel = pot.travel
        let scale = projection.scale(for: travel)

        let jarWidth = RiverConfig.potSize(isPad: isPad) * scale
        let artW = jarWidth / BankBearArt.potWidth
        let artH = artW / BankBearArt.aspect
        spriteSize = CGSize(width: artW, height: artH)
        jarCanvas = spriteSize

        let river = mirrored
            ? projection.riverRightStable(travel: travel)
            : projection.riverLeftStable(travel: travel)
        let edgeGap: CGFloat = 8 + 6 * scale
        let originX: CGFloat
        if mirrored {
            originX = river + edgeGap - (1 - BankBearArt.body.maxX) * artW
        } else {
            originX = river - edgeGap - BankBearArt.body.maxX * artW
        }

        let feetUV = CGPoint(
            x: mirrored ? 1 - BankBearArt.feet.x : BankBearArt.feet.x,
            y: BankBearArt.feet.y
        )
        let feetWorld = CGPoint(
            x: originX + feetUV.x * artW,
            y: projection.y(for: travel)
        )
        spriteOrigin = CGPoint(
            x: feetWorld.x - feetUV.x * artW,
            y: feetWorld.y - feetUV.y * artH
        )

        let waterPoint = projection.point(lateral: pot.lateral, travel: travel)
        let hangClearance = jarWidth * 0.62 + (isPad ? 20 : 14) * scale
        let sway = CGFloat(sin(clock * 1.35 + Double(pot.lateral) * 1.1 + Double(pot.fisherSide)))
            * 2.2 * scale * (1 - lift)
        let restLoop = CGPoint(
            x: waterPoint.x + sway * towardRiver * 0.15,
            y: waterPoint.y - hangClearance + abs(sway) * 0.08
        )

        let retractUVX = mirrored ? 1 - BankBearArt.retract.x : BankBearArt.retract.x
        let retractWorld = CGPoint(
            x: spriteOrigin.x + retractUVX * artW,
            y: spriteOrigin.y + BankBearArt.retract.y * artH
        )
        let pull = stillOnRod && !pot.hit ? lift : (stillOnRod ? 0 : lift)
        let aimLoop: CGPoint
        if stillOnRod && !pot.hit {
            aimLoop = Self.mix(restLoop, retractWorld, pull)
        } else if !stillOnRod {
            aimLoop = Self.mix(restLoop, retractWorld, lift)
        } else {
            aimLoop = restLoop
        }

        jarPoint = CGPoint(
            x: aimLoop.x,
            y: aimLoop.y + (BankBearArt.pot.y - BankBearArt.knot.y) * artH
        )
        hangPoint = jarPoint
        loopPoint = aimLoop
        poleWidth = max(2.4, 5.2 * scale)

        gripPx = CGPoint(x: BankBearArt.grip.x * artW, y: BankBearArt.grip.y * artH)
        restTipPx = CGPoint(x: BankBearArt.knot.x * artW, y: BankBearArt.knot.y * artH)
        var tx = (aimLoop.x - spriteOrigin.x) / max(artW, 1)
        let ty = (aimLoop.y - spriteOrigin.y) / max(artH, 1)
        if mirrored { tx = 1 - tx }
        targetTipPx = CGPoint(x: tx * artW, y: ty * artH)

        pad = max(48, max(abs(targetTipPx.x - restTipPx.x), abs(targetTipPx.y - restTipPx.y)) + 36)
        artCanvas = CGSize(width: artW + pad * 2, height: artH + pad * 2)

        let cub = CGRect(
            x: spriteOrigin.x + (mirrored ? (1 - BankBearArt.body.maxX) : BankBearArt.body.minX) * artW,
            y: spriteOrigin.y + BankBearArt.body.minY * artH,
            width: BankBearArt.body.width * artW,
            height: BankBearArt.body.height * artH
        )
        let screen = CGRect(x: -24, y: -48,
                            width: projection.size.width + 48,
                            height: projection.size.height + 64)
        isOnScreen = cub.intersects(screen) || screen.contains(hangPoint)
    }

    var spriteCenter: CGPoint {
        CGPoint(x: spriteOrigin.x + spriteSize.width / 2,
                y: spriteOrigin.y + spriteSize.height / 2)
    }

    var artCenter: CGPoint { spriteCenter }

    var jarCenter: CGPoint {
        CGPoint(
            x: jarPoint.x + (0.5 - BankBearArt.pot.x) * jarCanvas.width,
            y: jarPoint.y + (0.5 - BankBearArt.pot.y) * jarCanvas.height
        )
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

private struct FisherRigView: View {
    let layout: FisherLayout
    let text: String

    var body: some View {
        ZStack {
            if layout.isOnScreen {
                FisherArtCanvas(layout: layout)
                    .frame(width: layout.artCanvas.width, height: layout.artCanvas.height)
                    .scaleEffect(x: layout.mirrored ? -1 : 1, y: 1)
                    .position(layout.artCenter)
                RopeLineView(layout: layout)
            }
            if layout.stillOnRod {
                HoneyJarView(text: text, layout: layout)
                    .position(layout.jarCenter)
            }
        }
        .frame(width: layout.playfield.width, height: layout.playfield.height)
        .allowsHitTesting(false)
    }
}

/// Aim the painted pole as one piece: rotate and lengthen around the paws so
/// the wood and the empty rope loop stay intact. Slicing it was what left holes.
private struct RodPose {
    let pad: CGFloat
    let canvas: CGSize
    let art: CGRect
    let grip: CGPoint
    let restAngle: CGFloat
    let targetAngle: CGFloat
    let stretch: CGFloat

    init(layout: FisherLayout) {
        pad = layout.pad
        canvas = layout.artCanvas
        art = CGRect(x: pad, y: pad,
                     width: layout.spriteSize.width,
                     height: layout.spriteSize.height)
        grip = CGPoint(x: layout.gripPx.x + pad, y: layout.gripPx.y + pad)
        let rest = CGPoint(x: layout.restTipPx.x + pad, y: layout.restTipPx.y + pad)
        let target = CGPoint(x: layout.targetTipPx.x + pad, y: layout.targetTipPx.y + pad)
        let restVec = CGPoint(x: rest.x - grip.x, y: rest.y - grip.y)
        let targetVec = CGPoint(x: target.x - grip.x, y: target.y - grip.y)
        let restLen = max(1, hypot(restVec.x, restVec.y))
        let targetLen = max(1, hypot(targetVec.x, targetVec.y))
        restAngle = atan2(restVec.y, restVec.x)
        targetAngle = atan2(targetVec.y, targetVec.x)
        stretch = min(2.4, max(0.88, targetLen / restLen))
    }

    func bodyClip() -> Path {
        let r = BankBearArt.body
        return Path(CGRect(x: art.minX + r.minX * art.width,
                           y: art.minY + r.minY * art.height,
                           width: r.width * art.width,
                           height: r.height * art.height))
    }

    func stickClip() -> Path {
        let r = BankBearArt.stick
        return Path(CGRect(x: art.minX + r.minX * art.width,
                           y: art.minY + r.minY * art.height,
                           width: r.width * art.width,
                           height: r.height * art.height))
    }
}

private struct FisherArtCanvas: View {
    let layout: FisherLayout

    var body: some View {
        let pose = RodPose(layout: layout)
        return Canvas { context, _ in
            let image = context.resolve(Image("bear_without_honeypot"))

            var cub = context
            cub.clip(to: pose.bodyClip())
            cub.draw(image, in: pose.art)

            var rod = context
            rod.translateBy(x: pose.grip.x, y: pose.grip.y)
            rod.rotate(by: .radians(Double(pose.targetAngle)))
            rod.scaleBy(x: pose.stretch, y: 1)
            rod.rotate(by: .radians(Double(-pose.restAngle)))
            rod.translateBy(x: -pose.grip.x, y: -pose.grip.y)
            rod.clip(to: pose.stickClip())
            rod.draw(image, in: pose.art)
        }
        .frame(width: pose.canvas.width, height: pose.canvas.height)
    }
}

private struct RopeLineView: View {
    let layout: FisherLayout

    var body: some View {
        Canvas { context, _ in
            let wood = Color(red: 0.42, green: 0.24, blue: 0.10)
            let rope = Color(red: 0.72, green: 0.58, blue: 0.32)
            let ropeDeep = Color(red: 0.50, green: 0.36, blue: 0.16)
            let knotR = layout.poleWidth * 0.95
            let lineW = max(1.6, layout.poleWidth * 0.42)
            let neck = CGPoint(
                x: layout.jarPoint.x,
                y: layout.jarPoint.y - layout.jarCanvas.width * BankBearArt.potWidth * 0.36
            )
            let end = layout.stillOnRod
                ? neck
                : CGPoint(x: layout.loopPoint.x, y: layout.loopPoint.y + layout.poleWidth * 3.2)

            var line = Path()
            line.move(to: layout.loopPoint)
            line.addQuadCurve(
                to: end,
                control: CGPoint(
                    x: (layout.loopPoint.x + end.x) / 2,
                    y: min(layout.loopPoint.y, end.y) + abs(end.x - layout.loopPoint.x) * 0.08
                )
            )
            context.stroke(line, with: .color(ropeDeep),
                           style: StrokeStyle(lineWidth: lineW + 0.8, lineCap: .round))
            context.stroke(line, with: .color(rope),
                           style: StrokeStyle(lineWidth: lineW, lineCap: .round))

            if layout.stillOnRod {
                let loopW = layout.jarCanvas.width * BankBearArt.potWidth * 0.40
                let loopH = loopW * 0.42
                let ring = CGRect(x: neck.x - loopW / 2, y: neck.y - loopH / 2, width: loopW, height: loopH)
                context.stroke(Path(ellipseIn: ring.insetBy(dx: -0.6, dy: -0.6)),
                               with: .color(ropeDeep),
                               style: StrokeStyle(lineWidth: lineW + 0.7))
                context.stroke(Path(ellipseIn: ring),
                               with: .color(rope),
                               style: StrokeStyle(lineWidth: lineW))
            }

            let knot = CGRect(x: layout.loopPoint.x - knotR, y: layout.loopPoint.y - knotR,
                              width: knotR * 2, height: knotR * 2)
            context.fill(Path(ellipseIn: knot), with: .color(wood))
            context.stroke(Path(ellipseIn: knot), with: .color(wood.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1))
        }
        .frame(width: layout.playfield.width, height: layout.playfield.height)
        .allowsHitTesting(false)
    }
}

private struct HoneyJarView: View {
    let text: String
    let layout: FisherLayout

    var body: some View {
        let w = layout.jarCanvas.width
        let h = layout.jarCanvas.height
        ZStack {
            Image("honeypot-only")
                .resizable()
                .interpolation(.high)
                .frame(width: w, height: h)
            Text(verbatim: text)
                .font(.system(size: w * BankBearArt.potWidth * 0.42, weight: .black, design: .rounded))
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                .frame(width: w * BankBearArt.potWidth * 0.82)
                .position(x: BankBearArt.number.x * w, y: BankBearArt.number.y * h)
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }
}

private struct LogBoatView: View {
    let character: AnimalCharacter
    let clock: Double
    let current: CGFloat
    var grabReach: CGFloat = 0
    var grabTarget: CGPoint = .zero
    var boatCenter: CGPoint = .zero

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(colors: [
                            Color.white.opacity(0.55 + 0.20 * Double(current)),
                            Color(red: 0.70, green: 0.94, blue: 1.0).opacity(0.35),
                            Color.white.opacity(0)
                        ], center: .center, startRadius: 0, endRadius: w * 0.42)
                    )
                    .frame(width: w * 1.05, height: h * 0.28)
                    .offset(y: h * 0.40)

                // Log
                Capsule()
                    .fill(
                        LinearGradient(colors: [
                            Color(red: 0.55, green: 0.32, blue: 0.14),
                            Color(red: 0.38, green: 0.20, blue: 0.08)
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: w * 0.92, height: h * 0.28)
                    .overlay(
                        Capsule().stroke(Color(red: 0.28, green: 0.14, blue: 0.05), lineWidth: 2)
                    )
                    .offset(y: h * 0.28)

                Circle()
                    .fill(Color(red: 0.30, green: 0.62, blue: 0.22))
                    .frame(width: w * 0.10, height: w * 0.10)
                    .offset(x: w * 0.28, y: h * 0.22)
                Circle()
                    .fill(Color(red: 0.30, green: 0.62, blue: 0.22))
                    .frame(width: w * 0.08, height: w * 0.08)
                    .offset(x: w * 0.34, y: h * 0.28)

                captain(width: w, height: h)
                    .offset(y: -h * 0.06 + CGFloat(sin(clock * 6)) * 1.5)
            }
            .frame(width: w, height: h)
        }
    }

    private func captain(width w: CGFloat, height h: CGFloat) -> some View {
        let fur = character.color
        let deep = character.deepColor
        let reachSide: CGFloat = grabTarget.x >= boatCenter.x ? 1 : -1
        let localTarget = CGPoint(
            x: w / 2 + (grabTarget.x - boatCenter.x),
            y: h / 2 + (grabTarget.y - boatCenter.y)
        )
        return ZStack {
            // Body
            RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                .fill(fur)
                .frame(width: w * 0.46, height: h * 0.42)
                .offset(y: h * 0.02)
            // Vest
            RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                .fill(Color(red: 0.86, green: 0.16, blue: 0.16))
                .frame(width: w * 0.42, height: h * 0.30)
                .overlay(
                    RoundedRectangle(cornerRadius: w * 0.12, style: .continuous)
                        .stroke(Color.black.opacity(0.35), lineWidth: 2)
                )
                .offset(y: h * 0.06)
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(width: w * 0.05, height: h * 0.16)
                .offset(y: h * 0.04)
            Circle()
                .fill(Color(red: 0.95, green: 0.82, blue: 0.18))
                .frame(width: w * 0.07, height: w * 0.07)
                .offset(y: h * 0.12)

            // Head from behind
            Circle()
                .fill(fur)
                .frame(width: w * 0.40, height: w * 0.40)
                .overlay(Circle().stroke(deep.opacity(0.35), lineWidth: 1))
                .offset(y: -h * 0.22)
            Circle()
                .fill(fur)
                .frame(width: w * 0.16, height: w * 0.16)
                .offset(x: -w * 0.16, y: -h * 0.34)
            Circle()
                .fill(fur)
                .frame(width: w * 0.16, height: w * 0.16)
                .offset(x: w * 0.16, y: -h * 0.34)
            Circle()
                .fill(deep.opacity(0.35))
                .frame(width: w * 0.07, height: w * 0.07)
                .offset(x: -w * 0.16, y: -h * 0.34)
            Circle()
                .fill(deep.opacity(0.35))
                .frame(width: w * 0.07, height: w * 0.07)
                .offset(x: w * 0.16, y: -h * 0.34)

            character.thumbArtwork
                .resizable()
                .scaledToFit()
                .frame(width: w * 0.22, height: w * 0.22)
                .clipShape(Circle())
                .offset(y: -h * 0.18)
                .opacity(0.0)

            boatArm(side: -1, width: w, height: h, fur: fur, localTarget: localTarget, reachSide: reachSide)
            boatArm(side: 1, width: w, height: h, fur: fur, localTarget: localTarget, reachSide: reachSide)
        }
    }

    /// Resting paws stay on the log. The paw on the jar's side stretches out
    /// to lift it off the stick and drop it into the boat.
    @ViewBuilder
    private func boatArm(side: CGFloat, width w: CGFloat, height h: CGFloat,
                         fur: Color, localTarget: CGPoint, reachSide: CGFloat) -> some View {
        let reaching = grabReach > 0.02 && side == reachSide
        let rest = CGPoint(x: w * 0.5 + side * w * 0.28, y: h * 0.66)
        let shoulder = CGPoint(x: w * 0.5 + side * w * 0.12, y: h * 0.48)
        let hand = reaching
            ? CGPoint(
                x: rest.x + (localTarget.x - rest.x) * grabReach,
                y: rest.y + (localTarget.y - rest.y) * grabReach
              )
            : rest
        let dx = hand.x - shoulder.x
        let dy = hand.y - shoulder.y
        let length = max(w * 0.16, sqrt(dx * dx + dy * dy))
        let angle = Angle(radians: Double(atan2(dy, dx)))
        ZStack {
            Capsule()
                .fill(fur)
                .frame(width: length, height: w * 0.10)
                .rotationEffect(angle)
                .position(x: (shoulder.x + hand.x) / 2, y: (shoulder.y + hand.y) / 2)
            Circle()
                .fill(fur)
                .frame(width: w * 0.14, height: w * 0.14)
                .position(hand)
        }
        .frame(width: w, height: h)
    }
}


// MARK: - Answer stones

/// One freestanding answer carried by the current. The wide, low silhouette
/// and the ripple beneath it make the object read as a stone lying on the
/// water rather than a card hovering above it.
private struct RiverAnswerStoneView: View {
    let pot: RiverPot
    let projection: RiverProjection
    let isPad: Bool
    let clock: Double
    let groupDismissal: CGFloat

    var body: some View {
        let perspective = projection.scale(for: pot.travel)
        let width = RiverConfig.potSize(isPad: isPad) * 1.22 * perspective
        let height = width * 0.66
        let point = projection.point(lateral: pot.lateral, travel: pot.travel)
        let dismissal = min(max(max(groupDismissal, pot.reel), 0), 1)
        let hitFade = pot.hit ? min(1, CGFloat(pot.hitAge) / 0.22) : 0
        let fade = max(dismissal, hitFade)
        let bob = CGFloat(sin(clock * 2.1 + Double(pot.lateral) * 0.9)) * 1.4 * perspective

        return ZStack {
            Ellipse()
                .fill(Color(red: 0.12, green: 0.32, blue: 0.38).opacity(0.30))
                .frame(width: width * 1.18, height: height * 0.30)
                .offset(y: height * 0.27)

            RiverAnswerStoneShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.68, green: 0.64, blue: 0.54),
                            Color(red: 0.43, green: 0.42, blue: 0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RiverAnswerStoneShape()
                        .stroke(Color(red: 0.27, green: 0.28, blue: 0.27).opacity(0.75),
                                lineWidth: max(1, width * 0.025))
                }
                .overlay(alignment: .topLeading) {
                    Capsule()
                        .fill(.white.opacity(0.20))
                        .frame(width: width * 0.40, height: height * 0.10)
                        .rotationEffect(.degrees(-8))
                        .offset(x: width * 0.16, y: height * 0.15)
                }

            Text(verbatim: pot.text)
                .font(.system(size: width * 0.35, weight: .black, design: .rounded))
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                .padding(.horizontal, width * 0.12)
        }
        .frame(width: width, height: height)
        .scaleEffect(1 - fade * 0.18)
        .opacity(Double(1 - fade))
        .position(x: point.x, y: point.y - height * 0.18 + bob)
        .allowsHitTesting(false)
    }
}

private struct RiverAnswerStoneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.10,
                              y: rect.minY + rect.height * 0.57))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.25,
                                      y: rect.minY + rect.height * 0.14),
                          control: CGPoint(x: rect.minX + rect.width * 0.10,
                                           y: rect.minY + rect.height * 0.25))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.72,
                                      y: rect.minY + rect.height * 0.10),
                          control: CGPoint(x: rect.midX,
                                           y: rect.minY - rect.height * 0.02))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.05,
                                      y: rect.minY + rect.height * 0.55),
                          control: CGPoint(x: rect.maxX,
                                           y: rect.minY + rect.height * 0.22))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.68,
                                      y: rect.maxY - rect.height * 0.05),
                          control: CGPoint(x: rect.maxX,
                                           y: rect.maxY - rect.height * 0.08))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.18,
                                      y: rect.maxY - rect.height * 0.12),
                          control: CGPoint(x: rect.midX,
                                           y: rect.maxY + rect.height * 0.03))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.10,
                                      y: rect.minY + rect.height * 0.57),
                          control: CGPoint(x: rect.minX,
                                           y: rect.maxY - rect.height * 0.25))
        path.closeSubpath()
        return path
    }
}

// MARK: - Question

struct RiverQuestionBanner: View {
    let prompt: String
    let roundID: UUID?
    let ink: Color
    let isPad: Bool

    /// Native size of `som_board.png`.
    private static let imageAspect: CGFloat = 635.0 / 214.0
    /// Empty pixels above the wooden frame, so the visible top can sit on the
    /// same line as the pause and score discs.
    private static let visualTopInset: CGFloat = 32.0 / 214.0

    /// Keeps the wooden frame readable without covering the crabs below.
    static func height(isPad: Bool) -> CGFloat { isPad ? 154 : 110 }

    /// Insets of the cream writing area, as a fraction of the full asset.
    private static let creamLeading: CGFloat = 0.155
    private static let creamTrailing: CGFloat = 0.180
    private static let creamTop: CGFloat = 0.255
    private static let creamBottom: CGFloat = 0.295

    @State private var shownPrompt = ""
    @State private var isVisible = true

    var body: some View {
        Image("som_board")
            .resizable()
            .interpolation(.high)
            .aspectRatio(Self.imageAspect, contentMode: .fit)
            .frame(maxHeight: Self.height(isPad: isPad))
            .shadow(color: .black.opacity(0.22), radius: isPad ? 10 : 7, y: 4)
            .overlay {
                GeometryReader { geo in
                    Text(verbatim: shownPrompt)
                        .font(.system(size: isPad ? 51 : 37, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.34)
                        .lineLimit(1)
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.leading, geo.size.width * Self.creamLeading)
                        .padding(.trailing, geo.size.width * Self.creamTrailing)
                        .padding(.top, geo.size.height * Self.creamTop)
                        .padding(.bottom, geo.size.height * Self.creamBottom)
                        .opacity(isVisible ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .offset(y: -Self.height(isPad: isPad) * Self.visualTopInset)
            .onAppear { shownPrompt = prompt }
            .onChange(of: Question(id: roundID, prompt: prompt)) { _, question in
                reveal(question.prompt)
            }
            .accessibilityIdentifier("question-card")
            .accessibilityLabel(Text(L("game.question \(prompt)")))
            .accessibilityHidden(prompt.isEmpty)
    }

    private struct Question: Equatable {
        let id: UUID?
        let prompt: String
    }

    private func reveal(_ newPrompt: String) {
        guard shownPrompt != newPrompt else { return }
        // The wooden board stays put; only the ink on it is swapped.
        guard !shownPrompt.isEmpty, !newPrompt.isEmpty else {
            shownPrompt = newPrompt
            isVisible = true
            return
        }
        withAnimation(.easeOut(duration: 0.10)) { isVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            shownPrompt = newPrompt
            withAnimation(.easeOut(duration: 0.20)) { isVisible = true }
        }
    }
}

struct RiverMissedNote: View {
    let text: String
    let ink: Color
    let isPad: Bool

    static func height(isPad: Bool) -> CGFloat { isPad ? 46 : 34 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
            Text(verbatim: text)
                .font(.system(size: isPad ? 18 : 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(ink.opacity(0.86))
        .padding(.horizontal, 12)
        .frame(height: Self.height(isPad: isPad))
        .background(
            Capsule().fill(.white.opacity(0.92))
                .shadow(color: ink.opacity(0.20), radius: 8, y: 4)
        )
    }
}
