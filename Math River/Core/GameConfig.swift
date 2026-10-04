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

    /// Every exercise uses the same short, predictable run. Order, Random and
    /// Mixed change the question sequence, never how long the child has to play.
    public static let sessionQuestionCount = 12
    public static var maximumRoundCeiling: Int { sessionQuestionCount }

    /// One correct answer advances the session score by one and also earns one
    /// unit of honey when the run is completed.
    public static let normalCardReward = 1
    public static let honeyPerCorrectAnswer = 1

    // MARK: Bonuses

    /// Honey Flow rewards three consecutive correct answers without changing
    /// the physical or reading speed of the next answer phase.
    public static let honeyFlowThreshold = 3
    public static let honeyFlowBonusHoney = 2
    public static let honeyFlowTrailDuration = 2.6

    /// Compatibility values for the retired King Crab boost wiring.
    public static let streakThreshold = honeyFlowThreshold
    public static let streakMultiplier = 2
    public static let streakSpeedMultiplier = 1.0
    public static let streakWrongAnswerCostHalves = 1
    public static let bonusFishCount = 0...0
    public static let bonusFishMultiplier = 1

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
    /// A wrong answer writes out the complete solved equation and may be read
    /// aloud. Keep it visible long enough to understand, without holding up a
    /// correct answer or changing the approach speed.
    public static let wrongFeedbackDuration = 1.15
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
        0,          // starter — from the start
        500,        // second character
        1_500,      // third
        3_000,      // fourth
        5_000,      // fifth
        nil, nil, nil, nil, nil   // remaining five — Premium
    ]

    // MARK: Math River

    /// Seconds from the moment a honey-pot group is on screen until the first
    /// pot reaches the boat. The player reads the sum in this window.
    public static let riverApproachDuration = 4.0
    /// Bounds around the adaptive reading window. The slide may look fast, but
    /// a child never has to solve a sum as a split-second reaction test.
    public static let riverMinimumApproachDuration = 3.5
    public static let riverMaximumApproachDuration = 5.4
    /// The opening rounds teach the rhythm before the run starts tightening.
    public static let riverFirstRoundWarmup = 0.8
    public static let riverSecondRoundWarmup = 0.4
    /// Amount removed gradually between the opening and final round.
    public static let riverSessionPressure = 0.5
    /// Fractions and percentages need an extra reading beat even when their
    /// arithmetic happens to be easy.
    public static let riverFractionReadingBonus = 0.55
    public static let riverPercentageReadingBonus = 0.35
    public static let riverLongPromptThreshold = 13
    public static let riverLongPromptReadingBonus = 0.2
    /// Quiet water after the last pot of a group has gone by, before the next
    /// sum appears.
    public static let riverGroupGap = 1.25
    /// A wrong answer earns no point, but never removes a correct answer that
    /// was already earned. Mastery therefore always means “questions correct”.
    public static let riverWrongAnswerPenalty = 0

    // MARK: Level progress

    /// Kept solely to translate version-4 personal bests to the new twelve-
    /// question mastery scale. New gameplay never uses these as run lengths.
    public static let legacyOrderLevelMaximum = 20
    public static let legacyRandomLevelMaximum = 30
    public static let legacyMixedLevelMaximum = 40
    public static let legacySupermixLevelMaximum = 50

    /// Compatibility names for code and QA that asks for the largest possible
    /// board. All exercise forms now have the same length.
    public static let orderLevelMaximum = sessionQuestionCount
    public static let randomLevelMaximum = sessionQuestionCount
    public static let mixedLevelMaximum = sessionQuestionCount
    public static let supermixLevelMaximum = sessionQuestionCount
    public static let levelMaximum = sessionQuestionCount

    /// Ceiling on the "reached the maximum ×N" tally, so a long-lived save
    /// cannot grow the badge without bound.
    public static let maximumCompletionCount = 100

    /// Bronze, silver and gold mastery: 8, 10 and 12 correct answers.
    public static let masteryThresholds = [8, 10, 12]
    public static let levelTierShares = masteryThresholds.map {
        Double($0) / Double(sessionQuestionCount)
    }

    // MARK: Storage

    /// Bumped whenever the persisted shape changes; drives migration.
    public static let storageVersion = 5
}
