//
//  GameView.swift
//  Math River
//
//  The playing surface. A round runs on the river: the sum stands at the
//  top of the screen, four answer stones lie on the water, and the player
//  steers the honey-ring rider between three lanes to hit one answer.
//
//  All rules live in `MemoryGame` and the arena lives in
//  `MathRiverArena.swift` and `MathRiverPlayfield.swift`; this file only puts the
//  HUD and the arena together and hands every event straight to the engine,
//  which is the single place that decides what it costs or pays.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// `.numericText(value:)` picks a roll-up/roll-down direction from the value
/// and only exists from iOS 17; the app's floor is 16.4, so older systems fall
/// back to the direction-less transition instead of losing the digit roll entirely.
private struct NumericCountTransition: ViewModifier {
    let value: Double

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentTransition(.numericText(value: value))
        } else {
            content.contentTransition(.numericText())
        }
    }
}

/// Everything a session needs to start: which level to draw questions from and
/// how many answer cards each round lays out.
struct GameSessionRequest: Identifiable {
    let level: MathLevel
    /// Only meaningful for Supermix levels; every other topic has one operation.
    var mixedVariant: MixedVariant = .all
    /// Which of the three order buttons was chosen. Supermix ignores it.
    var mode: PracticeMode = .mixed
    /// True when the level was opened to be taught: the start card offers the
    /// walkthrough straight away. Deliberately outside `id`, which identifies
    /// the *board* being played.
    var startsTutorialArmed = false
    var id: String { "\(level.id).\(mixedVariant.rawValue).\(mode.rawValue)" }

    /// The scoreboard this session plays on.
    var board: LevelBoard {
        LevelBoard(level: level, mixedVariant: mixedVariant, mode: mode)
    }
}

struct GameView: View {
    let request: GameSessionRequest
    /// Optional replacement for the modal `dismiss` environment. The welcome
    /// hand-off shows this screen in-place rather than as a cover, so leaving
    /// has to tell the menu underneath instead of popping a presentation.
    var onExit: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var language = LanguageManager.shared
    @StateObject private var model: GameViewModel
    /// The walkthrough. Inert until a run is actually started with it armed.
    @StateObject private var tutorial = TutorialController()

    /// The window's safe area, sampled once the view is on screen — never from
    /// inside `body`; see `ScreenSafeArea`.
    @State private var screenInsets = ScreenSafeArea()

    /// The level's start card, shown before the first round and dismissed by
    /// the player. The session only begins once it is gone.
    @State private var showsIntro = true
    /// The same card doubles as the in-level pause screen. Keeping this state
    /// separate from `showsIntro` lets a brand-new run still say Start while a
    /// pause made before the first answer already says Continue.
    @State private var showsPauseCard = false
    /// After the card, the King gets the stage to himself while he climbs out
    /// of the sand. The first round only opens when that is finished.
    @State private var playsKingEntrance = false
    /// Measured from the real HUD layout so the flying currency glyph can land
    /// pixel-for-pixel over its stationary twin on every device and score width.
    @State private var scoreIconCenter: CGPoint?
    /// A completed board gets one last moment in the arena before its result
    /// card appears. Other endings (no lives, or leaving) remain immediate.
    @State private var playsLevelCompletion = false
    /// The King's celebration has actually begun. It trails `playsLevelCompletion`
    /// by however long the crab carrying the winning answer still needs to walk
    /// its shell in — the HUD belongs to that walk, not to the card after it.
    @State private var showsFinale = false
    @State private var showsResult = false
    /// Whether pressing Start will run the walkthrough. Armed from the menu for
    /// a brand-new player, and toggled by the cap button on the start card.
    @State private var isTutorialArmed: Bool
    /// Raised by the cap button once points have been earned, because a scored
    /// run cannot be rewound into a lesson.
    @State private var showsTutorialNotice = false
    @State private var chapterAnnouncement: HoneyRunChapter?
    @State private var showsRouteHoneyToast = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(request: GameSessionRequest, onExit: (() -> Void)? = nil) {
        self.request = request
        self.onExit = onExit
        _model = StateObject(wrappedValue: GameViewModel(request: request))
        // A level with a run waiting on it is continued, never taught: the
        // walkthrough needs a session it can shape from its very first round.
        _isTutorialArmed = State(
            initialValue: request.startsTutorialArmed
                && PausedSessionStore.shared.session(request.board) == nil
        )
    }

    private var character: AnimalCharacter { CharacterCatalog.current(isPremium: premium.isPremium) }
    private var isPad: Bool { AppLayout.isPad }

    var body: some View {
        ZStack {
            LinearGradient(colors: [character.skyColor, character.tintColor],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // The level's own wallpaper, exactly as the original game had it.
            LevelWallpaper(level: request.level, tint: character.color)
                .ignoresSafeArea()

            // Keep the level visible underneath every card. The result is an
            // overlay over the arena that was just played, exactly like the
            // start and pause cards, rather than a replacement for the game.
            playfield
                .transition(.opacity)

            if showsResult {
                ResultView(result: model.result,
                           board: request.board,
                           character: character,
                           onPlayAgain: {
                               showsResult = false
                               playsLevelCompletion = false
                               showsFinale = false
                               Task {
                                   await model.restart()
                                   // A won board ends with the King running off
                                   // the right of the screen, and nothing put
                                   // him back: the next run opened on an empty
                                   // arena with its crabs walking at a spot he
                                   // was not standing on. He walks on again
                                   // exactly as he does for a fresh session.
                                   //
                                   // After the restart, not alongside it: until
                                   // it lands the session still reads as over,
                                   // which holds the whole arena — and with it
                                   // the walk — stopped.
                                   playsKingEntrance = true
                               }
                           },
                           onExit: leave)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }

            if showsIntro {
                LevelIntroCard(board: request.board,
                               theme: character,
                               isPauseCard: showsPauseCard,
                               isTutorialArmed: isTutorialArmed,
                               onToggleTutorial: toggleTutorial,
                               onStart: startSession,
                               onExit: leave)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if showsTutorialNotice {
                TutorialNoticeCard(theme: character) {
                    withAnimation(.easeOut(duration: 0.2)) { showsTutorialNotice = false }
                }
                .transition(.opacity)
                    .zIndex(3)
            }

            if let chapterAnnouncement, !showsIntro, !showsResult {
                HoneyChapterAnnouncement(chapter: chapterAnnouncement,
                                         theme: character,
                                         isPad: isPad)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(4)
            }

            if showsRouteHoneyToast, !showsIntro, !showsResult {
                RouteHoneyToast(theme: character, isPad: isPad)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(4)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.isGameOver)
        .animation(.easeInOut(duration: 0.25), value: showsIntro)
        .onAppear {
            screenInsets = ScreenSafeArea.current
            model.prepare()
        }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(
            for: UIDevice.orientationDidChangeNotification
        )) { _ in
            // Safe-area sides change when an iPad rotates. Re-sample after
            // UIKit has committed the new window geometry so the HUD remains
            // clear of rounded corners in either landscape direction.
            DispatchQueue.main.async {
                screenInsets = ScreenSafeArea.current
            }
        }
#endif
        .onChange(of: model.isGameOver) { isOver in
            // There is nothing left to teach on a finished board.
            if isOver { tutorial.finish() }
            guard isOver else {
                showsResult = false
                playsLevelCompletion = false
                showsFinale = false
                return
            }
            if model.result.reason == .roundsCompleted {
                playsLevelCompletion = true
            } else {
                showsResult = true
            }
        }
        .onChange(of: model.roundNumber) { roundNumber in
            let chapter = HoneyRunChapter.chapter(roundNumber: roundNumber,
                                                  maximumRounds: model.maximumRounds)
            guard roundNumber == 1 || roundNumber == 5 || roundNumber == 9 else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                chapterAnnouncement = chapter
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                guard chapterAnnouncement == chapter else { return }
                withAnimation(.easeOut(duration: 0.28)) { chapterAnnouncement = nil }
            }
        }
        .onChange(of: model.routeHoneyPickupID) { pickupID in
            guard pickupID > 0 else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.70)) {
                showsRouteHoneyToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                guard model.routeHoneyPickupID == pickupID else { return }
                withAnimation(.easeOut(duration: 0.24)) { showsRouteHoneyToast = false }
            }
        }
        .onDisappear {
            tutorial.cancel()
            model.end()
        }
    }

    private func leave() {
        if let onExit {
            onExit()
        } else {
            dismiss()
        }
    }

    private func startSession() {
        showsIntro = false
        if isTutorialArmed, model.state != .intro {
            // A zero-point pause is not progress: rewind it so the lesson can
            // shape the arena from the first round, then walk on as usual.
            model.rewindUnscoredRun()
            showsPauseCard = false
            playsKingEntrance = true
        } else if showsPauseCard, model.state != .intro {
            showsPauseCard = false
            model.resume()
        } else {
            showsPauseCard = false
            playsKingEntrance = true
        }
    }

    private func finishKingEntrance() {
        guard playsKingEntrance else { return }
        playsKingEntrance = false
        Task {
            await model.begin()
            // The walkthrough opens on the first round, once the King is on his
            // feet and there is an arena to talk about. Disarming it here is
            // what makes the pause card offer Continue rather than Start
            // tutorial.
            if isTutorialArmed, model.state != .intro {
                isTutorialArmed = false
                tutorial.begin(model: model)
            }
        }
    }

    /// The cap on the start card. The lesson may still be added until the first
    /// point has been earned; after that the button explains itself instead.
    private func toggleTutorial() {
        AppAudio.shared.playMenuTap()
        let savedPoints = PausedSessionStore.shared.session(request.board)?.cards ?? 0
        guard !tutorial.isActive,
              !model.isGameOver,
              model.cards == 0,
              savedPoints == 0 else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                showsTutorialNotice = true
            }
            return
        }
        withAnimation(.snappy(duration: 0.2)) { isTutorialArmed.toggle() }
    }

    // MARK: - Playfield

    private var playfield: some View {
        // The arena is the whole screen — water from the very top edge down to
        // the sea floor at the very bottom — with the HUD laid over it. Reading
        // the insets here is what keeps the sum clear of the HUD and the crabs
        // clear of the home indicator.
        // The HUD keeps a floor under it, so it still clears the status bar on
        // the very first frame, before the insets have been sampled.
        let topInset = max(screenInsets.top, isPad ? 24 : 16)

        return ZStack(alignment: .top) {
            MathRiverPlayfield(round: model.round,
                               missedSum: model.missedSum,
                               maximumRounds: model.maximumRounds,
                               character: character,
                               isPad: isPad,
                               isLive: model.acceptsInput,
                               isRunning: isArenaRunning,
                               playsEntrance: playsKingEntrance,
                               playsLevelCompletion: playsLevelCompletion,
                               reduceMotion: reduceMotion,
                               honeyFlowActive: model.isHoneyFlowActive,
                               tutorialPlan: tutorial.plan,
                               reservesTutorialMessage: reservesTutorialMessage,
                               topReserve: playfieldTopReserve(topInset: topInset),
                               bottomReserve: screenInsets.bottom,
                               scoreTarget: scoreIconCenter,
                               onAnswer: { model.select(optionID: $0) },
                               onRewardArrived: model.scoreBubbleArrived,
                               onBranchHoney: model.collectRouteHoney,
                               onLanding: model.landed,
                               onEntranceComplete: finishKingEntrance,
                               onLevelCompletionStarted: { showsFinale = true },
                               onLevelCompletionFinished: finishLevelCompletion,
                               onTutorialEvent: tutorial.handle,
                               onWaveComplete: model.completeWave)

            // The forest stays vivid below, while the reading layer gets a
            // calm strip of contrast. It has no card edge and therefore never
            // competes with the sum board or the answer markers.
            LinearGradient(colors: [.black.opacity(0.20),
                                    .black.opacity(0.08),
                                    .clear],
                           startPoint: .top,
                           endPoint: .bottom)
                .frame(height: playfieldTopReserve(topInset: topInset) + (isPad ? 72 : 52))
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            hud
                .padding(.leading, max(isPad ? 28 : 16, screenInsets.leading + 12))
                .padding(.trailing, max(isPad ? 28 : 16, screenInsets.trailing + 12))
                .padding(.top, topInset + (isPad ? 12 : 6))
                // Stays for the last crab's walk: the shell it is carrying is
                // still on its way up to this counter.
                .opacity(showsFinale ? 0 : 1)
                .animation(.easeOut(duration: 0.22), value: showsFinale)
                .allowsHitTesting(!playsLevelCompletion)

            // The walkthrough speaks from the strip of water directly under the
            // sum, which the arena keeps free for the whole run. It never takes
            // a touch: every crab stays tappable while a step is being read.
            if let message = tutorial.message, !showsFinale {
                TutorialMessageCard(text: message, theme: character, isPad: isPad)
                    .padding(.horizontal, max(isPad ? 28 : 14, screenInsets.leading + 12))
                    .padding(.top, tutorialMessageTop(topInset: topInset))
                    // Fades in place rather than sliding down: a card that
                    // travelled would cross the HUD on its way in, and nothing
                    // around it moves for it either way.
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .allowsHitTesting(false)
                    .id(tutorial.step)
            }
        }
        .ignoresSafeArea()
        .onPreferenceChange(ScoreIconCenterPreferenceKey.self) { center in
            scoreIconCenter = center
        }
    }

    /// Whether the arena holds the strip under the sum free for the
    /// walkthrough's note. True from the session's very first layout of a run
    /// that was started to be taught — before the King has even walked on, let
    /// alone said anything — and it stays true after the last message has gone.
    /// The band appearing or disappearing is what used to shunt the sea floor,
    /// the King and every walking crab about, once at the opening and again at
    /// the end; held for the whole run, nothing moves at all.
    private var reservesTutorialMessage: Bool {
        isTutorialArmed || tutorial.reservesMessageArea
    }

    /// The room the arena leaves for the HUD above it.
    private func playfieldTopReserve(topInset: CGFloat) -> CGFloat {
        topInset + (isPad ? 12 : 6) + hudColumnHeight
    }

    /// The walkthrough sits flush under the sum board.
    private func tutorialMessageTop(topInset: CGFloat) -> CGFloat {
        topInset + (isPad ? 12 : 6) + hudColumnHeight + (isPad ? 10 : 8)
    }

    private func finishLevelCompletion() {
        guard playsLevelCompletion else { return }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
            showsResult = true
        }
        // Keep the final bubble bloom under the card during its entrance so
        // there is never a flash of the bare playfield between both scenes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            playsLevelCompletion = false
        }
    }

    // MARK: - HUD

    private var hud: some View {
        VStack(alignment: .leading, spacing: isPad ? 8 : 6) {
            // One landscape band. Equal rails keep the sum optically centred,
            // and every control shares the pause button's height so the HUD
            // stays a single row instead of a stacked portrait header.
            ZStack(alignment: .top) {
                RiverQuestionBanner(prompt: model.round?.question.prompt ?? "",
                                    roundID: model.round?.id,
                                    feedback: model.answerFeedback,
                                    ink: character.deepColor,
                                    isPad: isPad)
                    .padding(.horizontal, hudSideWidth)
                    .allowsHitTesting(false)

                HStack(alignment: .center, spacing: 0) {
                    HStack(spacing: isPad ? 10 : 8) {
                        pauseButton
                        LivesView(lives: model.livesRemaining,
                                  character: character,
                                  isPad: isPad,
                                  glyphSize: isPad ? 26 : 18,
                                  rowHeight: hudControlSize)
                    }
                    .frame(minWidth: hudSideWidth, alignment: .leading)
                    .frame(height: hudControlSize)

                    Spacer(minLength: 0)

                    HStack(spacing: isPad ? 8 : 6) {
                        progressCounter
                        HoneyFlowMeter(progress: model.honeyFlowProgress,
                                       isActive: model.isHoneyFlowActive,
                                       burstID: model.honeyFlowBurstID,
                                       theme: character,
                                       isPad: isPad,
                                       showsLabel: isPad)
                    }
                    .frame(minWidth: hudSideWidth, alignment: .trailing)
                    .frame(height: hudControlSize)
                }
            }

            if let missedSum = model.missedSum, !showsFinale, !tutorial.isActive {
                RiverMissedNote(text: missedSum.text, ink: character.deepColor, isPad: isPad)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Pausing freezes the arena in place and puts the level card over it. The
    /// player can continue immediately or leave for the main menu from there.
    private var pauseButton: some View {
        Button {
            AppAudio.shared.playMenuTap()
            model.pause()
            showsPauseCard = true
            showsIntro = true
        } label: {
            Circle()
                .fill(character.deepColor)
                .frame(width: hudControlSize, height: hudControlSize)
                .overlay {
                    Image(systemName: "pause.fill")
                        .font(.system(size: pauseGlyphSize, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().stroke(.white.opacity(0.92), lineWidth: isPad ? 3 : 2.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pause")
        .accessibilityLabel(Text("game.pause"))
    }

    private var hudControlSize: CGFloat { isPad ? 52 : 40 }
    private var pauseGlyphSize: CGFloat { isPad ? 24 : 18 }
    /// Wide enough for pause plus three hearts on the left, and the score
    /// plus Honey Flow on the right, without eating the sum board.
    private var hudSideWidth: CGFloat { isPad ? 300 : 186 }
    private var hudColumnHeight: CGFloat { RiverQuestionBanner.height(isPad: isPad) }

    /// Same disc as the pause button, with the score as a digit on it.
    private var progressCounter: some View {
        HStack(spacing: isPad ? 6 : 4) {
            MasteryIcon(size: isPad ? 19 : 14)
                .foregroundStyle(.white)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScoreIconCenterPreferenceKey.self,
                            value: CGPoint(x: proxy.frame(in: .global).midX,
                                           y: proxy.frame(in: .global).midY)
                        )
                    }
                }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: LN(model.cards))
                    .modifier(NumericCountTransition(value: Double(model.cards)))
                Text(verbatim: "/\(LN(model.maximumRounds))")
                    .opacity(0.72)
            }
            .font(.system(size: isPad ? 18 : 14, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
        .foregroundStyle(.white)
        .frame(height: hudControlSize)
        .padding(.horizontal, isPad ? 12 : 9)
        .background(Capsule().fill(character.deepColor))
        .overlay(Capsule().stroke(.white.opacity(0.92), lineWidth: isPad ? 3 : 2.5))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.cards)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("progress")
        .accessibilityLabel(Text(L("game.accessibility.scoreOutOf \(model.cards) \(model.maximumRounds)")))
        .accessibilityValue(Text(verbatim: "\(LN(model.cards)) / \(LN(model.maximumRounds))"))
    }

    /// The arena only ticks while the level is actually being played: never
    /// behind the start card or the result card, and never while the app is in
    /// the background.
    private var isArenaRunning: Bool {
        !showsIntro && (!model.isGameOver || playsLevelCompletion) && scenePhase == .active
    }
}

struct HoneyFlowMeter: View {
    let progress: Int
    let isActive: Bool
    let burstID: Int
    let theme: AnimalCharacter
    let isPad: Bool
    var showsLabel = true

    var body: some View {
        HStack(spacing: isPad ? 7 : 5) {
            CurrencyIcon(size: isPad ? 16 : 12)
            ForEach(0..<GameConfig.honeyFlowThreshold, id: \.self) { index in
                Capsule()
                    .fill(index < progress ? Color.yellow : Color.white.opacity(0.24))
                    .frame(width: isPad ? 24 : 18, height: isPad ? 8 : 6)
                    .shadow(color: isActive ? .yellow.opacity(0.9) : .clear, radius: 5)
            }
            if showsLabel {
                Text(verbatim: isActive
                     ? L("Honey Flow! +\(GameConfig.honeyFlowBonusHoney)")
                     : L(key: "Honey Flow"))
                    .font(.system(size: isPad ? 13 : 10, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, isPad ? 11 : 9)
        .frame(height: isPad ? 30 : 24)
        .background(Capsule().fill(theme.deepColor.opacity(isActive ? 0.96 : 0.78)))
        .overlay(Capsule().stroke(Color.yellow.opacity(isActive ? 0.9 : 0.24), lineWidth: 1.2))
        .scaleEffect(isActive ? 1.06 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.62), value: burstID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L("Honey Flow: \(progress) of \(GameConfig.honeyFlowThreshold)")))
    }
}

private struct HoneyChapterAnnouncement: View {
    let chapter: HoneyRunChapter
    let theme: AnimalCharacter
    let isPad: Bool

    var body: some View {
        VStack {
            Spacer()
            Text(verbatim: L(key: chapter.titleKey))
                .font(.system(size: isPad ? 26 : 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(theme.deepColor.opacity(0.86), in: Capsule())
                .overlay(Capsule().stroke(Color.yellow.opacity(0.7), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
            Spacer().frame(height: isPad ? 130 : 92)
        }
        .allowsHitTesting(false)
    }
}

private struct RouteHoneyToast: View {
    let theme: AnimalCharacter
    let isPad: Bool

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                CurrencyIcon(size: isPad ? 21 : 16)
                Text(verbatim: L(key: "Branch honey +1"))
                    .font(.system(size: isPad ? 17 : 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(theme.deepColor.opacity(0.90), in: Capsule())
            .padding(.bottom, isPad ? 80 : 54)
        }
        .allowsHitTesting(false)
    }
}

struct ScoreIconCenterPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint? = nil

    static func reduce(value: inout CGPoint?, nextValue: () -> CGPoint?) {
        value = nextValue() ?? value
    }
}

// MARK: - Level wallpaper

/// The level's own quiet wallpaper: a staggered grid of the level's number and
/// sign ("3×", "−4", "25%") or a stacked fraction, in a faint wash of the
/// theme colour. Carried over from the original game.
struct LevelWallpaper: View {
    let level: MathLevel
    let tint: Color

    /// The glyph that fills the wallpaper, built from the level's own card
    /// number so it reads like the level itself. Fractions draw a stacked
    /// fraction instead and return nil here.
    private var glyph: String? {
        let n = level.cardNumber
        switch level.topic {
        case .addition:    return "\(n)+"
        case .subtraction: return "−\(n)"
        case .tables:      return "\(n)×"
        case .percentages: return "\(n)%"
        case .mixed:       return "\(n)★"
        case .fractions:   return nil
        }
    }

    private var isPad: Bool { AppLayout.isPad }
    private var fontSize: CGFloat { isPad ? 30 : 22 }
    private var spacingX: CGFloat { isPad ? 118 : 86 }
    private var spacingY: CGFloat { isPad ? 104 : 76 }

    var body: some View {
        GeometryReader { proxy in
            let columns = Int(ceil(proxy.size.width / spacingX)) + 1
            let rows = Int(ceil(proxy.size.height / spacingY)) + 1

            ZStack {
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        tile
                            .position(
                                // Every other row is offset by half a step, so
                                // the pattern staggers instead of gridding.
                                x: CGFloat(column) * spacingX
                                    + (row.isMultiple(of: 2) ? 0 : spacingX / 2),
                                y: CGFloat(row) * spacingY
                            )
                    }
                }
            }
        }
        .foregroundStyle(tint.opacity(0.10))
        // Flatten ~100 Text tiles into one layer so the playfield does not
        // composite them under every crab redraw.
        .drawingGroup(opaque: false)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var tile: some View {
        if let glyph {
            Text(verbatim: glyph)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
        } else {
            // The fraction levels have one denominator each, so the wallpaper
            // mirrors it: 1/3 on the thirds level, and so on.
            VStack(spacing: 1) {
                Text(verbatim: "1")
                Rectangle().frame(height: 2)
                Text(verbatim: level.cardNumber)
            }
            .font(.system(size: fontSize * 0.62, weight: .heavy, design: .rounded))
            .fixedSize()
        }
    }
}

// MARK: - Lives

struct LivesView: View {
    let lives: Double
    let character: AnimalCharacter
    let isPad: Bool
    /// Matches the bubble in the centre of the HUD.
    var glyphSize: CGFloat = 16
    /// Keeps every HUD group centred on the pause button's horizontal axis.
    var rowHeight: CGFloat = 34

    private var wholeHearts: Int { Int(lives.rounded(.down)) }
    private var hasHalf: Bool { lives - Double(wholeHearts) >= 0.5 }
    private var capacity: Int { Int(GameConfig.startingLives.rounded(.up)) }

    /// Hearts wear the character's own deep colour — the same one the counter
    /// and the close button use — rather than a generic red.
    private var heartColor: Color { character.deepColor }

    var body: some View {
        HStack(spacing: isPad ? 5 : 3) {
            ForEach(0..<capacity, id: \.self) { index in
                heart(at: index)
            }
        }
        .frame(height: rowHeight, alignment: .center)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: lives)
        .accessibilityElement()
        .accessibilityIdentifier("lives")
        .accessibilityLabel(Text(L("game.livesRemaining \(livesText)")))
        .accessibilityValue(Text(verbatim: livesText))
    }

    private var livesText: String {
        // Halves read as "2.5" — or "2,5" in Dutch; whole lives never show a
        // decimal tail.
        lives == lives.rounded()
            ? "\(Int(lives))"
            : String(format: "%.1f", locale: LanguageManager.shared.locale, lives)
    }

    /// A full, half or empty heart. The half heart is the full glyph masked to
    /// its leading half over the empty one, so the two always align exactly.
    private func heart(at index: Int) -> some View {
        let size = glyphSize
        return ZStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(.white.opacity(0.85))
                .scaleEffect(1.22)
            Image(systemName: "heart.fill")
                .foregroundStyle(heartColor.opacity(0.22))
            if index < wholeHearts {
                Image(systemName: "heart.fill")
                    .foregroundStyle(heartColor)
            } else if index == wholeHearts && hasHalf {
                Image(systemName: "heart.fill")
                    .foregroundStyle(heartColor)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size / 2)
                    }
            }
        }
        .font(.system(size: size, weight: .bold))
        .frame(width: size, height: size)
    }
}
