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

/// Converts mathematical reading load and session progress into a predictable
/// decision window. It changes where a wave is placed on the authored route;
/// the rider and camera keep their normal speed, so difficulty never feels like
/// hidden input lag or a sudden physics change.
nonisolated struct RiverRoundPacing: Equatable {
    let decisionTime: Double

    static func make(roundNumber: Int,
                     maximumRounds: Int,
                     question: MathQuestion) -> Self {
        let safeMaximum = max(1, maximumRounds)
        let progress = Double(max(0, min(safeMaximum, roundNumber) - 1))
            / Double(max(1, safeMaximum - 1))
        var duration = GameConfig.riverApproachDuration
            - progress * GameConfig.riverSessionPressure

        if roundNumber <= 1 {
            duration += GameConfig.riverFirstRoundWarmup
        } else if roundNumber == 2 {
            duration += GameConfig.riverSecondRoundWarmup
        }

        switch question.kind {
        case .fraction:
            duration += GameConfig.riverFractionReadingBonus
        case .percentage:
            duration += GameConfig.riverPercentageReadingBonus
        case .addition, .subtraction, .multiplication:
            break
        }

        if question.prompt.count >= GameConfig.riverLongPromptThreshold {
            duration += GameConfig.riverLongPromptReadingBonus
        }

        return Self(decisionTime: min(GameConfig.riverMaximumApproachDuration,
                                      max(GameConfig.riverMinimumApproachDuration,
                                          duration)))
    }
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
    /// Four broad columns with a light depth stagger. The option order changes
    /// per round, while the minimum horizontal separation stays predictable.
    static func slots(for roundNumber: Int) -> [(lateral: CGFloat, extra: CGFloat)] {
        let extra: CGFloat = 0.02
        switch roundNumber % 6 {
        case 0: return [(-0.30, 0), (-0.84, extra), (0.84, extra), (0.30, extra * 2)]
        case 1: return [(-0.84, 0), (-0.30, extra * 0.85), (0.84, extra * 1.7), (0.30, extra * 2.5)]
        case 2: return [(0.84, 0), (0.30, extra * 0.85), (-0.84, extra * 1.7), (-0.30, extra * 2.5)]
        case 3: return [(-0.84, 0), (0.84, extra * 0.7), (0.30, extra * 1.6), (-0.30, extra * 2.4)]
        case 4: return [(0.30, 0), (0.84, extra * 0.8), (-0.84, extra * 1.6), (-0.30, extra * 2.4)]
        default: return [(-0.84, 0), (0.84, 0), (-0.30, extra * 1.15), (0.30, extra * 2.2)]
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
    /// Physical metres from the track centerline. This remains stable when a
    /// width multiplier or local frame changes; `displayLateral` is derived
    /// only for projection and existing answer hit testing.
    @Published private(set) var lateralPosition: CGFloat = 0
    @Published private(set) var lateralVelocity: CGFloat = 0
    @Published private(set) var steeringTargetLateral: CGFloat = 0
    @Published private(set) var steeringInput: CGFloat = 0
    @Published private(set) var curveDriftAcceleration: CGFloat = 0
    @Published private(set) var displayLateral: CGFloat = 0
    @Published private(set) var cameraLateral: CGFloat = 0
    @Published private(set) var activeBranch: Int = 0
    @Published private(set) var jumpLift: CGFloat = 0
    @Published private(set) var landingImpact: CGFloat = 0
    @Published private(set) var clock: Double = 0
    @Published private(set) var scroll: CGFloat = 0
    @Published private(set) var currentSlideSpeed: CGFloat = HoneySlideTuning.nominalSlideSpeed
    @Published private(set) var boatRoll: Double = 0
    @Published private(set) var boatPitch: Double = 0
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
    /// Purely visual/reward state. It never participates in slide speed or
    /// answer pacing.
    @Published private(set) var honeyFlowActive = false
    @Published private(set) var size: CGSize = .zero
    @Published private(set) var isPad = false

    var onAnswer: ((UUID) -> Bool)?
    var onRewardArrived: (() -> Void)?
    var onWaveComplete: (() -> Void)?
    var onBranchHoney: (() -> Void)?
    var onLanding: (() -> Void)?
    var onTutorialEvent: ((CrabTutorialEvent) -> Void)?

    private var loadedRoundID: UUID?
    private var maximumRounds = GameConfig.levelMaximum
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
    private var rewardedBranchKeys: Set<String> = []
#if DEBUG
    private var didApplyPreviewPhase = false
    private var previousDiagnosticPosition: HoneyVector3?
    private var previousDiagnosticFrame: HoneyTrackFrame?
    private var previousDiagnosticSegmentID: String?
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
    func setHoneyFlowActive(_ active: Bool) { honeyFlowActive = active }
    func configureSession(maximumRounds: Int) {
        self.maximumRounds = max(1, maximumRounds)
    }

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
        lateralPosition = 0
        lateralVelocity = 0
        steeringTargetLateral = 0
        steeringInput = 0
        curveDriftAcceleration = 0
        displayLateral = 0
        cameraLateral = 0
        activeBranch = 0
        jumpLift = 0
        landingImpact = 0
        boatRoll = 0
        boatPitch = 0
        entrance = 1
        entranceRemaining = RiverConfig.entranceDuration
        entranceCompletion = completion
        current = 1
        calmness = 0
        isCelebrating = false
        honeyFlowActive = false
        rewardedBranchKeys.removeAll(keepingCapacity: true)
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
        steeringOriginLateral = displayLateral
        steeringTargetLateral = displayLateral
    }

    func updateSteering(to point: CGPoint) {
        guard let origin = steeringOrigin, size.width > 0 else { return }
        let delta = (point.x - origin.x) / size.width
            * HoneySlideTuning.steeringDragScale
        steeringTargetLateral = min(1, max(-1, steeringOriginLateral + delta))
        let error = steeringTargetLateral - displayLateral
        steeringInput = min(1, max(-1, error / 0.24))
    }

    func endSteering() {
        steeringOrigin = nil
        // Releasing the finger means stop steering at the current location.
        // Keeping the old force alive made the rider coast across the slide.
        steeringTargetLateral = displayLateral
        steeringInput = 0
    }

    // MARK: Spawn

    private func spawn(round: GameRound) {
        let slots = RiverFormation.slots(for: round.number)
        guard !slots.isEmpty else {
            pots = []
            return
        }
        let options = round.options
        let pacing = RiverRoundPacing.make(roundNumber: round.number,
                                           maximumRounds: maximumRounds,
                                           question: round.question)
        let minimumLeadDistance = currentSlideSpeed * CGFloat(pacing.decisionTime)
        let checkpointDistance = HoneySlideRoute.verticalSlice.nextSafeAnswerDistance(
            after: scroll,
            minimumLeadDistance: minimumLeadDistance
        )
        let checkpointTravel = (checkpointDistance - scroll)
            / HoneySlideTuning.cameraLookAheadDistance(for: currentSlideSpeed)
        let checkpoint = HoneySlideRoute.verticalSlice.sample(at: checkpointDistance)
        let checkpointOffsets = checkpoint.answerOffsets
        var pots: [RiverPot] = []
        for (index, option) in options.enumerated() {
            let slot = slots[index % slots.count]
            let proposedLateral = checkpointOffsets.isEmpty
                ? slot.lateral
                : checkpointOffsets[index % checkpointOffsets.count]
            let lateral = HoneySlideTuning.answerLateral(proposedLateral,
                                                         trackWidth: checkpoint.width)
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
#if DEBUG
        if HoneySlidePreviewMode.freezesAnswers {
            for index in pots.indices {
                let previewTravel = CGFloat(0.30) + CGFloat(index) * 0.015
                pots[index].travel = previewTravel
                pots[index].fisherTravel = previewTravel
            }
        }
        if let previewFeedback = HoneySlidePreviewMode.answerFeedback,
           let chosenIndex = pots.firstIndex(where: {
               previewFeedback == .correct ? $0.isCorrect : !$0.isCorrect
           }) {
            pots[chosenIndex].hit = true
            pots[chosenIndex].hitAge = 0.08
        }
#endif
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

        let route = HoneySlideRoute.verticalSlice
        let frame = route.frame(at: scroll)
        let sample = frame.sample
        if sample.kind == .split,
           sample.localProgress >= HoneySlideTuning.splitCommitProgress,
           activeBranch == 0 {
            activeBranch = lateralPosition < 0 ? -1 : 1
            if isLive {
                let lap = Int(floor(scroll / route.totalLength))
                let rewardKey = "\(lap).\(sample.segmentID)"
                if rewardedBranchKeys.insert(rewardKey).inserted {
                    onBranchHoney?()
                    emitSplash(at: project(lateral: displayLateral, travel: 0), honey: true)
                }
            }
        } else if !sample.locksBranch, sample.kind != .split {
            activeBranch = 0
        }

#if DEBUG
        if let previewSteering = HoneySlidePreviewMode.steeringInput {
            steeringInput = previewSteering
            steeringTargetLateral = previewSteering
        }
#endif
        integrateLateralMotion(dt: dt, frame: frame)
        updateCameraFollow(dt: dt)

        jumpLift = sample.isAir
            ? CGFloat(sin(Double(sample.localProgress) * .pi)) * HoneySlideTuning.jumpHeight
            : 0
        if lastTrackKind == .jump, sample.kind == .landing {
            landingImpact = 1
            emitSplash(at: project(lateral: displayLateral, travel: 0), honey: true)
            onLanding?()
        } else {
            landingImpact = max(0, landingImpact - CGFloat(dt / HoneySlideTuning.landingRecoveryDuration))
        }
        lastTrackKind = sample.kind

        // Surface banking is applied from the projection itself. This is only
        // the small, smoothed suspension/steering response on top of it.
        let lateralSpeedLimit = HoneySlideTuning.maximumLateralSpeed(for: sample.width)
        let velocityShare = lateralVelocity / max(0.001, lateralSpeedLimit)
        let targetRoll = Double(velocityShare) * 5.5
            + Double(steeringInput) * 2.0
            + sin(clock * 3.4) * 1.15 * Double(1 - calmness)
        boatRoll += (targetRoll - boatRoll) * min(1, dt * 7.5)
        let targetPitch = Double(sample.downhillSlope * 180 / .pi) * 0.22
        boatPitch += (targetPitch - boatPitch) * min(1, dt * 5.5)
        let landingBounce = sin(Double(landingImpact) * .pi * 2) * Double(landingImpact) * 0.025
        boatBob = CGFloat(sin(clock * 5.2)) * (0.003 + 0.002 * (1 - calmness))
            - jumpLift - CGFloat(landingBounce)

#if DEBUG
        diagnoseSnap(dt: dt, frame: frame)
#endif

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

    private func integrateLateralMotion(dt: Double, frame: HoneyTrackFrame) {
        let sample = frame.sample
        let halfWidth = HoneySlideTuning.worldTrackHalfWidth * sample.width
        let allowedNormalized = HoneySlideTuning.playableLateralLimit(for: sample.width)
        var minimum = -halfWidth * allowedNormalized
        var maximum = halfWidth * allowedNormalized
        if sample.locksBranch, activeBranch < 0 {
            maximum = -halfWidth * 0.28
        } else if sample.locksBranch, activeBranch > 0 {
            minimum = halfWidth * 0.28
        }

        var targetNormalized = min(allowedNormalized,
                                   max(-allowedNormalized, steeringTargetLateral))
        if sample.locksBranch, activeBranch < 0 {
            targetNormalized = min(-0.28, targetNormalized)
        } else if sample.locksBranch, activeBranch > 0 {
            targetNormalized = max(0.28, targetNormalized)
        }
        steeringTargetLateral = targetNormalized
        let targetPosition = targetNormalized * halfWidth
        let lateralSpeedLimit = HoneySlideTuning.maximumLateralSpeed(for: sample.width)

        let bankingHelpsCurve = sample.banking * frame.curvature > 0
        let bankCompensation = bankingHelpsCurve
            ? max(0.38, 1 - abs(sample.banking) * HoneySlideTuning.bankingDriftCompensation)
            : 1
        let rawCurveDrift = -frame.curvature * currentSlideSpeed * currentSlideSpeed
            * HoneySlideTuning.curveDriftStrength * bankCompensation
        curveDriftAcceleration = min(HoneySlideTuning.maxCurveDriftAcceleration,
                                     max(-HoneySlideTuning.maxCurveDriftAcceleration,
                                         rawCurveDrift))

        var remaining = min(max(dt, 0), 1.0 / 30.0)
        while remaining > 0.000_001 {
            let step = min(remaining, HoneySlideTuning.lateralSimulationStep)
            let h = CGFloat(step)
            // Treat a drag as a desired position, not as an indefinitely held
            // acceleration. A damped velocity servo stays responsive at 30,
            // 60 and 120 Hz and comes to rest when the drag is released.
            let response = HoneySlideTuning.steeringResponse
                * sample.steeringResponseMultiplier
            let desiredVelocity = min(lateralSpeedLimit,
                                      max(-lateralSpeedLimit,
                                          (targetPosition - lateralPosition) * response))
            let velocityBlend = CGFloat(1 - exp(-Double(
                response * HoneySlideTuning.lateralDrag
            ) * step))
            lateralVelocity += (desiredVelocity - lateralVelocity) * velocityBlend
            lateralVelocity += curveDriftAcceleration * h
            lateralVelocity = min(lateralSpeedLimit,
                                  max(-lateralSpeedLimit, lateralVelocity))
            lateralPosition += lateralVelocity * h

            if lateralPosition < minimum {
                lateralPosition = minimum
                if lateralVelocity < 0 {
                    lateralVelocity = -lateralVelocity * HoneySlideTuning.railVelocityRetention
                }
            } else if lateralPosition > maximum {
                lateralPosition = maximum
                if lateralVelocity > 0 {
                    lateralVelocity = -lateralVelocity * HoneySlideTuning.railVelocityRetention
                }
            }
            remaining -= step
        }
        displayLateral = min(allowedNormalized,
                             max(-allowedNormalized, lateralPosition / max(0.001, halfWidth)))
    }

    private func updateCameraFollow(dt: Double) {
        let magnitude = max(0, abs(displayLateral) - HoneySlideTuning.cameraFollowDeadZone)
        let direction: CGFloat = displayLateral < 0 ? -1 : 1
        let target = direction * magnitude * HoneySlideTuning.cameraFollowStrength
        let blend = CGFloat(1 - exp(-Double(HoneySlideTuning.cameraFollowResponse)
                                    * max(0, dt)))
        cameraLateral += (target - cameraLateral) * blend
    }

#if DEBUG
    private func diagnoseSnap(dt: Double, frame: HoneyTrackFrame) {
        let route = HoneySlideRoute.verticalSlice
        let surface = route.surface(at: scroll, lateral: displayLateral)
        let playerPosition = surface.position
        let projection = RiverProjection(size: size, phase: scroll, speed: currentSlideSpeed,
                                         focusLateral: cameraLateral)
        let positionDelta = previousDiagnosticPosition.map { (playerPosition - $0).length } ?? 0
        let expectedDelta = currentSlideSpeed * CGFloat(dt)
        let basisDot = previousDiagnosticFrame.map { $0.right.dot(frame.right) } ?? 1
        let segmentChanged = previousDiagnosticSegmentID != nil
            && previousDiagnosticSegmentID != frame.sample.segmentID
        let unexpectedMovement = positionDelta > expectedDelta * 2.2 + 0.45
        let basisJump = basisDot < 0.997
        if segmentChanged || unexpectedMovement || basisJump {
            let p = playerPosition
            let c = frame.position
            let t = frame.tangent
            let r = frame.right
            let u = frame.surfaceUp
            let camera = projection.debugCameraPosition
            print(String(format:
                "[HoneySlide motion %@] progress=%.3f dt=%.4f segment=%@ nextBoundary=%.3f\nplayer=(%.3f,%.3f,%.3f) lateral=%.3fm velocity=%.3fm/s input=%.3f drift=%.3fm/s²\ncenter=(%.3f,%.3f,%.3f) tangent=(%.4f,%.4f,%.4f) right=(%.4f,%.4f,%.4f) up=(%.4f,%.4f,%.4f) curvature=%.6f\ncamera=(%.3f,%.3f,%.3f) frameDot=%.6f movement=%.3f expected=%.3f",
                segmentChanged ? "boundary" : "spike",
                scroll, dt, frame.sample.segmentID,
                route.distanceToNextSegmentBoundary(after: scroll),
                p.x, p.y, p.z, lateralPosition, lateralVelocity,
                steeringInput, curveDriftAcceleration,
                c.x, c.y, c.z,
                t.x, t.y, t.z, r.x, r.y, r.z, u.x, u.y, u.z,
                frame.curvature,
                camera.x, camera.y, camera.z,
                basisDot, positionDelta, expectedDelta))
        }
        previousDiagnosticPosition = playerPosition
        previousDiagnosticFrame = frame
        previousDiagnosticSegmentID = frame.sample.segmentID
    }
#endif

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
        let step: CGFloat
#if DEBUG
        if HoneySlidePreviewMode.freezesAnswers {
            step = 0
        } else {
            step = currentSlideSpeed
                / HoneySlideTuning.cameraLookAheadDistance(for: currentSlideSpeed)
                * CGFloat(dt)
        }
#else
        step = currentSlideSpeed
            / HoneySlideTuning.cameraLookAheadDistance(for: currentSlideSpeed)
            * CGFloat(dt)
#endif
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
            if pots[i].hit {
#if DEBUG
                if !HoneySlidePreviewMode.freezesAnswers { pots[i].hitAge += dt }
#else
                pots[i].hitAge += dt
#endif
            }
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
            let trackWidth = HoneySlideRoute.verticalSlice.sample(at: scroll).width
            let hitSlop = HoneySlideTuning.answerHitLateralSlop(for: trackWidth)
            let aligned = abs(displayLateral - pot.lateral) < hitSlop
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
            if honeyFlowActive, !reduceMotion {
                emitDroplet(nearBoat: true, honey: true)
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
            let projection = RiverProjection(size: size, phase: scroll, speed: currentSlideSpeed,
                                             focusLateral: cameraLateral)
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
        let hull = point ?? RiverProjection(size: size, phase: scroll, speed: currentSlideSpeed,
                                            focusLateral: cameraLateral)
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
        RiverProjection(size: size, phase: scroll, speed: currentSlideSpeed,
                        focusLateral: cameraLateral)
            .point(lateral: lateral, travel: travel)
    }

#if DEBUG
    var debugPerformanceText: String {
        let route = HoneySlideRoute.verticalSlice
        let frame = route.frame(at: scroll)
        let sample = frame.sample
        let fps = frameIntervalEMA > 0 ? 1 / frameIntervalEMA : 0
        let projection = RiverProjection(size: size, phase: scroll, speed: currentSlideSpeed,
                                         focusLateral: cameraLateral)
        let ready = projection.generationReadyDistance
        let halfWidth = HoneySlideTuning.worldTrackHalfWidth * sample.width
        let allowed = HoneySlideTuning.playableLateralLimit(for: sample.width)
        let world = route.surface(at: scroll, lateral: displayLateral).position
        return String(format: "FPS %.0f   %.1f ms   track %.2f ms\nSpeed %.1f   slope %.1f°   curve %+.5f\nLateral %+.2f m   v %+.2f   input %+.2f   drift %+.2f\nWidth %.2f m   allowed ±%.2f m (±%.3f)\n%@   next boundary %.2f m\nPlayer (%.1f, %.1f, %.1f)   P %.0f m   C %.0f m\nActive -%.0f m (%.1f s)   visible +%.0f m (%.1f s)\nReady +%.0f m (%.1f s)   %d/%d segments   %d particles",
                      fps, frameIntervalEMA * 1_000,
                      HoneySlideProfiler.latestTrackGenerationMilliseconds,
                      currentSlideSpeed, sample.downhillSlope * 180 / .pi,
                      frame.curvature,
                      lateralPosition, lateralVelocity, steeringInput, curveDriftAcceleration,
                      halfWidth * 2, halfWidth * allowed, allowed,
                      sample.segmentID, route.distanceToNextSegmentBoundary(after: scroll),
                      world.x, world.y, world.z,
                      scroll, projection.cameraProgress,
                      projection.activeBehindDistance, HoneySlideTuning.visibleBehindSeconds,
                      projection.visibleAheadDistance, HoneySlideTuning.visibleAheadSeconds,
                      ready, HoneySlideTuning.generationLookAheadSeconds,
                      activeSegmentCount(behind: projection.activeBehindDistance,
                                         ahead: ready), route.segments.count,
                      splashes.count)
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
         speed: CGFloat = HoneySlideTuning.nominalSlideSpeed,
         focusLateral: CGFloat = 0) {
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
        // A delayed, partial lateral translation starts only outside the
        // central dead zone. Translating camera and aim together preserves the
        // route perspective while keeping the rider visible near the new,
        // wider outer rails. The arena intentionally never supplies full
        // player lateral here, so crossing still reads as real movement.
        let clampedFocus = min(0.45, max(-0.45, focusLateral))
        let focusOffset = current.right
            * (HoneySlideTuning.worldTrackHalfWidth * current.sample.width * clampedFocus)
        let camera = cameraTrackFrame.position
            + HoneyVector3.up * cameraHeight
            + focusOffset
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
        ) + focusOffset
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
#if DEBUG
    var debugCameraPosition: HoneyVector3 { cameraPosition }
#endif

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

    struct ProjectedPlayerSurface {
        let contactPoint: CGPoint
        let screenNormal: CGVector
        let screenTangent: CGVector
        let surfaceRollDegrees: Double
        let worldPosition: HoneyVector3
        let worldNormal: HoneyVector3
        let worldTangent: HoneyVector3
        let lateral: CGFloat
        let trackWidth: CGFloat
        let allowedLateral: CGFloat

        func visualPoint(rideHeight: CGFloat, bounce: CGFloat = 0) -> CGPoint {
            CGPoint(x: contactPoint.x + screenNormal.dx * (rideHeight + bounce),
                    y: contactPoint.y + screenNormal.dy * (rideHeight + bounce))
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
        return projected.center + lateral * projected.halfWidth
    }

    func point(lateral: CGFloat, travel: CGFloat) -> CGPoint {
        let projected = projectedSample(for: travel)
        let t = min(1, max(0, (lateral + 1) * 0.5))
        return CGPoint(x: projected.center + lateral * projected.halfWidth,
                       y: projected.leftEdgeY
                        + (projected.rightEdgeY - projected.leftEdgeY) * t)
    }

    /// Projects the same banked trough-floor sample used by the player's
    /// logical contact. This deliberately differs from `point`, which remains
    /// the lightweight placement function for existing answer art.
    func playerSurface(lateral: CGFloat, travel: CGFloat = 0) -> ProjectedPlayerSurface {
        let distance = phase + travel * lookAheadDistance
        let surface = route.surface(at: distance, lateral: lateral)
        let contact = project(surface.position)
        let normalEnd = project(surface.position + surface.normal)
        let tangentEnd = project(surface.position + surface.tangent)
        let rightEnd = project(surface.position + surface.right)

        func normalized(_ delta: CGVector, fallback: CGVector) -> CGVector {
            let magnitude = max(0.000_001,
                                sqrt(delta.dx * delta.dx + delta.dy * delta.dy))
            guard magnitude.isFinite else { return fallback }
            return CGVector(dx: delta.dx / magnitude, dy: delta.dy / magnitude)
        }

        let normal = normalized(CGVector(dx: normalEnd.x - contact.x,
                                         dy: normalEnd.y - contact.y),
                                fallback: CGVector(dx: 0, dy: -1))
        let tangent = normalized(CGVector(dx: tangentEnd.x - contact.x,
                                          dy: tangentEnd.y - contact.y),
                                 fallback: CGVector(dx: 0, dy: -1))
        let rightDelta = CGVector(dx: rightEnd.x - contact.x,
                                  dy: rightEnd.y - contact.y)
        let roll = atan2(rightDelta.dy, rightDelta.dx) * 180 / .pi
        return ProjectedPlayerSurface(
            contactPoint: contact,
            screenNormal: normal,
            screenTangent: tangent,
            surfaceRollDegrees: Double(roll),
            worldPosition: surface.position,
            worldNormal: surface.normal,
            worldTangent: surface.tangent,
            lateral: surface.lateral,
            trackWidth: surface.halfWidth * 2,
            allowedLateral: HoneySlideTuning.playableLateralLimit(for: surface.track.width)
        )
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
