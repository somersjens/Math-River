//
//  LevelIntroCard.swift
//  Math Memory
//
//  The card shown before a level starts: what kind of sums it holds, which
//  levels the questions are drawn from, and how many cards can be collected.
//  Restored from the original start screen; only the settings it offers have
//  changed, since lives and the answer helper are no longer optional here.
//

import SwiftUI

/// Short, child-friendly descriptions of what a level contains. All copy comes
/// from the string catalog, and every number is read from `MathScaling` so the
/// text always matches the questions the player will actually get.
enum LevelIntro {
    /// Title plus the three explanation lines for a level.
    static func info(for board: LevelBoard) -> (title: String, bullets: [String]) {
        let level = board.level
        let n = max(1, level.index)

        let title: String
        let topicLine: String
        switch level.topic {
        case .addition:
            title = L("levelIntro.addition.title \(n)")
            topicLine = L("levelIntro.addition.intro")
        case .subtraction:
            title = L("levelIntro.subtraction.title \(n)")
            topicLine = L("levelIntro.subtraction.intro")
        case .tables:
            title = L("levelIntro.tables.title \(n)")
            topicLine = L("levelIntro.tables.intro")
        case .fractions:
            let d = MathScaling.fractionDenominator(n)
            title = L("levelIntro.fractions.title \(d)")
            topicLine = L("levelIntro.fractions.intro")
        case .percentages:
            // The percent sign travels inside the argument, so no catalog value
            // contains a bare "%".
            let p = "\(MathScaling.percentage(n))%"
            title = L("levelIntro.percentages.title \(p)")
            topicLine = L("levelIntro.percentages.intro")
        case .mixed:
            title = L("levelIntro.mixed.title \(n)")
            topicLine = L("levelIntro.mixed.intro")
        }

        // Line two: which sums this run actually draws, which depends on the
        // order button — and picking the right card out of the ones on offer.
        let levelLine = modeLine(for: board)

        // Line three: what there is to collect here.
        let cardsLine = L("levelIntro.cardsBullet \(board.maximum)")

        return (title, [topicLine, levelLine, cardsLine])
    }

    /// The middle line, written for the mode being played. Mixed is the only
    /// one that reaches down to the levels below, so it is the only one that
    /// names a range; Order and Random describe this level's own sums. On
    /// Fractions and Percentages the three buttons change the *kind* of sum,
    /// so those two topics get their own wording.
    private static func modeLine(for board: LevelBoard) -> String {
        let n = max(1, board.level.index)

        // Supermix has no order buttons — its four combinations are the choice
        // — and it always draws from this level and every level below it.
        if board.level.topic.usesSupermixGrid || board.mode == .mixed {
            return n == 1
                ? L("levelIntro.levelRange.first")
                : L("levelIntro.levelRange \(n)")
        }

        let topicPart: String
        switch board.level.topic {
        case .fractions:   topicPart = "fractions."
        case .percentages: topicPart = "percentages."
        default:           topicPart = ""
        }
        let suffix = board.mode == .order ? "order" : "random"
        return L(key: "levelIntro.mode.\(topicPart)\(suffix)")
    }

    /// The glyph shown beside the first line.
    static func symbol(for level: MathLevel) -> String {
        level.topic.symbolName
    }
}

struct LevelIntroCard: View {
    let board: LevelBoard
    let theme: AnimalCharacter
    /// True when this instance was opened by the in-game pause button. A saved
    /// session also makes the card a continuation screen on a later visit.
    var isPauseCard = false
    /// Whether pressing Start will play the walkthrough.
    var isTutorialArmed = false

    private var level: MathLevel { board.level }
    /// The cap beside the two audio switches. It decides for itself whether the
    /// walkthrough can be armed at all, and says so when it cannot.
    var onToggleTutorial: () -> Void = {}
    let onStart: () -> Void
    let onExit: () -> Void

    /// The session waiting to be continued, if the player left this level
    /// part-way through.
    private var paused: PausedSession? {
        PausedSessionStore.shared.session(board)
    }

    private var isContinuation: Bool { isPauseCard || paused != nil }

    @ObservedObject private var audio = AppAudio.shared
    @ObservedObject private var language = LanguageManager.shared

    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.2 : 1 }
    /// Text on the larger iPad card gets one additional readability step;
    /// buttons intentionally keep their established touch proportions.
    private var textScale: CGFloat { isPad ? 1.296 : 1 }
    private var actionScale: CGFloat { isPad ? 1.2 : 1 }
    /// The heading leads the copy without competing with the portrait.
    private var titleScale: CGFloat { 1.2 }
    /// The tile glyphs and their explanatory copy step down separately, so the
    /// three lines stay comfortably readable rather than shouting.
    private var featureIconScale: CGFloat { 0.8 }
    private var featureTextScale: CGFloat { isPad ? (1.1 * 0.9) : (0.88 * 0.9 * 1.1) }
    private var portraitSize: CGFloat { 70 * scale }

    var body: some View {
        let info = LevelIntro.info(for: board)
        let features = [
            IntroFeature(icon: LevelIntro.symbol(for: level), text: info.bullets[0]),
            IntroFeature(number: level.cardNumber, text: info.bullets[1]),
            IntroFeature(icon: Currency.icon, text: info.bullets[2])
        ]

        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            characterPortrait
                            // Title on top, its two audio switches directly
                            // beneath it, side by side.
                            VStack(alignment: .leading, spacing: 0) {
                                Text(info.title)
                                    .font(.system(size: 33 * textScale * titleScale,
                                                  weight: .heavy, design: .rounded))
                                    .foregroundStyle(theme.deepColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 0)
                                audioControlRow
                            }
                            .frame(height: portraitSize)
                        }

                        DashedDivider(color: theme.color.opacity(0.45))
                            .padding(.vertical, 4)

                        ForEach(features) { feature in
                            featureCard(feature)
                        }

                        VStack(spacing: 10) {
                            Button(action: onStart) {
                                Text(startTitleKey)
                                    .font(.system(size: 17 * actionScale, weight: .heavy))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15 * actionScale)
                                    .foregroundStyle(.white)
                                    .background(theme.deepColor,
                                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("intro-start")

                            Button(action: onExit) {
                                Text("game.intro.backToMainMenu")
                                    .font(.system(size: 17 * actionScale, weight: .heavy))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15 * actionScale)
                                    .foregroundStyle(theme.deepColor)
                                    .background(.white.opacity(0.7),
                                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(theme.deepColor.opacity(0.14), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("intro-back")
                        }

                        if isContinuation {
                            pausedMessage
                        }
                    }
                    .padding(28 * scale)
                    .padding(.top, 4)
                    .frame(maxWidth: 420 * scale)
                    // Explicit white: `.background` follows Dark Mode and the
                    // deep-purple copy on this card becomes unreadable.
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(theme.deepColor.opacity(0.14), lineWidth: 1))
                    .shadow(color: theme.deepColor.opacity(0.28), radius: 18, y: 8)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    /// What the big button promises. The walkthrough takes precedence over
    /// everything else: it can only be armed on a fresh run, so it can never
    /// contradict the continuation label.
    private var startTitleKey: LocalizedStringKey {
        if isTutorialArmed { return "game.intro.startTutorial" }
        return isContinuation ? "game.intro.continue" : "game.intro.start"
    }

    /// Confirms that the run is safely waiting without repeating a potentially
    /// awkward singular/plural bubble count.
    private var pausedMessage: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.fill")
            Text("game.intro.progressPaused")
        }
        .font(.system(size: 13 * textScale, weight: .semibold))
        .foregroundStyle(theme.deepColor.opacity(0.62))
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("intro-paused")
    }

    // MARK: - Pieces

    private var characterPortrait: some View {
        theme.artwork
            .resizable()
            .scaledToFit()
            .padding(5)
            .frame(width: portraitSize, height: portraitSize)
            .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.deepColor.opacity(0.12), lineWidth: 1))
    }

    /// Music and sound effects are controlled separately, so a player can keep
    /// the feedback sounds while silencing the background track.
    private var audioControlRow: some View {
        HStack(spacing: 7 * scale) {
            audioButton(icon: "music.note",
                        isOn: audio.musicEnabled,
                        accessibilityLabel: L("settings.music")) {
                withAnimation(.snappy(duration: 0.2)) { audio.toggleMusic() }
            }
            audioButton(icon: "speaker.wave.2.fill",
                        isOn: audio.gameSoundsEnabled,
                        accessibilityLabel: L("settings.soundEffects")) {
                withAnimation(.snappy(duration: 0.2)) { audio.toggleGameSounds() }
            }
            tutorialButton
            Spacer(minLength: 0)
        }
    }

    /// The third switch in the row: play this level as a walkthrough. It reads
    /// as "selected" rather than "on/off", because arming it changes what the
    /// big button below does.
    private var tutorialButton: some View {
        Button(action: onToggleTutorial) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 16 * scale, weight: .heavy))
                .foregroundStyle(isTutorialArmed ? .white : theme.deepColor)
                .frame(width: 40 * scale, height: 32 * scale)
                .background(isTutorialArmed ? AnyShapeStyle(theme.deepColor)
                                            : AnyShapeStyle(theme.skyColor),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.deepColor.opacity(isTutorialArmed ? 0 : 0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("intro-tutorial")
        .accessibilityLabel(Text("tutorial.button"))
        .accessibilityValue(Text(isTutorialArmed ? "common.on" : "common.off"))
    }

    private func audioButton(icon: String,
                             isOn: Bool,
                             accessibilityLabel: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 17 * scale, weight: .heavy))
                if !isOn {
                    // The struck-through glyph reads as "off" at a glance.
                    Capsule()
                        .fill(theme.deepColor)
                        .frame(width: 23 * scale, height: 2.3 * scale)
                        .rotationEffect(.degrees(-45))
                }
            }
            .foregroundStyle(theme.deepColor.opacity(isOn ? 1 : 0.55))
            .frame(width: 40 * scale, height: 32 * scale)
            .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(theme.deepColor.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityValue(Text(isOn ? "common.on" : "common.off"))
    }

    private func featureCard(_ feature: IntroFeature) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let number = feature.number {
                    Text(verbatim: number)
                        .font(.system(size: 34 * textScale * featureIconScale,
                                      weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .allowsTightening(true)
                } else {
                    if feature.icon == Currency.icon {
                        CurrencyIcon(size: 28 * textScale * featureIconScale)
                    } else {
                        Image(systemName: feature.icon)
                            .font(.system(size: (feature.icon == "multiply" ? 34 : 28)
                                          * textScale * featureIconScale, weight: .bold))
                    }
                }
            }
            .foregroundStyle(theme.deepColor)
            .frame(width: 54 * scale, height: 54 * scale)
            .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.deepColor.opacity(0.14), lineWidth: 1))

            Text(emphasizedAttributedString(feature.text))
                .font(.system(size: 15 * textScale * featureTextScale, weight: .regular))
                .foregroundStyle(theme.deepColor.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 6 * scale)
        .background(theme.skyColor.opacity(0.32), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(theme.deepColor.opacity(0.10), lineWidth: 1))
    }

    private struct IntroFeature: Identifiable {
        let icon: String
        let number: String?
        let text: String

        init(icon: String, text: String) {
            self.icon = icon
            self.number = nil
            self.text = text
        }

        init(number: String, text: String) {
            self.icon = "number"
            self.number = number
            self.text = text
        }

        var id: String { "\(icon)-\(number ?? "")-\(text)" }
    }

    /// A single-stroke divider avoids the doubled edge a dashed rectangle
    /// creates at this small height.
    private struct DashedDivider: View {
        let color: Color

        var body: some View {
            GeometryReader { proxy in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            .frame(height: 2)
        }
    }
}
