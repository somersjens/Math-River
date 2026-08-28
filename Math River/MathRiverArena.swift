//
//  MathRiverArena.swift
//  Math River
//
//  The in-game simulation: the honey-ring rider moves freely across a
//  data-driven honey slide, and four answer pots approach for each sum.
//  Scoring, rounds and the end of the board still live in `MemoryGame`; this
//  file only decides when a stone is hit, when a group has gone by, and how
//  the rider and the current move.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Tuning

enum RiverConfig {
    static let lateralMinimum: CGFloat = -1
    static let lateralMaximum: CGFloat = 1

    static func boatSize(isPad: Bool) -> CGFloat { isPad ? 172 : 128 }
    static func potSize(isPad: Bool) -> CGFloat { isPad ? 70 : 52 }

    /// Far plane shared by position and size. Travel above this is packed
    /// into a short band at the horizon so later jars never sit on top of
    /// each other before they start moving.
    static let farTravel: CGFloat = 1.15
    /// Past the boat; once every pot is here the group may end.
    static let passedTravel: CGFloat = -0.20
    static let hitTravel: CGFloat = 0.08
    static let hitLateralSlop: CGFloat = 0.25

    static let entranceDuration = 1.05
    static let calmDuration = 3.8
    static let calmSlowdown = 0.32
    static let rewardFlight = 0.48
    /// How long every cub takes to yank its rod up after a good pot is caught.
    static let reelDuration = 0.42
    static let reelDurationReduced = 0.16
    /// Reach, lift the jar off the stick, drop it in the boat.
    static let grabDuration = 0.50
    static let grabDurationReduced = 0.22
    /// The jar leaves the loop once the captain's paw has actually arrived.
    static let grabDetach: CGFloat = 0.32

    static let bankLeft: CGFloat = 0.18
    static let bankRight: CGFloat = 0.82
}

// MARK: - Live objects

struct RiverPot: Identifiable, Equatable {
    let id: UUID
    let optionID: UUID
    let text: String
    let isCorrect: Bool
    /// Continuous placement across the available slide width (-1...1).
    let lateral: CGFloat
    /// 1 is far, 0 is the boat, negative is behind the camera.
    var travel: CGFloat
    /// Left side is 0, right side is 1. Reassigned so the helpers remain
    /// readable around the slide instead of stacking on one side.
    var fisherSide: Int
    /// Along-bank seat of the cub, a little upstream of the hanging jar.
    var fisherTravel: CGFloat
    let fisherVest: Int
    var hit: Bool = false
    var hitAge: Double = 0
    var fisherReact: Double = 0
    /// 0 hanging over the water, 1 reeled into the cub's hands.
    var reel: CGFloat = 0
    /// 0 still on the stick, 1 stowed in the boat. Only set on a caught jar.
    var grabFlight: CGFloat = 0
}

struct RiverSplash: Identifiable, Equatable {
    let id: UUID
    var age: Double
    var life: Double
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var scale: CGFloat
    var honey: Bool

    var isActive: Bool { life > 0 && age <= life }
}

struct RiverReward: Identifiable, Equatable {
    let id: UUID
    var age: Double
    var start: CGPoint
    var target: CGPoint
}

struct RiverDecor: Identifiable, Equatable {
    let id: Int
    let kind: Int
    let side: Int
    let along: CGFloat
    let scale: CGFloat
}

// MARK: - Formations

/// Four pots across continuous offsets, lightly staggered for depth.
private enum RiverFormation {
    /// Continuous offsets are deliberately irregular: the slide never reads
    /// as three invisible rails even though the existing answer art is kept.
    static func slots(for roundNumber: Int) -> [(lateral: CGFloat, extra: CGFloat)] {
        let extra: CGFloat = 0.02
        switch roundNumber % 6 {
        case 0: return [(-0.22, 0), (-0.74, extra), (0.72, extra), (0.28, extra * 2)]
        case 1: return [(-0.76, 0), (-0.18, extra * 0.85), (0.70, extra * 1.7), (0.20, extra * 2.5)]
        case 2: return [(0.76, 0), (0.14, extra * 0.85), (-0.68, extra * 1.7), (-0.24, extra * 2.5)]
        case 3: return [(-0.62, 0), (0.66, extra * 0.7), (0.08, extra * 1.6), (-0.34, extra * 2.4)]
        case 4: return [(0.02, 0), (0.76, extra * 0.8), (-0.72, extra * 1.6), (0.30, extra * 2.4)]
        default: return [(-0.70, 0), (0.68, 0), (-0.12, extra * 1.15), (0.42, extra * 2.2)]
        }
    }
}

// MARK: - Arena

@MainActor
final class MathRiverArena: ObservableObject {
    @Published private(set) var pots: [RiverPot] = []
    /// Stable identities remove the append/UUID/remove churn that previously
    /// happened throughout play. Inactive entries stay dormant in this pool.
    @Published private(set) var splashes: [RiverSplash] = (0..<HoneySlideTuning.splashPoolCapacity).map { _ in
        RiverSplash(id: UUID(), age: 1, life: 0, x: 0, y: 0,
                    vx: 0, vy: 0, scale: 0, honey: true)
    }
    @Published private(set) var rewards: [RiverReward] = []
    @Published private(set) var decor: [RiverDecor] = []
    @Published private(set) var targetLateral: CGFloat = 0
    @Published private(set) var displayLateral: CGFloat = 0
    @Published private(set) var activeBranch: Int = 0
    @Published private(set) var jumpLift: CGFloat = 0
    @Published private(set) var landingImpact: CGFloat = 0
    @Published private(set) var clock: Double = 0
    @Published private(set) var scroll: CGFloat = 0
    @Published private(set) var currentSlideSpeed: CGFloat = HoneySlideTuning.nominalSlideSpeed
    @Published private(set) var boatRoll: Double = 0
    @Published private(set) var boatBob: CGFloat = 0
    @Published private(set) var current: CGFloat = 1
    @Published private(set) var visualQuality = HoneySlideVisualQuality.recommended {
        didSet {
#if DEBUG
            if oldValue != visualQuality, HoneySlidePreviewMode.isActive {
                print("[HoneySlide QA] quality \(oldValue) -> \(visualQuality); ema=\(frameIntervalEMA)")
            }
#endif
        }
    }
    @Published private(set) var calmness: CGFloat = 0
    @Published private(set) var entrance: CGFloat = 1
    /// 0 hanging, 1 fully yanked up — set on every cub when good honey is caught.
    @Published private(set) var reelLift: CGFloat = 0
    /// How far the captain's arm is stretched toward a jar he is taking.
    @Published private(set) var grabReach: CGFloat = 0
    /// World point the reaching paw aims at — the jar, while it is in flight.
    @Published private(set) var grabTarget: CGPoint = .zero
    @Published private(set) var isCelebrating = false
    @Published private(set) var size: CGSize = .zero
    @Published private(set) var isPad = false

    var onAnswer: ((UUID) -> Bool)?
    var onRewardArrived: (() -> Void)?
    var onWaveComplete: (() -> Void)?
    var onTutorialEvent: ((CrabTutorialEvent) -> Void)?

    private var loadedRoundID: UUID?
    private var pendingRound: GameRound?
    private var lastRound: GameRound?
    private var waveResolved = false
    private var waveFinishing = false
    private var isReeling = false
    private var gapRemaining: Double = 0
    private var isLive = false
    private var isRunning = false
    private var reduceMotion = false
    private var scoreTarget: CGPoint?
    private var steeringOrigin: CGPoint?
    private var steeringOriginLateral: CGFloat = 0
    private var lastTrackKind: HoneySegmentKind = .wide
    private var entranceRemaining: Double = 0
    private var entranceCompletion: (() -> Void)?
    private var calmRemaining: Double = 0
    private var calmStarted = false
    private var calmFinished = false
    private var onCalmStarted: (() -> Void)?
    private var onCalmFinished: (() -> Void)?
    private var lastFrameTimestamp: CFTimeInterval?
    private var frameIntervalEMA: CFTimeInterval = 1.0 / 60.0
    private var framePressureDuration: CFTimeInterval = 0
    private var frameRecoveryDuration: CFTimeInterval = 0
    private var qualityChangeCooldown: CFTimeInterval = 0
    private var splashBudget = 0
#if DEBUG
    private var didApplyPreviewPhase = false
#endif

#if canImport(UIKit)
    private final class DisplayLinkTarget: NSObject {
        weak var owner: MathRiverArena?
        init(owner: MathRiverArena) { self.owner = owner }
        @objc func advance(_ displayLink: CADisplayLink) {
            guard let owner else {
                displayLink.invalidate()
                return
            }
            owner.advance(displayLink)
        }
    }

    private lazy var displayLinkTarget = DisplayLinkTarget(owner: self)
    private var displayLink: CADisplayLink?
#else
    private var timer: Timer?
#endif

    func layout(size: CGSize, isPad: Bool) {
        self.size = size
        self.isPad = isPad
#if DEBUG
        if !didApplyPreviewPhase, HoneySlidePreviewMode.isActive,
           let previewPhase = HoneySlidePreviewMode.phase {
            scroll = previewPhase.truncatingRemainder(
                dividingBy: HoneySlideRoute.verticalSlice.totalLength
            )
            didApplyPreviewPhase = true
        }
#endif
        if decor.isEmpty { seedDecor() }
    }

    func setLive(_ live: Bool) { isLive = live }
    func setReduceMotion(_ reduces: Bool) { reduceMotion = reduces }
    func setScoreTarget(_ target: CGPoint?) { scoreTarget = target }

    func setRunning(_ running: Bool) {
        if running {
#if canImport(UIKit)
            guard displayLink == nil else { return }
            lastFrameTimestamp = nil
            resetVisualQualityMonitor()
            let link = CADisplayLink(target: displayLinkTarget,
                                     selector: #selector(DisplayLinkTarget.advance(_:)))
            let fps = Float(ArenaPerformanceBudget.preferredFramesPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: fps, maximum: fps, preferred: fps
            )
            link.add(to: .main, forMode: .common)
            displayLink = link
#else
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick(dt: 1.0 / 60.0) }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
#endif
        } else {
#if canImport(UIKit)
            displayLink?.invalidate()
            displayLink = nil
            lastFrameTimestamp = nil
            resetVisualQualityMonitor(keepsQuality: true)
#else
            timer?.invalidate()
            timer = nil
#endif
        }
        isRunning = running
    }

    func stop() { setRunning(false) }

    func load(round: GameRound?) {
        lastRound = round
        if entranceRemaining > 0 || entrance > 0.05 {
            pendingRound = round
            pots.removeAll()
            loadedRoundID = nil
            return
        }
        install(round)
    }

    private func install(_ round: GameRound?) {
        guard let round else {
            if loadedRoundID != nil {
                pots.removeAll()
                loadedRoundID = nil
            }
            return
        }
        guard round.id != loadedRoundID else { return }
        loadedRoundID = round.id
        spawn(round: round)
    }

    func beginEntrance(completion: @escaping () -> Void) {
        pots.removeAll()
        loadedRoundID = nil
        pendingRound = lastRound
        targetLateral = 0
        displayLateral = 0
        activeBranch = 0
        jumpLift = 0
        landingImpact = 0
        boatRoll = 0
        entrance = 1
        entranceRemaining = RiverConfig.entranceDuration
        entranceCompletion = completion
        current = 1
        calmness = 0
        isCelebrating = false
        isReeling = false
        reelLift = 0
        grabReach = 0
    }

    func beginCalm(reduceMotion: Bool,
                   started: @escaping () -> Void,
                   completion: @escaping () -> Void) {
        self.reduceMotion = reduceMotion
        calmRemaining = RiverConfig.calmDuration
        calmStarted = false
        calmFinished = false
        onCalmStarted = started
        onCalmFinished = completion
        pots.removeAll()
        waveFinishing = false
        isReeling = false
        reelLift = 0
        grabReach = 0
        gapRemaining = 0
    }

    func endCalm() {
        calmRemaining = 0
        onCalmStarted = nil
        onCalmFinished = nil
        isCelebrating = false
    }

    func beginSteering(at point: CGPoint) {
        guard steeringOrigin == nil else { return }
        steeringOrigin = point
        steeringOriginLateral = targetLateral
    }

    func updateSteering(to point: CGPoint) {
        guard let origin = steeringOrigin, size.width > 0 else { return }
        let delta = (point.x - origin.x) / size.width * HoneySlideTuning.steeringDragScale
        targetLateral = clampedLateral(steeringOriginLateral + delta)
    }

    func endSteering() {
        steeringOrigin = nil
    }

    private func clampedLateral(_ proposed: CGFloat) -> CGFloat {
        let sample = HoneySlideRoute.verticalSlice.sample(at: scroll)
        let outer = HoneySlideTuning.railInset
        guard sample.locksBranch, activeBranch != 0 else {
            return min(outer, max(-outer, proposed))
        }
        // Once the honeycomb divider has risen, the selected branch becomes
        // a real physical corridor. The merge releases this constraint again.
        if activeBranch < 0 {
            return min(-0.28, max(-outer, proposed))
        }
        return min(outer, max(0.28, proposed))
    }

    // MARK: Spawn

    private func spawn(round: GameRound) {
        let slots = RiverFormation.slots(for: round.number)
        guard !slots.isEmpty else {
            pots = []
            return
        }
        let options = round.options
        let checkpointDistance = HoneySlideRoute.verticalSlice.nextSafeAnswerDistance(after: scroll)
        let checkpointTravel = (checkpointDistance - scroll)
            / HoneySlideTuning.cameraLookAheadDistance(for: currentSlideSpeed)
        let checkpointOffsets = HoneySlideRoute.verticalSlice.sample(at: checkpointDistance).answerOffsets
        var pots: [RiverPot] = []
        for (index, option) in options.enumerated() {
            let slot = slots[index % slots.count]
            let lateral = checkpointOffsets.isEmpty
                ? slot.lateral
                : checkpointOffsets[index % checkpointOffsets.count]
            let side: Int
            if lateral < -0.20 { side = 0 }
            else if lateral > 0.20 { side = 1 }
            else { side = index % 2 }
            pots.append(RiverPot(
                id: option.id,
                optionID: option.id,
                text: option.text,
                isCorrect: option.isCorrect,
                lateral: lateral,
                travel: checkpointTravel + slot.extra,
                fisherSide: side,
                fisherTravel: checkpointTravel + slot.extra,
                fisherVest: index % 4
            ))
        }
        self.pots = pots
        followFishers()
        seatSides()
        waveResolved = false
        waveFinishing = false
        isReeling = false
        reelLift = 0
        grabReach = 0
        gapRemaining = 0
    }

    /// Each cub sits next to its own jar and stays there. Redistributing seats
    /// every frame was what made them jump.
    private func followFishers() {
        for i in pots.indices {
            pots[i].fisherTravel = pots[i].travel
        }
    }

    /// Farthest cub on the left, then right, then left, so the helpers remain
    /// visually separated along the slide.
    private func seatSides() {
        let order = pots.indices.sorted { a, b in
            if pots[a].travel == pots[b].travel { return a < b }
            return pots[a].travel > pots[b].travel
        }
        for (rank, index) in order.enumerated() {
            pots[index].fisherSide = rank % 2
        }
    }

    private func seedDecor() {
        var items: [RiverDecor] = []
        for i in 0..<28 {
            items.append(RiverDecor(
                id: i,
                kind: i % 7,
                side: i % 2,
                along: CGFloat(i) * 0.37 + CGFloat((i * 13) % 7) * 0.05,
                scale: 0.7 + CGFloat((i * 5) % 6) * 0.08
            ))
        }
        decor = items
    }

    // MARK: Tick

#if canImport(UIKit)
    private func advance(_ displayLink: CADisplayLink) {
        // Both display-link timestamps belong to the display clock. Simulator
        // and ProMotion may advance that clock independently of callback wall
        // time, which would speed up physics and falsely trigger quality LOD.
        // Core Animation's monotonic media time measures elapsed callback time.
        let timestamp = CACurrentMediaTime()
        let measured = lastFrameTimestamp.map { timestamp - $0 }
            ?? displayLink.duration
        lastFrameTimestamp = timestamp
        updateVisualQuality(frameInterval: measured)
        tick(dt: min(max(measured, 1.0 / 120.0), 1.0 / 30.0))
    }
#endif

    private func resetVisualQualityMonitor(keepsQuality: Bool = false) {
        frameIntervalEMA = 1.0 / 60.0
        framePressureDuration = 0
        frameRecoveryDuration = 0
        qualityChangeCooldown = 0
        if !keepsQuality { visualQuality = .recommended }
    }

    private func updateVisualQuality(frameInterval rawInterval: CFTimeInterval) {
        let interval = min(max(rawInterval, 1.0 / 120.0), 0.10)
        frameIntervalEMA += (interval - frameIntervalEMA) * 0.085
        qualityChangeCooldown = max(0, qualityChangeCooldown - interval)

#if DEBUG
        // A forced level is a deterministic visual-regression mode, not a
        // starting suggestion. Keep screenshots comparable under simulator
        // launch stalls and while profiling an individual LOD tier.
        if let override = HoneySlidePreviewMode.visualQualityOverride {
            if visualQuality != override { visualQuality = override }
            framePressureDuration = 0
            frameRecoveryDuration = 0
            return
        }
#endif

        // Device pressure is authoritative. Gameplay state never changes;
        // this only sheds texture, highlight and geometry detail.
        if ArenaPerformanceBudget.isConstrained {
            if visualQuality != .constrained { visualQuality = .constrained }
            framePressureDuration = 0
            frameRecoveryDuration = 0
            return
        }

        if frameIntervalEMA > 1.0 / 52.0 {
            framePressureDuration += interval
            frameRecoveryDuration = 0
            if framePressureDuration >= 0.75,
               qualityChangeCooldown == 0,
               visualQuality > .constrained {
                visualQuality = visualQuality.steppedDown()
                framePressureDuration = 0
                qualityChangeCooldown = 1.25
            }
        } else if frameIntervalEMA < 1.0 / 57.5 {
            frameRecoveryDuration += interval
            framePressureDuration = max(0, framePressureDuration - interval * 0.5)
            if frameRecoveryDuration >= 5.0,
               qualityChangeCooldown == 0,
               visualQuality < .high {
                visualQuality = visualQuality.steppedUp()
                frameRecoveryDuration = 0
                qualityChangeCooldown = 2.0
            }
        } else {
            framePressureDuration = max(0, framePressureDuration - interval * 0.35)
            frameRecoveryDuration = max(0, frameRecoveryDuration - interval * 0.5)
        }
    }

    private func tick(dt: Double) {
        clock += dt
        current = 1 + CGFloat(sin(clock * 2.1)) * 0.04 * (1 - calmness)
        let beforeAdvance = HoneySlideRoute.verticalSlice.sample(at: scroll)
        let slopeShare = min(1, max(0, beforeAdvance.downhillSlope / (.pi * 0.22)))
        let downhillBonus = 1 + slopeShare * HoneySlideTuning.maximumDownhillSpeedBonus
        let pace = CGFloat(1.0 - 0.68 * Double(calmness)) * current
            * beforeAdvance.speedMultiplier * downhillBonus
        currentSlideSpeed = HoneySlideTuning.nominalSlideSpeed * pace
#if DEBUG
        // Keep the direct visual-QA entry point on the authored opening shot.
        // The simulation and entrance still run, so character motion, flow and
        // particles can be inspected without the capture drifting into a
        // different segment while simctl writes the screenshot.
        if !HoneySlidePreviewMode.freezesMotion {
            scroll += CGFloat(dt) * currentSlideSpeed
        }
#else
        scroll += CGFloat(dt) * currentSlideSpeed
#endif

        let sample = HoneySlideRoute.verticalSlice.sample(at: scroll)
        if sample.kind == .split,
           sample.localProgress >= HoneySlideTuning.splitCommitProgress,
           activeBranch == 0 {
            activeBranch = targetLateral < 0 ? -1 : 1
        } else if !sample.locksBranch, sample.kind != .split {
            activeBranch = 0
        }

        targetLateral = clampedLateral(targetLateral)
        let steeringStrength = sample.steeringResponseMultiplier
        let lateralError = targetLateral - displayLateral
        displayLateral += lateralError * CGFloat(min(1, dt * Double(HoneySlideTuning.steeringResponse * steeringStrength)))
        displayLateral = clampedLateral(displayLateral)

        // The rail contact is forgiving: forward travel is untouched, while
        // lateral momentum is damped and nudged back into the honey channel.
        if sample.railVisibility > 0.20,
           abs(displayLateral) > HoneySlideTuning.railInset - 0.015 {
            let inward: CGFloat = displayLateral < 0 ? 1 : -1
            targetLateral += inward * HoneySlideTuning.railBounce
            targetLateral = clampedLateral(targetLateral)
        }

        jumpLift = sample.isAir
            ? CGFloat(sin(Double(sample.localProgress) * .pi)) * HoneySlideTuning.jumpHeight
            : 0
        if lastTrackKind == .jump, sample.kind == .landing {
            landingImpact = 1
            emitSplash(at: project(lateral: displayLateral, travel: 0), honey: true)
        } else {
            landingImpact = max(0, landingImpact - CGFloat(dt / HoneySlideTuning.landingRecoveryDuration))
        }
        lastTrackKind = sample.kind

        boatRoll = Double(lateralError) * 22
            + Double(sample.banking) * 11
            + sin(clock * 3.4) * 2.4 * Double(1 - calmness)
        let landingBounce = sin(Double(landingImpact) * .pi * 2) * Double(landingImpact) * 0.025
        boatBob = CGFloat(sin(clock * 5.2)) * (0.010 + 0.008 * (1 - calmness))
            - jumpLift - CGFloat(landingBounce)

        if entranceRemaining > 0 {
            entranceRemaining = max(0, entranceRemaining - dt)
            let t = 1 - entranceRemaining / RiverConfig.entranceDuration
            let ease = 1 - pow(1 - t, 3)
            entrance = CGFloat(1 - ease)
            if entranceRemaining == 0 {
                entrance = 0
                let done = entranceCompletion
                entranceCompletion = nil
                done?()
                if let pending = pendingRound {
                    pendingRound = nil
                    install(pending)
                }
            }
        }

        tickCalm(dt: dt)
        tickPots(dt: dt)
        tickEffects(dt: dt)
        objectWillChange.send()
    }

    private func tickCalm(dt: Double) {
        guard calmRemaining > 0 else { return }
        calmRemaining = max(0, calmRemaining - dt)
        let t = 1 - calmRemaining / RiverConfig.calmDuration
        calmness = CGFloat(min(1, t * 1.4))
        current = CGFloat(1 - (1 - RiverConfig.calmSlowdown) * min(1, t * 1.1))
        if !calmStarted, t > 0.18 {
            calmStarted = true
            isCelebrating = true
            onCalmStarted?()
        }
        if calmRemaining == 0, !calmFinished {
            calmFinished = true
            onCalmFinished?()
        }
    }

    private func tickPots(dt: Double) {
        guard !pots.isEmpty || waveFinishing else { return }
        // Answer timing is time-based too: changing forward speed grows the
        // preview distance, while the decision window stays predictable.
        let step = currentSlideSpeed
            / HoneySlideTuning.cameraLookAheadDistance(for: currentSlideSpeed)
            * CGFloat(dt)
        let duration = reduceMotion ? RiverConfig.reelDurationReduced : RiverConfig.reelDuration
        let grabDuration = reduceMotion ? RiverConfig.grabDurationReduced : RiverConfig.grabDuration
        if isReeling {
            reelLift = min(1, reelLift + CGFloat(dt / duration))
        }
        for i in pots.indices {
            // A pot that is being reeled stays put over the water while the
            // line pulls it in. The rest keep approaching until they are hit
            // or they pass the boat and get reeled themselves.
            if pots[i].grabFlight == 0 {
                pots[i].travel -= step
            }
            if pots[i].hit { pots[i].hitAge += dt }
            if pots[i].fisherReact > 0 {
                pots[i].fisherReact = max(0, pots[i].fisherReact - dt)
            }
            if pots[i].grabFlight > 0 {
                pots[i].grabFlight = min(1, pots[i].grabFlight + CGFloat(dt / grabDuration))
            }
            // The empty stick only comes in once the jar has left the loop.
            if pots[i].hit, pots[i].reel == 0,
               pots[i].grabFlight >= RiverConfig.grabDetach {
                pots[i].reel = 0.001
                pots[i].fisherReact = duration + 0.28
            }
            if !pots[i].hit, pots[i].reel == 0, !isReeling,
               pots[i].travel < -RiverConfig.hitTravel {
                pots[i].reel = 0.001
                pots[i].fisherReact = duration + 0.28
            }
            if pots[i].reel > 0 {
                pots[i].reel = min(1, pots[i].reel + CGFloat(dt / duration))
            }
        }
        followFishers()
        tickGrab()

        if isLive || !waveResolved {
            resolveHits()
        }

        if !waveFinishing, !isReeling, pots.allSatisfy({ $0.reel >= 1 && (!$0.hit || $0.grabFlight >= 1) }) {
            waveFinishing = true
            gapRemaining = 0.08
            onTutorialEvent?(.clearedWave)
        }
        if waveFinishing {
            gapRemaining = max(0, gapRemaining - dt)
            if gapRemaining == 0 {
                pots.removeAll()
                waveFinishing = false
                isReeling = false
                reelLift = 0
                grabReach = 0
                let done = onWaveComplete
                DispatchQueue.main.async { done?() }
            }
        }
    }

    private func resolveHits() {
        guard !waveResolved else { return }
        let boatTravel: CGFloat = 0
        for i in pots.indices {
            let pot = pots[i]
            guard !pot.hit else { continue }
            let near = abs(pot.travel - boatTravel) < RiverConfig.hitTravel
            let aligned = abs(displayLateral - pot.lateral) < RiverConfig.hitLateralSlop
            guard near && aligned else { continue }
            pots[i].hit = true
            pots[i].hitAge = 0.001
            pots[i].grabFlight = 0.001
            emitSplash(at: project(lateral: pot.lateral, travel: pot.travel),
                       honey: pot.isCorrect)
            if pot.isCorrect {
                waveResolved = true
                emitReward(from: project(lateral: pot.lateral, travel: pot.travel))
                yankEveryRod()
            } else {
                pots[i].fisherReact = 0.45
            }
            _ = onAnswer?(pot.optionID)
            onTutorialEvent?(.hitPot)
            return
        }
    }

    private func tickEffects(dt: Double) {
        let gravity: CGFloat = 980
        for i in splashes.indices where splashes[i].isActive {
            splashes[i].age += dt
            splashes[i].vy += gravity * CGFloat(dt)
            splashes[i].x += splashes[i].vx * CGFloat(dt)
            splashes[i].y += splashes[i].vy * CGFloat(dt)
        }
        for i in rewards.indices.reversed() {
            rewards[i].age += dt
            if rewards[i].age >= RiverConfig.rewardFlight {
                rewards.remove(at: i)
                onRewardArrived?()
            }
        }
        splashBudget += 1
        let cadence = reduceMotion ? max(8, visualQuality.splashCadence) : visualQuality.splashCadence
        if splashBudget % cadence == 0, size.width > 1, entrance < 0.4, calmness < 0.85 {
            emitDroplet(nearBoat: true, honey: true)
            if !reduceMotion, visualQuality != .constrained {
                emitDroplet(nearBoat: true, honey: true)
            }
        }
    }

    /// The captain's paw follows whichever jar is still on its way into the boat.
    private func tickGrab() {
        var flying: RiverPot?
        for pot in pots where pot.hit && pot.grabFlight < 1 {
            flying = pot
        }
        if let flying {
            let t = min(max(flying.grabFlight, 0), 1)
            grabReach = CGFloat(sin(Double(t) * .pi))
            let projection = RiverProjection(size: size, phase: scroll, speed: currentSlideSpeed)
            let water = projection.point(lateral: flying.lateral, travel: flying.travel)
            let hang = CGPoint(
                x: water.x,
                y: water.y - RiverConfig.potSize(isPad: isPad) * projection.scale(for: flying.travel) * 1.15
            )
            let hull = projection.point(lateral: displayLateral, travel: 0)
            let catchPoint = CGPoint(x: hull.x, y: hull.y - RiverConfig.boatSize(isPad: isPad) * 0.10)
            let ease = 1 - pow(1 - max(0, (t - RiverConfig.grabDetach) / max(0.001, 1 - RiverConfig.grabDetach)), 3)
            grabTarget = CGPoint(
                x: hang.x + (catchPoint.x - hang.x) * ease,
                y: hang.y + (catchPoint.y - hang.y) * ease - CGFloat(sin(Double(ease) * .pi)) * 36
            )
        } else if grabReach > 0.01 {
            grabReach = max(0, grabReach - 0.08)
        } else {
            grabReach = 0
        }
    }

    /// Good honey: leftover cubs yank their still-loaded sticks, and the next
    /// sum starts once that pull — and the caught jar's drop into the boat —
    /// have both landed.
    private func yankEveryRod() {
        let duration = reduceMotion ? RiverConfig.reelDurationReduced : RiverConfig.reelDuration
        let grab = reduceMotion ? RiverConfig.grabDurationReduced : RiverConfig.grabDuration
        isReeling = true
        reelLift = 0.001
        for i in pots.indices {
            if !pots[i].hit, pots[i].reel == 0 {
                pots[i].reel = 0.001
            }
            if !pots[i].hit {
                pots[i].fisherReact = duration + 0.28
            }
        }
        waveFinishing = true
        gapRemaining = max(duration, grab) + 0.12
        onTutorialEvent?(.clearedWave)
    }

    private func emitSplash(at point: CGPoint, honey: Bool) {
        let burst = reduceMotion ? 5 : 9
        for _ in 0..<burst {
            emitDroplet(at: point, honey: honey, burst: true)
        }
    }

    private func emitDroplet(nearBoat: Bool = false, at point: CGPoint? = nil, honey: Bool, burst: Bool = false) {
        let hull = point ?? RiverProjection(size: size, phase: scroll, speed: currentSlideSpeed)
            .point(lateral: displayLateral + CGFloat.random(in: -0.28...0.28),
                   travel: CGFloat.random(in: -0.02...0.06))
        let side: CGFloat = Bool.random() ? 1 : -1
        let up = burst ? CGFloat.random(in: 220...520) : CGFloat.random(in: 160...380)
        let out = burst ? CGFloat.random(in: 40...180) : CGFloat.random(in: 20...140)
        let slot = splashes.firstIndex(where: { !$0.isActive })
            ?? splashes.indices.max(by: { splashes[$0].age < splashes[$1].age })
            ?? splashes.startIndex
        splashes[slot].age = 0
        splashes[slot].life = burst ? 0.70 : Double.random(in: 0.40...0.65)
        splashes[slot].x = hull.x + CGFloat.random(in: -18...18)
        splashes[slot].y = hull.y + CGFloat.random(in: -8...12)
        splashes[slot].vx = side * out * (nearBoat ? 1 : 0.85)
        splashes[slot].vy = -up
        splashes[slot].scale = (burst ? 0.9 : 0.55) + CGFloat.random(in: 0...0.55)
        splashes[slot].honey = honey
    }

    private func emitReward(from point: CGPoint) {
        let target = scoreTarget ?? CGPoint(x: size.width * 0.5, y: 80)
        rewards.append(RiverReward(id: UUID(), age: 0, start: point, target: target))
    }

    func project(lateral: CGFloat, travel: CGFloat) -> CGPoint {
        RiverProjection(size: size, phase: scroll, speed: currentSlideSpeed)
            .point(lateral: lateral, travel: travel)
    }

#if DEBUG
    var debugPerformanceText: String {
        let route = HoneySlideRoute.verticalSlice
        let sample = route.sample(at: scroll)
        let fps = frameIntervalEMA > 0 ? 1 / frameIntervalEMA : 0
        let projection = RiverProjection(size: size, phase: scroll, speed: currentSlideSpeed)
        let ready = projection.generationReadyDistance
        return String(format: "FPS %.0f   %.1f ms\nSpeed %.1f   slope %.1f°\nP %.0f m   C %.0f m   elevation %.1f\nActive -%.0f m (%.1f s)   visible +%.0f m (%.1f s)\nReady +%.0f m (%.1f s)   %d/%d segments\nTrack gen %.2f ms   particles %d pooled",
                      fps, frameIntervalEMA * 1_000,
                      currentSlideSpeed, sample.downhillSlope * 180 / .pi,
                      scroll, projection.cameraProgress, sample.elevation,
                      projection.activeBehindDistance, HoneySlideTuning.visibleBehindSeconds,
                      projection.visibleAheadDistance, HoneySlideTuning.visibleAheadSeconds,
                      ready, HoneySlideTuning.generationLookAheadSeconds,
                      activeSegmentCount(behind: projection.activeBehindDistance,
                                         ahead: ready), route.segments.count,
                      HoneySlideProfiler.latestTrackGenerationMilliseconds, splashes.count)
    }

    private func activeSegmentCount(behind: CGFloat, ahead: CGFloat) -> Int {
        let route = HoneySlideRoute.verticalSlice
        var ids = Set<String>()
        let step: CGFloat = 4
        var cursor = -behind
        while cursor <= ahead {
            ids.insert(route.sample(at: scroll + cursor).segmentID)
            cursor += step
        }
        return ids.count
    }
#endif
}

// MARK: - Perspective

struct RiverProjection {
    let size: CGSize
    /// Absolute progress through the authored segment timeline.
    let phase: CGFloat
    let speed: CGFloat
    let lookAheadDistance: CGFloat
    let activeBehindDistance: CGFloat
    let visibleAheadDistance: CGFloat
    let generationReadyDistance: CGFloat
    let renderNearTravel: CGFloat
    let renderFarTravel: CGFloat
    let cameraProgress: CGFloat

    private let currentFrame: HoneyTrackFrame
    private let cameraPosition: HoneyVector3
    private let cameraForward: HoneyVector3
    private let cameraRight: HoneyVector3
    private let cameraUp: HoneyVector3
    private let focalLength: CGFloat
    private let principalY: CGFloat
    private let currentCameraDepth: CGFloat

    private var route: HoneySlideRoute { .verticalSlice }

    init(size: CGSize,
         phase: CGFloat = 0,
         speed: CGFloat = HoneySlideTuning.nominalSlideSpeed) {
        self.size = size
        self.phase = phase
        self.speed = speed
        lookAheadDistance = HoneySlideTuning.cameraLookAheadDistance(for: speed)
        let route = HoneySlideRoute.verticalSlice
        let current = route.frame(at: phase)
        currentFrame = current

        activeBehindDistance = HoneySlideTuning.activeBehindDistance(for: speed)
        visibleAheadDistance = HoneySlideTuning.visibleAheadDistance(for: speed)
        generationReadyDistance = HoneySlideTuning.generationLookAheadDistance(for: speed)

        let chaseDistance = max(13, speed * HoneySlideTuning.cameraChaseSeconds)
        cameraProgress = phase - chaseDistance
        let cameraTrackFrame = route.frame(at: phase - chaseDistance)
        let cameraHeight: CGFloat = 8.5
        let camera = cameraTrackFrame.position + HoneyVector3.up * cameraHeight
        cameraPosition = camera

        let aimDistance = speed * HoneySlideTuning.cameraAimSeconds
            * current.sample.cameraLookAhead
        let authoredAim = route.frame(at: phase + aimDistance).position
        // Pitch follows only part of the track's vertical change. Yaw follows
        // the spline, while world-up remains stable, so a 30° drop still reads
        // as a 30° drop against trees, cliffs and the horizon.
        let pitchFollow: CGFloat = 0.36
        let aim = HoneyVector3(
            x: authoredAim.x,
            y: current.position.y
                + (authoredAim.y - current.position.y) * pitchFollow - 2.0,
            z: authoredAim.z
        )
        let forward = (aim - camera).normalized
        cameraForward = forward
        cameraRight = HoneyVector3.up.cross(forward).normalized
        cameraUp = forward.cross(cameraRight).normalized

        let fovRadians = HoneySlideTuning.perspectiveFOVDegrees * .pi / 180
        focalLength = size.height * 0.5 / tan(fovRadians * 0.5)
        let currentRelative = current.position - camera
        let currentDepth = max(HoneySlideTuning.cameraNearPlane,
                               currentRelative.dot(forward))
        currentCameraDepth = currentDepth
        let currentVertical = currentRelative.dot(cameraUp)
        let desiredBoatY = size.height * 0.79
        principalY = desiredBoatY + currentVertical / currentDepth * focalLength

        // Keep the submitted near cap just in front of the camera plane, where
        // it projects below and wider than the viewport. The authored route
        // itself remains active for the full two-second safety window.
        let renderBehind = max(0, chaseDistance - HoneySlideTuning.cameraNearPlane * 1.7)
        renderNearTravel = -renderBehind / lookAheadDistance
        // Twelve seconds are submitted: ten seconds fully readable plus a
        // two-second atmospheric guard. Fifteen seconds are ready in the route
        // cache/debug lifecycle before any of it can enter that range.
        let renderAhead = visibleAheadDistance + speed * 2
        renderFarTravel = renderAhead / lookAheadDistance
    }

    var horizonY: CGFloat {
        let horizontalForward = sqrt(cameraForward.x * cameraForward.x
                                     + cameraForward.z * cameraForward.z)
        let pitch = atan2(cameraForward.y, max(0.001, horizontalForward))
        return min(size.height * 0.31,
                   max(size.height * 0.10, principalY + tan(pitch) * focalLength))
    }
    var boatY: CGFloat { size.height * 0.79 }
    var centerX: CGFloat { size.width * 0.5 }

    struct ProjectedTrackSample {
        let track: HoneyTrackSample
        let nearness: CGFloat
        let scale: CGFloat
        let y: CGFloat
        let center: CGFloat
        let halfWidth: CGFloat
        let leftEdgeY: CGFloat
        let rightEdgeY: CGFloat

        var bandEdges: [(left: CGFloat, right: CGFloat)] {
            guard track.splitAmount > 0.055 else {
                return [(center - halfWidth, center + halfWidth)]
            }
            let raw = min(max((track.splitAmount - 0.055) / 0.945, 0), 1)
            let split = raw * raw * (3 - 2 * raw)
            let branchHalf = halfWidth * (0.50 - 0.06 * split)
            let offset = halfWidth * (0.50 + 0.06 * split)
            return [
                (center - offset - branchHalf, center - offset + branchHalf),
                (center + offset - branchHalf, center + offset + branchHalf)
            ]
        }
    }

    /// 0 at the far water, 1 at the boat. Same far plane as `y`, so size and
    /// position stay in step and the approach never eases off near the hull.
    func nearness(for travel: CGFloat) -> CGFloat {
        let distance = max(0, travel * lookAheadDistance)
        return 1 - min(1, distance / max(1, visibleAheadDistance))
    }

    func scale(for travel: CGFloat) -> CGFloat {
        let point = route.frame(at: phase + travel * lookAheadDistance).position
        let depth = max(HoneySlideTuning.cameraNearPlane,
                        (point - cameraPosition).dot(cameraForward))
        return min(2.4, max(0.025, currentCameraDepth / depth))
    }

    private func project(_ world: HoneyVector3) -> CGPoint {
        let relative = world - cameraPosition
        let depth = max(HoneySlideTuning.cameraNearPlane,
                        relative.dot(cameraForward))
        return CGPoint(x: centerX + relative.dot(cameraRight) / depth * focalLength,
                       y: principalY - relative.dot(cameraUp) / depth * focalLength)
    }

    /// One route lookup produces every screen-space value needed by a track
    /// cross-section. Canvas passes share these projected sections instead of
    /// recursively re-sampling center, elevation, width and split topology.
    func projectedSample(for travel: CGFloat) -> ProjectedTrackSample {
        let frame = route.frame(at: phase + travel * lookAheadDistance)
        let track = frame.sample
        let near = nearness(for: travel)
        let perspective = scale(for: travel)
        let bank = track.banking
        let crossAxis = (frame.right * cos(bank) + frame.surfaceUp * sin(bank)).normalized
        let worldHalfWidth = HoneySlideTuning.worldTrackHalfWidth * track.width
        let centerPoint = project(frame.position)
        let leftPoint = project(frame.position - crossAxis * worldHalfWidth)
        let rightPoint = project(frame.position + crossAxis * worldHalfWidth)
        let center = (leftPoint.x + rightPoint.x) * 0.5
        let halfWidth = max(0.5, abs(rightPoint.x - leftPoint.x) * 0.5)
        return ProjectedTrackSample(
            track: track,
            nearness: near,
            scale: perspective,
            y: centerPoint.y,
            center: center,
            halfWidth: halfWidth,
            leftEdgeY: leftPoint.y,
            rightEdgeY: rightPoint.y
        )
    }

    func y(for travel: CGFloat) -> CGFloat {
        projectedSample(for: travel).y
    }

    func bankX(side: Int, travel: CGFloat) -> CGFloat {
        let inset = size.width * (0.07 + 0.04 * nearness(for: travel))
        return side == 0
            ? riverLeft(travel: travel) - inset
            : riverRight(travel: travel) + inset
    }

    func meander(for travel: CGFloat) -> CGFloat {
        projectedSample(for: travel).center - centerX
    }

    func sample(for travel: CGFloat) -> HoneyTrackSample {
        route.sample(at: phase + travel * lookAheadDistance)
    }

    func halfWidth(travel: CGFloat) -> CGFloat {
        projectedSample(for: travel).halfWidth
    }

    func x(lateral: CGFloat, travel: CGFloat) -> CGFloat {
        let projected = projectedSample(for: travel)
        return projected.center + lateral * projected.halfWidth * 0.82
    }

    func point(lateral: CGFloat, travel: CGFloat) -> CGPoint {
        let projected = projectedSample(for: travel)
        let t = min(1, max(0, (lateral * 0.82 + 1) * 0.5))
        return CGPoint(x: projected.center + lateral * projected.halfWidth * 0.82,
                       y: projected.leftEdgeY
                        + (projected.rightEdgeY - projected.leftEdgeY) * t)
    }

    func riverLeft(travel: CGFloat) -> CGFloat {
        riverLeftStable(travel: travel)
    }

    func riverRight(travel: CGFloat) -> CGFloat {
        riverRightStable(travel: travel)
    }

    /// Bank edge without the flowing wiggle, so a sitting cub does not slide
    /// inland and out again as the current scrolls.
    func riverLeftStable(travel: CGFloat) -> CGFloat {
        let projected = projectedSample(for: travel)
        return projected.center - projected.halfWidth
    }

    func riverRightStable(travel: CGFloat) -> CGFloat {
        let projected = projectedSample(for: travel)
        return projected.center + projected.halfWidth
    }

    func riverWidth(travel: CGFloat) -> CGFloat {
        riverRight(travel: travel) - riverLeft(travel: travel)
    }

    /// `t` is 0 at the left bank and 1 at the right, so a constant `t` is a
    /// filament of current that follows the meander all the way to the camera.
    func across(_ t: CGFloat, travel: CGFloat) -> CGFloat {
        let left = riverLeft(travel: travel)
        return left + (riverRight(travel: travel) - left) * t
    }

    func pointAcross(_ t: CGFloat, travel: CGFloat) -> CGPoint {
        let projected = projectedSample(for: travel)
        let left = projected.center - projected.halfWidth
        return CGPoint(x: left + projected.halfWidth * 2 * t,
                       y: projected.leftEdgeY
                        + (projected.rightEdgeY - projected.leftEdgeY) * t)
    }

    /// One band on normal track, two gradually separating bands through a
    /// split/branch/merge. Values are physical screen-space edges.
    func bandEdges(travel: CGFloat) -> [(left: CGFloat, right: CGFloat)] {
        projectedSample(for: travel).bandEdges
    }

    func riverPath() -> Path {
        var path = Path()
        let steps = 56
        let far = renderFarTravel
        let near = renderNearTravel
        for i in 0...steps {
            let travel = far - CGFloat(i) / CGFloat(steps) * (far - near)
            let point = CGPoint(x: riverLeft(travel: travel), y: y(for: travel))
            if i == 0 { path.move(to: point) }
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: riverLeft(travel: near), y: size.height))
        path.addLine(to: CGPoint(x: riverRight(travel: near), y: size.height))
        for i in (0...steps).reversed() {
            let travel = far - CGFloat(i) / CGFloat(steps) * (far - near)
            path.addLine(to: CGPoint(x: riverRight(travel: travel), y: y(for: travel)))
        }
        path.addLine(to: CGPoint(x: riverRight(travel: far), y: y(for: far)))
        path.closeSubpath()
        return path
    }
}
