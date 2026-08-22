//
//  GameConfig.swift
//  Elephant Challenge: Math Memory
//
//  The single source of truth for every tunable gameplay number. Nothing in the
//  game may hardcode a life count, a probability, a duration or an unlock
//  requirement — it is declared here and read from here.
//

import Foundation

// MARK: - Central configuration

nonisolated public enum GameConfig {

    // MARK: Answers

    /// How many answers a question offers. One fixed number for every topic and
    /// every combination: one crab walks in from each of the four corners, so a
    /// wave is always one right answer and three wrong ones. It used to be a
    /// choice between two, three and four, which made every level three
    /// separate scoreboards aiming at three different targets — see
    /// `migrateToFixedAnswerCount` for how those were merged back into one.
    public static let answerBubbleCount = 4

    /// Wrong answers a question must supply: every bubble but the right one.
    public static var distractorCount: Int { answerBubbleCount - 1 }

    // MARK: Lives

    /// Lives a session starts with. Lives are tracked internally in half units.
    public static let startingLives = 3.0
    /// Smashing the crab that carries the right answer costs one whole life.
    public static let wrongAnswerCost = 1.0

    /// Internal granularity: lives are stored as an integer number of halves,
    /// so no floating point rounding can ever strand the player on 0.4999
    /// lives.
    public static let lifeGranularity = 2
    public static var startingLifeHalves: Int { Int(startingLives * Double(lifeGranularity)) }
    public static var wrongAnswerCostHalves: Int { Int(wrongAnswerCost * Double(lifeGranularity)) }

    // MARK: King Crab

    /// How long a crab needs from its corner to the King. The whole round is
    /// read, judged and acted on inside this window, so it is the single most
    /// important number of the game.
    public static let crabWalkDuration = 6.0

    /// A crab carrying a wrong answer that reaches the King costs half a life.
    /// The round itself carries on: the right answer is still out there.
    public static let breachCostHalves = 1

    // MARK: Life crab

    /// The comeback crab appears at most once a game, and only from the moment
    /// the player first drops to this many half-lives (one life) or fewer.
    public static let lifeCrabCriticalHalves = 2
    /// Correct answers required after that drop before it may set off, so the
    /// reward follows recovered play rather than the damage itself.
    public static let lifeCrabCorrectAnswers = 2
    /// It never appears once the board is this far along — a comeback near the
    /// finish line is no comeback at all.
    public static let lifeCrabMaximumProgress = 0.9
    /// Reaching the King hands back one whole life.
    public static let lifeCrabRecoveryHalves = 2

    // MARK: Session

    /// A session ends when the board's own target is reached (`LevelBoard
    /// .maximum`) or the lives run out — never on a flat round count, which is
    /// what used to stop a 50-bubble board at around 24.
    ///
    /// Every round pays at least one bubble, so a board can always be filled
    /// within `maximum` rounds. This is the ceiling across every board, used
    /// only to sanity-check a stored session.
    public static var maximumRoundCeiling: Int { supermixLevelMaximum }

    /// Cards awarded for a correct answer on a normal card.
    public static let normalCardReward = 1

    // MARK: Bonuses

    /// Five correct answers in a row turn the crabs gold: the streak mode
    /// pays double and lasts until the next mistake. Five rather than three
    /// makes it a run the player has to actually string together, which is
    /// what earns the King his celebration when it lands.
    public static let streakThreshold = 5
    public static let streakMultiplier = 2
    /// The gold crabs march a little faster, so the doubled points are earned
    /// under real pressure rather than handed over.
    public static let streakSpeedMultiplier = 1.3
    /// The first mistake while the streak boost is active breaks the streak,
    /// but only costs half a life instead of a full one.
    public static let streakWrongAnswerCostHalves = 1

    /// A 2x crab scuttles across the level this many times. Tapping it doubles
    /// the next correct answer; a missed one simply leaves the screen.
    public static let bonusFishCount = 1...3
    public static let bonusFishMultiplier = 2

    // MARK: Timing (seconds)
    //
    // The brief is explicit: the next round must be able to start within
    // roughly 300–600 ms. These are the only durations gameplay may use.

    /// Card flip animation.
    public static let cardFlipDuration = 0.28
    /// Answer cards fading/scaling in once the question is visible.
    public static let answerRevealDuration = 0.18
    /// How long correct/wrong feedback stays on screen before the next round.
    public static let correctFeedbackDuration = 0.32
    public static let wrongFeedbackDuration = 0.55
    /// Gap between feedback ending and the next round's closed cards appearing.
    public static let roundTransitionDuration = 0.12

    /// Total time from answering to the next round being interactive.
    public static var nextRoundDelay: (correct: Double, wrong: Double) {
        (correctFeedbackDuration + roundTransitionDuration,
         wrongFeedbackDuration + roundTransitionDuration)
    }

    // MARK: Levels

    /// Levels available without Premium.
    public static let freeLevelCount = 12
    /// Highest level Premium unlocks.
    public static let maximumLevel = 99

    /// How strongly question selection leans toward the highest available
    /// sub-level. Weight of sub-level i (1-based) is `i ^ levelWeightExponent`,
    /// so lower levels stay in the mix but the top of the range dominates.
    public static let levelWeightExponent = 1.0
    /// The selected level itself is guaranteed at least this share of rounds,
    /// so "the highest available difficulty appears regularly" is not left to
    /// chance on a level-40 run.
    public static let topLevelMinimumShare = 0.35

    // MARK: Characters

    /// Total earned cards required to unlock each character, in catalog order.
    /// Index 0 is the starter character and is therefore always 0.
    ///
    /// The second half of the catalog is Premium-exclusive: `nil` means the
    /// character cannot be earned with cards at all, no matter the total.
    public static let characterUnlockRequirements: [Int?] = [
        0,          // crab — from the start
        500,        // elephant
        1_500,      // bear
        3_000,      // fox
        5_000,      // frog
        nil, nil, nil, nil, nil   // penguin, bunny, dog, lion, octopus — Premium
    ]

    // MARK: Level progress

    /// What a full score is worth depends on the chosen exercise. Supermix is
    /// intentionally the only route that goes all the way to 50 bubbles.
    public static let orderLevelMaximum = 20
    public static let randomLevelMaximum = 30
    public static let mixedLevelMaximum = 40
    public static let supermixLevelMaximum = 50

    /// Default used by views before they receive their concrete board.
    public static let levelMaximum = mixedLevelMaximum

    /// Ceiling on the "reached the maximum ×N" tally, so a long-lived save
    /// cannot grow the badge without bound.
    public static let maximumCompletionCount = 100

    /// The three progress dots fill at these shares of `levelCompletionCards`,
    /// so the card art follows the economy instead of hardcoded scores.
    public static let levelTierShares = [0.01, 0.4, 0.75]

    // MARK: Storage

    /// Bumped whenever the persisted shape changes; drives migration.
    public static let storageVersion = 4
}
