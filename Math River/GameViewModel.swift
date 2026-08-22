//
//  GameViewModel.swift
//  Elephant Challenge: Math Memory
//
//  The bridge between the pure `MemoryGame` engine and SwiftUI. It owns the
//  timing of a round (sum → answers → feedback → next sum), the audio and
//  haptics, and the persistence of a finished session.
//
//  It never re-implements a rule: every tap is forwarded to the engine, and the
//  engine's answer decides what happens. That is what keeps rapid tapping from
//  scoring twice or costing two lives.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// A sum that was lost, written out with the answer it wanted.
///
/// A fresh sum arriving on its own tells a child nothing about the one they
/// just got wrong: the crabs dig themselves in, the question changes, and the
/// only trace of the mistake is half a heart fewer. This is that trace made
/// readable — the sum, and the answer it was waiting for — and it is carried
/// under the next sum for exactly that one round.
struct MissedSum: Equatable {
    /// The sum with its answer filled in, e.g. "7 × 8 = 56".
    let text: String
    /// The round it was lost on. It must never be shown under that round: the
    /// sum is still standing there, and the answer would simply be given away.
    fileprivate let missedRoundID: UUID?
    /// The round it is being shown under, taken the moment the next sum
    /// arrives. It leaves when that round does.
    fileprivate var shownRoundID: UUID?
}

@MainActor
final class GameViewModel: ObservableObject {
    private let request: GameSessionRequest
    private var engine: MemoryGame

    /// `MemoryGame` is built on a worker and then transferred exactly once to
    /// the main actor. It is never read on both executors at the same time.
    private struct PreparedEngine: @unchecked Sendable {
        let engine: MemoryGame
        let pausedSession: PausedSession?
    }
    private var preparationTask: Task<PreparedEngine, Never>?

    // Published mirrors of the engine, so SwiftUI observes value changes.
    @Published private(set) var state: GameState = .intro
    @Published private(set) var round: GameRound?
    @Published private(set) var roundNumber = 0
    @Published private(set) var cards = 0
    @Published private(set) var livesRemaining = GameConfig.startingLives
    @Published private(set) var selectedOptionID: UUID?
    @Published private(set) var isGameOver = false
    @Published private(set) var result = SessionResult()
    @Published private(set) var hasBonusFishPower = false
    @Published private(set) var correctStreak = 0
    @Published private(set) var isStreakBoostActive = false
    @Published private(set) var isLifeCrabAvailable = false
    /// The sum the player just lost, held under the one that replaced it so a
    /// mistake is never silent. Nil whenever there is nothing to own up to.
    @Published private(set) var missedSum: MissedSum?
    /// The same note while the sum it belongs to is still standing: it is not
    /// shown yet, because its answer is the one thing that must not be given
    /// away in the moment between the mistake and the next question.
    private var pendingMissedSum: MissedSum?
    /// Changes each time the streak boost starts, allowing the view to replay
    /// its banner announcement even after an earlier streak was broken.
    @Published private(set) var streakAnnouncementID = 0

    /// Set by the tutorial, which needs to know about every answer the moment
    /// the engine accepts it — that is what moves its script on.
    var onAnswerResolved: ((_ isCorrect: Bool, _ startedStreak: Bool) -> Void)?

    /// Invalidates pending timed work when a round is superseded (restart, or
    /// leaving the screen), so a late callback can never touch a newer round.
    private var generation = 0
    private var hasRecordedResult = false
    private var isPaused = false
#if DEBUG
    /// Trailer sessions must not write to the player's save.
    var skipsPersistence = false
#endif
    /// A round-resolution callback that became due while the pause card was
    /// covering the arena. It runs once on continue instead of behind the card.
    private var pendingScheduledWork: (() -> Void)?
    /// The rules award shells immediately, while the HUD waits until the
    /// matching shell physically reaches it.
    private var pendingScoreRewards: [Int] = []

    var maximumRounds: Int { engine.maximumRounds }
    var acceptsInput: Bool { state == .answering && !isPaused }

    init(request: GameSessionRequest) {
        self.request = request
        self.engine = MemoryGame(level: request.level,
                            mixedVariant: request.mixedVariant,
                            mode: request.mode)
    }

    // MARK: - Lifecycle

    /// Builds the first two rounds while the level card (and then the King's
    /// entrance) is still on screen. Round generation is pure CPU work and
    /// does not belong on the frame that responds to Start.
    func prepare() {
        guard engine.state == .intro, preparationTask == nil else { return }
        startPreparation(pausedSession: PausedSessionStore.shared.session(request.board))
    }

    private func startPreparation(pausedSession: PausedSession?) {
        guard preparationTask == nil else { return }
        let level = request.level
        let mixedVariant = request.mixedVariant
        let mode = request.mode
        preparationTask = Task.detached(priority: .userInitiated) {
            let prepared = MemoryGame(level: level,
                                      mixedVariant: mixedVariant,
                                      mode: mode)
            if let pausedSession {
                prepared.resume(from: pausedSession)
            } else {
                prepared.start()
            }
            return PreparedEngine(engine: prepared, pausedSession: pausedSession)
        }
    }

    /// Starts the level, resuming a paused session when one is waiting.
    func begin() async {
        guard engine.state == .intro else { return }
        let token = generation
        prepare()
        guard let prepared = await preparationTask?.value,
              generation == token,
              engine.state == .intro else { return }
        engine = prepared.engine
        preparationTask = nil
        isPaused = false
        prepareHaptics()
        PlaytimeTracker.shared.challengeStarted()
        AppAudio.shared.setGameplayActive(true, questionText: nil)
        AppAudio.shared.playSessionStart()
        hasBonusFishPower = prepared.pausedSession?.hasBonusFishPower ?? false
        openRound()
        announceRound()
        sync()
    }

#if DEBUG
    /// Starts a scripted trailer session already on the first sum, with no
    /// intro, no persistence and no spoken prompt.
    func beginPromo(cards: Int, streak: Int, rounds: [GameRound]) {
        skipsPersistence = true
        engine.installPromoSession(cards: cards, streak: streak, rounds: rounds)
        isPaused = false
        prepareHaptics()
        AppAudio.shared.prepare()
        AppAudio.shared.setGameplayActive(true, questionText: nil)
        openRound()
        sync()
    }
#endif

    /// Opens a round for play. There is nothing to memorise here: the sum
    /// stands at the top of the screen from the first frame, so the round goes
    /// straight through to accepting an answer.
    private func openRound() {
        engine.turnCardsOver()
        engine.beginAnswering()
    }

    private func announceRound() {
        AppAudio.shared.playCardReveal()
    }

    func end() {
        // Leaving without finishing pauses the level rather than discarding it.
        savePausedSessionIfNeeded()
        recordResultIfNeeded()
        PlaytimeTracker.shared.challengeEnded()
        AppAudio.shared.setGameplayActive(false, questionText: nil)
        AppAudio.shared.setGameplayRate(1)
        generation &+= 1
        preparationTask?.cancel()
        preparationTask = nil
        pendingScheduledWork = nil
        pendingScoreRewards.removeAll()
    }

    /// Temporarily stops an active run without ending it. The snapshot also
    /// makes the same run available if the player chooses the main menu from
    /// the pause card instead of continuing immediately.
    func pause() {
        guard engine.state != .gameOver else { return }
        isPaused = true
        savePausedSessionIfNeeded()
        PlaytimeTracker.shared.challengeEnded()
        AppAudio.shared.setGameplayActive(false, questionText: nil)
        AppAudio.shared.setGameplayRate(1)
    }

    /// Continues the in-memory run after its pause card. No round is rebuilt,
    /// so the player returns to the exact question, score and remaining lives.
    func resume() {
        guard engine.state != .intro, engine.state != .gameOver else { return }
        isPaused = false
        prepareHaptics()
        PlaytimeTracker.shared.challengeStarted()
        AppAudio.shared.setGameplayActive(true, questionText: nil)
        AppAudio.shared.setGameplayRate(isStreakBoostActive
                                        ? Float(GameConfig.streakSpeedMultiplier) : 1)
        let work = pendingScheduledWork
        pendingScheduledWork = nil
        work?()
    }

    /// The close button: the level is put on pause with its cards intact, and
    /// those cards are banked to the player's total straight away.
    func quit() {
        savePausedSessionIfNeeded()
        engine.quit()
        recordResultIfNeeded()
        sync()
    }

    /// Freezes the session for this level, so re-entering it continues from
    /// here. A finished session has nothing to store and clears the record.
    ///
    /// A run that has not banked a single card is not worth coming back to:
    /// storing it would only put a pause marker on the menu for a level the
    /// player would restart from zero anyway.
    private func savePausedSessionIfNeeded() {
#if DEBUG
        if skipsPersistence { return }
#endif
        guard !hasRecordedResult,
              let paused = engine.pausedSession(hasBonusFishPower: hasBonusFishPower)
        else { return }
        guard paused.cards > 0 else {
            PausedSessionStore.shared.clear(request.board)
            return
        }
        PausedSessionStore.shared.save(paused)
    }

    /// Play again always starts a clean run, so any paused record for this
    /// level is spent.
    func restart() async {
        generation &+= 1
        let token = generation
        PausedSessionStore.shared.clear(request.board)
        // Normally this engine has already been built during the result
        // animation. If Play Again somehow wins that race, wait for the worker
        // instead of doing its remaining generation work on the tap frame.
        startPreparation(pausedSession: nil)
        guard let prepared = await preparationTask?.value,
              generation == token else { return }
        engine = prepared.engine
        preparationTask = nil
        hasRecordedResult = false
        isPaused = false
        pendingScheduledWork = nil
        pendingScoreRewards.removeAll()
        hasBonusFishPower = false
        streakAnnouncementID = 0
        missedSum = nil
        pendingMissedSum = nil
        AppAudio.shared.playSessionStart()
        openRound()
        announceRound()
        sync()
    }

    // MARK: - Round flow

    /// Forwards the answer a crab carried to the King. The engine decides
    /// whether it counts; an arrival that lands while feedback is still playing
    /// comes back as `.ignored` and changes nothing at all. The returned flag
    /// tells the arena whether the King's sweep actually scored.
    @discardableResult
    func select(optionID: UUID) -> Bool {
        resolve(engine.select(optionID: optionID, usesBonusFish: hasBonusFishPower))
    }

    /// The player smashed the crab carrying the right answer. It costs a whole
    /// life and the attempt starts over on the same sum.
    @discardableResult
    func smashGuardedAnswer() -> Bool {
        resolve(engine.smashGuardedAnswer())
    }

    /// A wrong answer slipped through to the King: half a life, and the round
    /// simply carries on.
    @discardableResult
    func absorbBreach() -> Bool {
        let outcome = engine.absorbBreach()
        guard case .absorbed(let endsSession) = outcome else { return false }
        PlaytimeTracker.shared.registerInteraction()
        if engine.appliesWrongAnswerPenalty {
            AppAudio.shared.playHalfLife()
        }
        haptic(.error)
        if endsSession { finishSession() }
        sync()
        return true
    }

    private func resolve(_ outcome: AnswerOutcome) -> Bool {
        guard outcome != .ignored else { return false }
        // Every real interaction advances the playtime clock. Without these the
        // tracker only ever sees one gap from the first touch to the last,
        // which its idle limit then discards — a whole session counting as no
        // time.
        PlaytimeTracker.shared.registerInteraction()

        let token = generation
        let delay: Double
        switch outcome {
        case .correct(let cardsEarned, let usedBonusFish, let startedStreak):
            pendingScoreRewards.append(cardsEarned)
            sync()
            onAnswerResolved?(true, startedStreak)
            AppAudio.shared.playCorrect()
            if usedBonusFish {
                hasBonusFishPower = false
                AppAudio.shared.playDoubleScore()
            }
            if startedStreak {
                streakAnnouncementID &+= 1
                AppAudio.shared.playDoubleScore()
            }
            haptic(.success)
            delay = GameConfig.nextRoundDelay.correct
        case .wrong(_, let lostHalfLife):
            // Before `advance` moves the session on: this is the last moment
            // the sum that was just lost is still readable.
            noteMissedSum()
            sync()
            onAnswerResolved?(false, false)
            AppAudio.shared.playWrong()
            // The tutorial's free attempt costs nothing, so it must not sound
            // like it did: only the plain "not that one" note plays there.
            if engine.appliesWrongAnswerPenalty {
                if lostHalfLife {
                    AppAudio.shared.playHalfLife()
                } else {
                    AppAudio.shared.playLifeLost()
                }
            }
            haptic(.error)
            delay = GameConfig.nextRoundDelay.wrong
        case .ignored:
            return false
        }

        schedule(after: delay, token: token) { [weak self] in
            guard let self else { return }
            guard self.engine.finishResolving() else { return }
            let previousRoundID = self.engine.round?.id
            self.engine.advance()
            if self.engine.state == .gameOver {
                self.finishSession()
            } else if self.engine.round?.id != previousRoundID {
                // A new sum is announced and opened. A wrong answer leaves the
                // same sum in place, and play simply resumes.
                self.announceRound()
                self.openRound()
            }
            self.sync()
        }
        return true
    }

    /// Writes down the sum that was just lost, so the next one can carry it.
    /// A round that comes straight back — the same sum, another attempt — is
    /// deliberately not noted: its answer is still there to be found.
    private func noteMissedSum() {
        guard let round = engine.round else { return }
        // Whatever was owed before is settled: only the newest mistake is worth
        // showing, and it takes the place under the next sum.
        missedSum = nil
        pendingMissedSum = MissedSum(text: round.question.solved,
                                     missedRoundID: round.id,
                                     shownRoundID: nil)
    }

    /// Carries the missed sum along with the questions: it appears with the sum
    /// that replaces the one it was lost on, and goes when that sum does.
    private func syncMissedSum() {
        let currentRoundID = engine.round?.id
        if var pending = pendingMissedSum {
            // Still on the sum it was lost on — the feedback beat before the
            // next question is installed, or a repeat attempt at the same sum,
            // which keeps its own answer to itself.
            guard currentRoundID != pending.missedRoundID else { return }
            pending.shownRoundID = currentRoundID
            pendingMissedSum = nil
            missedSum = pending
        } else if let shown = missedSum, currentRoundID != shown.shownRoundID {
            missedSum = nil
        }
    }

    /// A crab was knocked off the sea floor. The blow is pure feedback: what it
    /// cost, if anything, is decided by the engine through the calls above.
    func crabSmashed() {
        AppAudio.shared.playCardFlip()
        haptic(.rigid)
    }

    /// The King answers everything that reached him with one blow.
    func kingSweeps() {
        AppAudio.shared.playFlamethrower()
        haptic(.light)
    }

    /// Called by the arena at the exact frame a collected shell lands on the
    /// HUD icon.
    func scoreBubbleArrived() {
        guard !pendingScoreRewards.isEmpty else { return }
        cards += pendingScoreRewards.removeFirst()
        AppAudio.shared.playCardTotal()
        haptic(.light)
    }

    /// Called by the arena when the player taps the passing 2x crab. Multiple
    /// catches do not stack: one aura always represents one doubled answer.
    func catchBonusFish() {
        guard !hasBonusFishPower else { return }
        hasBonusFishPower = true
        AppAudio.shared.playDoubleCardAppear()
        haptic(.rigid)
    }

    /// The life crab is a direct life reward, not a power held for the next
    /// answer, so the engine applies it the moment it reaches the King.
    @discardableResult
    func catchLifeCrab() -> Bool {
        let restoredHalves = engine.catchLifeCrab()
        guard restoredHalves > 0 else {
            // Arriving with nothing to give still spends the comeback, so the
            // crab cannot loop round for a second attempt.
            engine.spendLifeCrab()
            sync()
            return false
        }
        PlaytimeTracker.shared.registerInteraction()
        sync()
        AppAudio.shared.playLifeRestored()
        haptic(.success)
        return true
    }

    // MARK: - Tutorial

    /// The tutorial's free attempt: a mistake may be made once without paying
    /// for it. The rule is untouched — only waived, and only there.
    func setWrongAnswerPenalty(_ applies: Bool) {
        engine.appliesWrongAnswerPenalty = applies
    }

    /// Arms the life crab directly, for the step that teaches it.
    func makeLifeCrabAvailable() {
        engine.makeLifeCrabAvailable()
        sync()
    }

    // MARK: - Finishing

    private func finishSession() {
        AppAudio.shared.setGameplayRate(1)
        recordResultIfNeeded()
        // Hide replay generation under the finale/result card too.
        startPreparation(pausedSession: nil)
    }

    /// Writes the session to disk exactly once, whichever way the screen is
    /// left: game over, the close button, or a swipe away.
    private func recordResultIfNeeded() {
#if DEBUG
        if skipsPersistence {
            if engine.state == .gameOver, engine.gameOverReason != .quit {
                AppAudio.shared.playSessionComplete()
                result = engine.result
            }
            return
        }
#endif
        guard engine.state == .gameOver, !hasRecordedResult else { return }
        hasRecordedResult = true
        // A level that reached its end is finished, not paused.
        if engine.gameOverReason != .quit {
            PausedSessionStore.shared.clear(request.board)
        }

        let store = Progress.store
        let previousTotal = store.totalCards
        let board = request.board
        // Only the improvement on this board joins the player's total. A board
        // can therefore contribute its maximum once, even though subsequent
        // maximum runs still count toward the separate ×N completion badge.
        let previousBest = store.bestScore(board)
        let gained = max(0, min(engine.cards, board.maximum) - previousBest)
        let newTotal = store.addCards(gained)
        // The score belongs to the board this session was played on: the card
        // count, and on Supermix the combination, keep separate bests.
        let best = store.recordScore(engine.cards, board: board)
        let unlocked = CharacterUnlocks.newlyUnlocked(from: previousTotal, to: newTotal)

        // Reaching this board's maximum is tallied every time, which is what
        // the ×N badge on a completed card counts.
        let maximum = board.maximum
        if engine.cards >= maximum {
            store.recordMaxCompletion(board)
        }

        engine.applyProgressOutcome(previousBest: best.previousBest,
                                    isNewPersonalBest: best.isNewBest,
                                    unlockedCharacterIDs: unlocked)

        ReviewRequestCoordinator.shared.recordCompletedGame(
            isNewHighScore: best.isNewBest,
            score: engine.cards,
            maximumScore: maximum
        )

        // Leaving a level part-way through is not an achievement: the pause
        // button banks the cards quietly, with no end-of-session fanfare.
        if engine.gameOverReason != .quit {
            if best.isNewBest && engine.cards > 0 { AppAudio.shared.playHighScore() }
            else { AppAudio.shared.playSessionComplete() }
        }
        result = engine.result
    }

    // MARK: - Plumbing

    /// Copies the engine's state onto the published properties in one pass, so
    /// a single tap causes exactly one SwiftUI update rather than eight.
    private func sync() {
        state = engine.state
        round = engine.round
        roundNumber = engine.roundNumber
        if pendingScoreRewards.isEmpty { cards = engine.cards }
        livesRemaining = engine.livesRemaining
        selectedOptionID = engine.selectedOptionID
        // Publish the completed result before the game-over flag. GameView
        // uses its reason to decide whether to play the arena finale first.
        if engine.state == .gameOver { result = engine.result }
        isGameOver = engine.state == .gameOver
        correctStreak = engine.correctStreak
        isStreakBoostActive = engine.isStreakBoostActive
        isLifeCrabAvailable = engine.isLifeCrabAvailable
        syncMissedSum()
        AppAudio.shared.setGameplayRate(isStreakBoostActive
                                        ? Float(GameConfig.streakSpeedMultiplier) : 1)
    }

    /// Runs `work` after a delay, unless the session moved on in the meantime.
    private func schedule(after delay: Double, token: Int, work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == token else { return }
            guard !self.isPaused else {
                self.pendingScheduledWork = work
                return
            }
            work()
        }
    }

    private enum Haptic { case light, rigid, success, error }

#if canImport(UIKit)
    // Built once and kept warm. A generator created on the spot has to wake the
    // Taptic Engine from idle on the calling thread, and that landed on the
    // exact main-thread frame in which an answer was taken.
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationHaptic = UINotificationFeedbackGenerator()
#endif

    /// Puts the Taptic Engine on standby while nothing is happening yet, so the
    /// first answer of a round pays no start-up cost either.
    private func prepareHaptics() {
#if canImport(UIKit)
        lightHaptic.prepare()
        rigidHaptic.prepare()
        notificationHaptic.prepare()
#endif
    }

    private func haptic(_ kind: Haptic) {
#if canImport(UIKit)
        switch kind {
        case .light: lightHaptic.impactOccurred()
        case .rigid: rigidHaptic.impactOccurred()
        case .success: notificationHaptic.notificationOccurred(.success)
        case .error: notificationHaptic.notificationOccurred(.error)
        }
        // Firing leaves the engine idle again; this keeps the *next* answer,
        // which in fast play is only a moment away, just as immediate.
        prepareHaptics()
#endif
    }
}
