//
//  HoneySlideTrack.swift
//  Math River
//
//  A small, data-driven route model for the Honey Slide vertical slice.
//  Rendering and player control sample this same model, so curves, railings,
//  branch locks, jumps and answer-safe areas cannot drift apart.
//

import SwiftUI
import os

enum HoneySlideTuning {
    /// The old game travelled at 18 points/second. Keep that authored value as
    /// the base and expose the requested speed-up as one tuneable multiplier.
    static let baseSlideSpeed: CGFloat = 18
    static let speedMultiplier: CGFloat = 2.0
    static var nominalSlideSpeed: CGFloat { baseSlideSpeed * speedMultiplier }
    static let maximumDownhillSpeedBonus: CGFloat = 0.16
    static let cameraLookAheadSeconds: CGFloat = 2.6
    static let cameraAimSeconds: CGFloat = 0.85
    static let generationLookAheadSeconds: CGFloat = 8.0
    static let minimumLookAheadDistance: CGFloat = 72
    static func cameraLookAheadDistance(for speed: CGFloat) -> CGFloat {
        max(minimumLookAheadDistance, speed * cameraLookAheadSeconds)
    }
    static func generationLookAheadDistance(for speed: CGFloat) -> CGFloat {
        max(minimumLookAheadDistance, speed * generationLookAheadSeconds)
    }
    /// Geometry keeps rendering well beyond the perspective horizon. Its far
    /// cap therefore lives above the screen instead of appearing as the end of
    /// the slide at the skyline.
    static let visualFarTravel: CGFloat = 1.82
    static let visualNearTravel: CGFloat = -0.20
    static let steeringResponse: CGFloat = 8.8
    static let steeringDragScale: CGFloat = 1.85
    static let railInset: CGFloat = 0.88
    static let railBounce: CGFloat = 0.10
    static let airControl: CGFloat = 0.42
    static let jumpHeight: CGFloat = 0.115
    static let landingRecoveryDuration: Double = 0.52
    static let splitCommitProgress: CGFloat = 0.42
    static let answerDecisionLeadTime: Double = 3.0
    static var answerLeadDistance: CGFloat {
        nominalSlideSpeed * CGFloat(answerDecisionLeadTime)
    }
    static let splashPoolCapacity = 48
}

enum HoneySlideVisualQuality: Int, Comparable {
    case constrained
    case balanced
    case high

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    static var recommended: Self {
#if DEBUG
        if let override = HoneySlidePreviewMode.visualQualityOverride { return override }
#endif
        return ArenaPerformanceBudget.isConstrained ? .constrained : .high
    }

    var floorSteps: Int {
        switch self { case .high: 136; case .balanced: 104; case .constrained: 76 }
    }
    var railSteps: Int {
        switch self { case .high: 136; case .balanced: 102; case .constrained: 72 }
    }
    var highlightCount: Int {
        switch self { case .high: 34; case .balanced: 27; case .constrained: 19 }
    }
    var supportCount: Int {
        switch self { case .high: 12; case .balanced: 9; case .constrained: 7 }
    }
    var splitNoseSteps: Int {
        switch self { case .high: 84; case .balanced: 66; case .constrained: 48 }
    }
    var materialTileCount: Int { self == .constrained ? 3 : 4 }
    var materialOpacity: Double {
        switch self { case .high: 0.50; case .balanced: 0.46; case .constrained: 0.40 }
    }
    var splashCadence: Int {
        switch self { case .high: 4; case .balanced: 5; case .constrained: 7 }
    }
    var splashLimit: Int {
        switch self { case .high: 36; case .balanced: 28; case .constrained: 20 }
    }

    func steppedDown() -> Self {
        Self(rawValue: max(Self.constrained.rawValue, rawValue - 1)) ?? .constrained
    }

    func steppedUp() -> Self {
        Self(rawValue: min(Self.high.rawValue, rawValue + 1)) ?? .high
    }
}

enum HoneySegmentKind: String, CaseIterable {
    case straight
    case wide
    case curve
    case sCurve
    case descent
    case narrow
    case split
    case branch
    case merge
    case jump
    case landing
    case tunnel
    case answerApproach
}

struct HoneySlideSegment: Identifiable {
    let id: String
    let kind: HoneySegmentKind
    let length: CGFloat
    let startWidth: CGFloat
    let endWidth: CGFloat
    let lateralShift: CGFloat
    let heightDelta: CGFloat
    let bendAmplitude: CGFloat
    let troughDepth: CGFloat
    let railHeight: CGFloat
    let banking: CGFloat
    let railings: Bool
    let speedMultiplier: CGFloat
    let cameraLookAhead: CGFloat
    let answerOffsets: [CGFloat]

    init(_ id: String,
         kind: HoneySegmentKind,
         length: CGFloat,
         width: CGFloat = 1,
         endWidth: CGFloat? = nil,
         lateralShift: CGFloat = 0,
         heightDelta: CGFloat = 0,
         bendAmplitude: CGFloat = 0,
         troughDepth: CGFloat = 0.10,
         railHeight: CGFloat = 0.13,
         banking: CGFloat = 0,
         railings: Bool = true,
         speedMultiplier: CGFloat = 1,
         cameraLookAhead: CGFloat = 1,
         answerOffsets: [CGFloat] = []) {
        self.id = id
        self.kind = kind
        self.length = length
        startWidth = width
        self.endWidth = endWidth ?? width
        self.lateralShift = lateralShift
        self.heightDelta = heightDelta
        self.bendAmplitude = bendAmplitude
        self.troughDepth = troughDepth
        self.railHeight = railHeight
        self.banking = banking
        self.railings = railings
        self.speedMultiplier = speedMultiplier
        self.cameraLookAhead = cameraLookAhead
        self.answerOffsets = answerOffsets
    }
}

struct HoneyTrackSample {
    let segmentID: String
    let kind: HoneySegmentKind
    let localProgress: CGFloat
    let center: CGFloat
    let width: CGFloat
    let elevation: CGFloat
    let splitAmount: CGFloat
    let troughDepth: CGFloat
    let railHeight: CGFloat
    let railVisibility: CGFloat
    let banking: CGFloat
    let hasSurface: Bool
    let railings: Bool
    let speedMultiplier: CGFloat
    let cameraLookAhead: CGFloat
    let answerOffsets: [CGFloat]
    /// Positive radians mean downhill. This is the local tangent of the
    /// authored elevation curve, not a physics-derived value.
    let downhillSlope: CGFloat

    var isAir: Bool { kind == .jump }
    var steeringResponseMultiplier: CGFloat {
        switch kind {
        case .straight, .wide, .answerApproach: return 1.06
        case .curve, .sCurve, .descent: return 0.96
        case .split, .branch, .merge, .narrow: return 0.90
        case .landing: return 0.78
        case .jump: return HoneySlideTuning.airControl
        case .tunnel: return 0.94
        }
    }
    var isAnswerSafe: Bool {
        (kind == .answerApproach || kind == .wide)
            && localProgress > 0.12 && localProgress < 0.88
    }
    var locksBranch: Bool {
        kind == .branch
            || (kind == .split && localProgress >= HoneySlideTuning.splitCommitProgress)
            || (kind == .merge && localProgress < 0.68)
    }
}

struct HoneyRouteCheckpoint: Identifiable {
    let id: String
    let segmentID: String
    let validRouteIDs: Set<String>
}

struct HoneySlideRoute {
    static let verticalSlice = HoneySlideRoute(segments: [
        // A purpose-built downhill feel test: long descent, falling curves,
        // a short drop, a ravine jump, a low landing and a final fast run.
        HoneySlideSegment("high-start-descent", kind: .wide, length: 54, width: 1.12,
                          heightDelta: -16, cameraLookAhead: 1.10),
        HoneySlideSegment("falling-soft-left", kind: .curve, length: 52, width: 1.12, endWidth: 1.00,
                          lateralShift: -0.65, heightDelta: -15, bendAmplitude: -0.14,
                          troughDepth: 0.13, banking: -0.13, cameraLookAhead: 1.16),
        HoneySlideSegment("short-steep-drop", kind: .descent, length: 28, width: 1.00, endWidth: 0.94,
                          lateralShift: -0.10, heightDelta: -15, troughDepth: 0.15,
                          speedMultiplier: 1.10, cameraLookAhead: 1.28),
        HoneySlideSegment("descending-right-s", kind: .sCurve, length: 62, width: 0.94, endWidth: 1.08,
                          lateralShift: 0.75, heightDelta: -19, bendAmplitude: 0.42,
                          troughDepth: 0.14, banking: 0.15, cameraLookAhead: 1.18),
        HoneySlideSegment("quiet-answer-run", kind: .answerApproach, length: 48, width: 1.08, endWidth: 1.18,
                          heightDelta: -7, answerOffsets: [-0.74, -0.25, 0.25, 0.74]),
        HoneySlideSegment("strong-valley-descent", kind: .descent, length: 42, width: 1.18, endWidth: 1.02,
                          lateralShift: -0.25, heightDelta: -22, troughDepth: 0.15,
                          speedMultiplier: 1.14, cameraLookAhead: 1.30),
        HoneySlideSegment("ravine-gap", kind: .jump, length: 12, width: 1.02, endWidth: 1.24,
                          lateralShift: 0.05, heightDelta: -5, railings: false,
                          speedMultiplier: 1.10, cameraLookAhead: 1.36),
        HoneySlideSegment("low-valley-landing", kind: .landing, length: 38, width: 1.24, endWidth: 1.08,
                          lateralShift: 0.08, heightDelta: -8),
        HoneySlideSegment("long-fast-honey-slide", kind: .curve, length: 62, width: 1.08, endWidth: 1.16,
                          lateralShift: 0.12, heightDelta: -20, bendAmplitude: 0.16,
                          troughDepth: 0.14, banking: 0.11,
                          speedMultiplier: 1.12, cameraLookAhead: 1.18),
        HoneySlideSegment("valley-answer-finish", kind: .answerApproach, length: 50, width: 1.16, endWidth: 1.12,
                          heightDelta: -8, answerOffsets: [-0.74, -0.25, 0.25, 0.74])
    ])

    let segments: [HoneySlideSegment]
    let checkpoints: [HoneyRouteCheckpoint]
    let totalLength: CGFloat
    let elevationChangePerLap: CGFloat

    private let starts: [CGFloat]
    private let startCenters: [CGFloat]
    private let startElevations: [CGFloat]

    init(segments: [HoneySlideSegment]) {
        self.segments = segments
        var starts: [CGFloat] = []
        var centers: [CGFloat] = []
        var elevations: [CGFloat] = []
        var distance: CGFloat = 0
        var center: CGFloat = 0
        var elevation: CGFloat = 0
        for segment in segments {
            starts.append(distance)
            centers.append(center)
            elevations.append(elevation)
            distance += segment.length
            center += segment.lateralShift
            elevation += segment.heightDelta
        }
        self.starts = starts
        startCenters = centers
        startElevations = elevations
        totalLength = max(1, distance)
        elevationChangePerLap = elevation
#if DEBUG
        // Horizontal position and width close seamlessly. Elevation deliberately
        // does not: every repeated lap continues farther down the mountain.
        assert(abs(center) < 0.001, "Honey Slide loop must return to its starting center")
        assert(elevation < 0, "Honey Slide must make net downhill progress")
        if let first = segments.first, let last = segments.last {
            assert(abs(last.endWidth - first.startWidth) < 0.001,
                   "Honey Slide loop widths must meet at the seam")
        }
#endif
        checkpoints = segments
            .filter { !$0.answerOffsets.isEmpty }
            .map {
                HoneyRouteCheckpoint(id: "checkpoint-\($0.id)",
                                     segmentID: $0.id,
                                     validRouteIDs: ["main", "left", "right"])
            }
#if DEBUG
        debugValidateContinuity()
#endif
    }

    func sample(at rawDistance: CGFloat) -> HoneyTrackSample {
        let distance = wrapped(rawDistance)
        let lap = floor(rawDistance / totalLength)
        let index = segmentIndex(at: distance)
        let segment = segments[index]
        let nextSegment = segments[(index + 1) % segments.count]
        let previousSegment = segments[(index - 1 + segments.count) % segments.count]
        let local = min(max((distance - starts[index]) / max(segment.length, 0.001), 0), 1)
        let eased = smoothstep(local)
        let bend: CGFloat
        if segment.kind == .sCurve {
            let envelope = pow(sin(local * .pi), 2)
            bend = sin(local * .pi * 2) * envelope * segment.bendAmplitude
        } else {
            bend = pow(sin(local * .pi), 2) * segment.bendAmplitude
        }
        let edgeProgress = min(max((local - 0.68) / 0.32, 0), 1)
        let edgeBlend = smoothstep(edgeProgress)
        let railVisibility: CGFloat
        if segment.kind == .jump || !segment.railings {
            railVisibility = 0
        } else if nextSegment.kind == .jump {
            let fade = min(max((local - 0.56) / 0.44, 0), 1)
            railVisibility = 1 - smoothstep(fade)
        } else if previousSegment.kind == .jump && segment.kind == .landing {
            railVisibility = smoothstep(min(max(local / 0.34, 0), 1))
        } else {
            railVisibility = 1
        }
        let split: CGFloat
        switch segment.kind {
        case .split: split = eased
        case .branch: split = 1
        case .merge: split = 1 - eased
        default: split = 0
        }
        return HoneyTrackSample(
            segmentID: segment.id,
            kind: segment.kind,
            localProgress: local,
            center: startCenters[index] + segment.lateralShift * eased + bend,
            width: segment.startWidth + (segment.endWidth - segment.startWidth) * eased,
            elevation: startElevations[index] + segment.heightDelta * eased
                + lap * elevationChangePerLap,
            splitAmount: split,
            troughDepth: segment.troughDepth
                + (nextSegment.troughDepth - segment.troughDepth) * edgeBlend,
            railHeight: segment.railHeight
                + (nextSegment.railHeight - segment.railHeight) * edgeBlend,
            railVisibility: railVisibility,
            banking: segment.banking * CGFloat(sin(Double(local) * .pi)),
            hasSurface: segment.kind != .jump,
            railings: segment.railings,
            speedMultiplier: segment.speedMultiplier,
            cameraLookAhead: segment.cameraLookAhead,
            answerOffsets: segment.answerOffsets,
            downhillSlope: atan2(
                -(segment.heightDelta / max(segment.length, 0.001))
                    * (6 * local * (1 - local)),
                1
            )
        )
    }

    func nextSafeAnswerDistance(after rawDistance: CGFloat) -> CGFloat {
        let start = rawDistance + HoneySlideTuning.answerLeadDistance
        var distance = start
        let limit = start + totalLength
        while distance < limit {
            let first = sample(at: distance)
            let last = sample(at: distance + 5)
            if first.isAnswerSafe, last.isAnswerSafe,
               first.segmentID == last.segmentID {
                return distance
            }
            distance += 2
        }
        return start
    }

    private func segmentIndex(at distance: CGFloat) -> Int {
        for index in starts.indices.reversed() where distance >= starts[index] {
            return index
        }
        return 0
    }

    private func wrapped(_ distance: CGFloat) -> CGFloat {
        let result = distance.truncatingRemainder(dividingBy: totalLength)
        return result >= 0 ? result : result + totalLength
    }

    private func smoothstep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }

#if DEBUG
    private func debugValidateContinuity() {
        let epsilon: CGFloat = 0.0001

        for segment in segments {
            assert(segment.length > 0, "Honey Slide segments need positive length")
            assert(segment.startWidth > 0 && segment.endWidth > 0,
                   "Honey Slide segments need positive width")
            assert(segment.speedMultiplier > 0, "Honey Slide speed must remain positive")
            if segment.kind == .jump {
                assert(!segment.railings, "Jump gaps cannot retain normal railings")
            }
            if !segment.answerOffsets.isEmpty {
                assert(segment.kind == .wide || segment.kind == .answerApproach,
                       "Answers may only spawn on safe, broad track")
            }
        }

        for index in segments.indices {
            let next = segments[(index + 1) % segments.count]
            assert(abs(segments[index].endWidth - next.startWidth) < epsilon,
                   "Honey Slide width discontinuity at \(next.id)")
            if segments[index].kind == .jump {
                assert(next.kind == .landing, "Every Honey Slide jump needs a landing")
            }
        }

        for boundary in starts.dropFirst() {
            let before = sample(at: boundary - epsilon)
            let after = sample(at: boundary + epsilon)
            assert(abs(before.center - after.center) < 0.002,
                   "Honey Slide centerline discontinuity near \(after.segmentID)")
            assert(abs(before.width - after.width) < 0.002,
                   "Honey Slide width discontinuity near \(after.segmentID)")
            assert(abs(before.elevation - after.elevation) < 0.002,
                   "Honey Slide elevation discontinuity near \(after.segmentID)")
        }

        let beforeSeam = sample(at: totalLength - epsilon)
        let afterSeam = sample(at: totalLength + epsilon)
        assert(abs(beforeSeam.center - afterSeam.center) < 0.002,
               "Honey Slide loop centerline seam is visible")
        assert(abs(beforeSeam.width - afterSeam.width) < 0.002,
               "Honey Slide loop width seam is visible")
        assert(abs(beforeSeam.elevation - afterSeam.elevation) < 0.002,
               "Honey Slide loop elevation seam is visible")

        for index in 0...512 {
            let sample = sample(at: CGFloat(index) / 512 * totalLength)
            assert(sample.center.isFinite && sample.width.isFinite && sample.elevation.isFinite,
                   "Honey Slide route produced non-finite geometry")
            assert(sample.width > 0 && (0...1).contains(sample.splitAmount),
                   "Honey Slide route produced invalid track geometry")
        }
    }
#endif
}

#if DEBUG
struct HoneySlideDebugState {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-honeySlideDebug")
}

enum HoneySlideProfiler {
    private static let frameDuration = OSAllocatedUnfairLock(initialState: 0.0)
    private static let log = OSLog(subsystem: "Hakketjak.Math-River",
                                   category: .pointsOfInterest)

    static var latestTrackGenerationMilliseconds: Double {
        frameDuration.withLock { $0 }
    }

    static func beginTrackGeneration() -> (CFAbsoluteTime, OSSignpostID) {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "Honey Slide Track Frame", signpostID: id)
        return (CFAbsoluteTimeGetCurrent(), id)
    }

    static func endTrackGeneration(_ measurement: (CFAbsoluteTime, OSSignpostID)) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - measurement.0) * 1_000
        frameDuration.withLock { $0 = elapsed }
        os_signpost(.end, log: log, name: "Honey Slide Track Frame",
                    signpostID: measurement.1, "milliseconds %.3f", elapsed)
    }
}

enum HoneySlidePreviewMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-HoneySlidePreview")
    }

    /// Optional deterministic route position for simulator QA, e.g.
    /// `-HoneySlidePreview -HoneySlidePreviewPhase 164` for the split.
    static var phase: CGFloat? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HoneySlidePreviewPhase"),
              arguments.indices.contains(index + 1),
              let value = Double(arguments[index + 1]) else { return nil }
        return CGFloat(value)
    }

    /// Animated preview for sustained performance QA. The regular preview is
    /// deterministic and remains frozen for screenshot comparisons.
    static var freezesMotion: Bool {
        isActive && !ProcessInfo.processInfo.arguments.contains("-HoneySlidePreviewRuns")
    }

    static var visualQualityOverride: HoneySlideVisualQuality? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HoneySlideVisualQuality"),
              arguments.indices.contains(index + 1) else { return nil }
        switch arguments[index + 1].lowercased() {
        case "high": return .high
        case "balanced": return .balanced
        case "low", "constrained": return .constrained
        default: return nil
        }
    }
}

/// A debug-only direct entry point for visual QA and performance captures.
/// It bypasses onboarding/HUD without changing the production game flow.
struct HoneySlideDebugPreview: View {
    private let round = GameRound(
        number: 1,
        question: MathQuestion(prompt: "7 × 8 = ?",
                               correctAnswer: "56",
                               distractors: ["48", "54", "64"],
                               sourceLevel: 1,
                               kind: .multiplication),
        options: [
            AnswerOption(text: "48", isCorrect: false),
            AnswerOption(text: "56", isCorrect: true),
            AnswerOption(text: "54", isCorrect: false),
            AnswerOption(text: "64", isCorrect: false)
        ]
    )

    var body: some View {
        MathRiverPlayfield(round: round,
                           maximumRounds: 20,
                           character: CharacterCatalog.current(isPremium: false),
                           isPad: AppLayout.isPad,
                           isLive: true,
                           isRunning: true,
                           playsEntrance: true,
                           playsLevelCompletion: false,
                           reduceMotion: false,
                           topReserve: 0,
                           bottomReserve: 0,
                           scoreTarget: nil,
                           onAnswer: { _ in false },
                           onRewardArrived: {},
                           onEntranceComplete: {},
                           onLevelCompletionFinished: {},
                           onWaveComplete: {})
            .ignoresSafeArea()
    }
}
#endif
