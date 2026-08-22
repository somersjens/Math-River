//
//  KingCrabArena.swift
//  King Krab
//
//  The playing surface's simulation: the sum stands at the top of the screen,
//  the King Crab holds the middle of the sea floor, and one small crab walks in
//  from each of the four corners carrying an answer card. Three of them are
//  wrong and are meant to be smashed with a tap; the fourth carries the right
//  answer and has to be let through.
//
//  This file holds the whole of the simulation and nothing else. Every rule
//  about scoring, lives, rounds and progress still lives in `MemoryGame`; the
//  arena only decides *when* something reaches the King or is smashed, and
//  hands that event over. The engine that owns the session has the final say on
//  every one of them.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Screen edges

/// The window's own safe area. The arena is laid out edge to edge, so it needs
/// the real insets to keep the sum clear of the HUD and the sea floor clear of
/// the home indicator — and a `GeometryReader` nested inside the playing field
/// reports zero for them, because its container has already been inset.
///
/// Sample this in `onAppear` and keep the value in state. Reading it from
/// inside a `body` wedges SwiftUI's update pass: the view renders once and then
/// stops receiving updates entirely, which shows up as a frozen playing field
/// with no sum on it.
struct ScreenSafeArea: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    var leading: CGFloat = 0
    var trailing: CGFloat = 0

    @MainActor
    static var current: ScreenSafeArea {
#if canImport(UIKit)
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let insets = window?.safeAreaInsets else { return ScreenSafeArea() }
        return ScreenSafeArea(top: insets.top,
                              bottom: insets.bottom,
                              leading: insets.left,
                              trailing: insets.right)
#else
        return ScreenSafeArea()
#endif
    }
}

// MARK: - Tuning

/// A conservative decoration budget for older hardware and Low Power Mode.
/// Gameplay, taps and arrivals always retain their full step; only effects that
/// do not carry information become a little sparser.
enum ArenaPerformanceBudget {
    /// Re-checked each use so Low Power Mode and thermal pressure can tighten
    /// the budget mid-session without waiting for a relaunch.
    static var isConstrained: Bool {
        ProcessInfo.processInfo.physicalMemory < 4_000_000_000
            || ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState.rawValue
                >= ProcessInfo.ThermalState.serious.rawValue
    }

    static var moteCount: Int { isConstrained ? 10 : 16 }
    static var maximumAmbientBubbles: Int { isConstrained ? 10 : 18 }
    static var grainsPerBurst: Int { isConstrained ? 5 : 10 }
    /// Hard ceiling on live sand grains so a multi-crab burrow cannot flood the
    /// effects canvas. Footfalls skip when the budget is already spent.
    static var maximumLiveGrains: Int { isConstrained ? 36 : 56 }
    static var celebrationInterval: Double { isConstrained ? 0.10 : 0.065 }
    static var celebrationSpeckCap: Int { isConstrained ? 48 : 90 }
    /// Always target 60 Hz. Dropping to 45 under pressure reads as lag to the
    /// player; particle budgets already shed load without chopping motion.
    static var preferredFramesPerSecond: Int { 60 }
    /// Scenery sway: 16 Hz normally, 10 Hz where the frame budget is tightest.
    static var swayInterval: Double { isConstrained ? 1.0 / 10.0 : 1.0 / 16.0 }
    static var driftInterval: Double { isConstrained ? 1.0 / 4.0 : 1.0 / 6.0 }
}

/// Every tunable number of the arena, kept together the way `GameConfig` keeps
/// the session's. Timings that are *rules* rather than presentation — how long
/// a crab takes to cross, what a breach costs — live in `GameConfig`.
enum ArenaConfig {
    // MARK: Crabs

    /// Body width of a walking crab; everything about it is measured from this.
    static func crabSize(isPad: Bool) -> CGFloat { isPad ? 53 : 38 }
    /// One full walk cycle, as a share of the body width. The gait is measured
    /// off ground actually covered rather than off time, so this is the length
    /// a planted foot is worth — and every footfall is counted against it.
    static let strideLength: CGFloat = 0.44
    /// How far below its middle a walking crab's feet come down, as a share of
    /// its body width. Measured off the artwork: see `AnswerCrabRig`.
    static let footLine: CGFloat = 0.68
    /// The answer shell a crab carries over its head. It is deliberately wider
    /// than the crab itself: the number is the thing being read, and a small
    /// crab under a big shell is what makes it read as *carried*.
    static func cardWidth(isPad: Bool) -> CGFloat { isPad ? 106 : 77 }
    static func cardHeight(isPad: Bool) -> CGFloat { isPad ? 86 : 64 }
    /// How far the shell floats above the body's centre, as a share of its own
    /// height. The claws are placed from the same number. It clears the crab's
    /// head: the arms have to be visibly holding the shell *up*, not propping
    /// it on top of the animal.
    static let cardLift: CGFloat = 0.88

    /// A tap counts as a hit anywhere inside this radius of the crab, which is
    /// deliberately generous: the player is aiming at a moving target with a
    /// finger, and a near miss that costs a life would be unfair.
    static func tapRadius(isPad: Bool) -> CGFloat { isPad ? 88 : 66 }

    /// A crab comes on at a scurry and settles into its walk exactly as its
    /// answer becomes readable. Crabs scuttle in bursts anyway, and a wave that
    /// strolls into view keeps the player waiting on the numbers.
    static let approachRush: Double = 5.5
    /// Smashed: flung away, spinning, shrinking into the sand.
    static let smashDuration = 0.46
    /// The retreat every remaining crab makes when the attempt is over. It is
    /// long enough to read as an animal digging itself in — a crab that hunkers
    /// down, scrabbles, and sinks — rather than as one being switched off.
    static let burrowDuration = 0.88
    /// The share of the dig spent hunkering down and scrabbling before the sand
    /// actually starts swallowing the crab. A crab digs itself in tail first,
    /// and the working is most of what you see.
    static let burrowSquatShare = 0.38
    /// How often a digging crab throws up a fresh spray of sand. The spray is
    /// what tells the player the sand is being *moved*.
    static let burrowPuffInterval = 0.065

    /// Handing the answer over: the right crab reaches its shell out to the
    /// King's claws and comes back down out of the reach. A crab that got the
    /// answer right is on the King's side, so it is never swept aside — it
    /// gives, and digs itself in.
    static let deliverDuration = 0.62
    /// Where in that movement the stone is actually down and let go of, and
    /// with it the moment the King's own shell can leave for the score.
    static let deliverGiveShare = 0.62
    /// Swept aside by the King's own blow, which throws them much further.
    static let sweptDuration = 0.62
    /// The longest the finale will wait for the crab that won the board to get
    /// its shell to the King. A crab that is walking always beats this; it is
    /// here so that nothing — a stalled wave, a crab caught in some state the
    /// walk never reaches — can leave a player sat in front of a finished
    /// board with no celebration coming.
    static let finalDeliveryWait = 3.5

    /// With every wrong answer taken, the right one stops being careful and
    /// runs the rest of the way to the King. This is how much faster than its
    /// own walk it covers what is left.
    static let rushSpeed: Double = 6.4
    /// It breaks into the run rather than snapping to full speed.
    static let rushRamp = 0.30
    /// Sand thrown up behind a running crab.
    static let rushPuffInterval = 0.10

    // MARK: The King

    /// Sized so outstretched claws keep clear of the screen edges on a phone;
    /// the rig canvas is wider still so a swing is not clipped by its own layer.
    static func kingSize(isPad: Bool) -> CGFloat { isPad ? 248 : 178 }
    /// Where a walking crab stops: on a ring around the King, wide enough that
    /// four arrivals stand around him rather than on top of him.
    static let arrivalRingFactor: CGFloat = 0.72
    /// Arrivals inside this window are answered by a single sweep, so two crabs
    /// reaching the King together never produce two separate animations.
    static let sweepGather = 0.14
    /// A breather before the sea floor sends the same sum's answers around
    /// again, for any wave that ends without the right answer being settled.
    static let waveRefillGap = 0.9
    static let sweepDuration = 0.52
    /// The heal flash when the life crab gets through.
    static let healDuration = 1.0

    /// The King scuttles on from the left before the first round and plants
    /// himself in the middle of the floor.
    static let entranceDuration = 1.05
    /// The first wave sets off well before the King has settled, so the round
    /// opens into motion rather than into a held pose — the crabs are already
    /// coming while he is still crossing the last of the sand.
    static let entranceAnswerLead = 0.46
    /// Sand kicked up under him on the way in.
    static let entrancePuffInterval = 0.085

    /// Answering a tap: the claw on that side winds up and throws a handful of
    /// sand at the crab the player picked. Short enough that a child who taps
    /// twice in a second sees both throws.
    static let clawThrowDuration = 0.40
    /// The share of the throw spent cocking the claw (scoop or overhead).
    static let clawWindUpShare = 0.40
    /// How much of the throw the strike itself takes, measured from the end of
    /// the wind-up. What is left is the arm easing back to rest.
    static let clawStrikeShare = 0.24
    /// Where in the throw the sand actually leaves: near the end of the strike,
    /// with the arm at full reach and moving fastest.
    static let clawReleaseShare = 0.58
    /// A second crab taken on the same side waits its turn rather than cutting
    /// the throw short, so the arm always completes the swing it started.
    static let clawThrowQueue = 3
    /// How long the thrown sand takes to reach what it was thrown at.
    static let sandFlightDuration = 0.18
    /// How long a tapped crab keeps walking before the sand actually reaches it
    /// and it starts flying: the same span the claw takes to wind up and
    /// release, plus the sand's own time in the air.
    static let sandImpactDelay = clawThrowDuration * clawReleaseShare + sandFlightDuration
    /// The pincer at rest, as a share of the King's size from his centre. The
    /// sand leaves from here so it comes out of a claw, not out of his middle.
    static let clawTip = CGSize(width: 0.353, height: -0.255)

    /// True when the target sits in front of the King on screen (larger y).
    /// Forward throws scoop sand low; backward throws cock the claw high.
    static func isForwardThrow(targetY: CGFloat, kingY: CGFloat) -> Bool {
        targetY >= kingY
    }

    /// Unsigned claw angle for a sand throw before the left/right sign flip.
    /// Positive lifts the left claw (and drops the right once signed).
    static func clawThrowPoseAngle(progress: Double,
                                   targetRise: Double,
                                   isForward: Bool) -> Double {
        let wind = clawWindUpShare
        let strike = clawStrikeShare
        let aim = max(-1, min(1, targetRise))
        let windAngle: Double
        let thrownAngle: Double
        if isForward {
            // Scoop: dip to the sand, then fling out and forward.
            windAngle = -26 + aim * 4
            thrownAngle = -68 + aim * 10
        } else {
            // Overhead: cock up toward the crown, then hurl back at a high target.
            windAngle = 42 + aim * 8
            thrownAngle = -22 + aim * 20
        }

        let value: Double
        if progress < wind {
            let u = progress / wind
            // Ease into the wind-up; a soft overshoot sells the scoop / cock.
            value = windAngle * (1 - pow(1 - u, 2.4))
        } else if progress < wind + strike {
            let u = (progress - wind) / strike
            let snap = u * u * (3 - 2 * u)
            value = windAngle + (thrownAngle - windAngle) * snap
        } else {
            let u = (progress - wind - strike) / max(0.001, 1 - wind - strike)
            // Follow-through past the release, then settle home.
            let coast = thrownAngle * (1 + 0.12 * (1 - u))
            value = coast * (1 - u) * (1 - u)
        }
        return value
    }

    /// The finale: a hop on the spot, a beat to gather himself, then off to the
    /// right at a run. A jump this high needs the airtime to match — halve the
    /// duration and the same arc reads as a twitch rather than a leap.
    static let kingHopDuration = 0.58
    static let kingHopHeight: CGFloat = 0.68
    static let kingHopSettle = 0.16
    static let kingExitDuration = 0.72

    /// The streak celebration: the King steps out to one side, back across to
    /// the other and home again, while his claws dip and then go up as high as
    /// the artwork carries them — see `streakCelebrationClawTouch`.
    static let streakCelebrationDuration = 1.5
    /// How far to either side he travels, as a share of his own size. He is
    /// back on his anchor by the end, so this only ever borrows the ground.
    static let streakCelebrationSway: CGFloat = 0.30
    /// How far each claw turns as it goes up. As high as the artwork allows:
    /// the rig draws the body *over* the limbs, so a claw carried further than
    /// this slides behind the head and disappears instead of reading as raised.
    /// Measured on the device — at 52° only the shoulders still showed, and the
    /// turn that would actually touch the two pincers together over the crown
    /// (about 74°) hides them completely.
    static let streakCelebrationClawTouch = 40.0
    /// The dip that precedes it, as a share of that same turn.
    static let streakCelebrationClawDip = 0.24

    // MARK: Carrier crabs

    /// The artwork square a helper crab is drawn on. Its body is a little over
    /// half of this — see `CharacterRig.bonusHelper` — so it stands a shade
    /// larger than an answer crab, which is what a crab walking the very front
    /// of the floor should do. The life crab is a touch larger still: the heart
    /// between its claws needs room to read without a plate behind it.
    static func helperCrabSize(isPad: Bool, kind: CarrierCrab.Kind = .bonus) -> CGFloat {
        switch kind {
        case .bonus: return isPad ? 112 : 82
        case .life:  return isPad ? 128 : 94
        }
    }
    /// How wide the 2× coin is, on that same square.
    static let helperTokenShare: CGFloat = 0.35
    /// How wide the bare heart is between the life crab's claws. Larger than
    /// the coin share: without a disc behind it, the glyph itself has to carry
    /// the read.
    static let lifeTokenShare: CGFloat = 0.50
    /// How far above the bottom of the walking area the helper crabs cross. It
    /// is the lane the lower answer crabs used to come in at, which is now the
    /// near edge of the floor: they walk in front of the reef and of everything
    /// else, because they are the nearest thing in the scene.
    static func helperLane(isPad: Bool) -> CGFloat { isPad ? 40 : 29 }
    /// Wall-clock time for a helper to cross the near lane, end to end. Tuned
    /// on the phone; kept as a duration (not a points/sec speed) so a wider
    /// iPad arena does not quietly hand the player more time to tap.
    static let helperCrabCrossingDuration: ClosedRange<Double> = 3.5...4.3
    /// How fast one walks once the player has sent it to the King, in points
    /// per second on a phone-width arena. On a wider board the speed scales
    /// with `arena.width` so the trip in still takes the same time.
    static let helperFetchSpeed: CGFloat = 210
    /// Arena width the fetch speed above was tuned for (~iPhone portrait).
    static let helperSpeedReferenceWidth: CGFloat = 390
    /// After one of the preselected questions appears, this little extra delay
    /// keeps the exact arrival surprising and independent of the wave.
    static let bonusCrabQuestionDelay: ClosedRange<Double> = 2.0...5.0

    /// How long after being earned the comeback crab appears.
    static let lifeCrabDelay: ClosedRange<Double> = 1.2...2.6
    /// A helper crab that crossed without being tapped comes round again after
    /// this. Neither reward is ever lost by being missed once.
    static let helperCrabRetry: ClosedRange<Double> = 2.4...4.5

    // MARK: Walkthrough

    /// How long the walkthrough's helper crab takes to come round, both the
    /// first time and after a miss.
    static let tutorialCrabArrival = 0.8
    /// Water the walkthrough keeps free under the sum for its note: the strip
    /// itself and a little clear water under it, so a crab walking the top lane
    /// carries its answer in below the note rather than behind it.
    ///
    /// Reserved for the whole run rather than only while a message is up. The
    /// band changing size is what used to jolt the floor, the King and every
    /// crab already walking, once when the first line arrived and again when
    /// the last one cleared.
    static func tutorialMessageReserve(isPad: Bool) -> CGFloat {
        TutorialMessageCard.height(isPad: isPad) + (isPad ? 22 : 16)
    }

    // MARK: Level completion

    /// Hop, run, and hand over while he is still going. This lands a little
    /// before the run ends, so the card comes up over a King on his way out of
    /// frame rather than over an empty floor he left seconds ago.
    static let completionDuration = kingHopDuration + kingHopSettle
        + kingExitDuration * 0.86

    // MARK: Scenery

    /// How far below the top of the walking area the sea floor's crest lies.
    ///
    /// Deliberately well down: the top third of the screen is open water, and
    /// the floor has to start low enough to leave it. The crabs walking the
    /// upper lane come in below this — their shells are held up into the blue,
    /// which is the whole point of standing on a floor that has water above it.
    static func floorCrest(isPad: Bool) -> CGFloat { isPad ? 84 : 64 }

    /// How far the near reef in the two front corners stands up out of the
    /// sand. The lower lane is walked above it — see `entryPoints` — so a crab
    /// coming in down there passes *behind* the coral, the way something
    /// further away should, while the answer it holds up stays in clear water.
    static func nearReefRise(isPad: Bool) -> CGFloat { isPad ? 60 : 44 }

    /// Where the King stands in the walking area, top to bottom. The scenery
    /// reads it too: the sun lands where he is, not on the middle of the sand.
    /// He stands high enough on the floor for the sun to land squarely on him
    /// and for the near reef to pass in front of the sand below his feet.
    static let kingAnchorShare: CGFloat = 0.47
    /// How far the arena keeps clear of the bottom edge, on top of whatever the
    /// home indicator already reserves.
    static func floorInset(isPad: Bool) -> CGFloat { isPad ? 26 : 18 }
    static func sideInset(isPad: Bool) -> CGFloat { isPad ? 16 : 10 }

    /// The sum's banner at the top of the screen.
    static func bannerHeight(isPad: Bool) -> CGFloat { isPad ? 108 : 82 }

    // MARK: Rewards

    /// A collected answer leaves the King as a shell that reaches the HUD just
    /// after the next sum appears.
    static let shellFlightDuration = 0.92

    // MARK: Ambience

    static let ambientBubbleGap: ClosedRange<Double> = 0.32...0.72
    static let ambientBubbleSpeed: ClosedRange<CGFloat> = 28...54
    static let ambientBubbleRadius: ClosedRange<CGFloat> = 3.5...9
    static var maximumAmbientBubbles: Int { ArenaPerformanceBudget.maximumAmbientBubbles }
    static let ambientBubblePopDuration = 0.24

    static var moteCount: Int { ArenaPerformanceBudget.moteCount }
    static let moteSpeed: ClosedRange<CGFloat> = 8...22
    static let moteRadius: ClosedRange<CGFloat> = 1.5...4.5

    /// How often the swaying scenery is re-sampled. Coral and plants breathe at
    /// well under 1.2 Hz, so a fresh position ~16 times a second is already
    /// smoother than the eye can follow — while a full 60 Hz rebuild of that
    /// whole sea floor is by far the most expensive thing in the frame.
    static var swayInterval: Double { ArenaPerformanceBudget.swayInterval }
    /// The sun shafts drift on a 35-second cycle and are the one full-screen
    /// soft layer in the scene, so they are re-sampled far more sparingly still.
    static var driftInterval: Double { ArenaPerformanceBudget.driftInterval }

    /// Simulation step used where no display link is available.
    static let tick = 1.0 / 60.0
}

// MARK: - Palette

/// The arena's colours. Each one starts from the player's own character colours
/// and is pulled toward the sea, so a fox arena and a penguin arena are still
/// recognisably theirs while both read as an underwater sea floor.
struct ReefPalette: Equatable {
    let character: AnimalCharacter
    /// The sea floor's own colours and taste, before the character is mixed in.
    /// One row per character — see `ReefTheme`, which is where an animal is
    /// given its own reef.
    let theme: ReefTheme

    /// The character decides every colour in here — the theme is looked up from
    /// it — so it is the whole of the comparison. This is what lets the scenery
    /// views be `Equatable` on their palette and skip a rebuild they would only
    /// redraw identically.
    static func == (lhs: ReefPalette, rhs: ReefPalette) -> Bool {
        lhs.character == rhs.character
    }

    private static let surface = (0.60, 0.87, 0.95)
    private static let depth = (0.10, 0.45, 0.66)
    private static let sandTone = (0.95, 0.86, 0.66)
    private static let sandShadow = (0.78, 0.65, 0.43)
    /// The four rungs of the water column, from the surface just off the top of
    /// the screen down to the sand. Shallow tropical water is not one blue: it
    /// is almost white-cyan where the sun goes in, saturated blue through the
    /// open middle, and green again where it picks the sea floor back up.
    private static let surfaceTone = (0.74, 0.97, 0.99)
    private static let shallowTone = (0.36, 0.83, 0.93)
    private static let midTone = (0.13, 0.55, 0.82)
    private static let floorTone = (0.26, 0.63, 0.71)
    /// The warm patch the sun lays down in the middle of the arena.
    private static let sandSunTone = (1.00, 0.93, 0.72)

    // Every one of these used to be recomputed on each access — a tuple blend
    // and a fresh `Color` — and the drawing code reads them constantly: the
    // sand shadow alone is asked for once per crab and once per leg, on every
    // frame. They depend on nothing but the character, so they are mixed once.
    let waterTop: Color
    let waterDeep: Color
    let sand: Color
    let sandDeep: Color

    /// The rungs of the water column, top to bottom. `waterTop` stays the
    /// shallow blue the rest of the app already borrows for menus; these carry
    /// the depth the arena itself is drawn with.
    let waterSurface: Color
    let waterShallow: Color
    let waterMid: Color
    /// The colour everything far away is losing itself to — the water at the
    /// depth the sand starts at. Haze, distant weed and the far sand all mix
    /// toward this, which is what makes the floor recede instead of simply
    /// starting at a line.
    let waterFloor: Color
    /// Sand with the sun full on it, for the bright patch in the middle.
    let sandSunlit: Color

    /// The coral keeps the character's own colour: it is the one warm thing on
    /// the sea floor, and it frames the arena the King holds.
    let coral: Color
    let coralDeep: Color
    let rock: Color
    let rockDeep: Color
    /// The reef's accents, resolved for every hue up front: `reefAccent(_:)` is
    /// called from inside the sea floor's rebuild, once per coral.
    private let accents: [Color]
    private let accentsDeep: [Color]

    /// The greens the grass and the weed are drawn in. They come from the
    /// theme, so a reef can be given its own planting alongside its own coral.
    let plant: Color
    let plantLight: Color

    init(character: AnimalCharacter) {
        let theme = ReefTheme.theme(for: character.id)
        self.character = character
        self.theme = theme
        waterTop = Self.mix(character.skyRGB, Self.surface, 0.72)
        waterDeep = Self.mix(character.primaryRGB, Self.depth, 0.85)
        sand = Self.mix(character.tintRGB, Self.sandTone, 0.72)
        sandDeep = Self.mix(character.deepRGB, Self.sandShadow, 0.62)
        waterSurface = Self.mix(character.skyRGB, Self.surfaceTone, 0.82)
        waterShallow = Self.mix(character.skyRGB, Self.shallowTone, 0.88)
        waterMid = Self.mix(character.primaryRGB, Self.midTone, 0.84)
        waterFloor = Self.mix(character.primaryRGB, Self.floorTone, 0.82)
        sandSunlit = Self.mix(character.tintRGB, Self.sandSunTone, 0.86)
        coral = character.color
        coralDeep = character.deepColor
        rock = Self.mix(theme.rock, character.primaryRGB, theme.rockPull)
        rockDeep = Self.mix(theme.rockDeep, character.deepRGB, theme.rockPull)
        plant = Color(red: theme.plant.0, green: theme.plant.1, blue: theme.plant.2)
        plantLight = Color(red: theme.plantLight.0,
                           green: theme.plantLight.1,
                           blue: theme.plantLight.2)
        accents = theme.accents.map {
            Self.mix($0, character.primaryRGB, theme.accentPull)
        }
        accentsDeep = theme.accents.map {
            Self.mix(Self.mix3($0, 0.62), character.deepRGB, theme.accentPull - 0.02)
        }
    }

    /// One palette per character, built once. The playfield asks for its
    /// palette from inside `body`, so without this every frame mixed the whole
    /// set again and handed the scenery views a value they could not recognise
    /// as unchanged.
    @MainActor
    private static var cache: [String: ReefPalette] = [:]

    @MainActor
    static func palette(for character: AnimalCharacter) -> ReefPalette {
        if let cached = cache[character.id] { return cached }
        let palette = ReefPalette(character: character)
        cache[character.id] = palette
        return palette
    }

    func reefAccent(_ index: Int) -> Color {
        accents[abs(index) % accents.count]
    }

    func reefAccentDeep(_ index: Int) -> Color {
        accentsDeep[abs(index) % accentsDeep.count]
    }

    /// Which growth a scenery slot actually draws. The layouts ask for a style
    /// by index — 0 fan, 1 branch, 2 tubes, 3 cups — and the theme is allowed
    /// to send it somewhere else, so a reef can be *the tube reef* without a
    /// single coral being moved. The classic map is the identity.
    func growth(_ style: Int) -> Int {
        theme.growthMap[abs(style) % theme.growthMap.count]
    }

    /// Darkens a hue toward its own shadow.
    private static func mix3(_ base: (Double, Double, Double),
                             _ amount: Double) -> (Double, Double, Double) {
        (base.0 * amount, base.1 * amount, base.2 * amount)
    }

    private static func mix(_ base: (Double, Double, Double),
                            _ target: (Double, Double, Double),
                            _ amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        return Color(red: base.0 + (target.0 - base.0) * t,
                     green: base.1 + (target.1 - base.1) * t,
                     blue: base.2 + (target.2 - base.2) * t)
    }
}

// MARK: - Model

/// One small crab on its way to the King, carrying an answer card.
struct AnswerCrab: Identifiable {
    /// The only states a crab can be in. Everything the arena decides — a tap,
    /// an arrival, the end of an attempt — is expressed as one of these, so a
    /// crab can never be smashed twice or arrive after it has been swept away.
    enum Phase: Equatable {
        /// Standing off the side of the screen, waiting for its turn to walk on.
        case waiting
        case walking
        /// Standing at the King's ring, waiting for the sweep that answers it.
        case arrived
        /// Tapped, and still walking while the thrown sand is on its way to it.
        /// It only starts flying once the sand actually arrives.
        case hit
        /// Hit by the player.
        case smashed
        /// Handing its shell to the King, which is what a crab carrying the
        /// right answer does when it gets there.
        case delivering
        /// Digging itself back into the sand: the attempt is over.
        case burrowing
        /// Thrown aside by the King's blow.
        case swept
    }

    let id = UUID()
    /// The session's option, which is what an arrival reports back.
    let optionID: UUID
    let text: String
    let isCorrect: Bool
    /// Whether this crab came up gold, decided once when its wave was laid out.
    /// A crab never changes colour on the sand: the streak starting or breaking
    /// under one is the *next* wave's news, not a repaint of the crabs the
    /// player is already reading.
    let isGolden: Bool

    /// Off the side of the screen: a crab walks in rather than appearing.
    private(set) var start: CGPoint
    private(set) var target: CGPoint
    var position: CGPoint
    /// 0 → off screen, 1 → at the King.
    var progress: Double = 0
    /// The share of the walk that happens before the answer is fully in view.
    /// It is covered at a scurry, so the shell shows up early; everything after
    /// it is walked at the pace the game has always had.
    let entryProgress: Double
    /// Seconds this crab needs for the part of the walk that is on screen.
    let duration: Double
    /// Seconds it waits out of sight before setting off.
    var startDelay: Double

    /// Small honest differences, so four crabs never march as one shape.
    let waddleAmplitude: CGFloat
    let waddleRate: Double
    /// How long this crab's stride is, against the standard one. Together with
    /// `gaitOffset` it keeps four crabs from stepping in lockstep.
    let strideFactor: CGFloat
    let gaitOffset: Double
    /// Ground actually covered, in points. The walk cycle is measured off this
    /// rather than off time, so a foot that is planted never slides: when the
    /// crab hesitates mid-scuttle its legs hesitate with it.
    var walked: CGFloat = 0
    /// The stride the next footfall lands on, measured in that same ground. It
    /// is what the little kick of sand under a walking crab is counted off, so
    /// the floor is disturbed by steps rather than by seconds.
    var nextFootfall: CGFloat = 0
    let cardLean: Double
    /// A crab does not glide: it scuttles a few steps, hesitates, and goes
    /// again. This is the rhythm of that visual surge along the path — it no
    /// longer changes how fast the crab covers ground, so a wave still shares
    /// one arrival.
    let scuttleRate: Double
    let scuttlePhase: Double
    /// Which way it is travelling across the screen, so it leads with the
    /// claw on that side and looks where it is going.
    let facing: CGFloat

    var phase: Phase = .waiting
    /// Time spent in the current phase, which drives every exit animation.
    var phaseAge: Double = 0
    var age: Double = 0
    /// Where a smashed or swept crab is being thrown, and how fast it tumbles.
    var flingVelocity: CGPoint = .zero
    var spin: Double = 0
    /// Set on the right answer once it is the only one left walking: it runs
    /// the rest of the way in rather than strolling into an empty arena.
    var isRushing = false
    /// How long it has been running, which is what eases it up to speed.
    var rushAge: Double = 0
    /// Time to the next spray of sand, for whatever this crab is doing to the
    /// sea floor: running across it or digging into it.
    var puffCountdown: Double = 0
    /// Where the King's claws are, in this crab's own coordinates: the point it
    /// reaches its shell out to while handing the answer over.
    var handOver: CGPoint = .zero
    /// True once the King has the shell. It never comes back: a crab that has
    /// given its answer away digs itself in empty-handed.
    var hasDelivered = false
    /// Set when the session has already counted this crab's answer. From that
    /// moment it is no longer part of the wave — it is the tail of the last
    /// one, running its shell up to the King while the next sum is already
    /// walking in behind it.
    var hasAnswered = false

    /// Whether this crab is still one of the answers on offer. A crab whose
    /// answer has been counted is finished with, however much of its own
    /// animation is left to play.
    var isLive: Bool { (phase == .waiting || phase == .walking) && !hasAnswered }
    /// Whether a tap may still take this crab. A crab still waiting its turn is
    /// out of sight, so a tap near the edge must never take it blind.
    var isTappable: Bool { phase == .walking && !hasAnswered }

    /// Moves the whole walk when the arena itself moves under it.
    mutating func shift(by delta: CGPoint) {
        start.x += delta.x; start.y += delta.y
        target.x += delta.x; target.y += delta.y
        position.x += delta.x; position.y += delta.y
    }
}

/// One of the two crabs that carry something other than an answer: the 2x crab
/// with a doubling coin, and the comeback crab with a life.
///
/// Both work the same way, and neither hands anything over by itself. They
/// cross the very front of the floor holding what they have brought up over
/// their heads, and only a tap sends one of them in to the King. That is what
/// makes taking a reward a thing the player *does*: a life that arrived on its
/// own was something that merely happened to them.
struct CarrierCrab: Identifiable {
    enum Kind { case bonus, life }

    enum Phase {
        /// Walking the near lane, offering itself.
        case crossing
        /// Tapped: on its way to the King with what it is carrying.
        case fetching
        /// Delivered, and digging itself back into the sand.
        case burrowing
    }

    let id = UUID()
    let kind: Kind
    /// The artwork square it is drawn on; its body is a little over half of it.
    let size: CGFloat
    private(set) var start: CGPoint
    private(set) var target: CGPoint
    var position: CGPoint
    var progress: Double = 0
    private(set) var duration: Double
    var phase: Phase = .crossing
    /// Time in the current phase, which drives the dig at the end of it.
    var phaseAge: Double = 0
    let waddleRate: Double
    let strideFactor: CGFloat
    let gaitOffset: Double
    /// Ground covered, for the same distance-driven gait the answer crabs use.
    var walked: CGFloat = 0
    /// The stride the next footfall lands on, in the same ground.
    var nextFootfall: CGFloat = 0
    /// Which way it is facing, for the sprite's mirror.
    var facing: CGFloat = 1
    /// Time to its next spray of sand while it is digging itself in.
    var puffCountdown: Double = 0

    /// How wide the animal itself is inside that square. Both helper crabs are
    /// drawn to the same template, so one number covers the pair.
    var bodyWidth: CGFloat { size * 0.57 }

    /// True until it has put what it brought into the King's claws.
    var isCarryingReward: Bool { phase != .burrowing }
    /// A tap only counts while it is still crossing: one already on its way to
    /// the King has been asked for, and asking twice must not send it twice.
    var isTappable: Bool { phase == .crossing }

    mutating func shift(by delta: CGPoint) {
        start.x += delta.x; start.y += delta.y
        target.x += delta.x; target.y += delta.y
        position.x += delta.x; position.y += delta.y
    }

    /// Turns it out of the lane and in towards the King, from wherever the tap
    /// caught it. The walk starts over from here, so the pace of the trip in is
    /// the King's distance rather than whatever was left of the crossing.
    mutating func fetch(to point: CGPoint, speed: CGFloat) {
        start = position
        target = point
        progress = 0
        duration = Double(max(1, hypot(point.x - position.x, point.y - position.y)) / speed)
        phase = .fetching
        phaseAge = 0
        facing = point.x >= position.x ? 1 : -1
    }
}

/// The shell a scored answer sends up to the HUD. It is deliberately separate
/// from anything the player can touch.
struct ShellReward: Identifiable {
    let id = UUID()
    let diameter: CGFloat
    let start: CGPoint
    let firstControl: CGPoint
    let secondControl: CGPoint
    let target: CGPoint
    var position: CGPoint
    var age: Double = 0
}

/// The 2× coin after the bonus crab has handed it over. It rests under the
/// King until the doubled answer's shell goes up, then flies the same route
/// behind him — never crossing in front of his body.
struct DoublingCoin: Identifiable {
    let id = UUID()
    let diameter: CGFloat
    var position: CGPoint
    /// Nil while it is sitting at his feet; set the moment it leaves with a shell.
    var start: CGPoint?
    var firstControl: CGPoint?
    var secondControl: CGPoint?
    var target: CGPoint?
    var age: Double = 0

    var isFlying: Bool { start != nil }

    /// True once it has risen clear of his silhouette and can sit with the
    /// shells in front of the scene again.
    func isClear(ofKingAt kingY: CGFloat, kingSize: CGFloat) -> Bool {
        position.y < kingY - kingSize * 0.52
    }
}

/// One grain of the sand kicked up by an emerging, smashed or burrowing crab —
/// or thrown by the King.
struct SandGrain: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGPoint
    let radius: CGFloat
    /// 0 → pale sand, 1 → the darker tone underneath.
    let tone: Double
    let lifetime: Double
    /// Sand knocked loose is thrown up and falls straight back; sand thrown at
    /// something has to carry, so it drops far more slowly and keeps its aim.
    /// The defaults are the disturbed-floor behaviour every puff has always had.
    var gravity: CGFloat = 420
    /// The share of its sideways speed a grain keeps per second.
    var drag: CGFloat = 0.22
    var age: Double = 0
}

/// A speck of drifting plankton. Decoration only.
struct ReefMote: Identifiable {
    let id = UUID()
    var position: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    let sway: CGFloat
    let period: Double
    let phase: Double
    let baseX: CGFloat
    var age: Double = 0
}

/// A small, purely decorative air pocket rising off the sea floor.
struct ReefAmbientBubble: Identifiable {
    let id = UUID()
    let baseX: CGFloat
    var position: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    let phase: Double
    var age: Double = 0
    var popAge: Double?
}

/// One decorative shell or bubble in the completed-level finale.
struct CelebrationSpeck: Identifiable {
    enum Kind { case bubble, shell }

    let id = UUID()
    var position: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    let phase: Double
    let kind: Kind
    var age: Double = 0
}

/// One swing of one claw: scoop or overhead wind-up, the throw, and the sand
/// it lets go of. Forward targets (lower on screen) scoop; backward targets
/// cock the claw high.
struct ClawThrow {
    /// What is being thrown at, in arena coordinates.
    let target: CGPoint
    var age: Double = 0
    /// Whether the sand has already left the claw this swing.
    var hasThrown = false

    /// 0 at the wind-up, 1 once the arm is back at rest.
    var progress: Double { min(1, age / ArenaConfig.clawThrowDuration) }
}

/// Where the King is and what he is doing. The whole game is played around one
/// spot — his `anchor` — which he leaves only to walk on at the start of a
/// board and to run off at the end of one.
struct KingState {
    /// The spot the arena is built around. Crabs walk at it, shells leave from
    /// it, and it moves only when the screen itself is re-laid out.
    var anchor: CGPoint = .zero
    /// Where he is actually drawn. Equal to `anchor` except while he is
    /// arriving or leaving.
    var position: CGPoint = .zero
    /// Time since the current sweep started, or nil while he is simply waiting.
    var sweepAge: Double?
    /// Which way the sweep began, so two sweeps in a row are not identical.
    var sweepDirection: Double = 1
    /// Time since a life was handed back, which drives the heal glow.
    var healAge: Double?
    /// Time since he came on from the left, or nil once he has settled.
    var entranceAge: Double?
    /// Time since the board was won: the hop, and then the run off to the right.
    var farewellAge: Double?
    /// Time since the streak landed, or nil when he is not celebrating one.
    var streakAge: Double?
    /// He has run off and stays off. The result card comes up while he is still
    /// leaving, so without this he would be put back on his anchor underneath it
    /// and read as walking off and then reappearing.
    var hasLeft = false
    /// Set while the finale is playing.
    var isCheering = false
    /// The swing each claw is in the middle of, if any. They are independent,
    /// so a crab taken on the left never interrupts a throw on the right.
    var leftClaw: ClawThrow?
    var rightClaw: ClawThrow?
    /// How hard the legs are working: 0 standing still, 1 at a full run.
    var effort: Double = 0
    /// Stride phase. It only ever advances, so a walk that speeds up or slows
    /// down never jumps mid-step.
    var stride: Double = 0
    /// How far off the sand he is, in points. Only the finale's hop uses it.
    var lift: CGFloat = 0
}

// MARK: - Engine

/// Drives the crabs, the King and the sea floor. It owns exactly one timer,
/// holds no rules about scoring, and reports everything that happens through
/// its callbacks — each of which returns whether the session accepted it.
@MainActor
final class KingCrabArena: ObservableObject {
    // These values all advance together in `tick()`. Publishing each array
    // element mutation caused many redundant SwiftUI invalidations per frame.
    // `clock` is the single render signal for the completed simulation frame.
    private(set) var crabs: [AnswerCrab] = []
    private(set) var carriers: [CarrierCrab] = []
    private(set) var shells: [ShellReward] = []
    /// The doubling coin under the King, or on its way up with a scored shell.
    private(set) var doublingCoin: DoublingCoin?
    private(set) var grains: [SandGrain] = []
    private(set) var motes: [ReefMote] = []
    private(set) var ambientBubbles: [ReefAmbientBubble] = []
    private(set) var celebration: [CelebrationSpeck] = []
    private(set) var king = KingState()
    private(set) var hasBonusAura = false
    /// Set once the power is spent: the resting coin waits for the next shell
    /// and then leaves with it.
    private var launchDoublingCoinWithShell = false

    /// True from the frame the King actually starts celebrating. Everything
    /// drawn over the arena hangs on this rather than on the session being
    /// over: the crab that won the board is still walking its shell in while
    /// the session already knows the sum was answered.
    @Published private(set) var isCelebrating = false

    /// Seconds of running time. It stops when the game does, so nothing moves
    /// behind a pause. Everything the player reads timing from follows this at
    /// the display's full cadence (60 or 120 Hz).
    @Published private(set) var clock: Double = 0
    /// The same clock, held still between sway steps. The sea floor is a large
    /// pile of gradient, stroke and shadow nodes; rebuilding all of them 60
    /// times a second leaves no frame budget for the moments that actually
    /// matter. Because the scenery views are `Equatable` on their clock, an
    /// unchanged value here skips that entire rebuild.
    private(set) var swayClock: Double = 0
    /// Coarser still, for the drifting sun shafts and their full-screen blur.
    private(set) var driftClock: Double = 0

    // MARK: Callbacks

    /// The crab carrying the right answer reached the King. Returns whether the
    /// session took it, so an arrival it ignores leaves the arena as it was.
    var onGuardedArrival: ((UUID) -> Bool)?
    /// A wrong answer reached the King.
    var onBreach: (() -> Void)?
    /// The player smashed the crab carrying the right answer. Returns whether
    /// the session accepted it; only then is the attempt actually over.
    var onSmashedGuard: (() -> Bool)?
    /// Any crab the player smashed, right or wrong — for the sound and the
    /// small kick of feedback that goes with it.
    var onSmash: ((Bool) -> Void)?
    /// The King's blow, whether or not it scored.
    var onSweep: (() -> Void)?
    var onShellArrived: (() -> Void)?
    var onBonusCrabCaught: (() -> Void)?
    /// The comeback crab reached the King. Returns whether a life was restored.
    var onLifeCrabArrived: (() -> Bool)?
    var onTutorialEvent: ((CrabTutorialEvent) -> Void)?

    // MARK: Geometry, set from the view's layout

    private var size: CGSize = .zero
    /// The rectangle the crabs actually walk in: below the sum, above the very
    /// bottom edge.
    private var arena: CGRect = .zero
    private var isPad = false
    private var crabSize: CGFloat = 56
    private var kingSize: CGFloat = 124
    private var scoreTarget: CGPoint?
    private var clawTip = ArenaConfig.clawTip

    // MARK: Round state

    private var round: GameRound?
    private var isLive = false
    /// The colour the next wave is laid out in. See `setGolden`.
    private var isGolden = false
    private var speedMultiplier = 1.0
    /// Counts down while several arrivals are gathered into one sweep.
    private var sweepGather: Double?
    /// Set when the player smashed the guarded answer: the wave is over and a
    /// fresh one starts as soon as the session accepts input again.
    private var pendingWaveRestart = false
    /// Counts down while an empty arena waits for its next wave.
    private var refillDelay: Double?
    /// Guards the tap handler against a second touch landing in the same frame
    /// as the one that ended the attempt.
    private var isResolvingWave = false
    /// Counts down from a hand-over to the moment the King has the shell and
    /// sends it up to the score.
    private var shellHandOver: Double?

    /// Crabs waiting to be thrown at, one queue per claw. A player who takes
    /// two crabs on the same side in the same second gets two full throws, one
    /// after the other; the arm is never yanked back mid-swing.
    private var pendingLeftThrows: [CGPoint] = []
    private var pendingRightThrows: [CGPoint] = []
    /// Counts down to the next puff of sand under him while he is walking.
    private var footPuff: Double = 0

    // At the start, one to three hidden question numbers are picked across the
    // whole board. This makes a 2x crab possible near the beginning or near the
    // end without tying it to how many seconds the player needs.
    private var maximumRounds = 1
    private var bonusTriggerRounds: [Int] = []
    private var nextBonusTrigger = 0
    private var pendingBonusDelays: [Double] = []

#if DEBUG
    /// Trailer-only: answer text → entry-point index (0 top-left, 1 top-right,
    /// 2 bottom-left, 3 bottom-right). Nil uses the ordinary shuffle.
    var promoEntryAssignment: [String: Int]?
    /// When true, a lone correct crab still runs in, but the session is not
    /// told until it actually reaches the King. The trailer needs that arrival
    /// on screen before the next beat (character swap, streak banner) starts.
    var promoDefersRushScoring = false
    /// When true, the hidden 2× plan is not rolled and crabs only appear when
    /// the director asks for one.
    var promoSuppressesBonusPlan = false
    /// When true, an empty board does not send the same answers around again.
    var promoSuppressesRefill = false
#endif

    // The comeback crab is scheduled by the rules engine once it is earned.
    // This scene only owns the short randomized arrival delay.
    private var isLifeCrabAvailable = false
    private var lifeCrabDelay: Double?

    // The walkthrough. While a plan is active it decides what may be in the
    // arena; the crabs walk, are smashed and arrive exactly as they otherwise
    // would. See `Tutorial.swift`.
    private var tutorialPlan = CrabTutorialPlan()
    private var tutorialCrabDelay: Double?

    // Entrance and finale.
    private var entranceCompletion: (() -> Void)?
    private var entranceDidOpenRound = false
    private var completionElapsed: Double?
    private var completionCallback: (() -> Void)?
    private var completionSpeckCountdown = 0.0
    private var reducesCompletionMotion = false
    /// The finale, held back while the crab that won the board is still walking
    /// its shell up to the King. See `beginLevelCompletion`.
    private var pendingCompletion: (reduceMotion: Bool,
                                    started: () -> Void,
                                    callback: () -> Void)?
    private var pendingCompletionAge = 0.0
    private var ambientBubbleCountdown = Double.random(in: ArenaConfig.ambientBubbleGap)

#if canImport(UIKit)
    /// A display-linked driver avoids timer firings landing halfway through a
    /// screen refresh, which is visible as uneven motion on slower devices.
    private final class DisplayLinkTarget: NSObject {
        weak var owner: KingCrabArena?

        init(owner: KingCrabArena) {
            self.owner = owner
        }

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
    private var lastFrameTargetTimestamp: CFTimeInterval?
#else
    private var timer: Timer?
#endif

    deinit {
#if canImport(UIKit)
        displayLink?.invalidate()
#else
        timer?.invalidate()
#endif
    }

    // MARK: Layout

    /// Called from the view's geometry. Re-running it on a size change keeps the
    /// King and the crabs inside the new bounds.
    func layout(size: CGSize, arena: CGRect, isPad: Bool) {
        guard size.width > 0, size.height > 0, arena.height > 0 else { return }
        let isFirst = self.size == .zero
        self.size = size
        self.arena = arena
        self.isPad = isPad
        self.crabSize = ArenaConfig.crabSize(isPad: isPad)
        self.kingSize = ArenaConfig.kingSize(isPad: isPad)

        let previousKing = king.anchor
        king.anchor = CGPoint(x: arena.midX,
                              y: arena.minY + arena.height * ArenaConfig.kingAnchorShare)
        placeKing(0)
        if !isFirst {
            // A rotation, or the walkthrough's message card claiming the top of
            // the arena, moves the King. Everything already walking toward him
            // moves with him, so no crab is left aiming at where he used to be.
            let delta = CGPoint(x: king.anchor.x - previousKing.x,
                                y: king.anchor.y - previousKing.y)
            if delta.x != 0 || delta.y != 0 {
                for index in crabs.indices { crabs[index].shift(by: delta) }
                for index in carriers.indices { carriers[index].shift(by: delta) }
                if var coin = doublingCoin, !coin.isFlying {
                    coin.position = restingDoublingCoinPoint()
                    doublingCoin = coin
                }
            }
        }
        if isFirst {
            // Small upper bounds, reserving capacity only; they do not create
            // or draw a single additional object.
            crabs.reserveCapacity(GameConfig.answerBubbleCount)
            grains.reserveCapacity(ArenaPerformanceBudget.maximumLiveGrains)
            ambientBubbles.reserveCapacity(ArenaConfig.maximumAmbientBubbles)
            celebration.reserveCapacity(ArenaPerformanceBudget.celebrationSpeckCap)
        }
        seedMotes()
    }

    private func seedMotes() {
        motes = (0..<ArenaConfig.moteCount).map { _ in
            let x = CGFloat.random(in: 0...size.width)
            return ReefMote(position: CGPoint(x: x, y: CGFloat.random(in: 0...size.height)),
                            radius: CGFloat.random(in: ArenaConfig.moteRadius),
                            speed: CGFloat.random(in: ArenaConfig.moteSpeed),
                            sway: CGFloat.random(in: 4...14),
                            period: Double.random(in: 3...7),
                            phase: Double.random(in: 0..<(2 * .pi)),
                            baseX: x)
        }
    }

    // MARK: Session control

    /// Supplies the board length before its first question is loaded. The actual
    /// hidden trigger questions are chosen when that question arrives, which
    /// also makes a resumed board plan only over its remaining rounds.
    func configureBonusCrab(maximumRounds: Int) {
        self.maximumRounds = max(1, maximumRounds)
    }

    /// Installs a round. Called whenever the sum changes — including right
    /// after the guarded answer was smashed directly, which still moves on to
    /// a fresh sum rather than repeating the one just given away.
    func load(round: GameRound?) {
        // The streak flipping does not install a round, so the same sum can
        // arrive here again purely because the gold flag moved. Nothing about
        // the wave on the sand changes then — repainting or respawning it is
        // exactly what a crab is not allowed to do mid-walk.
        guard round?.id != self.round?.id else { return }
        let previousRoundNumber = self.round?.number
        self.round = round
        guard let round else {
            crabs.removeAll()
            return
        }

        // Playing again reuses this SwiftUI playfield and therefore this engine.
        // A fresh round one starts a genuinely fresh hidden plan.
        if round.number == 1, previousRoundNumber != nil {
            shells.removeAll()
            carriers.removeAll()
            clearDoublingCoin()
            bonusTriggerRounds.removeAll()
            nextBonusTrigger = 0
            pendingBonusDelays.removeAll()
            isLifeCrabAvailable = false
            lifeCrabDelay = nil
        }
        if bonusTriggerRounds.isEmpty {
#if DEBUG
            if !promoSuppressesBonusPlan {
                makeBonusCrabPlan(startingAt: round.number)
            }
#else
            makeBonusCrabPlan(startingAt: round.number)
#endif
        }
        while nextBonusTrigger < bonusTriggerRounds.count,
              round.number >= bonusTriggerRounds[nextBonusTrigger] {
            pendingBonusDelays.append(Double.random(in: ArenaConfig.bonusCrabQuestionDelay))
            nextBonusTrigger += 1
        }
        beginWave()
    }

    private func makeBonusCrabPlan(startingAt firstRound: Int) {
        let requestedCount = Int.random(in: GameConfig.bonusFishCount)

        // `maximumRounds` is only the one-shell-per-answer ceiling. A perfect
        // streak pays two shells, and every caught 2x crab can make one of those
        // answers worth four. Plan against that shortest possible run; a crab
        // may then be late, but never on a question the level cannot reach.
        let streakStart = min(GameConfig.streakThreshold, maximumRounds)
        let shellsAfterStreakStart = max(0,
            maximumRounds - streakStart - requestedCount * GameConfig.bonusFishMultiplier
        )
        let shortestPossibleRun = streakStart
            + Int(ceil(Double(shellsAfterStreakStart) / Double(GameConfig.streakMultiplier)))
        let lastRound = max(firstRound, min(maximumRounds, shortestPossibleRun))
        let availableRounds = Array(firstRound...lastRound)
        let count = min(requestedCount, availableRounds.count)
        bonusTriggerRounds = Array(availableRounds.shuffled().prefix(count)).sorted()
        nextBonusTrigger = 0
    }

    /// Which colour the *next* wave comes up in. Crabs already on the sand keep
    /// the colour they were laid out in, so a streak that starts or breaks
    /// under them never repaints a crab the player is in the middle of reading.
    func setGolden(_ golden: Bool) {
        isGolden = golden
    }

    /// Play is live only while the session is accepting an answer.
    func setLive(_ live: Bool) {
        guard isLive != live else { return }
        isLive = live
        // The wave the player lost is replaced the moment the session is ready
        // for a new attempt, not while its feedback is still playing.
        if live { restartWaveIfReady() }
    }

    func setBonusAura(_ active: Bool) {
        guard hasBonusAura != active else { return }
        hasBonusAura = active
        if active {
            placeRestingDoublingCoin()
        } else if let coin = doublingCoin, !coin.isFlying {
            // Spent on an answer: leave it under him until that shell goes up.
            launchDoublingCoinWithShell = true
        } else if doublingCoin == nil {
            launchDoublingCoinWithShell = false
        }
        // This can change while the simulation is paused, so it cannot wait for
        // the next clock update to be drawn.
        objectWillChange.send()
    }

    func setLifeCrabAvailable(_ available: Bool) {
        if available, !isLifeCrabAvailable, !carriers.contains(where: { $0.kind == .life }) {
            lifeCrabDelay = Double.random(in: ArenaConfig.lifeCrabDelay)
        } else if !available {
            lifeCrabDelay = nil
        }
        isLifeCrabAvailable = available
    }

    func setSpeedMultiplier(_ multiplier: Double) {
        speedMultiplier = max(1, multiplier)
    }

    func setScoreTarget(_ target: CGPoint?) {
        scoreTarget = target
    }

    /// Where this character's pincers actually are. A rigged character reaches
    /// much further out of his own square than a flat portrait does, and the
    /// thrown sand has to leave from the claw the player saw swing.
    func setClawTip(_ offset: CGSize) {
        clawTip = offset
    }

    /// Starts and stops the simulation itself. Everything freezes when the game
    /// is paused, covered or left.
    func setRunning(_ running: Bool) {
        if running {
#if canImport(UIKit)
            guard displayLink == nil else { return }
            lastFrameTargetTimestamp = nil
            let link = CADisplayLink(target: displayLinkTarget,
                                     selector: #selector(DisplayLinkTarget.advance(_:)))
            // Lock to exactly 60 Hz — never ProMotion 120 (too much SwiftUI
            // work) and never a floating minimum that lets the system settle
            // on a choppy 45.
            let fps = Float(ArenaPerformanceBudget.preferredFramesPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: fps,
                maximum: fps,
                preferred: fps
            )
            link.add(to: .main, forMode: .common)
            displayLink = link
#else
            guard timer == nil else { return }
            let timer = Timer(timeInterval: ArenaConfig.tick, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick(dt: ArenaConfig.tick) }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
#endif
        } else {
#if canImport(UIKit)
            displayLink?.invalidate()
            displayLink = nil
            lastFrameTargetTimestamp = nil
#else
            timer?.invalidate()
            timer = nil
#endif
        }
    }

    /// Tears the scene down for good: no timer, no crabs, nothing pending.
    func stop() {
        setRunning(false)
        crabs.removeAll()
        carriers.removeAll()
        shells.removeAll()
        clearDoublingCoin()
        grains.removeAll()
        celebration.removeAll()
        round = nil
        sweepGather = nil
        shellHandOver = nil
        pendingLeftThrows.removeAll()
        pendingRightThrows.removeAll()
        king.leftClaw = nil
        king.rightClaw = nil
        king.farewellAge = nil
        king.hasLeft = false
        entranceCompletion = nil
        completionElapsed = nil
        completionCallback = nil
        pendingCompletion = nil
        isCelebrating = false
        tutorialPlan = CrabTutorialPlan()
        tutorialCrabDelay = nil
        onGuardedArrival = nil
        onBreach = nil
        onSmashedGuard = nil
        onSmash = nil
        onSweep = nil
        onShellArrived = nil
        onBonusCrabCaught = nil
        onLifeCrabArrived = nil
        onTutorialEvent = nil
    }

    /// The King scuttles on from the left before the first round and takes up
    /// his spot in the middle. Gameplay is deliberately started by the
    /// completion, not alongside it — and that completion fires part-way
    /// through the walk, so the first crabs are already on their way while he
    /// is still crossing the floor.
    func beginKingEntrance(completion: @escaping () -> Void) {
        guard size.width > 0, arena.height > 0 else {
            completion()
            return
        }
        entranceCompletion = completion
        entranceDidOpenRound = false
        king.farewellAge = nil
        king.hasLeft = false
        king.entranceAge = 0
        footPuff = 0
        placeKing(0)
    }

    /// The streak has just landed. The King steps out to one side, back across
    /// to the other and home again, and takes his claws down and then up beside
    /// his crown — so the player is told something has changed by the animal
    /// rather than only by the colour.
    ///
    /// He never leaves his anchor: crabs keep walking at the same spot, and a
    /// wave that arrives mid-celebration is answered from it exactly as always.
    func beginStreakCelebration() {
        // Not over the top of the two journeys that move him off his anchor for
        // real, and not while the board is being wrapped up.
        guard completionElapsed == nil,
              king.entranceAge == nil,
              king.farewellAge == nil,
              !king.hasLeft else { return }
        king.streakAge = 0
        // So the first sand comes up with the first stride rather than
        // whenever the walk-on's timer happened to leave the countdown.
        footPuff = 0
    }

    /// Takes over after the final answer: the King hops for the board he has
    /// just won, and runs off to the right while the shells stream up.
    ///
    /// The session counts the winning answer the moment the last crab breaks
    /// into its run, which is a good half-second before that crab reaches the
    /// King. Celebrating there cut the run off mid-stride and ended the board on
    /// a crab vanishing. So the finale waits: the crab walks in, bows, puts its
    /// shell down — and only then does the King jump for it.
    /// `started` fires at the moment the King actually begins to celebrate,
    /// which is what the screen around the arena waits for: the sum and the HUD
    /// belong to a round that is still finishing while the last crab walks.
    func beginLevelCompletion(reduceMotion: Bool,
                              started: @escaping () -> Void,
                              completion: @escaping () -> Void) {
        guard completionElapsed == nil, pendingCompletion == nil else { return }
        if awaitsFinalDelivery {
            // Nothing more can be answered, so the arena is closed to touches
            // for the walk — but the crabs keep moving, and the sweep that
            // takes the shell still runs.
            isLive = false
            pendingCompletion = (reduceMotion, started, completion)
            pendingCompletionAge = 0
            return
        }
        startLevelCompletion(reduceMotion: reduceMotion,
                             started: started,
                             completion: completion)
    }

    /// True while the crab that won the board still has its shell in its claws:
    /// walking in, standing at the ring, or in the middle of handing it over.
    private var awaitsFinalDelivery: Bool {
        crabs.contains { crab in
            guard crab.isCorrect, !crab.hasDelivered else { return false }
            switch crab.phase {
            case .waiting, .walking, .arrived:
                return true
            case .delivering:
                // Up to the moment the shell is actually let go of. The dig it
                // makes afterwards is its own business and may finish, or not,
                // under the celebration.
                return crab.phaseAge < ArenaConfig.deliverDuration
                    * ArenaConfig.deliverGiveShare
            case .hit, .smashed, .swept, .burrowing:
                return false
            }
        }
    }

    /// Lets the held-back finale go once the shell is in the King's claws — or
    /// once the wait has gone on long enough that something must have gone
    /// wrong, which must never leave a player looking at a finished board.
    private func releasePendingCompletionIfDue(_ dt: Double) {
        guard let pending = pendingCompletion else { return }
        pendingCompletionAge += dt
        guard !awaitsFinalDelivery
                || pendingCompletionAge >= ArenaConfig.finalDeliveryWait else { return }
        pendingCompletion = nil
        startLevelCompletion(reduceMotion: pending.reduceMotion,
                             started: pending.started,
                             completion: pending.callback)
    }

    private func startLevelCompletion(reduceMotion: Bool,
                                      started: () -> Void,
                                      completion: @escaping () -> Void) {
        isLive = false
        crabs.removeAll()
        carriers.removeAll()
        celebration.removeAll()
        shellHandOver = nil
        // A spent coin should already be flying with the last shell; anything
        // still resting here never got a shell and must not linger under him.
        if launchDoublingCoinWithShell {
            launchDoublingCoinFlight(with: nil)
        } else if doublingCoin?.isFlying != true {
            clearDoublingCoin()
        }
        completionElapsed = 0
        completionCallback = completion
        completionSpeckCountdown = 0
        reducesCompletionMotion = reduceMotion
        // Nothing is left to answer, so no throw is left to finish either.
        king.leftClaw = nil
        king.rightClaw = nil
        pendingLeftThrows.removeAll()
        pendingRightThrows.removeAll()
        king.isCheering = !reduceMotion
        king.entranceAge = nil
        king.farewellAge = reduceMotion ? nil : 0
        king.hasLeft = false
        king.sweepAge = nil
        if reduceMotion { placeKing(0) }
        isCelebrating = true
        started()
    }

    /// The finale is over as far as the session is concerned. He is deliberately
    /// left where he ran to: only a fresh entrance puts him back on the floor.
    func endLevelCompletion() {
        completionElapsed = nil
        completionCallback = nil
        pendingCompletion = nil
        isCelebrating = false
        celebration.removeAll()
        king.isCheering = false
        king.farewellAge = nil
        placeKing(0)
    }

    // MARK: The walkthrough

    /// Takes the walkthrough's marching orders for the step now being taught. A
    /// step that changes what the arena holds clears it first, so the player
    /// always reads the new message against the crabs that message describes.
    func applyTutorial(_ plan: CrabTutorialPlan) {
        let previous = tutorialPlan
        tutorialPlan = plan
        guard plan != previous else { return }

        guard plan.isActive else {
            tutorialCrabDelay = nil
            return
        }

        if plan.suppressesAnswers {
            burrowLiveCrabs()
        } else if plan.answers != previous.answers || previous.suppressesAnswers {
            burrowLiveCrabs()
            pendingWaveRestart = true
            if isLive { restartWaveIfReady() }
        }

        // A helper crab that has already given up its reward is on its way out
        // and may finish crossing; one still carrying a reward belongs to the
        // step that asked for it and leaves with it.
        if !plan.wantsLifeCrab {
            carriers.removeAll { $0.kind == .life && $0.isCarryingReward }
        }
        if !plan.wantsBonusCrab {
            carriers.removeAll { $0.kind == .bonus && $0.isCarryingReward }
        }
        if plan.wantsLifeCrab != previous.wantsLifeCrab
            || plan.wantsBonusCrab != previous.wantsBonusCrab {
            tutorialCrabDelay = (plan.wantsLifeCrab || plan.wantsBonusCrab)
                ? ArenaConfig.tutorialCrabArrival
                : nil
        }
    }

    // MARK: Taps

    /// The player touched the glass. Exactly one crab can be taken by one touch,
    /// and only ever the nearest one inside its own reach.
    func tap(at point: CGPoint) {
        // The first crabs set off while the King is still walking on, so a tap
        // is live from the moment the round opens rather than from the moment
        // he plants himself.
        guard completionElapsed == nil,
              king.entranceAge == nil || entranceDidOpenRound else { return }

        // A helper crab stays catchable during answer feedback, exactly as the
        // passing power-up always has been. Tapping one does not take what it
        // is carrying: it sends the crab in to the King with it, and the reward
        // lands when the crab does.
        if let index = carriers.firstIndex(where: { carrier in
            carrier.isTappable
                && within(point, of: helperCentre(of: carrier),
                          radius: ArenaConfig.tapRadius(isPad: isPad))
        }) {
            // A second 2x is worth nothing while one is already in hand, so
            // that crab keeps walking rather than making a trip for nothing.
            guard carriers[index].kind != .bonus || !hasBonusAura else { return }
            carriers[index].fetch(to: helperTarget(for: carriers[index]),
                                  speed: scaledHelperFetchSpeed)
            burst(at: carriers[index].position, strength: 0.45)
            return
        }

        guard isLive, !isResolvingWave else { return }

        let reach = ArenaConfig.tapRadius(isPad: isPad)
        let hit = crabs.indices
            .filter { crabs[$0].isTappable && within(point, of: hitCentre(of: crabs[$0]), radius: reach) }
            .min { distance(point, hitCentre(of: crabs[$0])) < distance(point, hitCentre(of: crabs[$1])) }
        guard let index = hit else { return }

        if crabs[index].isCorrect {
            // The session has the final say. If it does not take it — feedback
            // still playing, round already resolved — nothing happens at all.
            guard onSmashedGuard?() == true else { return }
            smash(index: index)
            // Every other crab gives up and digs itself back in, so the arena
            // is clear for the next attempt without a long wait. The next sum
            // is on its way — `load(round:)` starts the new wave once it
            // lands, exactly as it does after a correct delivery or a breach.
            burrowLiveCrabs()
        } else {
            smash(index: index)
            onSmash?(false)
            onTutorialEvent?(.smashedWrongCrab)
            if !crabs.contains(where: { $0.isLive }) {
                onTutorialEvent?(.clearedWave)
            }
            // With that one gone the right answer may be alone out there.
            rushLoneCorrectCrab()
        }
    }

#if DEBUG
    /// Trailer director: smash the walking crab carrying this answer, using
    /// the ordinary tap path so the throw, sand and hit are production.
    @discardableResult
    func promoTapAnswer(_ text: String) -> Bool {
        guard let crab = crabs.first(where: { $0.text == text && $0.isTappable }) else {
            return false
        }
        tap(at: hitCentre(of: crab))
        return true
    }

    /// Trailer director: send the crossing 2× crab in to the King.
    @discardableResult
    func promoTapBonusCarrier() -> Bool {
        guard let carrier = carriers.first(where: { $0.kind == .bonus && $0.isTappable }) else {
            return false
        }
        tap(at: helperCentre(of: carrier))
        return true
    }

    /// Trailer director: walk a 2× crab along the near lane using the same
    /// helper motion as a live game, with a duration chosen so it stays on
    /// screen through the later beats.
    func promoSpawnBonusCrab(duration: Double, fromLeading: Bool) {
        guard arena.height > 0 else { return }
        pendingBonusDelays.removeAll()
        let size = ArenaConfig.helperCrabSize(isPad: isPad, kind: .bonus)
        let direction: CGFloat = fromLeading ? 1 : -1
        let lane = arena.maxY - ArenaConfig.helperLane(isPad: isPad)
        let lead = size + 36
        let start = CGPoint(x: direction > 0 ? -lead : arena.maxX + lead, y: lane)
        let target = CGPoint(x: direction > 0 ? arena.maxX + lead : -lead, y: lane)
        carriers.removeAll { $0.kind == .bonus && $0.isCarryingReward }
        carriers.append(CarrierCrab(
            kind: .bonus,
            size: size,
            start: start,
            target: target,
            position: start,
            duration: max(2.5, duration),
            waddleRate: 4.1,
            strideFactor: 1.0,
            gaitOffset: 0.6,
            facing: direction
        ))
        objectWillChange.send()
    }
#endif

    /// The shell is carried well above the body, so the middle of what a child
    /// actually aims at sits between the two — a radius measured from the feet
    /// would miss the answer they were pointing at.
    private func hitCentre(of crab: AnswerCrab) -> CGPoint {
        CGPoint(x: crab.position.x, y: crab.position.y - crabSize * 0.55)
    }

    /// The same idea for a helper crab: what a child aims at is the coin or the
    /// heart held over its head, not the feet the position is measured at.
    private func helperCentre(of carrier: CarrierCrab) -> CGPoint {
        CGPoint(x: carrier.position.x, y: carrier.position.y - carrier.size * 0.22)
    }

    private func within(_ point: CGPoint, of centre: CGPoint, radius: CGFloat) -> Bool {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        return dx * dx + dy * dy <= radius * radius
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func smash(index: Int) {
        var crab = crabs[index]
        // A tap only marks the crab: it keeps covering ground until the sand
        // lands in `moveCrabs`, and only then starts flying.
        crab.phase = .hit
        crab.phaseAge = 0
        // Aim where the crab will be when the sand arrives, not where the
        // finger landed — otherwise the throw trails a walking target.
        var aim = crab
        advanceWalking(&aim, dt: ArenaConfig.sandImpactDelay, emitEffects: false)
        requestClawThrow(at: hitCentre(of: aim))
        // Fling is computed at impact from the live position, so a crab that
        // kept walking still flies away from the King rather than from the tap.
        crab.spin = Double.random(in: -9...9)
        crabs[index] = crab
        if crab.isCorrect { onSmash?(true) }
    }

    /// Every crab still walking digs itself back into the sand. Short and
    /// unmistakable: the attempt is over, and the next one is seconds away.
    private func burrowLiveCrabs() {
        for index in crabs.indices where crabs[index].isLive {
            let wasWalking = crabs[index].phase == .walking
            crabs[index].phase = .burrowing
            crabs[index].phaseAge = 0
            crabs[index].isRushing = false
            // The dig throws sand from the first frame; `moveCrabs` keeps it
            // coming for as long as the crab is still working its way down. A
            // crab that never made it on screen digs in out of sight, and must
            // not throw sand across the edge of the arena to announce it.
            crabs[index].puffCountdown = ArenaConfig.burrowPuffInterval
            if wasWalking { burst(at: crabs[index].position, strength: 0.7) }
        }
    }

    /// Every wrong answer has been taken and the right one is the only crab
    /// left walking, so there is nothing left to choose between: it drops the
    /// caution, breaks into a run and carries its shell to the King itself.
    ///
    /// The sum goes with it. Nothing about the round is undecided any more, so
    /// the session is told the answer here rather than when the crab arrives —
    /// the next sum and its own wave come on while this one is still running,
    /// which is what keeps a cleared wave from turning into a wait. The crab
    /// itself plays out in full: it is no longer an answer, only the finish of
    /// the last one.
    ///
    /// The walkthrough plays by exactly the same rule: a child who has just
    /// cleared the wrong answers should see the reward for it there too, and a
    /// lone crab still picking its way in is the slowest moment of the lesson.
    private func rushLoneCorrectCrab() {
        let live = crabs.indices.filter { crabs[$0].isLive }
        guard live.count == 1, let index = live.first,
              crabs[index].isCorrect, !crabs[index].isRushing
        else { return }

        crabs[index].isRushing = true
        crabs[index].rushAge = 0
        crabs[index].puffCountdown = ArenaConfig.rushPuffInterval
        // If the session cannot take the answer yet — feedback still playing,
        // the round already settled — the crab simply runs it up to the King
        // and it is counted on arrival, exactly as it always was.
        let defersScoring: Bool
#if DEBUG
        defersScoring = promoDefersRushScoring
#else
        defersScoring = false
#endif
        if !defersScoring {
            crabs[index].hasAnswered = onGuardedArrival?(crabs[index].optionID) == true
        }

        // One still waiting its turn off screen has nothing left to wait for.
        if crabs[index].phase == .waiting {
            crabs[index].startDelay = 0
            crabs[index].phase = .walking
            crabs[index].phaseAge = 0
        } else {
            burst(at: crabs[index].position, strength: 0.5)
        }
    }

    // MARK: Waves

    /// Walks one crab in from each side of the screen: the right answer and
    /// three wrong ones, in a fresh arrangement every time, so nothing about
    /// where the answer comes from can be learned.
    private func beginWave() {
        // Anything already thrown or digging itself in keeps its animation: the
        // new wave arrives over the top of the old one leaving.
        crabs.removeAll { $0.isLive }
        // A crab still standing at the ring keeps its gather: it is the tail of
        // the last sum, waiting to be answered, and taking the timer away from
        // it would strand it there.
        if !crabs.contains(where: { $0.phase == .arrived }) { sweepGather = nil }
        isResolvingWave = false
        pendingWaveRestart = false
        guard let round, arena.height > 0, !tutorialPlan.suppressesAnswers else { return }

        let options = waveOptions(from: round)
        guard !options.isEmpty else { return }
        let points = entryPoints
        let pairs: [(AnswerOption, CGPoint)]
#if DEBUG
        if let assignment = promoEntryAssignment {
            var used = Set<Int>()
            var assigned: [(AnswerOption, CGPoint)] = []
            for option in options {
                if let index = assignment[option.text],
                   points.indices.contains(index),
                   !used.contains(index) {
                    assigned.append((option, points[index]))
                    used.insert(index)
                }
            }
            let leftoverEntries = points.enumerated()
                .filter { !used.contains($0.offset) }
                .map(\.element)
            let leftoverOptions = options.filter { option in
                !assigned.contains(where: { $0.0.id == option.id })
            }
            for (option, entry) in zip(leftoverOptions, leftoverEntries) {
                assigned.append((option, entry))
            }
            pairs = assigned
        } else {
            pairs = Array(zip(options, points.shuffled().prefix(options.count)))
        }
#else
        pairs = Array(zip(options, points.shuffled().prefix(options.count)))
#endif
        let ring = kingSize * ArenaConfig.arrivalRingFactor

        // One shared entry split for the whole wave. Per-lane readable points
        // differ slightly left-to-right; using the furthest keeps every shell
        // readable in time and, more importantly, keeps every crab on the same
        // arrival clock so the King answers them in one sweep.
        var sharedEntryProgress = 0.0
        var starts: [CGPoint] = []
        var targets: [CGPoint] = []
        for pair in pairs {
            let entry = pair.1
            let angle = atan2(Double(entry.y - king.anchor.y),
                              Double(entry.x - king.anchor.x))
            let target = CGPoint(x: king.anchor.x + ring * CGFloat(cos(angle)),
                                 y: king.anchor.y + ring * CGFloat(sin(angle)))
            let start = offscreenStart(for: entry)
            let span = target.x - start.x
            let entryProgress = abs(span) < 1
                ? 0
                : min(0.6, max(0, Double((readablePoint(for: entry) - start.x) / span)))
            sharedEntryProgress = max(sharedEntryProgress, entryProgress)
            starts.append(start)
            targets.append(target)
        }

        for (index, pair) in pairs.enumerated() {
            let option = pair.0
            let start = starts[index]
            let target = targets[index]
            crabs.append(AnswerCrab(
                optionID: option.id,
                text: option.text,
                isCorrect: option.isCorrect,
                isGolden: isGolden,
                start: start,
                target: target,
                position: start,
                entryProgress: sharedEntryProgress,
                // Every crab in a wave shares the same duration and start time
                // so all four reach the King's ring together — the King can
                // then answer the whole wave at once rather than crabs
                // trickling in one at a time.
                duration: GameConfig.crabWalkDuration,
                startDelay: 0,
                waddleAmplitude: crabSize * CGFloat.random(in: 0.05...0.10),
                // One sway per pair of steps: the body leans onto the legs that
                // are carrying it.
                waddleRate: Double.random(in: 3.4...4.6),
                strideFactor: CGFloat.random(in: 0.90...1.12),
                gaitOffset: Double.random(in: 0..<(2 * .pi)),
                cardLean: Double.random(in: -5...5),
                scuttleRate: Double.random(in: 1.6...2.6),
                scuttlePhase: Double.random(in: 0..<(2 * .pi)),
                facing: target.x >= start.x ? 1 : -1
            ))
        }
    }

    /// The four points a crab is fully on screen at, one per corner of the
    /// walking area. A crab starts outside the screen level with one of these
    /// and walks in through it, which is what keeps the pace of the walk from
    /// here on exactly what it has always been.
    private var entryPoints: [CGPoint] {
        let side = crabSize * 0.85 + ArenaConfig.sideInset(isPad: isPad)
        // The shell is carried above the head, so the two upper lanes run low
        // enough that a fresh answer never overlaps the sum.
        let top = crabSize * 0.75 + ArenaConfig.cardHeight(isPad: isPad) * 1.1
        // …and the two lower ones run above the near reef, which is drawn in
        // front of the crabs. A crab down there walks out from behind the coral
        // with its answer already clear of it.
        let bottom = crabSize * 0.75 + ArenaConfig.nearReefRise(isPad: isPad)
        return [
            CGPoint(x: arena.minX + side, y: arena.minY + top),
            CGPoint(x: arena.maxX - side, y: arena.minY + top),
            CGPoint(x: arena.minX + side, y: arena.maxY - bottom),
            CGPoint(x: arena.maxX - side, y: arena.maxY - bottom)
        ]
    }

    /// Where a crab starts: level with the point it walks in at, and only just
    /// far enough past the side of the screen to be out of sight. Any further
    /// out is ground it has to cover before the answer can be read.
    private func offscreenStart(for entry: CGPoint) -> CGPoint {
        let clearance = ArenaConfig.cardWidth(isPad: isPad) * 0.54 + 6
        return CGPoint(x: entry.x < arena.midX ? arena.minX - clearance
                                              : arena.maxX + clearance,
                       y: entry.y)
    }

    /// How far in a crab has to be for the number it carries to be readable:
    /// the shell's middle, and with it the answer, is over the screen by then.
    private func readablePoint(for entry: CGPoint) -> CGFloat {
        let inset = ArenaConfig.cardWidth(isPad: isPad) * 0.20
        return entry.x < arena.midX ? arena.minX + inset : arena.maxX - inset
    }

    /// The right answer and three wrong ones, shuffled. A walkthrough step may
    /// ask for fewer — never for more, since a wave has four corners.
    private func waveOptions(from round: GameRound) -> [AnswerOption] {
        let correct = round.correctOption
        let wrong = round.options.filter { !$0.isCorrect }.shuffled()

        if tutorialPlan.isActive, let wave = tutorialPlan.answers {
            var picks: [AnswerOption] = []
            if wave.correct > 0, let correct { picks.append(correct) }
            picks += wrong.prefix(wave.wrong)
            return picks.shuffled()
        }

        var picks = Array(wrong.prefix(max(0, GameConfig.answerBubbleCount - 1)))
        if let correct { picks.append(correct) }
        return picks.shuffled()
    }

    private func restartWaveIfReady() {
        guard pendingWaveRestart, isLive else { return }
        // A crab already at the ring — credited or not — is still waiting on
        // `resolveSweepIfDue` to hand its shell over or fling it aside.
        // Starting the next wave out from under it would strand it there,
        // frozen, until some unrelated later crab happens to arrive and
        // re-arms the gather timer that was supposed to free it.
        guard !crabs.contains(where: { $0.isLive || $0.phase == .arrived }),
              sweepGather == nil
        else { return }
        pendingWaveRestart = false
        beginWave()
    }

    /// The sea floor keeps offering the same answers for as long as the sum
    /// stands. A wave that ends without settling the question — every crab
    /// smashed or swept, and the right answer still unanswered — is followed by
    /// a fresh one after a short breather rather than by an empty arena.
    private func refillWaveIfEmpty(_ dt: Double) {
        var suppressesRefill = false
#if DEBUG
        suppressesRefill = promoSuppressesRefill
#endif
        guard isLive,
              round != nil,
              !pendingWaveRestart,
              sweepGather == nil,
              !tutorialPlan.suppressesAnswers,
              !suppressesRefill,
              !crabs.contains(where: { $0.isLive || $0.phase == .arrived })
        else {
            refillDelay = nil
            return
        }
        let remaining = (refillDelay ?? ArenaConfig.waveRefillGap) - dt
        guard remaining <= 0 else {
            refillDelay = remaining
            return
        }
        refillDelay = nil
        beginWave()
    }

    // MARK: Simulation

#if canImport(UIKit)
    /// Uses the display's real presentation interval. This keeps motion at the
    /// same speed when a frame is late and lets ProMotion devices render the
    /// simulation at their native cadence instead of repeating every frame.
    private func advance(_ displayLink: CADisplayLink) {
        let target = displayLink.targetTimestamp
        let measured = lastFrameTargetTimestamp.map { target - $0 }
            ?? (target - displayLink.timestamp)
        lastFrameTargetTimestamp = target
        // Do not let a debugger stop or a transient system stall teleport a crab
        // into the King. Normal 60/120 Hz intervals pass unchanged.
        tick(dt: min(max(measured, 1.0 / 120.0), 1.0 / 30.0))
    }
#endif

    private func tick(dt: Double) {
        moveMotes(dt)
        moveGrains(dt)
        moveShells(dt)
        moveDoublingCoin(dt)
        moveKing(dt)

        // Before anything else this frame: the board may have been won last
        // frame, with the finale waiting on the last shell being handed over.
        releasePendingCompletionIfDue(dt)

        if completionElapsed != nil {
            moveLevelCompletion(dt)
            advanceClocks(dt)
            return
        }

        moveAmbientBubbles(dt)
        spawnAmbientBubbleIfDue(dt)
        moveCrabs(dt)
        moveCarriers(dt)
        spawnBonusCrabIfDue(dt)
        spawnLifeCrabIfDue(dt)
        spawnTutorialCrabIfDue(dt)
        resolveSweepIfDue(dt)
        emitHandedOverShellIfDue(dt)
        restartWaveIfReady()
        refillWaveIfEmpty(dt)
        // Publish only after every part of this frame has been simulated, so
        // SwiftUI observes one coherent scene rather than intermediate state.
        advanceClocks(dt)
    }

    private func advanceClocks(_ dt: Double) {
        let nextClock = clock + dt
        swayClock = (nextClock / ArenaConfig.swayInterval).rounded(.down)
            * ArenaConfig.swayInterval
        driftClock = (nextClock / ArenaConfig.driftInterval).rounded(.down)
            * ArenaConfig.driftInterval
        // This is the one published write for the completed frame.
        clock = nextClock
    }

    // MARK: Crabs

    /// Advances a crab along its path for one simulation step. Does not change
    /// phase: callers decide what reaching the King means (arrival vs. still
    /// waiting on sand). Pass `emitEffects: false` when only predicting where
    /// the crab will be (e.g. aiming a throw).
    private func advanceWalking(_ crab: inout AnswerCrab, dt: Double,
                                emitEffects: Bool = true) {
        // The walk is a straight line from off screen to the King; the
        // waddle only makes it look like walking, never like drifting.
        // Progress itself stays free of per-crab scuttle so every
        // careful crab in the wave still shares one arrival — a single
        // King sweep, not a trickle of blows.
        var run = 0.0
        if crab.isRushing {
            crab.rushAge += dt
            let ramp = min(1, crab.rushAge / ArenaConfig.rushRamp)
            run = ramp * ramp
        }
        // A careful crab still hesitates in place along its path: the
        // surge is visual only and averages out, so arrival time does
        // not drift crab-to-crab the way a rate multiplier would.
        let scuttle = sin(crab.age * crab.scuttleRate + crab.scuttlePhase)
            * (1 - 0.8 * run)
        // The on-screen stretch is the one the duration is about; the
        // rush over the last of the off-screen stretch eases out of
        // itself, so the crab arrives in view already walking.
        let onScreen = max(0.05, 1 - crab.entryProgress)
        var rate = onScreen / crab.duration
        if crab.progress < crab.entryProgress {
            let left = 1 - crab.progress / crab.entryProgress
            rate *= 1 + (ArenaConfig.approachRush - 1) * left * left
        }
        rate *= 1 + (ArenaConfig.rushSpeed - 1) * run
        crab.progress = min(1, crab.progress + dt * speedMultiplier * rate)
        let eased = crab.progress
        let base = CGPoint(
            x: crab.start.x + (crab.target.x - crab.start.x) * CGFloat(eased),
            y: crab.start.y + (crab.target.y - crab.start.y) * CGFloat(eased)
        )
        let along = CGVector(dx: crab.target.x - crab.start.x,
                             dy: crab.target.y - crab.start.y)
        let length = max(1, hypot(along.dx, along.dy))
        // Sideways sway across the line of travel, one lean per pair of
        // steps, which is how a crab actually crosses open ground.
        let sway = CGFloat(sin(crab.age * crab.waddleRate)) * crab.waddleAmplitude
        // A little surge along the path — stop-start feel without
        // changing when the crab reaches the ring.
        let surge = CGFloat(scuttle) * crab.waddleAmplitude * 0.55
            * CGFloat(eased * (1 - eased) * 4)
        let stepped = CGPoint(
            x: base.x - along.dy / length * sway + along.dx / length * surge,
            y: base.y + along.dx / length * sway + along.dy / length * surge
        )
        crab.walked += hypot(stepped.x - crab.position.x,
                             stepped.y - crab.position.y)
        crab.position = stepped
        guard emitEffects else { return }
        // Each footfall takes a little of the floor with it, which is
        // where a walk on sand shows.
        shedSandIfStepped(&crab.walked, next: &crab.nextFootfall,
                          at: crab.position, of: crabSize,
                          strideFactor: crab.strideFactor,
                          facing: crab.facing,
                          onScreen: crab.progress > crab.entryProgress
                              && arena.contains(crab.position))
        // A run kicks up the sea floor behind it. Only once the crab
        // is actually on screen: sand thrown from off the edge would
        // announce a crab the player cannot see yet.
        if crab.isRushing, crab.progress > crab.entryProgress {
            crab.puffCountdown -= dt
            if crab.puffCountdown <= 0 {
                crab.puffCountdown = ArenaConfig.rushPuffInterval
                burst(at: crab.position, strength: 0.3,
                      drift: -crab.facing * 120)
            }
        }
    }

    private func moveCrabs(_ dt: Double) {
        for index in crabs.indices {
            var crab = crabs[index]
            crab.age += dt
            crab.phaseAge += dt

            switch crab.phase {
            case .waiting:
                // It stands off the side of the screen until its turn in the
                // stagger comes, and then simply starts walking on.
                crab.startDelay -= dt
                if crab.startDelay <= 0 {
                    crab.phase = .walking
                    crab.phaseAge = 0
                }

            case .walking:
                advanceWalking(&crab, dt: dt)
                if crab.progress >= 1 {
                    crab.phase = .arrived
                    crab.phaseAge = 0
                    crab.position = crab.target
                    if sweepGather == nil { sweepGather = ArenaConfig.sweepGather }
                }

            case .arrived:
                // Held at the ring, shuffling in place until the King answers.
                let jitter = CGFloat(sin(crab.age * 11)) * crabSize * 0.02
                crab.position = CGPoint(x: crab.target.x + jitter, y: crab.target.y)
                // A crab standing at the ring is *always* waiting on a gather
                // to resolve it. Anything that clears that timer out from under
                // it — a new sum arriving in the same breath as the crab, most
                // of all — would otherwise leave it stood there holding its
                // answer until some later, unrelated arrival happened to re-arm
                // the timer and free them both at once.
                if sweepGather == nil { sweepGather = ArenaConfig.sweepGather }

            case .hit:
                // Keep walking until the sand lands — a tap must not plant it.
                // Reaching the ring here does not count as an arrival: the
                // answer was already taken, and the sand is still on its way.
                advanceWalking(&crab, dt: dt)
                if crab.progress >= 1 {
                    crab.position = crab.target
                }
                if crab.phaseAge >= ArenaConfig.sandImpactDelay {
                    let dx = crab.position.x - king.anchor.x
                    let dy = crab.position.y - king.anchor.y
                    let length = max(1, hypot(dx, dy))
                    crab.flingVelocity = CGPoint(
                        x: dx / length * CGFloat.random(in: 220...320),
                        y: dy / length * 90 - CGFloat.random(in: 240...330))
                    crab.phase = .smashed
                    crab.phaseAge = 0
                    burst(at: crab.position, strength: 1.0)
                }

            case .smashed, .swept:
                crab.position.x += crab.flingVelocity.x * CGFloat(dt)
                crab.position.y += crab.flingVelocity.y * CGFloat(dt)
                crab.flingVelocity.y += 1_050 * CGFloat(dt)

            case .delivering:
                // Standing at the King's claw, holding the shell up to him. It
                // steadies itself over its own feet while it lets go.
                let settle = min(1, crab.phaseAge / ArenaConfig.deliverDuration)
                crab.position = CGPoint(x: crab.target.x, y: crab.target.y)
                if settle >= 1 {
                    // Handed over. Its work is done, so it digs itself in like
                    // every other crab whose wave is finished — but without the
                    // shell, which is the King's now.
                    crab.hasDelivered = true
                    crab.phase = .burrowing
                    crab.phaseAge = 0
                    crab.puffCountdown = 0
                }

            case .burrowing:
                // Straight down into the sand, no travel — but the digging
                // itself throws sand out for as long as it lasts, and the
                // legs are what is doing the throwing, so the spray keeps
                // coming from under the crab rather than once at the start.
                crab.puffCountdown -= dt
                if crab.puffCountdown <= 0,
                   crab.phaseAge < ArenaConfig.burrowDuration * 0.86,
                   arena.contains(crab.position) {
                    crab.puffCountdown = ArenaConfig.burrowPuffInterval
                    // It bites deeper as it goes: the last of the sand is
                    // thrown hardest, just as the crab pulls itself under.
                    let bite = 0.34 + 0.5 * (crab.phaseAge / ArenaConfig.burrowDuration)
                    burst(at: crab.position, strength: CGFloat(bite))
                }
            }
            crabs[index] = crab
        }

        crabs.removeAll { crab in
            switch crab.phase {
            case .smashed:   return crab.phaseAge >= ArenaConfig.smashDuration
            case .burrowing: return crab.phaseAge >= ArenaConfig.burrowDuration
            case .swept:     return crab.phaseAge >= ArenaConfig.sweptDuration
            default:         return false
            }
        }
    }

    // MARK: The King

    private func moveKing(_ dt: Double) {
        if var age = king.entranceAge {
            age += dt
            if !entranceDidOpenRound,
               age >= ArenaConfig.entranceDuration - ArenaConfig.entranceAnswerLead {
                entranceDidOpenRound = true
                let completion = entranceCompletion
                entranceCompletion = nil
                completion?()
            }
            king.entranceAge = age >= ArenaConfig.entranceDuration ? nil : age
            if king.entranceAge == nil, !entranceDidOpenRound {
                // Normally delivered during the walk, but keep a fallback so a
                // future timing change can never stall play.
                entranceDidOpenRound = true
                let completion = entranceCompletion
                entranceCompletion = nil
                completion?()
            }
        }
        if let age = king.farewellAge {
            king.farewellAge = age + dt
        }
        if var age = king.streakAge {
            age += dt
            king.streakAge = age >= ArenaConfig.streakCelebrationDuration ? nil : age
        }
        if var age = king.sweepAge {
            age += dt
            king.sweepAge = (age >= ArenaConfig.sweepDuration && !king.isCheering) ? nil : age
        }
        if var age = king.healAge {
            age += dt
            king.healAge = age >= ArenaConfig.healDuration ? nil : age
        }
        placeKing(dt)
        moveClaws(dt)
    }

    /// Far enough past the right edge that no part of him is still showing.
    private var exitPoint: CGFloat { size.width + kingSize }

    /// Works out where the King is standing this frame and how hard his legs
    /// are working, from whichever of the two journeys he is on. At rest — the
    /// whole of normal play — this settles him on his anchor and leaves the
    /// idling to the view.
    private func placeKing(_ dt: Double) {
        var point = king.anchor
        var effort = 0.0
        var lift: CGFloat = 0
        // Which way he is heading, so the sand comes off the side he is
        // leaving behind. Every journey but the celebration crosses the floor
        // rightward, which is the direction this used to be hardcoded to.
        var travel: Double = 1

        if let age = king.entranceAge {
            // He comes on at a scurry and eases down onto his spot, so the
            // arrival reads as an animal stopping rather than as a slide ending.
            let t = min(1, age / ArenaConfig.entranceDuration)
            let eased = CGFloat(1 - pow(1 - t, 2.4))
            let start = arena.minX - kingSize * 0.95
            point.x = start + (king.anchor.x - start) * eased
            // Working right up to the last stride, then planting himself.
            effort = min(1, (1 - t) / 0.18)
        } else if king.hasLeft {
            // He is gone. Nothing brings him back on stage while the result is
            // coming up over the floor he just ran off.
            point.x = exitPoint
        } else if let age = king.farewellAge {
            let hop = ArenaConfig.kingHopDuration
            let settle = hop + ArenaConfig.kingHopSettle
            if age < hop {
                // One jump on the spot, straight up and straight down.
                let t = age / hop
                lift = CGFloat(sin(t * .pi)) * kingSize * ArenaConfig.kingHopHeight
            } else if age >= settle {
                let t = min(1, (age - settle) / ArenaConfig.kingExitDuration)
                // Accelerating away rather than starting at full speed.
                let eased = CGFloat(t * t)
                point.x = king.anchor.x + (exitPoint - king.anchor.x) * eased
                effort = 1
                if t >= 1 { king.hasLeft = true }
            }
        } else if let age = king.streakAge {
            // Out to the left, across to the right and home: one full turn of
            // the sine, which is what puts him back on his anchor to the point
            // rather than near it.
            let t = min(1, age / ArenaConfig.streakCelebrationDuration)
            let turn = t * 2 * .pi
            let swing = sin(turn)
            point.x -= CGFloat(swing) * kingSize * ArenaConfig.streakCelebrationSway
            // He is at his quickest crossing the middle and stands still at
            // each end of the sway, so the legs — and with them the sand —
            // work off how fast he is actually moving rather than off how far
            // out he is. That is `cos`, the rate the sine above changes at.
            let speed = cos(turn)
            effort = 0.30 + 0.62 * abs(speed)
            // `point.x` moves against the sine, so he is heading right exactly
            // while that rate is negative. The sign flips at the two ends,
            // where `effort` has dipped under the sand threshold — so no puff
            // is ever thrown on an ambiguous direction.
            travel = speed < 0 ? 1 : -1
        }

        // The stride only ever runs forward, so a walk that speeds up or slows
        // down never jumps a step. Even standing still he shifts his weight.
        king.stride += dt * (2.3 + 17 * effort)
        king.effort = effort
        king.lift = lift
        king.position = CGPoint(x: point.x, y: point.y - lift)

        guard effort > 0.35, dt > 0, size.width > 0 else { return }
        footPuff -= dt
        guard footPuff <= 0 else { return }
        footPuff = ArenaConfig.entrancePuffInterval
        // Sand kicked out from under the feet, off the side he is leaving
        // behind and drifting back the way he came.
        burst(at: CGPoint(x: king.position.x - CGFloat(travel) * kingSize * 0.22,
                          y: king.anchor.y + kingSize * 0.30),
              strength: 0.5, drift: -230 * travel)
    }

    // MARK: The claws

    /// The King answers the crab the player picked with the claw on that side:
    /// the two answers on the left are thrown at with the left claw, the two on
    /// the right with the right one.
    private func requestClawThrow(at target: CGPoint) {
        if target.x >= king.anchor.x {
            enqueue(target, in: &king.rightClaw, queue: &pendingRightThrows)
        } else {
            enqueue(target, in: &king.leftClaw, queue: &pendingLeftThrows)
        }
    }

    private func enqueue(_ target: CGPoint, in claw: inout ClawThrow?,
                         queue: inout [CGPoint]) {
        guard claw != nil else {
            claw = ClawThrow(target: target)
            return
        }
        // A swing already under way is always finished. The next crab waits its
        // turn behind it rather than cutting it short.
        guard queue.count < ArenaConfig.clawThrowQueue else { return }
        queue.append(target)
    }

    private func moveClaws(_ dt: Double) {
        // Deliberately by value rather than `inout`: releasing the sand reads
        // where the King is standing, which is the same `king` an in-place
        // update would already be holding.
        king.leftClaw = advanced(king.leftClaw, queue: &pendingLeftThrows,
                                 isRight: false, dt)
        king.rightClaw = advanced(king.rightClaw, queue: &pendingRightThrows,
                                  isRight: true, dt)
    }

    private func advanced(_ claw: ClawThrow?, queue: inout [CGPoint],
                          isRight: Bool, _ dt: Double) -> ClawThrow? {
        guard var swing = claw else { return nil }
        swing.age += dt
        if !swing.hasThrown,
           swing.age >= ArenaConfig.clawThrowDuration * ArenaConfig.clawReleaseShare {
            swing.hasThrown = true
            throwSand(at: swing.target, isRight: isRight)
        }
        guard swing.age < ArenaConfig.clawThrowDuration else {
            // The swing is finished, so the next crab taken on this side — if
            // any has been waiting — gets its own full throw now.
            return queue.isEmpty ? nil : ClawThrow(target: queue.removeFirst())
        }
        return swing
    }

    /// The handful itself: a cone of sand out of the pincer that opens as it
    /// travels, timed to reach the crab while it is still being thrown clear.
    private func throwSand(at target: CGPoint, isRight: Bool) {
        let isForward = ArenaConfig.isForwardThrow(targetY: target.y,
                                                   kingY: king.anchor.y)
        let rise = Double((king.anchor.y - target.y) / max(1, kingSize))
        let degrees = ArenaConfig.clawThrowPoseAngle(
            progress: ArenaConfig.clawReleaseShare,
            targetRise: rise,
            isForward: isForward
        ) * (isRight ? -1 : 1)
        let origin = clawTipOrigin(degrees: degrees, isRight: isRight, isForward: isForward)
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let span = max(kingSize * 0.5, hypot(dx, dy))
        let heading = atan2(Double(dy), Double(dx))
        let room = ArenaPerformanceBudget.maximumLiveGrains - grains.count
        guard room > 0 else { return }
        let count = min(room, max(12, Int(Double(ArenaPerformanceBudget.grainsPerBurst) * 3.2)))
        // Forward scoops fan wider; overhead sprays tighter and a touch faster.
        let spray = isForward ? 0.34 : 0.22
        let speedBias: ClosedRange<CGFloat> = isForward ? 0.66...1.18 : 0.78...1.28
        for _ in 0..<count {
            let angle = heading + Double.random(in: -spray...spray)
            let speed = span / CGFloat(ArenaConfig.sandFlightDuration)
                * CGFloat.random(in: speedBias)
            grains.append(SandGrain(
                position: CGPoint(x: origin.x + CGFloat.random(in: -4...4),
                                  y: origin.y + CGFloat.random(in: -4...4)),
                velocity: CGPoint(x: CGFloat(cos(angle)) * speed,
                                  y: CGFloat(sin(angle)) * speed),
                radius: CGFloat.random(in: isForward ? 2.4...6.0 : 2.0...5.2),
                tone: Double.random(in: 0...1),
                lifetime: Double.random(in: ArenaConfig.sandFlightDuration
                                            ... ArenaConfig.sandFlightDuration * 2.1),
                // Thrown sand has to carry to what it was thrown at, so it
                // holds its line where a kicked-up puff would already be back
                // on the floor.
                gravity: isForward ? 170 : 130,
                drag: isForward ? 0.78 : 0.84
            ))
        }
    }

    /// Where the swinging pincer is at `degrees`, so sand leaves the claw rather
    /// than the rest pose. The shoulder sits a little inside the tip reach.
    private func clawTipOrigin(degrees: Double, isRight: Bool,
                               isForward: Bool) -> CGPoint {
        let side: CGFloat = isRight ? 1 : -1
        let joint = CGPoint(x: side * 0.12, y: 0.11)
        let rest = CGPoint(x: clawTip.width * side, y: clawTip.height)
        let dx = rest.x - joint.x
        let dy = rest.y - joint.y
        let rad = degrees * .pi / 180
        let cosT = cos(rad)
        let sinT = sin(rad)
        var tip = CGPoint(x: joint.x + dx * cosT - dy * sinT,
                          y: joint.y + dx * sinT + dy * cosT)
        // A scoop releases a touch lower; an overhead toss a touch higher.
        tip.y += isForward ? 0.04 : -0.06
        tip.x += side * (isForward ? 0.03 : 0.01)
        return CGPoint(x: king.position.x + kingSize * tip.x,
                       y: king.position.y + kingSize * tip.y)
    }

    /// One blow answers everything standing at the ring. Two crabs arriving all
    /// but together therefore produce a single sweep, and their score and life
    /// consequences are applied afterwards, one by one.
    private func resolveSweepIfDue(_ dt: Double) {
        guard var remaining = sweepGather else { return }
        // Hold the gather while careful crabs of this wave are still en route,
        // so early arrivals share one sweep. A rushing crab — the lone right
        // answer running in after the rest were cleared — answers on its own
        // clock and must not wait for a later wave. Same for a crab the
        // session has already credited: it is only there to hand the shell over.
        let carefulStillComing = crabs.contains {
            !$0.hasAnswered
                && !$0.isRushing
                && ($0.phase == .waiting || $0.phase == .walking)
        }
        let creditedAtRing = crabs.contains { $0.phase == .arrived && $0.hasAnswered }
        if carefulStillComing && !creditedAtRing { return }

        remaining -= dt
        guard remaining <= 0 else {
            sweepGather = remaining
            return
        }
        sweepGather = nil

        let arrived = crabs.indices.filter { crabs[$0].phase == .arrived }
        guard !arrived.isEmpty else { return }

        // A crab whose answer the session has already taken is not answering
        // anything here: it is finishing the errand it was counted for. It
        // hands the shell over and nothing else about the round moves.
        for index in arrived where crabs[index].hasAnswered {
            deliver(index: index)
        }
        let contenders = arrived.filter { !crabs[$0].hasAnswered }
        guard !contenders.isEmpty else { return }

#if DEBUG
        // Trailer: a lone correct crab that already ran in is handing its
        // shell over, not an attacker. A sweep ring here would look like the
        // King is shoving it away.
        if promoDefersRushScoring,
           contenders.count == 1,
           let index = contenders.first,
           crabs[index].isCorrect,
           crabs[index].isRushing {
            let scored = onGuardedArrival?(crabs[index].optionID) == true
            if scored {
                deliver(index: index)
                burrowLiveCrabs()
            } else {
                deliver(index: index)
            }
            return
        }
#endif

        king.sweepAge = 0
        king.sweepDirection = Bool.random() ? 1 : -1
        onSweep?()

        // Wrong answers land first: they are what the King is being hit with,
        // and the right answer is what he is left holding. Two of them standing
        // there are still one breach — what it costs is the session's to decide,
        // and it charges for the sum rather than for the crab.
        var scored = false
        if contenders.contains(where: { !crabs[$0].isCorrect }) {
            onBreach?()
        }
        if let index = contenders.first(where: { crabs[$0].isCorrect }) {
            scored = onGuardedArrival?(crabs[index].optionID) == true
        }

        for index in contenders {
            // The blow is for the crabs that brought the King a wrong answer.
            // One that brought the right one is not an attacker: it hands its
            // shell over and digs itself in afterwards.
            if crabs[index].isCorrect, scored {
                deliver(index: index)
            } else {
                fling(index: index)
            }
        }
        if scored {
            // The sum is about to change, so everything else gives up and digs
            // itself back in rather than waiting to be swept.
            burrowLiveCrabs()
        } else {
            // A wrong answer the King has just swept aside can leave the right
            // one alone on the sea floor exactly as a tap does.
            rushLoneCorrectCrab()
        }
    }

    /// The right answer, presented. The crab turns to the King, bows, and sets
    /// its shell down on the sand in front of him; `moveCrabs` sends it digging
    /// itself in once it has straightened up again.
    private func deliver(index: Int) {
        var crab = crabs[index]
        crab.phase = .delivering
        crab.phaseAge = 0
        crab.isRushing = false
        // Where the King is, seen from the crab: it is the way the crab turns
        // and bows, and the way the shell goes down in front of it.
        crab.handOver = CGPoint(x: king.anchor.x - crab.position.x,
                                y: king.anchor.y - crab.position.y)
        crabs[index] = crab
        // The King's own shell goes up to the score as he takes it, not before:
        // the stone has to be down at his feet first for it to be a gift.
        shellHandOver = ArenaConfig.deliverDuration * ArenaConfig.deliverGiveShare
    }

    private func fling(index: Int) {
        var crab = crabs[index]
        let dx = crab.position.x - king.anchor.x
        let dy = crab.position.y - king.anchor.y
        let length = max(1, hypot(dx, dy))
        crab.phase = .swept
        crab.phaseAge = 0
        crab.flingVelocity = CGPoint(x: dx / length * CGFloat.random(in: 420...560),
                                     y: dy / length * 260 - CGFloat.random(in: 180...260))
        crab.spin = Double.random(in: -13...13)
        crabs[index] = crab
    }

    /// The King sends the shell up to the score only once the crab has actually
    /// put it in his claws.
    private func emitHandedOverShellIfDue(_ dt: Double) {
        guard var remaining = shellHandOver else { return }
        remaining -= dt
        guard remaining <= 0 else {
            shellHandOver = remaining
            return
        }
        shellHandOver = nil
        emitShell()
    }

    /// The shell a scored answer sends to the HUD, along a curve that leaves the
    /// King and settles exactly over its stationary twin in the score counter.
    private func emitShell() {
        let diameter: CGFloat = isPad ? 34 : 26
        let start = CGPoint(x: king.anchor.x, y: king.anchor.y - kingSize * 0.46)
        let target = scoreTarget ?? CGPoint(x: size.width / 2,
                                            y: max(diameter / 2, arena.minY - 30))
        let firstControl = CGPoint(x: start.x + (start.x - target.x) * 0.18,
                                   y: start.y - kingSize * 0.42)
        let secondControl = CGPoint(x: target.x + (start.x - target.x) * 0.24,
                                    y: start.y + (target.y - start.y) * 0.72)
        let shell = ShellReward(diameter: diameter,
                                start: start,
                                firstControl: firstControl,
                                secondControl: secondControl,
                                target: target,
                                position: start)
        shells.append(shell)
        if launchDoublingCoinWithShell {
            launchDoublingCoinFlight(with: shell)
        }
    }

    private func moveShells(_ dt: Double) {
        for index in shells.indices {
            shells[index].age += dt
            let raw = min(1, shells[index].age / ArenaConfig.shellFlightDuration)
            let t = CGFloat(raw * raw * (3 - 2 * raw))
            let shell = shells[index]
            shells[index].position = cubicPoint(from: shell.start,
                                                control1: shell.firstControl,
                                                control2: shell.secondControl,
                                                to: shell.target,
                                                t: t)
        }
        let arrived = shells.reduce(into: 0) { count, shell in
            if shell.age >= ArenaConfig.shellFlightDuration { count += 1 }
        }
        shells.removeAll { $0.age >= ArenaConfig.shellFlightDuration }
        for _ in 0..<arrived { onShellArrived?() }
    }

    /// Keeps the doubling coin under his feet while it waits, then flies it on
    /// the same curve as the shell once the doubled answer is paid.
    private func moveDoublingCoin(_ dt: Double) {
        guard var coin = doublingCoin else { return }
        if let start = coin.start,
           let first = coin.firstControl,
           let second = coin.secondControl,
           let target = coin.target {
            coin.age += dt
            let raw = min(1, coin.age / ArenaConfig.shellFlightDuration)
            let t = CGFloat(raw * raw * (3 - 2 * raw))
            coin.position = cubicPoint(from: start,
                                       control1: first,
                                       control2: second,
                                       to: target,
                                       t: t)
            if coin.age >= ArenaConfig.shellFlightDuration {
                doublingCoin = nil
                return
            }
            doublingCoin = coin
            return
        }
        // Resting: only rewrite when his feet moved. The idle pulse is driven
        // from `swayClock` in the view, so age is unused while it waits.
        let point = restingDoublingCoinPoint()
        guard coin.position != point else { return }
        coin.position = point
        doublingCoin = coin
    }

    /// Where the coin sits while the power is held: under him, on the sand,
    /// drawn behind his body so only the near edge peeks out.
    private func restingDoublingCoinPoint() -> CGPoint {
        CGPoint(x: king.position.x,
                y: king.position.y + kingSize * 0.34)
    }

    private func placeRestingDoublingCoin() {
        launchDoublingCoinWithShell = false
        let diameter = ArenaConfig.helperCrabSize(isPad: isPad) * ArenaConfig.helperTokenShare
        let point = restingDoublingCoinPoint()
        if var coin = doublingCoin, !coin.isFlying {
            coin.position = point
            doublingCoin = coin
            return
        }
        doublingCoin = DoublingCoin(diameter: diameter, position: point)
    }

    private func clearDoublingCoin() {
        doublingCoin = nil
        launchDoublingCoinWithShell = false
    }

    /// Sends the resting coin up with the shell — starting from his feet and
    /// arcing slightly aside so the rise reads as behind him, not over him.
    private func launchDoublingCoinFlight(with shell: ShellReward?) {
        guard var coin = doublingCoin, !coin.isFlying else {
            launchDoublingCoinWithShell = false
            return
        }
        launchDoublingCoinWithShell = false
        let start = coin.position
        let target = shell?.target
            ?? scoreTarget
            ?? CGPoint(x: size.width / 2, y: max(coin.diameter / 2, arena.minY - 30))
        // Nudge the first lift off-centre so it clears past his flank rather
        // than climbing straight through the middle of the silhouette.
        let side: CGFloat = king.position.x >= size.width / 2 ? -1 : 1
        let firstControl = CGPoint(x: start.x + side * kingSize * 0.18,
                                   y: start.y - kingSize * 0.55)
        let secondControl = shell.map {
            CGPoint(x: $0.secondControl.x + side * kingSize * 0.06,
                    y: $0.secondControl.y)
        } ?? CGPoint(x: target.x + side * kingSize * 0.08,
                     y: start.y + (target.y - start.y) * 0.72)
        coin.start = start
        coin.firstControl = firstControl
        coin.secondControl = secondControl
        coin.target = target
        coin.age = 0
        coin.position = start
        doublingCoin = coin
    }

    private func cubicPoint(from start: CGPoint, control1: CGPoint,
                            control2: CGPoint, to end: CGPoint,
                            t: CGFloat) -> CGPoint {
        let remaining = 1 - t
        let a = remaining * remaining * remaining
        let b = 3 * remaining * remaining * t
        let c = 3 * remaining * t * t
        let d = t * t * t
        return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                       y: a * start.y + b * control1.y + c * control2.y + d * end.y)
    }

    // MARK: Carrier crabs

    private func spawnBonusCrabIfDue(_ dt: Double) {
        // While the walkthrough is running, the only helper crab in the arena is
        // the one the current step put there.
        guard !tutorialPlan.isActive,
              carriers.isEmpty,
              !hasBonusAura,
              !pendingBonusDelays.isEmpty,
              arena.height > 0 else { return }
        pendingBonusDelays[0] -= dt
        guard pendingBonusDelays[0] <= 0 else { return }
        pendingBonusDelays.removeFirst()
        spawnBonusCrab()
    }

    private func spawnBonusCrab() {
        spawnHelperCrab(kind: .bonus)
    }

    private func spawnLifeCrabIfDue(_ dt: Double) {
        guard !tutorialPlan.isActive,
              carriers.isEmpty,
              isLifeCrabAvailable,
              var delay = lifeCrabDelay,
              arena.height > 0 else { return }
        delay -= dt
        lifeCrabDelay = delay
        guard delay <= 0 else { return }
        lifeCrabDelay = nil
        spawnLifeCrab()
    }

    private func spawnLifeCrab() {
        spawnHelperCrab(kind: .life)
    }

    /// Both helper crabs walk the very front of the sea floor, right along the
    /// near edge, holding what they have brought up over their heads. Nothing
    /// is ever in front of them there — which is the point: they are an offer
    /// the player has to see and take, not a thing walking past behind the
    /// scenery.
    private func spawnHelperCrab(kind: CarrierCrab.Kind) {
        let size = ArenaConfig.helperCrabSize(isPad: isPad, kind: kind)
        let direction: CGFloat = Bool.random() ? 1 : -1
        let lane = arena.maxY - ArenaConfig.helperLane(isPad: isPad)
        let start = CGPoint(x: direction > 0 ? -size : arena.maxX + size, y: lane)
        let target = CGPoint(x: direction > 0 ? arena.maxX + size : -size, y: lane)
        carriers.append(CarrierCrab(
            kind: kind,
            size: size,
            start: start,
            target: target,
            position: start,
            // Same crossing time on every device: a wider board just means a
            // faster scuttle, not a longer window to catch the reward.
            duration: Double.random(in: ArenaConfig.helperCrabCrossingDuration),
            waddleRate: Double.random(in: 3.6...4.8),
            strideFactor: CGFloat.random(in: 0.92...1.08),
            gaitOffset: Double.random(in: 0..<(2 * .pi)),
            facing: direction
        ))
    }

    /// Points/sec for a tapped helper walking in to the King. Scales with the
    /// arena so a long diagonal on iPad does not linger the way a phone trip
    /// would if the old fixed speed were kept.
    private var scaledHelperFetchSpeed: CGFloat {
        let scale = max(1, arena.width / ArenaConfig.helperSpeedReferenceWidth)
        return ArenaConfig.helperFetchSpeed * scale
    }

    /// Where a tapped helper crab is sent: the same ring around the King the
    /// answers walk to, on the side it was tapped on.
    private func helperTarget(for carrier: CarrierCrab) -> CGPoint {
        let ring = kingSize * ArenaConfig.arrivalRingFactor
        let angle = atan2(Double(carrier.position.y - king.anchor.y),
                          Double(carrier.position.x - king.anchor.x))
        return CGPoint(x: king.anchor.x + ring * CGFloat(cos(angle)),
                       y: king.anchor.y + ring * CGFloat(sin(angle)))
    }

    /// Puts the taught helper crab in the arena, and puts it back whenever it
    /// crosses without being taken: a step ends because the player managed it,
    /// never because they were unlucky.
    private func spawnTutorialCrabIfDue(_ dt: Double) {
        guard tutorialPlan.isActive,
              tutorialPlan.wantsLifeCrab || tutorialPlan.wantsBonusCrab,
              arena.height > 0,
              !carriers.contains(where: \.isCarryingReward) else { return }

        guard var delay = tutorialCrabDelay else {
            tutorialCrabDelay = ArenaConfig.tutorialCrabArrival
            return
        }
        delay -= dt
        tutorialCrabDelay = delay
        guard delay <= 0 else { return }
        tutorialCrabDelay = nil
        if tutorialPlan.wantsLifeCrab {
            spawnLifeCrab()
        } else {
            spawnBonusCrab()
        }
    }

    private func moveCarriers(_ dt: Double) {
        for index in carriers.indices {
            var carrier = carriers[index]
            carrier.phaseAge += dt

            switch carrier.phase {
            case .crossing, .fetching:
                carrier.progress = min(1, carrier.progress + dt / carrier.duration)
                let base = CGPoint(
                    x: carrier.start.x + (carrier.target.x - carrier.start.x) * CGFloat(carrier.progress),
                    y: carrier.start.y + (carrier.target.y - carrier.start.y) * CGFloat(carrier.progress)
                )
                let stepped = CGPoint(
                    x: base.x,
                    y: base.y + CGFloat(sin(clock * carrier.waddleRate)) * carrier.size * 0.022
                )
                carrier.walked += hypot(stepped.x - carrier.position.x,
                                        stepped.y - carrier.position.y)
                carrier.position = stepped
                shedSandIfStepped(&carrier.walked, next: &carrier.nextFootfall,
                                  at: carrier.position, of: carrier.bodyWidth,
                                  strideFactor: carrier.strideFactor,
                                  facing: carrier.facing,
                                  onScreen: arena.contains(carrier.position))

            case .burrowing:
                carrier.puffCountdown -= dt
                if carrier.puffCountdown <= 0,
                   carrier.phaseAge < ArenaConfig.burrowDuration * 0.86,
                   arena.contains(carrier.position) {
                    carrier.puffCountdown = ArenaConfig.burrowPuffInterval
                    let bite = 0.30 + 0.5 * (carrier.phaseAge / ArenaConfig.burrowDuration)
                    burst(at: carrier.position, strength: CGFloat(bite))
                }
            }
            carriers[index] = carrier
        }

        // One that reaches the King puts what it brought into his claws, and
        // then digs itself in exactly as an answer crab does once its own work
        // is finished. Taken by id: handing a life over runs back through the
        // session, which is free to clear the arena out from under this loop.
        let arrived = carriers
            .filter { $0.phase == .fetching && $0.progress >= 1 }
            .map(\.id)
        for id in arrived {
            guard let index = carriers.firstIndex(where: { $0.id == id }) else { continue }
            deliverHelp(at: index)
        }

        carriers.removeAll { carrier in
            switch carrier.phase {
            case .crossing:
                // Missed. It comes round again rather than taking the reward
                // with it: nothing the player has earned is lost to bad luck.
                guard carrier.progress >= 1 else { return false }
                retryHelperCrab(carrier.kind)
                return true
            case .fetching:
                return false
            case .burrowing:
                return carrier.phaseAge >= ArenaConfig.burrowDuration
            }
        }
    }

    /// The hand-over. The session has the last word on both rewards, exactly as
    /// it does on an answer; the crab digs itself in either way, because from
    /// its own point of view it has arrived and given what it was carrying.
    private func deliverHelp(at index: Int) {
        let carrier = carriers[index]
        // It is finished with before the session hears about it: taking a life
        // can end a round, and a round ending is entitled to clear the arena.
        carriers[index].phase = .burrowing
        carriers[index].phaseAge = 0
        carriers[index].puffCountdown = 0
        burst(at: carrier.position, strength: 0.6)

        switch carrier.kind {
        case .bonus:
            hasBonusAura = true
            placeRestingDoublingCoin()
            onBonusCrabCaught?()
            onTutorialEvent?(.caughtBonusCrab)
        case .life:
            if onLifeCrabArrived?() == true {
                king.healAge = 0
            }
            onTutorialEvent?(.lifeCrabArrived)
        }
    }

    /// Sends the missed crab round again. In the walkthrough that is the step's
    /// own retry, which comes round quicker; in a game it is a fresh wait.
    private func retryHelperCrab(_ kind: CarrierCrab.Kind) {
        if tutorialPlan.wantsBonusCrab || tutorialPlan.wantsLifeCrab {
            tutorialCrabDelay = ArenaConfig.tutorialCrabArrival
            return
        }
        switch kind {
        case .bonus:
            guard !hasBonusAura else { return }
            pendingBonusDelays.append(Double.random(in: ArenaConfig.helperCrabRetry))
        case .life:
            guard isLifeCrabAvailable else { return }
            lifeCrabDelay = Double.random(in: ArenaConfig.helperCrabRetry)
        }
    }

    // MARK: Sand

    /// A puff of sand. Used by everything that meets the sea floor hard enough
    /// to disturb it: an emerging crab, a smashed one, a burrowing one.
    /// `drift` throws the whole puff one way, for sand that is being kicked
    /// backwards by something moving rather than knocked straight up.
    private func burst(at point: CGPoint, strength: CGFloat, drift: CGFloat = 0) {
        let room = ArenaPerformanceBudget.maximumLiveGrains - grains.count
        guard room > 0 else { return }
        let count = min(room, max(3, Int(CGFloat(ArenaPerformanceBudget.grainsPerBurst) * strength)))
        for _ in 0..<count {
            let angle = Double.random(in: -Double.pi ... 0)
            let speed = CGFloat.random(in: 60...190) * strength
            grains.append(SandGrain(
                position: CGPoint(x: point.x + CGFloat.random(in: -6...6),
                                  y: point.y + crabSize * 0.30 + CGFloat.random(in: -4...4)),
                velocity: CGPoint(x: CGFloat(cos(angle)) * speed + drift * CGFloat.random(in: 0.6...1.2),
                                  y: CGFloat(sin(angle)) * speed),
                radius: CGFloat.random(in: 1.6...4.4) * (0.7 + strength * 0.5),
                tone: Double.random(in: 0...1),
                lifetime: Double.random(in: 0.34...0.62)
            ))
        }
    }

    /// The kick of sand a walking crab leaves under itself, one footfall at a
    /// time.
    ///
    /// Deliberately nothing like a `burst`: a handful of grains, barely off the
    /// floor, thrown back the way the crab came. What it says is that there is
    /// sand under the animal and that its feet are in it — the difference
    /// between a crab walking on the sea floor and one sliding over a picture
    /// of one.
    ///
    /// It leaves from under the trailing foot rather than from the middle of
    /// the animal, and from the two sides in turn, so the puffs come off the
    /// floor in the same alternating rhythm the legs step in.
    private func scuff(at point: CGPoint, bodyWidth: CGFloat,
                       facing: CGFloat, nearFoot: Bool) {
        let room = ArenaPerformanceBudget.maximumLiveGrains - grains.count
        // Footfall scuffs are the first thing to drop when the canvas is full:
        // a walking wave without sand kicks is still readable; a flooded
        // effects pass is not.
        guard room > 0 else { return }
        let count = min(room, ArenaPerformanceBudget.isConstrained ? 2 : 3)
        let heel = CGPoint(
            x: point.x - facing * bodyWidth * (nearFoot ? 0.34 : 0.24),
            y: point.y + bodyWidth
                * (ArenaConfig.footLine + (nearFoot ? 0.06 : -0.03))
        )
        for _ in 0..<count {
            grains.append(SandGrain(
                position: CGPoint(x: heel.x + CGFloat.random(in: -4...4),
                                  y: heel.y + CGFloat.random(in: -2...2)),
                velocity: CGPoint(x: -facing * CGFloat.random(in: 22...84),
                                  y: -CGFloat.random(in: 30...78)),
                radius: CGFloat.random(in: 1.2...3.1),
                tone: Double.random(in: 0.35...1),
                lifetime: Double.random(in: 0.30...0.54),
                // It is pushed off the floor rather than thrown up off it, so
                // it settles back almost at once and hardly travels.
                gravity: 170,
                drag: 0.05
            ))
        }
    }

    /// Counts a walk into footfalls and sheds sand on each one.
    ///
    /// The stride is measured in ground covered rather than in time — exactly
    /// as the legs themselves are — so a crab that hesitates mid-scuttle stops
    /// kicking sand up with it, and one that breaks into a run leaves a trail.
    private func shedSandIfStepped(_ walked: inout CGFloat,
                                   next: inout CGFloat,
                                   at point: CGPoint,
                                   of bodyWidth: CGFloat,
                                   strideFactor: CGFloat,
                                   facing: CGFloat,
                                   onScreen: Bool) {
        let stride = max(1, bodyWidth * ArenaConfig.strideLength * strideFactor)
        guard walked >= next else { return }
        // Two footfalls to the cycle: the two sides carry the weight in turn.
        next = walked + stride / 2
        guard onScreen else { return }
        // Which side has just come down. It is the same stride the legs
        // themselves are stepped off, so the sand leaves the floor on the beat
        // the feet do rather than on one of its own.
        let footfall = Int(walked / (stride / 2))
        scuff(at: point, bodyWidth: bodyWidth, facing: facing,
              nearFoot: footfall.isMultiple(of: 2))
    }

    private func moveGrains(_ dt: Double) {
        for index in grains.indices {
            grains[index].age += dt
            grains[index].position.x += grains[index].velocity.x * CGFloat(dt)
            grains[index].position.y += grains[index].velocity.y * CGFloat(dt)
            // Sand thrown up underwater slows quickly and drifts back down.
            grains[index].velocity.y += grains[index].gravity * CGFloat(dt)
            let damping = CGFloat(pow(grains[index].drag, dt))
            grains[index].velocity.x *= damping
        }
        grains.removeAll { $0.age >= $0.lifetime }
    }

    // MARK: Ambience

    private func moveMotes(_ dt: Double) {
        guard size.height > 0 else { return }
        for index in motes.indices {
            motes[index].age += dt
            var mote = motes[index]
            mote.position.y -= mote.speed * CGFloat(dt)
            let sway = sin(mote.age * 2 * .pi / mote.period + mote.phase)
            mote.position.x = mote.baseX + mote.sway * CGFloat(sway)
            if mote.position.y < -mote.radius {
                mote.position.y = size.height + mote.radius
            }
            motes[index] = mote
        }
    }

    private func spawnAmbientBubbleIfDue(_ dt: Double) {
        ambientBubbleCountdown -= dt
        guard ambientBubbleCountdown <= 0 else { return }
        ambientBubbleCountdown = Double.random(in: ArenaConfig.ambientBubbleGap)
        guard ambientBubbles.count < ArenaConfig.maximumAmbientBubbles,
              size.width > 0, arena.height > 0 else { return }

        let inset = ArenaConfig.sideInset(isPad: isPad)
            + ArenaConfig.ambientBubbleRadius.upperBound
        let x = CGFloat.random(in: inset...max(inset, size.width - inset))
        ambientBubbles.append(ReefAmbientBubble(
            baseX: x,
            position: CGPoint(x: x, y: arena.maxY - CGFloat.random(in: 0...40)),
            radius: CGFloat.random(in: ArenaConfig.ambientBubbleRadius),
            speed: CGFloat.random(in: ArenaConfig.ambientBubbleSpeed),
            phase: Double.random(in: 0..<(2 * .pi))
        ))
    }

    private func moveAmbientBubbles(_ dt: Double) {
        for index in ambientBubbles.indices {
            ambientBubbles[index].age += dt
            if let popAge = ambientBubbles[index].popAge {
                ambientBubbles[index].popAge = popAge + dt
                continue
            }
            ambientBubbles[index].position.y -= ambientBubbles[index].speed * CGFloat(dt)
            ambientBubbles[index].position.x = ambientBubbles[index].baseX
                + CGFloat(sin(ambientBubbles[index].age * 2.4
                              + ambientBubbles[index].phase)) * 8
        }
        ambientBubbles.removeAll { bubble in
            if let popAge = bubble.popAge {
                return popAge >= ArenaConfig.ambientBubblePopDuration
            }
            return bubble.position.y < -bubble.radius * 2
        }
    }

    // MARK: Level completion

    private func moveLevelCompletion(_ dt: Double) {
        guard let elapsed = completionElapsed else { return }
        let next = elapsed + dt

        if !reducesCompletionMotion {
            completionSpeckCountdown -= dt
            if completionSpeckCountdown <= 0 {
                completionSpeckCountdown = ArenaPerformanceBudget.celebrationInterval
                spawnCelebrationSpeck()
            }
        }
        moveCelebration(dt)

        completionElapsed = next
        let duration = reducesCompletionMotion ? 0.9 : ArenaConfig.completionDuration
        if next >= duration {
            completionElapsed = nil
            king.isCheering = false
            king.sweepAge = nil
            // The card is coming up over the last of his run, so he is marked
            // gone here rather than waiting for the run to finish under it.
            king.hasLeft = !reducesCompletionMotion
            king.farewellAge = nil
            placeKing(0)
            let callback = completionCallback
            completionCallback = nil
            callback?()
        }
    }

    private func spawnCelebrationSpeck() {
        guard size.width > 0,
              celebration.count < ArenaPerformanceBudget.celebrationSpeckCap else { return }
        let x = CGFloat.random(in: 0...size.width)
        celebration.append(CelebrationSpeck(
            position: CGPoint(x: x, y: arena.maxY + 10),
            radius: CGFloat.random(in: isPad ? 6...16 : 5...12),
            speed: CGFloat.random(in: 110...230),
            phase: Double.random(in: 0..<(2 * .pi)),
            // Roughly one in three is a shell, so the finale reads as the
            // currency being showered rather than as plain bubbles.
            kind: Int.random(in: 0..<3) == 0 ? .shell : .bubble
        ))
    }

    private func moveCelebration(_ dt: Double) {
        for index in celebration.indices {
            celebration[index].age += dt
            celebration[index].position.y -= celebration[index].speed * CGFloat(dt)
            celebration[index].position.x += CGFloat(sin(
                celebration[index].age * 3 + celebration[index].phase
            )) * CGFloat(dt) * 11
        }
        celebration.removeAll { $0.position.y < -$0.radius * 2 }
    }
}
