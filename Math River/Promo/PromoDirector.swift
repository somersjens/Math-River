#if DEBUG
import Foundation
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Drives the live arena through the teaser beats. Every throw, spawn and
/// character change goes through production entry points.
@MainActor
final class PromoDirector: ObservableObject {
    enum Phase: Equatable {
        case waitingForWave
        case openingWait
        case q1Throws(Int)
        case waitForQ2
        case showcase(Int)
        case q2Pressure
        case q2Recover(Int)
        case waitStreak
        case tapHelper
        case waitGold
        case goldThrows(Int)
        case waitCompletion
        case icon
        case done
    }

    @Published private(set) var phase: Phase = .waitingForWave
    @Published var characterID = "crab"
    @Published var headline: String? = PromoScript.headlineThrow
    @Published var showsIcon = false
    @Published var blursPlayfield = false
    @Published var isFinished = false
    /// Streak colour, speed and banner wait until the last Q2 smash has landed.
    @Published var revealsStreakBoost = false

    let model: GameViewModel
    private(set) weak var arena: KingCrabArena?

    private var startedAt: TimeInterval = 0
    private var phaseStartedAt: TimeInterval = 0
    private var timer: Timer?
    var onGameplayReady: (() -> Void)?

    private var spawnedHelper = false
    private var tappedHelper = false
    private var attached = false
    private var completionFinished = false
    private var didSignalReady = false
    private var finaleStartedAt: TimeInterval?

    var elapsed: Double { CACurrentMediaTime() - startedAt }
    private var phaseElapsed: Double { CACurrentMediaTime() - phaseStartedAt }

    init(model: GameViewModel) {
        self.model = model
    }

    func attach(_ arena: KingCrabArena) {
        guard !attached else { return }
        attached = true
        self.arena = arena
        arena.promoSuppressesBonusPlan = true
        arena.promoSuppressesRefill = true
        arena.promoDefersRushScoring = true
        arena.promoEntryAssignment = PromoScript.entryAssignment
        model.beginPromo(cards: 2, streak: 3, rounds: PromoScript.rounds)
        startedAt = CACurrentMediaTime()
        enter(.waitingForWave)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func markCompletionFinished() {
        completionFinished = true
    }

    func markFinaleStarted() {
        guard finaleStartedAt == nil else { return }
        finaleStartedAt = CACurrentMediaTime()
    }

    private func enter(_ phase: Phase) {
        self.phase = phase
        phaseStartedAt = CACurrentMediaTime()
        switch phase {
        case .waitingForWave, .openingWait, .q1Throws, .waitForQ2:
            headline = PromoScript.headlineThrow
        case .showcase:
            headline = PromoScript.headlineUnlock
        case .q2Pressure, .q2Recover, .waitStreak, .tapHelper:
            headline = PromoScript.headlineShells
        case .waitGold, .goldThrows, .waitCompletion, .icon, .done:
            headline = nil
        }
    }

    private func tick() {
        guard let arena, !isFinished else { return }
        if elapsed > 70, phase != .done, phase != .icon, phase != .waitCompletion {
            enter(.icon)
            return
        }
        switch phase {
        case .waitingForWave:
            if unansweredWalkingCount(in: arena) >= 4 {
                enter(.openingWait)
                if !didSignalReady {
                    didSignalReady = true
                    onGameplayReady?()
                }
            }
        case .openingWait:
            if firstWaveWellInView(in: arena) || phaseElapsed >= 4.4 {
                enter(.q1Throws(0))
            }
        case .q1Throws(let index):
            let answers = PromoScript.q1Wrong
            guard answers.indices.contains(index) else {
                enter(.waitForQ2)
                return
            }
            if index == 0 || phaseElapsed >= 1.02 {
                if arena.promoTapAnswer(answers[index]) {
                    if index + 1 < answers.count {
                        enter(.q1Throws(index + 1))
                    } else {
                        enter(.waitForQ2)
                    }
                }
            }
        case .waitForQ2:
            if hasReachedKing("15", in: arena) {
                headline = PromoScript.headlineUnlock
                enter(.showcase(1))
            } else if phaseElapsed >= 4.2 {
                enter(.showcase(1))
            }
        case .showcase(let step):
            applyShowcase(step: step)
            if phaseElapsed >= 1.38 {
                if step < 4 {
                    enter(.showcase(step + 1))
                } else {
                    enter(.q2Pressure)
                }
            }
        case .q2Pressure:
            applyCharacter("crab")
            headline = PromoScript.headlineShells
            let lowerReady = PromoScript.q2LowerWrong.allSatisfy {
                crabProgress($0, in: arena) >= 0.74
            }
            if lowerReady || phaseElapsed >= 0.28 {
                enter(.q2Recover(0))
            }
        case .q2Recover(let index):
            recoverQuestion2(index: index, arena: arena)
        case .waitStreak:
            if hasReachedKing("56", in: arena) {
                revealsStreakBoost = true
                if phaseElapsed >= 0.35 {
                    enter(.tapHelper)
                }
            } else if phaseElapsed >= 4.8 {
                revealsStreakBoost = hasReachedKing("56", in: arena)
                    && model.isStreakBoostActive
                enter(.tapHelper)
            }
        case .tapHelper:
            if !tappedHelper {
                tappedHelper = arena.promoTapBonusCarrier() || tappedHelper
            }
            if isQuestion3 || phaseElapsed >= 0.55 {
                enter(.waitGold)
            }
        case .waitGold:
            headline = nil
            let goldReady = arena.crabs.contains { $0.isGolden && $0.phase == .walking }
            if goldReady, phaseElapsed >= 2.0 {
                enter(.goldThrows(0))
            } else if phaseElapsed >= 3.4 {
                enter(.goldThrows(0))
            }
        case .goldThrows(let index):
            let answers = PromoScript.q3Wrong
            guard answers.indices.contains(index) else {
                enter(.waitCompletion)
                return
            }
            let gap = index == 0 ? 0.0 : 0.16
            if phaseElapsed >= gap {
                if arena.promoTapAnswer(answers[index]) {
                    if index + 1 < answers.count {
                        enter(.goldThrows(index + 1))
                    } else {
                        enter(.waitCompletion)
                    }
                }
            }
        case .waitCompletion:
            let hop = ArenaConfig.kingHopDuration
            let settle = ArenaConfig.kingHopSettle
            let exit = ArenaConfig.kingExitDuration
            let iconAt = hop + settle + exit * 0.12
            if let start = finaleStartedAt, CACurrentMediaTime() - start >= iconAt {
                enter(.icon)
            } else if let age = arena.king.farewellAge, age >= iconAt {
                enter(.icon)
            } else if completionFinished, phaseElapsed >= 0.2 {
                enter(.icon)
            } else if phaseElapsed >= 14 {
                enter(.icon)
            }
        case .icon:
            if !showsIcon {
                withAnimation(.easeOut(duration: 0.45)) {
                    blursPlayfield = true
                }
                withAnimation(.spring(response: 0.72, dampingFraction: 0.78)) {
                    showsIcon = true
                }
            }
            if phaseElapsed >= 2.0 {
                enter(.done)
            }
        case .done:
            isFinished = true
            stop()
        }
    }

    private func recoverQuestion2(index: Int, arena: KingCrabArena) {
        switch index {
        case 0:
            if arena.promoTapAnswer(PromoScript.q2LowerWrong[0]) {
                enter(.q2Recover(1))
            }
        case 1:
            if phaseElapsed >= 0.11, arena.promoTapAnswer(PromoScript.q2LowerWrong[1]) {
                enter(.q2Recover(2))
            }
        case 2:
            if phaseElapsed >= 0.20, arena.promoTapAnswer(PromoScript.q2TopWrong) {
                enter(.waitStreak)
            }
        default:
            enter(.waitStreak)
        }
    }

    private func applyShowcase(step: Int) {
        let ids = PromoScript.characterIDs
        let id = ids.indices.contains(step) ? ids[step] : "crab"
        applyCharacter(id)
        if step == 2, !spawnedHelper {
            spawnedHelper = true
            arena?.promoSpawnBonusCrab(duration: 10.4, fromLeading: true)
        }
    }

    private func applyCharacter(_ id: String) {
        guard characterID != id else { return }
        characterID = id
    }

    private var isQuestion3: Bool {
        model.round?.question.prompt.contains("−") == true
    }

    private func unansweredWalkingCount(in arena: KingCrabArena) -> Int {
        arena.crabs.filter { $0.phase == .walking && !$0.hasAnswered }.count
    }

    private func firstWaveWellInView(in arena: KingCrabArena) -> Bool {
        ["15", "16", "14", "24"].allSatisfy { text in
            guard let crab = arena.crabs.first(where: {
                $0.text == text && $0.phase == .walking
            }) else { return false }
            return crab.progress >= crab.entryProgress + 0.34
        }
    }

    private func crabProgress(_ text: String, in arena: KingCrabArena) -> Double {
        arena.crabs.first { $0.text == text && !$0.hasAnswered }?.progress ?? 0
    }

    private func hasReachedKing(_ text: String, in arena: KingCrabArena) -> Bool {
        arena.crabs.contains { crab in
            guard crab.text == text else { return false }
            switch crab.phase {
            case .delivering, .burrowing:
                return true
            default:
                return false
            }
        }
    }
}
#endif
