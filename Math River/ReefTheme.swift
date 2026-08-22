//
//  ReefTheme.swift
//  Number Reef
//
//  The sea floor's own colours and taste, one set per character. `ReefPalette`
//  mixes these with the character's colours and hands the result to the arena;
//  nothing else in the app reads them.
//

import SwiftUI

/// A reef before the character's colours are mixed into it.
///
/// Every arena is built from one of these. The point of the table is that each
/// of the ten animals can end up with a sea floor that is visibly *theirs* — an
/// octopus reef in violets and inks, a frog reef in greens and yellows — while
/// all ten still read as the same underwater game. What keeps that a table
/// rather than ten hand-drawn scenes is that only colour and a little taste
/// change: the sand, the stones and the growths are the same drawings.
///
/// **Today every character uses `.classic`**, so the arena looks exactly as it
/// always has. Giving one its own vibe is one row of `themes` below:
///
/// * `accents` — the reef's own five hues, in the order the scenery asks for
///   them (fan, branch, tubes, cups, buds). This is the biggest lever: it is
///   what every coral, sponge and starfish is coloured from.
/// * `accentPull` — how far those hues are dragged toward the character's own
///   colour. Low keeps a mixed reef; high makes the whole floor the animal's.
/// * `rock` / `rockDeep` / `rockPull` — the stone. Warm grey today; a themed
///   reef can go slate, sandstone or near-black.
/// * `plant` / `plantLight` — the greens the grass and weed are drawn in.
/// * `growthMap` — which growth a scenery slot actually draws. The layouts ask
///   for a style by index (0 fan, 1 branch, 2 tubes, 3 cups) and this remaps
///   it, so a reef can be *the tube reef* or *the fan reef* without a single
///   position being moved.
struct ReefTheme {
    /// Red, green, blue in 0…1. The catalog stores colours the same way.
    typealias RGB = (Double, Double, Double)

    /// The reef's five hues, in the order `reefAccent(_:)` indexes them.
    let accents: [RGB]
    /// How far each accent is pulled toward the character's colour, 0…1.
    let accentPull: Double

    let rock: RGB
    let rockDeep: RGB
    /// How far the stone is tinted by the character, 0…1.
    let rockPull: Double

    let plant: RGB
    let plantLight: RGB

    /// Where each of the four coral growths is sent. The identity map leaves
    /// every layout drawing what it asked for.
    let growthMap: [Int]

    /// The reef the game has always had: a mixed tropical garden, warm grey
    /// stone, and no growth favoured over another.
    static let classic = ReefTheme(
        accents: [
            (0.86, 0.30, 0.62),   // magenta fan
            (0.98, 0.53, 0.18),   // orange branch
            (0.56, 0.36, 0.86),   // violet tubes
            (0.20, 0.71, 0.73),   // teal cups
            (0.97, 0.42, 0.47)    // rose buds
        ],
        accentPull: 0.26,
        rock: (0.52, 0.57, 0.66),
        rockDeep: (0.31, 0.36, 0.46),
        rockPull: 0.18,
        plant: (0.18, 0.56, 0.34),
        plantLight: (0.43, 0.72, 0.30),
        growthMap: [0, 1, 2, 3]
    )

    /// One row per character, in catalog order. They all point at `.classic`
    /// for now — the rows exist so that giving a character its own reef is an
    /// edit here and nowhere else. Replacing one looks like this:
    ///
    /// ```swift
    /// "octopus": ReefTheme(
    ///     accents: [(0.62, 0.28, 0.86), (0.42, 0.36, 0.92), (0.78, 0.34, 0.90),
    ///               (0.34, 0.52, 0.88), (0.86, 0.42, 0.72)],
    ///     accentPull: 0.20,
    ///     rock: (0.46, 0.44, 0.62), rockDeep: (0.26, 0.24, 0.44), rockPull: 0.14,
    ///     plant: (0.24, 0.46, 0.52), plantLight: (0.38, 0.66, 0.62),
    ///     growthMap: [2, 1, 2, 3]
    /// ),
    /// ```
    ///
    /// Four violets and a rose rather than one violet: the reef still has to
    /// have colours *in* it, or the floor goes flat and the coral stops being
    /// the thing the eye picks out of the sand. What carries the territory is
    /// that they are all neighbours — and that the stone and the weed came
    /// along with them, which is what the last three lines are for.
    private static let themes: [String: ReefTheme] = [
        "crab": .classic,
        "elephant": .classic,
        "bear": .classic,
        "fox": .classic,
        "frog": .classic,
        "penguin": .classic,
        "bunny": .classic,
        "dog": .classic,
        "lion": .classic,
        "octopus": .classic
    ]

    static func theme(for characterID: String) -> ReefTheme {
        themes[characterID] ?? .classic
    }
}
