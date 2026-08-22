//
//  CrabLegWalk.swift
//  King Krab
//
//  The walk in a run of legs that ships as a single picture.
//
//  Every crab in the arena that is drawn rather than solved — the answer crabs
//  and the helpers — carries its legs as one drawing: three of them converging
//  on a single hip. Turned as one, that drawing wipes back and forth like a
//  paddle; left alone, it hangs still under a body that is visibly crossing the
//  sea floor. Neither of those is a walk.
//
//  Cutting the drawing into three is not the answer either. The artist drew the
//  legs over each other, so any cut runs through one leg to free the next, and
//  those cut edges show as broken pieces the moment the legs swing apart.
//
//  So the run is rebuilt instead. One whole leg — the one drawn last, at the
//  bottom of the fan, the only one nothing lies over — is cut out of the artwork
//  along the line the artist drew beside it, and the run is laid back out of
//  copies of that one leg, one where each of the three stood. Every leg on the
//  crab is then a complete drawing with its own outline all the way round: there
//  is no cut edge anywhere to break, and the copies overlap deep in the middle
//  of the fan exactly as the drawn legs did, so no gap can open between them
//  either. Tools/build_crab_leg.py does the cutting and writes the copies out
//  already turned and sized, which leaves this file only the walk itself.
//
//  That walk is the one the King's own solved legs keep: a long stance with the
//  foot down and driving back under the animal, then a short swing that throws
//  it forward again. It is counted in the same stride the body's roll and bob
//  are, so the legs, the animal over them and the sand they shed all keep the
//  same time — and each leg lags the one before it, which is what makes a rank
//  of them read as walking rather than as one board turning.
//

import SwiftUI

/// A run of legs, rebuilt out of copies of one of them.
struct LegRun {
    /// The legs, from the front of the fan backwards — which is the order they
    /// were drawn in, and the reverse of the order they are laid down in. Each
    /// is the same leg, already turned to where its own leg stood and sized to
    /// how long it was, so all that is added here is the step.
    let legs: [String]
    /// How far a leg swings on its hip over one stride, in degrees. It is the
    /// stroke a foot makes: the artwork's legs reach about a fifth of the
    /// square, so this is a step of roughly the size the animal takes.
    var swing: Double = 16
    /// How far one leg lags the one in front of it, in strides. The wave runs
    /// along the row rather than a whole side lifting at once.
    var lag: Double = 0.26

    /// How much of a whole-run swing a rebuilt run keeps under its own
    /// stepping — the hip itself rocking with the body. Enough that the run
    /// still surges; little enough that it no longer reads as one board
    /// turning. It is what a rigged character's pose contributes once its legs
    /// walk one at a time.
    static let hipShare: Double = 0.35

    /// The share of a stride a foot spends on the sand. Above a half means
    /// something is always carrying the animal, which is what a walk is.
    private static let stance = 0.62

    /// Where one leg of the run stands this frame, in degrees on its own hip.
    ///
    /// `stride` is the walk cycle in radians — the same one the body's roll and
    /// bob are taken from — and `side` is which of the two runs this is: they
    /// carry in turn, and the right-hand run is the left one's drawing
    /// mirrored, so its swing has to go the other way round as well.
    func degrees(leg index: Int, stride: Double, side: CGFloat) -> Double {
        var cycle = stride / (2 * .pi) + lag * Double(index)
        if side < 0 { cycle += 0.5 }
        cycle -= cycle.rounded(.down)
        // Planted and driving back under the animal, then picked up and thrown
        // forward again in the time that is left.
        let travel = cycle < Self.stance
            ? 0.5 - cycle / Self.stance
            : -0.5 + (cycle - Self.stance) / (1 - Self.stance)
        return -swing * travel * (side < 0 ? -1 : 1)
    }
}
