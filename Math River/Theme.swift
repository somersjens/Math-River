//
//  Theme.swift
//  Elephant Challenge: Math Memory
//
//  Character catalog: 10 animals, each with a clearly different colour and a
//  matching visual theme for the whole app. Characters are earned by collecting
//  cards; the requirements live in `GameConfig.characterUnlockRequirements`.
//

import SwiftUI

/// The game's currency. A player collects shells: on the sea floor, on the menu
/// totals, on the level cards and in the shop. One glyph, used everywhere, so
/// the same thing is never drawn two ways.
enum Currency {
    /// Identifies the currency glyph where a view has to tell it apart from an
    /// SF Symbol. It is drawn by `CurrencyIcon`, not loaded from the catalog.
    static let icon = "shell"
}

/// The glyph used anywhere a shell count is shown. It is drawn rather than
/// loaded, so it stays crisp from the 9-point level card up to the flying
/// reward, and it takes the surrounding foreground style exactly as the old
/// template image did.
struct CurrencyIcon: View {
    let size: CGFloat

    var body: some View {
        ShellShape()
            .fill(.foreground, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
    }
}

/// A scallop shell: a ribbed fan hinged at the bottom. The ribs are cut out of
/// the same path, so the whole glyph is one silhouette in one colour.
struct ShellShape: Shape {
    /// Bumps along the top edge.
    private static let scallops = 5

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }

        let hinge = point(0.5, 0.97)
        // The fan's top edge: a dome from the left corner to the right one.
        let rim: [CGPoint] = (0...Self.scallops).map { index in
            let t = Double(index) / Double(Self.scallops)
            return point(0.05 + 0.90 * t, 0.44 - 0.36 * sin(.pi * t))
        }

        var path = Path()
        path.move(to: hinge)
        path.addQuadCurve(to: rim[0], control: point(0.10, 0.82))
        for index in 1...Self.scallops {
            let previous = rim[index - 1]
            let next = rim[index]
            let mid = CGPoint(x: (previous.x + next.x) / 2, y: (previous.y + next.y) / 2)
            // Push each scallop's control point away from the hinge, which is
            // what turns a plain dome into a fluted edge.
            let dx = mid.x - hinge.x
            let dy = mid.y - hinge.y
            let length = max(0.001, (dx * dx + dy * dy).squareRoot())
            path.addQuadCurve(to: next,
                              control: CGPoint(x: mid.x + dx / length * w * 0.09,
                                               y: mid.y + dy / length * h * 0.09))
        }
        path.addQuadCurve(to: hinge, control: point(0.90, 0.82))
        path.closeSubpath()

        // The ribs, cut out by the even-odd rule.
        for index in 1..<Self.scallops {
            let tip = rim[index]
            let dx = tip.x - hinge.x
            let dy = tip.y - hinge.y
            let length = max(0.001, (dx * dx + dy * dy).squareRoot())
            let normalX = -dy / length
            let normalY = dx / length
            let width = w * 0.028
            func along(_ amount: CGFloat, _ spread: CGFloat) -> CGPoint {
                CGPoint(x: hinge.x + dx * amount + normalX * width * spread,
                        y: hinge.y + dy * amount + normalY * width * spread)
            }
            path.move(to: along(0.14, 1))
            path.addLine(to: along(0.90, 0.45))
            path.addLine(to: along(0.90, -0.45))
            path.addLine(to: along(0.14, -1))
            path.closeSubpath()
        }
        return path
    }
}

struct AnimalCharacter: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    // Colour components (0–1).
    let primaryRGB: (Double, Double, Double)
    let deepRGB: (Double, Double, Double)
    let skyRGB: (Double, Double, Double)
    let tintRGB: (Double, Double, Double)

    static func == (lhs: AnimalCharacter, rhs: AnimalCharacter) -> Bool {
        lhs.id == rhs.id
    }

    var color: Color { Color(red: primaryRGB.0, green: primaryRGB.1, blue: primaryRGB.2) }
    var deepColor: Color { Color(red: deepRGB.0, green: deepRGB.1, blue: deepRGB.2) }
    var skyColor: Color { Color(red: skyRGB.0, green: skyRGB.1, blue: skyRGB.2) }
    var tintColor: Color { Color(red: tintRGB.0, green: tintRGB.1, blue: tintRGB.2) }

    /// Position in the catalog, 1-based. Both pictures below and the rig's
    /// separate limbs are all exported under this number, so a character can
    /// never be paired with someone else's artwork.
    var catalogOrder: Int {
        (CharacterUnlocks.orderedCharacterIDs.firstIndex(of: id) ?? 0) + 1
    }

    /// Facing the player: menus, cards, the shop and every portrait slot. It is
    /// the whole animal — shell, claws and legs — on a square canvas, and all
    /// ten are centred and optically equalised, so one square frame renders any
    /// character at the same apparent size. The King keeps the picture he has
    /// always had: he is the app's mascot and wears his crown in it.
    var imageName: String { catalogOrder == 1 ? "1_main" : "\(catalogOrder)_full" }
    var artwork: Image { Image(imageName) }

    /// The same animal at chip size, for the slots that draw him no bigger than
    /// a stamp: the shop's grid, the row of animals just earned, the line
    /// counting down to the next one, and the small talking heads. Handing
    /// those the full-size picture makes the renderer unpack a 640-pixel square
    /// to paint forty points of it, and ten of those is most of what opening
    /// the shop costs.
    var thumbImageName: String { "\(catalogOrder)_thumb" }
    var thumbArtwork: Image { Image(thumbImageName) }

    /// The separate limbs the arena animates this character from, when the
    /// character has been cut into parts. Everyone else is drawn from the one
    /// square portrait above, so a character without a rig still works.
    var rig: CharacterRig? { CharacterRig.rig(for: id) }

    /// Localized display name, resolved per language from the string catalog
    /// ("character.fox", "character.frog", …).
    var localizedName: String {
        L(key: "character.\(id)")
    }
}

enum CharacterCatalog {
    /// The character available from the very first card.
    static let freeCharacterID = CharacterUnlocks.starterCharacterID

    /// The localized fallback used when the player leaves their name empty.
    /// Resolve it through the character catalog so it can never drift from the
    /// name shown for the starter character in the active language.
    static var defaultPlayerName: String {
        character(id: freeCharacterID).localizedName
    }

    /// Order must match `CharacterUnlocks.orderedCharacterIDs`; a test asserts it.
    ///
    /// Every palette is sampled from that character's own artwork, so the reef,
    /// the menu and the motion trail behind a portrait all carry the colours
    /// the player is actually looking at.
    static let all: [AnimalCharacter] = [
        AnimalCharacter(id: "crab", name: "Crab", emoji: "🦀",
                        primaryRGB: (0.90, 0.27, 0.10), deepRGB: (0.62, 0.13, 0.03),
                        skyRGB: (1.00, 0.90, 0.87), tintRGB: (1.00, 0.82, 0.77)),
        AnimalCharacter(id: "elephant", name: "Elephant", emoji: "🐘",
                        primaryRGB: (0.36, 0.58, 0.78), deepRGB: (0.19, 0.38, 0.58),
                        skyRGB: (0.90, 0.94, 0.97), tintRGB: (0.81, 0.89, 0.96)),
        AnimalCharacter(id: "bear", name: "Bear", emoji: "🐻",
                        primaryRGB: (0.72, 0.44, 0.16), deepRGB: (0.42, 0.20, 0.06),
                        skyRGB: (0.99, 0.94, 0.88), tintRGB: (0.98, 0.89, 0.79)),
        AnimalCharacter(id: "fox", name: "Fox", emoji: "🦊",
                        primaryRGB: (0.94, 0.60, 0.26), deepRGB: (0.68, 0.30, 0.07),
                        skyRGB: (1.00, 0.94, 0.87), tintRGB: (1.00, 0.89, 0.77)),
        AnimalCharacter(id: "frog", name: "Frog", emoji: "🐸",
                        primaryRGB: (0.45, 0.76, 0.18), deepRGB: (0.12, 0.47, 0.15),
                        skyRGB: (0.93, 0.99, 0.88), tintRGB: (0.88, 0.97, 0.80)),
        AnimalCharacter(id: "penguin", name: "Penguin", emoji: "🐧",
                        primaryRGB: (0.22, 0.36, 0.68), deepRGB: (0.08, 0.16, 0.38),
                        skyRGB: (0.89, 0.92, 0.98), tintRGB: (0.81, 0.86, 0.96)),
        AnimalCharacter(id: "bunny", name: "Bunny", emoji: "🐰",
                        primaryRGB: (0.94, 0.56, 0.60), deepRGB: (0.72, 0.29, 0.37),
                        skyRGB: (1.00, 0.87, 0.89), tintRGB: (0.99, 0.78, 0.80)),
        AnimalCharacter(id: "dog", name: "Dog", emoji: "🐶",
                        primaryRGB: (0.20, 0.66, 0.69), deepRGB: (0.06, 0.42, 0.46),
                        skyRGB: (0.89, 0.97, 0.98), tintRGB: (0.81, 0.95, 0.96)),
        AnimalCharacter(id: "lion", name: "Lion", emoji: "🦁",
                        primaryRGB: (0.95, 0.74, 0.20), deepRGB: (0.68, 0.45, 0.08),
                        skyRGB: (1.00, 0.96, 0.87), tintRGB: (1.00, 0.94, 0.77)),
        AnimalCharacter(id: "octopus", name: "Octopus", emoji: "🐙",
                        primaryRGB: (0.62, 0.40, 0.87), deepRGB: (0.35, 0.18, 0.60),
                        skyRGB: (0.93, 0.88, 0.99), tintRGB: (0.88, 0.79, 0.98))
    ]

    static func character(id: String) -> AnimalCharacter {
        all.first { $0.id == id } ?? all[0]
    }

    /// The first half of the catalog: earned purely by collecting cards.
    static var cardCharacters: [AnimalCharacter] {
        all.filter { !CharacterUnlocks.premiumCharacterIDs.contains($0.id) }
    }

    /// The second half: still earnable with cards, but Premium grants them at once.
    static var premiumCharacters: [AnimalCharacter] {
        all.filter { CharacterUnlocks.premiumCharacterIDs.contains($0.id) }
    }

    /// The selected character, falling back to the starter when the selected
    /// one is not available (yet).
    static func current(isPremium: Bool) -> AnimalCharacter {
        let selected = character(id: GameSettings.characterID)
        if !CharacterUnlockStore.canUse(characterID: selected.id, isPremium: isPremium) {
            return character(id: freeCharacterID)
        }
        return selected
    }
}

/// Character access, derived from the player's card total so an unlock can
/// never be lost through a missed animation. Only the one-time celebration
/// receipt is stored separately.
enum CharacterUnlockStore {
    static var totalCards: Int {
        get { Progress.store.totalCards }
        set { Progress.store.totalCards = newValue }
    }

    /// Cards required for a character, or nil when it is not card-unlockable.
    static func requirement(for characterID: String) -> Int? {
        CharacterUnlocks.cardsRequired(for: characterID)
    }

    static func canUse(characterID: String, isPremium: Bool) -> Bool {
        CharacterUnlocks.isUnlocked(characterID: characterID,
                                    totalCards: totalCards,
                                    isPremium: isPremium)
    }

    /// The next animal still to be earned, for the home screen and reminders.
    static func nextMilestone() -> (character: AnimalCharacter, remaining: Int)? {
        guard let next = CharacterUnlocks.nextMilestone(totalCards: totalCards) else { return nil }
        return (CharacterCatalog.character(id: next.characterID), next.remaining)
    }

    /// Characters that crossed their requirement but have not been celebrated.
    static func unannouncedUnlocks(at total: Int) -> [AnimalCharacter] {
        let announced = Progress.store.announcedUnlocks
        return CharacterUnlocks.unlockedCharacterIDs(totalCards: total)
            .filter { $0 != CharacterCatalog.freeCharacterID && !announced.contains($0) }
            .map { CharacterCatalog.character(id: $0) }
    }

    static func markAnnounced(_ characterID: String) {
        var announced = Progress.store.announcedUnlocks
        announced.insert(characterID)
        Progress.store.announcedUnlocks = announced
    }
}
