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
    static let cameraAimSeconds: CGFloat = 2.6
    static let visibleBehindSeconds: CGFloat = 2.0
    static let fullyDetailedAheadSeconds: CGFloat = 8.0
    static let visibleAheadSeconds: CGFloat = 10.0
    static let generationLookAheadSeconds: CGFloat = 15.0
    static let minimumLookAheadDistance: CGFloat = 72
    static func cameraLookAheadDistance(for speed: CGFloat) -> CGFloat {
        max(minimumLookAheadDistance, speed * cameraLookAheadSeconds)
    }
    static func generationLookAheadDistance(for speed: CGFloat) -> CGFloat {
        max(minimumLookAheadDistance, speed * generationLookAheadSeconds)
    }
    static func visibleAheadDistance(for speed: CGFloat) -> CGFloat {
        max(minimumLookAheadDistance, speed * visibleAheadSeconds)
    }
    static func activeBehindDistance(for speed: CGFloat) -> CGFloat {
        speed * visibleBehindSeconds
    }
    /// The Canvas camera is roughly half a second behind the rider. Geometry
    /// remains active for two seconds behind it, but only the part in front of
    /// the near plane is submitted. That makes the near cap land well below
    /// the viewport instead of becoming a horizontal polygon edge.
    static let cameraChaseSeconds: CGFloat = 0.72
    static let cameraNearPlane: CGFloat = 1.4
    static let perspectiveFOVDegrees: CGFloat = 74
    static let worldLateralScale: CGFloat = 22
    /// The physical half-width is deliberately 1.5x the previous 4.8 m lane.
    /// Authored width multipliers can open answer approaches further without
    /// changing steering into discrete lanes.
    static let additionalWidthMultiplier: CGFloat = 1.20
    static let worldTrackHalfWidth: CGFloat = 7.2 * additionalWidthMultiplier
    static let steeringResponse: CGFloat = 8.8
    static let steeringDragScale: CGFloat = 1.85
    static let playerFootprintRadius: CGFloat = 0.85
    static let railClearance: CGFloat = 0.25
    static let maximumPlayerLateral: CGFloat = 0.91
    /// Visual lift above the sampled honey surface, expressed as a fraction
    /// of the donut sprite. The front honey lip then covers seven percent of
    /// the donut to sell a small, viscous immersion rather than hovering.
    static let playerRideHeightFraction: CGFloat = 0.08
    static let playerImmersionFraction: CGFloat = 0.07
    static let curveDriftStrength: CGFloat = 0.07
    static let maxCurveDriftAcceleration: CGFloat = 1.25
    static let lateralDrag: CGFloat = 1.35
    static let steeringAcceleration: CGFloat = 8.5
    static let maxLateralSpeed: CGFloat = 4.8
    static let bankingDriftCompensation: CGFloat = 1.8
    static let railVelocityRetention: CGFloat = 0.12
    static let lateralSimulationStep: Double = 1.0 / 120.0
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

    static func playableLateralLimit(for width: CGFloat) -> CGFloat {
        let halfWidth = max(0.001, worldTrackHalfWidth * width)
        let footprintLimit = 1 - (playerFootprintRadius + railClearance) / halfWidth
        return min(maximumPlayerLateral, max(0.68, footprintLimit))
    }
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
        switch self { case .high: 184; case .balanced: 142; case .constrained: 104 }
    }
    var railSteps: Int {
        switch self { case .high: 184; case .balanced: 140; case .constrained: 100 }
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
    let elevationUndulation: CGFloat
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
         elevationUndulation: CGFloat = 0,
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
        self.elevationUndulation = elevationUndulation
        self.railings = railings
        self.speedMultiplier = speedMultiplier
        self.cameraLookAhead = cameraLookAhead
        self.answerOffsets = answerOffsets
    }
}

/// Lightweight world-space vector used by the route and camera. Keeping the
/// math here makes the authored route genuinely three-dimensional without
/// coupling gameplay to a particular rendering framework.
struct HoneyVector3 {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat

    static let up = HoneyVector3(x: 0, y: 1, z: 0)

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    static func * (lhs: Self, rhs: CGFloat) -> Self {
        Self(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    func dot(_ other: Self) -> CGFloat {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: Self) -> Self {
        Self(x: y * other.z - z * other.y,
             y: z * other.x - x * other.z,
             z: x * other.y - y * other.x)
    }

    var length: CGFloat { sqrt(dot(self)) }

    var normalized: Self {
        let magnitude = max(0.000_001, length)
        return self * (1 / magnitude)
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

/// A sampled 3D centerline and its local orthonormal frame. `right` follows
/// the curve in world space; banking is applied around `tangent` by the camera
/// projection when it constructs the trough cross-section.
struct HoneyTrackFrame {
    let distance: CGFloat
    let position: HoneyVector3
    let tangent: HoneyVector3
    let right: HoneyVector3
    let surfaceUp: HoneyVector3
    /// Signed horizontal curvature in 1/metres. Positive is a right turn.
    let curvature: CGFloat
    let sample: HoneyTrackSample
}

/// The single physical contact representation shared by steering, player
/// placement and debug rendering. It is the banked trough floor—not the
/// unbanked centerline or the decorative top edge of the slide.
struct HoneyTrackSurfaceSample {
    let distance: CGFloat
    let position: HoneyVector3
    let tangent: HoneyVector3
    let right: HoneyVector3
    let normal: HoneyVector3
    let halfWidth: CGFloat
    let lateral: CGFloat
    let track: HoneyTrackSample
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
        HoneySlideSegment("high-start-descent", kind: .wide, length: 108, width: 1.48, endWidth: 1.10,
                          heightDelta: -44, elevationUndulation: 2.8,
                          cameraLookAhead: 1.10),
        HoneySlideSegment("falling-soft-left", kind: .curve, length: 104, width: 1.10, endWidth: 1.02,
                          lateralShift: -0.65, heightDelta: -42, bendAmplitude: -0.20,
                          troughDepth: 0.13, banking: -0.20, elevationUndulation: -3.6,
                          cameraLookAhead: 1.16),
        HoneySlideSegment("short-steep-drop", kind: .descent, length: 56, width: 1.02, endWidth: 1.00,
                          lateralShift: -0.10, heightDelta: -44, troughDepth: 0.15,
                          elevationUndulation: 2.4,
                          speedMultiplier: 1.10, cameraLookAhead: 1.28),
        HoneySlideSegment("descending-right-s", kind: .sCurve, length: 124, width: 1.00, endWidth: 1.14,
                          lateralShift: 0.75, heightDelta: -52, bendAmplitude: 0.48,
                          troughDepth: 0.14, banking: 0.22, elevationUndulation: -4.4,
                          cameraLookAhead: 1.18),
        HoneySlideSegment("quiet-answer-run", kind: .answerApproach, length: 96, width: 1.14, endWidth: 1.48,
                          heightDelta: -20, elevationUndulation: 1.6,
                          answerOffsets: [-0.82, -0.28, 0.28, 0.82]),
        HoneySlideSegment("strong-valley-descent", kind: .descent, length: 84, width: 1.48, endWidth: 1.10,
                          lateralShift: -0.25, heightDelta: -60, troughDepth: 0.15,
                          elevationUndulation: 3.6,
                          speedMultiplier: 1.14, cameraLookAhead: 1.30),
        HoneySlideSegment("ravine-gap", kind: .jump, length: 24, width: 1.10, endWidth: 1.30,
                          lateralShift: 0.05, heightDelta: -14, elevationUndulation: -1.0,
                          railings: false,
                          speedMultiplier: 1.10, cameraLookAhead: 1.36),
        HoneySlideSegment("low-valley-landing", kind: .landing, length: 76, width: 1.30, endWidth: 1.12,
                          lateralShift: 0.08, heightDelta: -24, elevationUndulation: 2.4),
        HoneySlideSegment("long-fast-honey-slide", kind: .curve, length: 124, width: 1.12, endWidth: 1.18,
                          lateralShift: 0.12, heightDelta: -56, bendAmplitude: 0.22,
                          troughDepth: 0.14, banking: 0.16, elevationUndulation: -4.0,
                          speedMultiplier: 1.12, cameraLookAhead: 1.18),
        HoneySlideSegment("valley-answer-finish", kind: .answerApproach, length: 100, width: 1.18, endWidth: 1.48,
                          lateralShift: 0, heightDelta: -24, elevationUndulation: 1.8,
                          answerOffsets: [-0.82, -0.28, 0.28, 0.82])
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
        let elevationShape = verticalShape(local)
        let previousAverageSlope = previousSegment.heightDelta / max(previousSegment.length, 0.001)
        let currentAverageSlope = segment.heightDelta / max(segment.length, 0.001)
        let nextAverageSlope = nextSegment.heightDelta / max(nextSegment.length, 0.001)
        let startSlope = monotoneJointSlope(previousAverageSlope, currentAverageSlope)
        let endSlope = monotoneJointSlope(currentAverageSlope, nextAverageSlope)
        let t2 = local * local
        let t3 = t2 * local
        let startTangent = startSlope * segment.length
        let endTangent = endSlope * segment.length
        let hermiteElevation = (local - 2 * t2 + t3) * startTangent
            + (-2 * t3 + 3 * t2) * segment.heightDelta
            + (t3 - t2) * endTangent
        let hermiteDerivative = (1 - 4 * local + 3 * t2) * startTangent
            + (-6 * t2 + 6 * local) * segment.heightDelta
            + (3 * t2 - 2 * local) * endTangent
        let elevationDerivative = hermiteDerivative
            + segment.elevationUndulation * verticalShapeDerivative(local)
        return HoneyTrackSample(
            segmentID: segment.id,
            kind: segment.kind,
            localProgress: local,
            center: startCenters[index] + segment.lateralShift * eased + bend,
            width: segment.startWidth + (segment.endWidth - segment.startWidth) * eased,
            elevation: startElevations[index] + hermiteElevation
                + segment.elevationUndulation * elevationShape
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
            speedMultiplier: segment.speedMultiplier
                + (nextSegment.speedMultiplier - segment.speedMultiplier) * edgeBlend,
            cameraLookAhead: segment.cameraLookAhead
                + (nextSegment.cameraLookAhead - segment.cameraLookAhead) * edgeBlend,
            answerOffsets: segment.answerOffsets,
            downhillSlope: atan2(
                -(elevationDerivative / max(segment.length, 0.001)),
                1
            )
        )
    }

    func frame(at rawDistance: CGFloat) -> HoneyTrackFrame {
        let sample = sample(at: rawDistance)
        let position = worldPosition(at: rawDistance)
        let delta: CGFloat = 0.35
        let tangent = (worldPosition(at: rawDistance + delta)
                       - worldPosition(at: rawDistance - delta)).normalized
        // Locally parallel-transport the preceding right vector onto the new
        // tangent. This avoids rebuilding a potentially different basis from
        // world-up at every segment/sample boundary.
        let previousTangent = (worldPosition(at: rawDistance)
                               - worldPosition(at: rawDistance - delta * 2)).normalized
        var previousRight = HoneyVector3.up.cross(previousTangent).normalized
        if previousRight.length < 0.5 {
            previousRight = HoneyVector3(x: 1, y: 0, z: 0)
        }
        let rotationAxis = previousTangent.cross(tangent)
        let sine = rotationAxis.length
        let cosine = min(1, max(-1, previousTangent.dot(tangent)))
        var right = previousRight
        if sine > 0.000_001 {
            let axis = rotationAxis * (1 / sine)
            right = previousRight * cosine
                + axis.cross(previousRight) * sine
                + axis * (axis.dot(previousRight) * (1 - cosine))
        }
        right = (right - tangent * right.dot(tangent)).normalized
        if right.length < 0.5 { right = HoneyVector3(x: 1, y: 0, z: 0) }
        let surfaceUp = tangent.cross(right).normalized
        let curvatureDelta: CGFloat = 0.75
        let tangentBefore = (worldPosition(at: rawDistance)
                             - worldPosition(at: rawDistance - curvatureDelta)).normalized
        let tangentAfter = (worldPosition(at: rawDistance + curvatureDelta)
                            - worldPosition(at: rawDistance)).normalized
        let tangentChange = (tangentAfter - tangentBefore) * (1 / curvatureDelta)
        let curvature = tangentChange.dot(right)
        return HoneyTrackFrame(distance: rawDistance,
                               position: position,
                               tangent: tangent,
                               right: right,
                               surfaceUp: surfaceUp,
                               curvature: curvature,
                               sample: sample)
    }

    func surface(at rawDistance: CGFloat, lateral proposedLateral: CGFloat) -> HoneyTrackSurfaceSample {
        let frame = frame(at: rawDistance)
        let halfWidth = HoneySlideTuning.worldTrackHalfWidth * frame.sample.width
        let lateralLimit = HoneySlideTuning.playableLateralLimit(for: frame.sample.width)
        let lateral = min(lateralLimit, max(-lateralLimit, proposedLateral))
        let bank = frame.sample.banking
        let surfaceRight = (frame.right * cos(bank) + frame.surfaceUp * sin(bank)).normalized
        let surfaceNormal = (frame.surfaceUp * cos(bank) - frame.right * sin(bank)).normalized
        // The visible honey floor sits inside the trough. Modelling that depth
        // here keeps the sprite, wake and debug sample on the same surface.
        let troughDepth = halfWidth * frame.sample.troughDepth
        let position = frame.position
            + surfaceRight * (halfWidth * lateral)
            - surfaceNormal * troughDepth
        return HoneyTrackSurfaceSample(distance: rawDistance,
                                       position: position,
                                       tangent: frame.tangent,
                                       right: surfaceRight,
                                       normal: surfaceNormal,
                                       halfWidth: halfWidth,
                                       lateral: lateral,
                                       track: frame.sample)
    }

    private func worldPosition(at rawDistance: CGFloat) -> HoneyVector3 {
        let sample = sample(at: rawDistance)
        return HoneyVector3(x: sample.center * HoneySlideTuning.worldLateralScale,
                            y: sample.elevation,
                            z: rawDistance)
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

    func distanceToNextSegmentBoundary(after rawDistance: CGFloat) -> CGFloat {
        let distance = wrapped(rawDistance)
        let index = segmentIndex(at: distance)
        let boundary = starts[index] + segments[index].length
        return max(0, boundary - distance)
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

    /// Harmonic blending preserves the sign of two downhill slopes and gives
    /// both neighbouring Hermite spans exactly the same boundary tangent.
    private func monotoneJointSlope(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        guard a * b > 0 else { return 0 }
        return 2 * a * b / (a + b)
    }

    /// Zero position and zero derivative at both ends, so vertical shaping can
    /// add crests/compressions without introducing a segment seam.
    private func verticalShape(_ value: CGFloat) -> CGFloat {
        let sine = sin(value * .pi)
        return sine * sine * sin(value * .pi * 2)
    }

    private func verticalShapeDerivative(_ value: CGFloat) -> CGFloat {
        let sine = sin(value * .pi)
        let cosine = cos(value * .pi)
        return 2 * .pi * sine * cosine * sin(value * .pi * 2)
            + 2 * .pi * sine * sine * cos(value * .pi * 2)
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
            let beforeFrame = frame(at: boundary - epsilon)
            let afterFrame = frame(at: boundary + epsilon)
            assert(beforeFrame.tangent.dot(afterFrame.tangent) > 0.999,
                   "Honey Slide tangent discontinuity near \(after.segmentID)")
            assert(beforeFrame.right.dot(afterFrame.right) > 0.999,
                   "Honey Slide right-frame discontinuity near \(after.segmentID)")
            assert(beforeFrame.surfaceUp.dot(afterFrame.surfaceUp) > 0.999,
                   "Honey Slide up-frame discontinuity near \(after.segmentID)")
            assert(abs(beforeFrame.curvature - afterFrame.curvature) < 0.02,
                   "Honey Slide curvature discontinuity near \(after.segmentID)")
        }

        let beforeSeam = sample(at: totalLength - epsilon)
        let afterSeam = sample(at: totalLength + epsilon)
        assert(abs(beforeSeam.center - afterSeam.center) < 0.002,
               "Honey Slide loop centerline seam is visible")
        assert(abs(beforeSeam.width - afterSeam.width) < 0.002,
               "Honey Slide loop width seam is visible")
        assert(abs(beforeSeam.elevation - afterSeam.elevation) < 0.002,
               "Honey Slide loop elevation seam is visible")
        assert(frame(at: totalLength - epsilon).tangent
            .dot(frame(at: totalLength + epsilon).tangent) > 0.999,
               "Honey Slide loop tangent seam is visible")

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
    static let contactEnabled = ProcessInfo.processInfo.arguments
        .contains("-honeySlideContactDebug")
    static let solidOpaqueTrack = ProcessInfo.processInfo.arguments
        .contains("-honeySlideSolidOpaqueTrack")
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

    /// Deterministic force input for steering QA; normal gameplay never reads
    /// this unless the explicit preview argument is present.
    static var steeringInput: CGFloat? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HoneySlidePreviewSteering"),
              arguments.indices.contains(index + 1),
              let value = Double(arguments[index + 1]) else { return nil }
        return min(1, max(-1, CGFloat(value)))
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
