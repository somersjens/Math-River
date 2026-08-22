//
//  Tutorial.swift
//  King Krab
//
//  The guided first game. A new player is walked through the arena one step at
//  a time: smashing the wrong crabs, letting the right one reach the King, what
//  a mistake costs, the two helper crabs and the golden streak — after which the
//  level simply carries on as an ordinary session.
//
//  The tutorial never re-implements a rule. Each step only *shapes* what the
//  arena sends in (`CrabTutorialPlan`) and listens for the one thing that step
//  is waiting for; scoring, lives and rounds keep running through `MemoryGame`
//  exactly as they do in a normal game. That is what makes the tutorial a real
//  session rather than a scripted demo: the shells the player collects here
//  count, and the level continues from where the last step leaves it.
//

import SwiftUI
import Combine

// MARK: - Steps

/// The nine in-game steps, in the order they are played. The closing step of
/// the script is the score pointer on the home screen, which lives there rather
/// than in a session — see `HomeView`, which shows `tutorial.step.10` itself.
enum TutorialStep: Int, CaseIterable, Identifiable {
    /// Only wrong answers walk in. Tapping them costs nothing here.
    case smashWrong = 1
    /// One right answer among the wrong ones: let that one through.
    case guardCorrect
    /// A full wave, with what smashing the right crab would cost spelled out.
    case protectKing
    /// The comeback crab, which walks a life to the King.
    case lifeCrab
    /// The 2x crab, which doubles the next answer.
    case bonusCrab
    /// Right answers in a row, one crab at a time, to reach the streak.
    case buildStreak
    /// The streak is running: gold crabs, double shells.
    case superBonusRunning
    /// Normal play resumes; the last lesson clears itself after a few seconds.
    case freePlay
    /// The sign-off, which only says the walkthrough is over and then hands the
    /// level back untouched.
    case complete

    var id: Int { rawValue }

    /// The message shown on screen for this step.
    var messageKey: String { "tutorial.step.\(rawValue)" }

    var next: TutorialStep? { TutorialStep(rawValue: rawValue + 1) }

    /// How long a message that nothing in the arena can finish stays on screen
    /// before the script moves itself on.
    var messageDuration: Double? {
        switch self {
        case .freePlay: return 5.0
        case .complete: return 3.0
        default: return nil
        }
    }
}

// MARK: - What the arena should send in

/// The shape the tutorial asks the arena to take for the current step. The
/// arena owns *how* crabs walk, are smashed and arrive; this only says what may
/// be on the sea floor while a step is being taught.
struct CrabTutorialPlan: Equatable {
    /// One fixed wave: how many right and wrong answers walk in together.
    struct Wave: Equatable {
        var correct: Int
        var wrong: Int
    }

    /// False for every ordinary session, which leaves the arena untouched.
    var isActive = false
    /// Fixes the composition of every wave. Nil leaves the normal four.
    var answers: Wave?
    /// No answer crab may be on the sea floor at all.
    var suppressesAnswers = false
    /// Sends the 2x crab across, and sends it back whenever it is missed.
    var wantsBonusCrab = false
    /// The same for the comeback crab.
    var wantsLifeCrab = false
}

/// The things the arena itself notices, which the tutorial waits on.
enum CrabTutorialEvent {
    case smashedWrongCrab
    /// The last crab of a wave was smashed, leaving the sea floor empty.
    case clearedWave
    case caughtBonusCrab
    case lifeCrabArrived
}

// MARK: - Controller

/// Runs the script: holds the current step, hands the arena its plan, and moves
/// on the moment the step's own condition is met. Everything it needs to know
/// arrives as an event — nothing here polls the game.
@MainActor
final class TutorialController: ObservableObject {
    @Published private(set) var step: TutorialStep?
    @Published private(set) var plan = CrabTutorialPlan()
    /// True from the first step until the player leaves the screen — including
    /// after the last message has gone. The arena keeps the band under the sum
    /// free for the whole run, so neither the first line appearing nor the last
    /// one clearing moves the sea floor, the King or a crab already walking.
    @Published private(set) var reservesMessageArea = false

    /// The session being taught. Weak, so the controller can never keep a
    /// finished game alive.
    private weak var model: GameViewModel?
    /// Invalidates the pending close of the last message when the run is left,
    /// restarted or finished first.
    private var generation = 0

    var isActive: Bool { step != nil }

    /// The line currently on screen, in the player's own language.
    var message: String? {
        step.map { L(key: $0.messageKey) }
    }

    // MARK: Lifecycle

    /// Starts the walkthrough on a session that has just opened its first round.
    func begin(model: GameViewModel) {
        guard step == nil else { return }
        self.model = model
        model.onAnswerResolved = { [weak self] isCorrect, startedStreak in
            self?.answerResolved(isCorrect: isCorrect, startedStreak: startedStreak)
        }
        // Whatever happens to this session from here — finished, lost or left —
        // the player has seen the arena, so the home screen owes them the last
        // step of the script.
        GameSettings.tutorialHomeHintPending = true
        reservesMessageArea = true
        enter(.smashWrong)
    }

    /// Ends the walkthrough and hands the level back unchanged: normal waves,
    /// normal penalties, normal helper crabs. The band the messages spoke from
    /// stays reserved for the rest of the session; see `reservesMessageArea`.
    func finish() {
        guard step != nil else { return }
        generation &+= 1
        release()
        withAnimation(.easeOut(duration: 0.32)) {
            step = nil
            plan = CrabTutorialPlan()
        }
    }

    /// Leaving the game screen: the same tidy-up, without the animation of a
    /// view that is on its way out.
    func cancel() {
        guard step != nil else { return }
        generation &+= 1
        release()
        step = nil
        plan = CrabTutorialPlan()
        reservesMessageArea = false
    }

    private func release() {
        model?.setWrongAnswerPenalty(true)
        model?.onAnswerResolved = nil
    }

    // MARK: Events

    /// Reported by the arena itself.
    func handle(_ event: CrabTutorialEvent) {
        guard let step else { return }
        switch event {
        case .smashedWrongCrab:
            break
        case .clearedWave:
            // The first step is over once every wrong crab has been dealt with,
            // which is exactly the skill it teaches.
            if step == .smashWrong { advance() }
        case .caughtBonusCrab:
            if step == .bonusCrab { advance() }
        case .lifeCrabArrived:
            if step == .lifeCrab { advance() }
        }
    }

    /// Reported by the session for every answer it accepts.
    private func answerResolved(isCorrect: Bool, startedStreak: Bool) {
        guard let step else { return }
        switch step {
        case .guardCorrect, .protectKing, .superBonusRunning:
            if isCorrect { advance() }
        case .buildStreak:
            // True on the answer that starts the boost, which is the last of
            // the run of `GameConfig.streakThreshold` — the point of this step.
            if startedStreak { advance() }
        default:
            break
        }
    }

    // MARK: Steps

    private func advance() {
        guard let next = step?.next else {
            finish()
            return
        }
        enter(next)
    }

    private func enter(_ step: TutorialStep) {
        generation &+= 1
        let token = generation

        // Only the opening step is free: everywhere else a mistake costs
        // exactly what it costs in a real game.
        model?.setWrongAnswerPenalty(step != .smashWrong)
        if step == .lifeCrab {
            model?.makeLifeCrabAvailable()
        }

        withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
            self.step = step
            self.plan = Self.plan(for: step)
        }

        // The closing pair of messages have nothing in the arena to finish
        // them: they simply have their moment and hand on.
        if let duration = step.messageDuration {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.generation == token else { return }
                self.advance()
            }
        }
    }

    /// The arena's marching orders for each step.
    private static func plan(for step: TutorialStep) -> CrabTutorialPlan {
        var plan = CrabTutorialPlan()
        plan.isActive = true
        switch step {
        case .smashWrong:
            // Every wrong answer this question has, and no right one: there is
            // nothing here to protect yet, so tapping is all there is to learn.
            plan.answers = .init(correct: 0, wrong: GameConfig.distractorCount)
        case .guardCorrect:
            plan.answers = .init(correct: 1, wrong: 1)
        case .protectKing:
            plan.answers = .init(correct: 1, wrong: 2)
        case .lifeCrab:
            plan.suppressesAnswers = true
            plan.wantsLifeCrab = true
        case .bonusCrab:
            plan.suppressesAnswers = true
            plan.wantsBonusCrab = true
        case .buildStreak:
            plan.answers = .init(correct: 1, wrong: 1)
        case .superBonusRunning:
            plan.answers = .init(correct: 1, wrong: 2)
        case .freePlay, .complete:
            // Nothing shaped any more: full waves, both helper crabs back on
            // their own schedule. Only the message is still the tutorial's.
            break
        }
        return plan
    }
}

// MARK: - Message

/// The line the tutorial is currently teaching: a note tucked in directly under
/// the sum, in the same white card the sum itself is drawn on, only smaller and
/// quieter — the same relationship the missed-sum note has to the question above
/// it. The character does the talking, so it reads as the same voice as the
/// level card.
///
/// It is deliberately a fixed-height strip rather than a card that grows with
/// its text: the arena keeps exactly this much water free under the sum for the
/// whole run, so a longer line never pushes the sea floor about. Nothing in the
/// arena moves when a message arrives or leaves — only the note itself fades.
struct TutorialMessageCard: View {
    let text: String
    let theme: AnimalCharacter
    var isPad: Bool = AppLayout.isPad

    /// The tallest the strip is ever drawn, which is what the arena reserves.
    static func height(isPad: Bool) -> CGFloat { isPad ? 92 : 70 }

    private var portraitSize: CGFloat { isPad ? 46 : 34 }
    private var corner: CGFloat { isPad ? 22 : 18 }

    var body: some View {
        HStack(alignment: .center, spacing: isPad ? 12 : 9) {
            theme.thumbArtwork
                .resizable()
                .scaledToFit()
                .padding(isPad ? 3 : 2)
                .frame(width: portraitSize, height: portraitSize)
                .background(theme.skyColor, in: Circle())
                .overlay(Circle().stroke(theme.deepColor.opacity(0.14), lineWidth: 1))

            Text(verbatim: text)
                .font(.system(size: isPad ? 17 : 13, weight: .bold, design: .rounded))
                .foregroundStyle(theme.deepColor)
                .multilineTextAlignment(.leading)
                // Three lines is what the reserved band holds; a stubbornly
                // long translation shrinks into it rather than being cut off.
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isPad ? 15 : 11)
        .padding(.vertical, isPad ? 8 : 6)
        .frame(maxWidth: isPad ? 600 : 400)
        .frame(height: Self.height(isPad: isPad))
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.white.opacity(0.95))
                    .shadow(color: theme.deepColor.opacity(0.20), radius: 9, y: 5)
                // The sum's own dashed edge, one size down: the note reads as a
                // footnote to the question rather than as a second panel.
                RoundedRectangle(cornerRadius: corner * 0.78, style: .continuous)
                    .stroke(theme.deepColor.opacity(0.26),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .padding(isPad ? 6 : 5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - "Only at the start" notice

/// Shown when the tutorial is asked for on a game that is already under way.
/// Same card, same button as everything else the level screen puts up.
struct TutorialNoticeCard: View {
    let theme: AnimalCharacter
    let onDismiss: () -> Void

    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.2 : 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14 * scale) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 30 * scale, weight: .bold))
                    .foregroundStyle(theme.deepColor)
                    .frame(width: 62 * scale, height: 62 * scale)
                    .background(theme.skyColor, in: Circle())

                Text("tutorial.notice.title")
                    .font(.system(size: 22 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)
                    .multilineTextAlignment(.center)

                Text("tutorial.notice.message")
                    .font(.system(size: 15 * scale, weight: .regular))
                    .foregroundStyle(theme.deepColor.opacity(0.84))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onDismiss) {
                    Text("common.ok")
                        .font(.system(size: 17 * scale, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14 * scale)
                        .foregroundStyle(.white)
                        .background(theme.deepColor,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tutorial-notice-ok")
            }
            .padding(26 * scale)
            .frame(maxWidth: 340 * scale)
            // Same light fill as the start/pause card: `.background` turns
            // black in Dark Mode against this card's deep-purple copy.
            .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(theme.deepColor.opacity(0.14), lineWidth: 1))
            .shadow(color: theme.deepColor.opacity(0.3), radius: 20, y: 10)
            .padding(24)
        }
    }
}
