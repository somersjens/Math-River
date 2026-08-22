//
//  MemoryGame.swift
//  Elephant Challenge: Math Memory
//
//  The session state machine. Every rule that decides what a tap does lives
//  here, and every transition is guarded by the current state — that is what
//  makes double taps, double scoring and double life loss impossible.
//
//  This type is deliberately free of SwiftUI and of timers: the view drives it
//  with explicit calls and asks it what to show. That keeps it fully testable.
//
//  The King Crab arena uses the same state machine: it opens a round straight
//  through `turnCardsOver` and `beginAnswering` — there is nothing to memorise
//  on the sea floor — and then reports the three things that can happen to a
//  wave of crabs: the guarded answer arrives (`select`), the player smashes it
//  themselves (`smashGuardedAnswer`), or a wrong answer slips through to the
//  King (`absorbBreach`).
//

import Foundation

// MARK: - State

nonisolated public enum GameState: String, Equatable, Sendable {
    /// Session created, nothing shown yet.
    case intro
    /// The answer cards lie face up: this is the memorising beat. The question
    /// is still hidden, and a tap turns the cards over.
    case memorising
    /// The cards are mid-flip: they are turning face down while the question
    /// comes up. No input is accepted during the turn.
    case questionVisible
    /// The cards are face down and the question is readable. Exactly one tap
    /// is accepted — the player must remember where the answer was.
    case answering
    /// An answer was taken: feedback is showing, input is locked.
    case resolving
    /// Feedback finished; the next round can be installed.
    case roundComplete
    /// Out of lives, or the round limit was reached.
    case gameOver
}

nonisolated public enum GameOverReason: String, Equatable, Sendable {
    case outOfLives
    case roundsCompleted
    case quit
}

/// What resolving a tap produced, so the view knows which feedback to play.
nonisolated public enum AnswerOutcome: Equatable, Sendable {
    case correct(cardsEarned: Int, usedBonusFish: Bool, startedStreak: Bool)
    case wrong(correctOptionID: UUID, lostHalfLife: Bool)
    /// The tap was ignored (wrong state, or the round was already answered).
    case ignored
}

/// What a wrong answer reaching the King cost. The round is deliberately not
/// ended by one: the crab carrying the right answer is still walking.
nonisolated public enum BreachOutcome: Equatable, Sendable {
    /// Half a life spent; `endsSession` is true when it was the last one.
    case absorbed(endsSession: Bool)
    /// The breach arrived in a state that no longer takes damage.
    case ignored
}

// MARK: - Result

nonisolated public struct SessionResult: Equatable, Sendable {
    public var correctAnswers = 0
    public var wrongAnswers = 0
    public var cardsEarned = 0
    /// Cards awarded over and above the normal one-bubble reward.
    public var bonusCards = 0
    /// Kept under its persisted name for save compatibility; now counts caught
    /// 2x fish whose bonus was paid out.
    public var doubleCardsAnswered = 0
    public var isNewPersonalBest = false
    public var previousPersonalBest = 0
    public var unlockedCharacterIDs: [String] = []
    public var reason: GameOverReason = .roundsCompleted

    public init() {}
}

// MARK: - Engine

nonisolated public final class MemoryGame {
    // MARK: Configuration

    public let level: MathLevel
    /// Which scoreboard this session plays on, so a paused run can only ever be
    /// resumed onto the exact board it came from.
    public let board: LevelBoard
    private let factory: RoundFactory

    // MARK: Observable state (read by the view)

    public private(set) var state: GameState = .intro
    public private(set) var round: GameRound?
    /// The round after this one, built ahead of time so a transition never
    /// waits on generation.
    private var preparedRound: GameRound?

    public private(set) var roundNumber = 0
    public private(set) var cards = 0
    /// Lives in half units. 6 == three lives.
    public private(set) var lifeHalves = GameConfig.startingLifeHalves
    /// The option the player tapped this round, if any.
    public private(set) var selectedOptionID: UUID?
    public private(set) var lastOutcome: AnswerOutcome?
    public private(set) var result = SessionResult()
    public private(set) var correctStreak = 0
    /// Correct answers given since the player first dropped to their last life.
    public private(set) var lifeCrabProgress = 0
    public private(set) var lifeCrabTarget = GameConfig.lifeCrabCorrectAnswers
    /// True once the comeback crab may set off from a corner.
    public private(set) var isLifeCrabAvailable = false
    /// The comeback happens at most once a game, whether or not it was used.
    public private(set) var hasSpentLifeCrab = false
    /// Set the first time the player is down to a single life, which is what
    /// starts counting toward the comeback.
    private var isCounting = false

    /// Set once the session is over; nil while playing.
    public private(set) var gameOverReason: GameOverReason?

    /// Smashing the guarded answer costs a life but leaves the sum standing:
    /// a fresh wave of crabs carries the same answers around again. Only a
    /// safe arrival moves the session on to the next sum.
    private var repeatsRound = false

    /// Whether this sum has already been charged for a crab getting through.
    /// One sum costs half a life however many wrong answers reach the King on
    /// it: three crabs walking past — together in one sweep, or one after the
    /// other across the same wave — is one mistake, not three.
    private var hasBreachedRound = false

    /// The walkthrough's first steps let a mistake be made without paying for
    /// it. Every other run, and every later step, leaves this on — the rule
    /// itself is unchanged, it is only waived while the player is being shown
    /// what the crabs are.
    public var appliesWrongAnswerPenalty = true

    // MARK: Derived

    public var livesRemaining: Double {
        Double(lifeHalves) / Double(GameConfig.lifeGranularity)
    }

    /// Rounds this board can run to. Every round pays at least one bubble, so
    /// the target is always reachable inside this many.
    public var maximumRounds: Int { board.maximum }

    /// Whether a tap on an answer card can be accepted right now.
    public var acceptsInput: Bool { state == .answering }
    public var isStreakBoostActive: Bool { correctStreak >= GameConfig.streakThreshold }

    /// Whether the answer values are readable. They are during the memorising
    /// beat, and again while the round resolves so the player can see what they
    /// picked and where the right card was.
    public var showsAnswerValues: Bool {
        state == .memorising || state == .resolving || state == .roundComplete
    }

    /// Whether the question is readable. It appears only once the cards are
    /// face down, which is what makes this a memory game.
    public var showsQuestion: Bool {
        state != .intro && state != .memorising
    }

    // MARK: Init

    public init(level: MathLevel,
                mixedVariant: MixedVariant = .all,
                mode: PracticeMode = .mixed,
                seed: UInt64? = nil) {
        self.level = level
        self.board = LevelBoard(level: level,
                                mixedVariant: mixedVariant,
                                mode: mode)
        self.factory = RoundFactory(level: level,
                                    mixedVariant: mixedVariant,
                                    mode: board.mode,
                                    seed: seed)
    }

#if DEBUG
    /// Predetermined rounds for the App Store teaser. Production play never
    /// installs these; `advance` finishes the board after the last one rather
    /// than asking the factory for another sum.
    private var promoRounds: [GameRound] = []
    private var promoRoundIndex = 0
    private var promoFinishesAfterLast = false

    /// Opens a scripted session already on the first sum, with the score and
    /// streak the trailer needs, then plays by the ordinary rules.
    public func installPromoSession(cards: Int,
                                    streak: Int,
                                    rounds: [GameRound]) {
        guard !rounds.isEmpty else { return }
        promoRounds = rounds
        promoRoundIndex = 0
        promoFinishesAfterLast = true
        self.cards = max(0, cards)
        correctStreak = max(0, streak)
        result.cardsEarned = self.cards
        roundNumber = 1
        round = rounds[0]
        preparedRound = rounds.count > 1 ? rounds[1] : nil
        state = .memorising
    }
#endif

    // MARK: - Session lifecycle

    /// Starts the session and deals the first round's answer cards face up.
    @discardableResult
    public func start() -> Bool {
        guard state == .intro else { return false }
        roundNumber = 1
        round = factory.makeRound(number: 1)
        preparedRound = factory.makeRound(number: 2)
        state = .memorising
        return true
    }

    /// Resumes a level the player left part-way through, restoring the cards,
    /// lives and round they stopped on. Rejected if the record is not playable.
    @discardableResult
    public func resume(from session: PausedSession) -> Bool {
        guard state == .intro, session.isResumable else { return false }
        roundNumber = session.roundNumber
        cards = session.cards
        lifeHalves = session.lifeHalves
        result.correctAnswers = session.correctAnswers
        result.wrongAnswers = session.wrongAnswers
        result.doubleCardsAnswered = session.doubleCardsAnswered
        result.bonusCards = session.bonusCards
        result.cardsEarned = session.cards
        correctStreak = session.correctStreak ?? 0
        lifeCrabProgress = session.heartFishProgress ?? 0
        lifeCrabTarget = session.heartFishTarget ?? GameConfig.lifeCrabCorrectAnswers
        isLifeCrabAvailable = session.isHeartFishAvailable ?? false
        hasSpentLifeCrab = session.hasSpentLifeCrab ?? false
        // A run resumed on its last life keeps counting toward the comeback
        // rather than waiting for a drop that already happened.
        isCounting = lifeHalves <= GameConfig.lifeCrabCriticalHalves
        round = factory.makeRound(number: roundNumber)
        preparedRound = factory.makeRound(number: roundNumber + 1)
        state = .memorising
        return true
    }

    /// A snapshot of the session as it stands, for storing when the player
    /// leaves. Nil once the session is over — there is nothing to come back to.
    public func pausedSession(hasBonusFishPower: Bool = false) -> PausedSession? {
        guard state != .intro, state != .gameOver else { return nil }
        return PausedSession(boardID: board.storageID,
                             roundNumber: roundNumber,
                             cards: cards,
                             lifeHalves: lifeHalves,
                             correctAnswers: result.correctAnswers,
                             wrongAnswers: result.wrongAnswers,
                             doubleCardsAnswered: result.doubleCardsAnswered,
                             bonusCards: result.bonusCards,
                             // Legacy field: the helper it counted is gone.
                             flamethrowersUsed: 0,
                             correctStreak: correctStreak,
                             hasBonusFishPower: hasBonusFishPower,
                             // Legacy field names: they now carry the life
                             // crab's meter, so old saves stay decodable.
                             heartFishProgress: lifeCrabProgress,
                             heartFishTarget: lifeCrabTarget,
                             isHeartFishAvailable: isLifeCrabAvailable,
                             hasSpentLifeCrab: hasSpentLifeCrab)
    }

    /// The tap that turns the answer cards face down and brings the question
    /// up. From here on the player is working from memory.
    @discardableResult
    public func turnCardsOver() -> Bool {
        guard state == .memorising else { return false }
        state = .questionVisible
        return true
    }

    /// Called once the cards have finished turning. From here the round accepts
    /// exactly one answer.
    @discardableResult
    public func beginAnswering() -> Bool {
        guard state == .questionVisible else { return false }
        state = .answering
        return true
    }

    // MARK: - Answering

    /// Resolves an answer reaching the King. Anything that arrives in the wrong
    /// state — a second arrival in the same round, an arrival during feedback —
    /// is ignored without touching score or lives.
    @discardableResult
    public func select(optionID: UUID, usesBonusFish: Bool = false) -> AnswerOutcome {
        guard state == .answering,
              let round,
              selectedOptionID == nil,
              let option = round.options.first(where: { $0.id == optionID })
        else {
            // Deliberately leaves `lastOutcome` alone: an ignored tap must not
            // disturb the feedback the view is currently showing.
            return .ignored
        }

        // Lock input for the whole of the resolve phase, before any scoring.
        selectedOptionID = optionID
        state = .resolving

        let outcome: AnswerOutcome
        if option.isCorrect {
            let streakWasActive = isStreakBoostActive
            let fishMultiplier = usesBonusFish ? GameConfig.bonusFishMultiplier : 1
            let streakMultiplier = streakWasActive ? GameConfig.streakMultiplier : 1
            let earned = GameConfig.normalCardReward * fishMultiplier * streakMultiplier
            cards += earned
            result.correctAnswers += 1
            result.cardsEarned += earned
            if usesBonusFish {
                result.doubleCardsAnswered += 1
            }
            result.bonusCards += earned - GameConfig.normalCardReward
            correctStreak += 1
            advanceLifeCrabProgressIfNeeded()
            let startedStreak = !streakWasActive && isStreakBoostActive
            outcome = .correct(cardsEarned: earned,
                               usedBonusFish: usesBonusFish,
                               startedStreak: startedStreak)
        } else {
            outcome = penaliseGuardedAnswer(correctOptionID:
                                                round.correctOption?.id ?? optionID)
        }
        lastOutcome = outcome
        return outcome
    }

    /// The player smashed the crab carrying the right answer. It costs a whole
    /// life and the attempt is over at once, but the sum still moves on to a
    /// fresh one — the player has already seen this exact sum and its answer,
    /// so bringing it straight back would just be asking the same question
    /// again rather than testing anything new.
    @discardableResult
    public func smashGuardedAnswer() -> AnswerOutcome {
        guard state == .answering,
              let round,
              selectedOptionID == nil,
              let correct = round.correctOption
        else { return .ignored }

        selectedOptionID = correct.id
        state = .resolving
        let outcome = penaliseGuardedAnswer(correctOptionID: correct.id, repeatsRound: false)
        lastOutcome = outcome
        return outcome
    }

    /// Shared by both ways of losing the right answer: the whole life and the
    /// broken streak. `repeatsRound` decides whether the same sum comes back
    /// (a plain wrong tap, which has not revealed the right answer) or a fresh
    /// one is installed (the guarded answer was smashed directly, which has).
    private func penaliseGuardedAnswer(correctOptionID: UUID, repeatsRound: Bool = true) -> AnswerOutcome {
        result.wrongAnswers += 1
        correctStreak = 0
        if appliesWrongAnswerPenalty {
            // Deliberately the full cost even mid-streak: destroying the answer
            // the King was waiting for is the one mistake that always hurts.
            spendLifeHalves(GameConfig.wrongAnswerCostHalves)
        }
        self.repeatsRound = repeatsRound
        return .wrong(correctOptionID: correctOptionID, lostHalfLife: false)
    }

    /// A crab carrying a wrong answer walked past the player and reached the
    /// King. It costs half a life and breaks the streak, but the round carries
    /// on: the right answer is still on its way.
    ///
    /// Only the first one on a sum is paid for. A wave the player misses
    /// entirely used to empty a life and a half between two sums, which is a
    /// punishment out of all proportion to one lapse of attention — so every
    /// further crab on the same sum walks past for nothing.
    @discardableResult
    public func absorbBreach() -> BreachOutcome {
        guard state == .answering || state == .resolving,
              lifeHalves > 0,
              !hasBreachedRound else { return .ignored }
        hasBreachedRound = true
        result.wrongAnswers += 1
        correctStreak = 0
        if appliesWrongAnswerPenalty {
            spendLifeHalves(GameConfig.breachCostHalves)
        }
        guard lifeHalves > 0 else {
            finish(reason: .outOfLives)
            return .absorbed(endsSession: true)
        }
        return .absorbed(endsSession: false)
    }

    /// Restores a whole life when the comeback crab reaches the King. The
    /// return value is the number of half-hearts restored, or zero when the
    /// arrival was stale.
    @discardableResult
    public func catchLifeCrab() -> Int {
        guard isLifeCrabAvailable,
              lifeHalves > 0,
              lifeHalves < GameConfig.startingLifeHalves else { return 0 }
        let previous = lifeHalves
        lifeHalves = min(GameConfig.startingLifeHalves,
                         lifeHalves + GameConfig.lifeCrabRecoveryHalves)
        spendLifeCrab()
        return lifeHalves - previous
    }

    /// Hands the life crab its cue directly, which is what the walkthrough's
    /// step needs: there the crab is the lesson, not a reward that has to be
    /// earned back from the brink first.
    public func makeLifeCrabAvailable() {
        guard state != .gameOver, lifeHalves > 0 else { return }
        isCounting = true
        lifeCrabProgress = lifeCrabTarget
        isLifeCrabAvailable = true
    }

    /// Called once the comeback has happened — it cannot happen twice in a game.
    public func spendLifeCrab() {
        hasSpentLifeCrab = true
        isLifeCrabAvailable = false
        lifeCrabProgress = 0
    }

    // MARK: - Round transitions

    /// Called by the view when the feedback animation has finished.
    @discardableResult
    public func finishResolving() -> Bool {
        guard state == .resolving else { return false }
        state = .roundComplete
        return true
    }

    /// Installs the next round, puts the current one back into play after a
    /// wrong answer, or ends the session. Returns the new state.
    @discardableResult
    public func advance() -> GameState {
        guard state == .roundComplete else { return state }

        // Whatever comes next is a fresh attempt, and pays for its own breach.
        hasBreachedRound = false

        if lifeHalves <= 0 {
            finish(reason: .outOfLives)
            return state
        }
        // A missed answer does not use up a round: the same sum comes straight
        // back, with the life already paid for it.
        if repeatsRound {
            repeatsRound = false
            selectedOptionID = nil
            lastOutcome = nil
            state = .answering
            return state
        }
        // The board is full: this is what "level complete" means, and it is
        // what the target quoted on the start and result cards refers to.
        if cards >= board.maximum {
            finish(reason: .roundsCompleted)
            return state
        }
        if roundNumber >= maximumRounds {
            finish(reason: .roundsCompleted)
            return state
        }

#if DEBUG
        if promoFinishesAfterLast, promoRoundIndex + 1 >= promoRounds.count {
            finish(reason: .roundsCompleted)
            return state
        }
#endif

        roundNumber += 1
#if DEBUG
        if promoFinishesAfterLast, !promoRounds.isEmpty {
            promoRoundIndex += 1
            round = promoRounds[promoRoundIndex]
            preparedRound = promoRoundIndex + 1 < promoRounds.count
                ? promoRounds[promoRoundIndex + 1]
                : nil
            selectedOptionID = nil
            lastOutcome = nil
            state = .memorising
            return state
        }
#endif
        round = preparedRound ?? factory.makeRound(number: roundNumber)
        // Build the round after next while the player is looking at this one.
        preparedRound = factory.makeRound(number: roundNumber + 1)
        selectedOptionID = nil
        lastOutcome = nil
        state = .memorising
        return state
    }

    /// Ends the session early (the player left the game screen).
    public func quit() {
        guard state != .gameOver else { return }
        finish(reason: .quit)
    }

    // MARK: - Private

    private func spendLifeHalves(_ halves: Int) {
        lifeHalves = max(0, lifeHalves - halves)
        // The first drop to the last life — whether it lands on one life or on
        // a half — is what opens the comeback window.
        if !isCounting, lifeHalves > 0, lifeHalves <= GameConfig.lifeCrabCriticalHalves {
            isCounting = true
            lifeCrabProgress = 0
            lifeCrabTarget = GameConfig.lifeCrabCorrectAnswers
        }
    }

    /// Counts the correct answers that follow the drop to the last life. The
    /// crab only sets off once the player has genuinely steadied — and never on
    /// a board that is all but finished, where a spare life buys nothing.
    private func advanceLifeCrabProgressIfNeeded() {
        guard isCounting,
              !hasSpentLifeCrab,
              !isLifeCrabAvailable,
              lifeHalves > 0,
              lifeHalves < GameConfig.startingLifeHalves else { return }
        lifeCrabProgress += 1
        guard lifeCrabProgress >= lifeCrabTarget else { return }
        let progressShare = Double(cards) / Double(max(1, board.maximum))
        guard progressShare < GameConfig.lifeCrabMaximumProgress else { return }
        isLifeCrabAvailable = true
    }

    private func finish(reason: GameOverReason) {
        gameOverReason = reason
        result.reason = reason
        state = .gameOver
    }

    /// Fills in the persistence-derived parts of the result. Called by the view
    /// model once the score has been recorded, so the engine itself stays free
    /// of storage concerns.
    public func applyProgressOutcome(previousBest: Int,
                                     isNewPersonalBest: Bool,
                                     unlockedCharacterIDs: [String]) {
        result.previousPersonalBest = previousBest
        result.isNewPersonalBest = isNewPersonalBest
        result.unlockedCharacterIDs = unlockedCharacterIDs
    }
}
