//
//  ResultView.swift
//  Math Memory
//
//  The end-of-session card: a level-specific completion title (or game-over
//  title), a short message, the score out of what the board holds, and the two
//  ways onward. Its sizing mirrors the Jumping Fox end-level card.
//

import SwiftUI

struct ResultView: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let result: SessionResult
    /// Which scoreboard was played: it sets what a full score is worth here.
    let board: LevelBoard
    let character: AnimalCharacter
    let onPlayAgain: () -> Void
    let onExit: () -> Void

    @State private var isPresented = false
    @State private var badgeLanded = false
    @State private var shineSweep = false
    @State private var showsBubbleRain = false

    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.2 : 1 }
    private var textScale: CGFloat { isPad ? 1.296 : 1 }

    private var maximum: Int { board.maximum }
    /// The score is simply the number of questions answered correctly.
    private var levelScore: Int { min(result.cardsEarned, maximum) }
    private var bestScore: Int { min(max(result.personalBest, levelScore), maximum) }
    private var masteryStars: Int {
        GameConfig.masteryThresholds.filter { bestScore >= $0 }.count
    }
    private var showsNewBest: Bool { result.isNewPersonalBest && result.cardsEarned > 0 }

    private var isCompleted: Bool { result.reason == .roundsCompleted }

    /// A completed board always gets the same celebratory description. When
    /// the player runs out of lives, every three bubbles advance to the next
    /// encouraging message, capped at the tenth message.
    private var encouragement: String {
        guard !isCompleted else { return L(key: "Great run — your honey is safely stored.") }
        let index = min(max(levelScore, 0) / 3, 9)
        return L(key: "game.encouragement.\(index)")
    }

    private var recommendation: String {
        if bestScore >= maximum { return L(key: "Ready for the next level!") }
        return L("Practice \(LevelIntro.info(for: board).title) one more time.")
    }

    private var titleKey: LocalizedStringKey {
        switch result.reason {
        case .outOfLives:      return "game.end.gameOverTitle"
        case .roundsCompleted: return "result.complete"
        case .quit:            return "result.stopped"
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(isPresented ? 0.30 : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.42), value: isPresented)

            LinearGradient(
                colors: [character.deepColor.opacity(isPresented ? 0.14 : 0),
                         .clear,
                         character.tintColor.opacity(isPresented ? 0.08 : 0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    landscapeCard
                        .padding(22 * scale)
                        .frame(maxWidth: isPad ? 820 : 700)
                        .resultCardSurface(character: character)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(isPresented ? 1 : 0.965)
            .offset(y: isPresented ? 0 : 14)

            // Layered above the card, so the burst rains over the result rather
            // than behind it. It starts once the card entrance is underway.
            if showsBubbleRain {
                BubbleRainView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                isPresented = true
            }
            // Only a score this level has never seen before rains bubbles;
            // matching or falling short of the old best ends quietly.
            guard showsNewBest else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                showsBubbleRain = true
            }
            // The badge drops in after the card has settled, then glints once.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.52)) {
                    badgeLanded = true
                }
                withAnimation(.easeInOut(duration: 0.7).delay(0.22)) {
                    shineSweep = true
                }
            }
        }
    }

    /// The result, the explanation and the score form one reading column.
    /// The action side contains actions only.
    private var landscapeCard: some View {
        HStack(alignment: .center, spacing: 28 * scale) {
            VStack(spacing: 0) {
                characterBadge
                    .accessibilityHidden(true)
                    .padding(.bottom, -6 * scale)

                titleBlock

                scoreSummary
                    .padding(.top, 14 * scale)

                if !result.unlockedCharacterIDs.isEmpty {
                    unlockedRow
                        .padding(.top, 12 * scale)
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(character.deepColor.opacity(0.14))
                .frame(width: 1, height: isPad ? 280 : 220)

            buttons
                .frame(width: isPad ? 250 : 210)
        }
    }

    /// Same treatment as the premium preview: a soft glow, a thin ring and the
    /// artwork floating free, so the end card belongs to the same landscape
    /// family as the rest of the menus.
    private var characterBadge: some View {
        let heroSize = 108 * scale
        return ZStack {
            if isCompleted {
                Text(verbatim: "✦")
                    .font(.system(size: 18 * scale, weight: .bold))
                    .foregroundStyle(character.color.opacity(0.68))
                    .offset(x: -heroSize * 0.42, y: -heroSize * 0.28)
                Text(verbatim: "✦")
                    .font(.system(size: 14 * scale, weight: .bold))
                    .foregroundStyle(character.color.opacity(0.68))
                    .offset(x: heroSize * 0.44, y: -heroSize * 0.12)
            }
            Circle()
                .fill(RadialGradient(
                    colors: [character.color.opacity(0.35), character.color.opacity(0.05)],
                    center: .center, startRadius: 6, endRadius: heroSize * 0.8
                ))
                .frame(width: heroSize, height: heroSize)
            Circle()
                .stroke(character.color.opacity(0.30), lineWidth: 2)
                .frame(width: heroSize * 0.92, height: heroSize * 0.92)
            character.artwork
                .resizable()
                .scaledToFit()
                .frame(width: heroSize * 0.86, height: heroSize * 0.86)
                .shadow(color: character.deepColor.opacity(0.25), radius: 12, y: 7)
                .scaleEffect(isPresented ? 1 : 0.4)
                .rotationEffect(.degrees(isPresented ? 0 : -18))
                .animation(.spring(response: 0.55, dampingFraction: 0.55),
                           value: isPresented)
        }
        .frame(width: heroSize, height: heroSize)
    }

    private var titleBlock: some View {
        VStack(spacing: 10 * scale) {
            if isCompleted {
                completionTitle
                    .frame(maxWidth: .infinity)
            } else {
                Text(titleKey)
                    .font(.system(size: 29 * textScale, weight: .heavy, design: .rounded))
                    .foregroundStyle(character.deepColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            }

            encouragementRow
        }
    }

    private var encouragementRow: some View {
        HStack(spacing: 6 * scale) {
            starOrnament
            Text(verbatim: encouragement)
                .font(.system(size: (isCompleted ? 13 : 14) * textScale,
                              weight: isCompleted ? .medium : .semibold))
                .foregroundStyle(character.deepColor.opacity(0.64))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            starOrnament
        }
        .frame(minHeight: 20 * scale)
    }

    private var starOrnament: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 10 * textScale, weight: .semibold))
            .foregroundStyle(character.color.opacity(0.5))
    }

    /// "×7 complete!" — where the "×7" is a drawn label (a stacked fraction, or
    /// a glyph beside a star) rather than text, so it cannot simply be
    /// interpolated into the sentence.
    ///
    /// The catalog still owns the whole sentence: it carries one `%@`, and the
    /// label is dropped in wherever that placeholder lands. A language that puts
    /// the verb first therefore needs no code change — only a moved `%@`.
    private var completionTitle: some View {
        let fontSize = 29 * textScale
        let font = Font.system(size: fontSize, weight: .heavy, design: .rounded)
        // U+FFFC OBJECT REPLACEMENT CHARACTER: the standard stand-in for
        // embedded content, and never part of a translation.
        let placeholder = "\u{FFFC}"
        let sentence = L("game.end.completionTitle \(placeholder)")
        let parts = sentence.components(separatedBy: placeholder)

        return HStack(spacing: 7 * scale) {
            if let leading = parts.first, !leading.isEmpty {
                sentenceFragment(leading, font: font)
            }
            operationLabel(fontSize: fontSize)
            if parts.count > 1, !parts[1].isEmpty {
                sentenceFragment(parts[1], font: font)
            }
        }
        .foregroundStyle(character.deepColor)
        .accessibilityElement(children: .combine)
    }

    /// One side of the completion sentence. Leading and trailing spaces around
    /// the placeholder are dropped, since the `HStack` already spaces the parts.
    private func sentenceFragment(_ text: String, font: Font) -> some View {
        Text(verbatim: text.trimmingCharacters(in: .whitespaces))
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    @ViewBuilder
    private func operationLabel(fontSize: CGFloat) -> some View {
        let level = board.level
        let font = Font.system(size: fontSize, weight: .heavy, design: .rounded)

        switch level.topic {
        case .addition:
            scalableTitleText("+\(level.cardNumber)", font: font)
        case .subtraction:
            scalableTitleText("−\(level.cardNumber)", font: font)
        case .tables:
            scalableTitleText("×\(level.cardNumber)", font: font)
        case .percentages:
            scalableTitleText("\(level.cardNumber)%", font: font)
        case .fractions:
            stackedTitleFraction(denominator: level.cardNumber, fontSize: fontSize)
        case .mixed:
            HStack(spacing: 5 * scale) {
                scalableTitleText(level.cardNumber, font: font)
                Image(systemName: "star.fill")
                    .font(.system(size: fontSize * 0.7, weight: .heavy))
            }
        }
    }

    private func scalableTitleText(_ value: String, font: Font) -> some View {
        Text(verbatim: value)
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func stackedTitleFraction(denominator: String, fontSize: CGFloat) -> some View {
        let thickness = max(2, fontSize * 0.07)
        let font = Font.system(size: fontSize * 0.6, weight: .heavy, design: .rounded)

        return VStack(spacing: thickness + 3 * scale) {
            Text(verbatim: "1")
                .font(font)
                .lineLimit(1)
            Text(verbatim: denominator)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .overlay {
            Rectangle()
                .fill(character.deepColor)
                .frame(height: thickness)
        }
        .fixedSize()
        .padding(.horizontal, 2 * scale)
    }

    private var scoreSummary: some View {
        VStack(spacing: 12 * scale) {
            scoreCapsule

            HStack(spacing: 10 * scale) {
                resultMetric(title: L(key: "game.highScore"),
                             value: "\(LN(bestScore)) / \(LN(maximum))",
                             usesHoney: false)
                resultMetric(title: L(key: "Honey"),
                             value: "+\(LN(result.honeyEarned))",
                             usesHoney: true)
            }

            if result.honeyFlowBonusHoney + result.routeBonusHoney > 0 {
                HStack(spacing: 7 * scale) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                    Text(verbatim: L("Bonus honey +\(result.honeyFlowBonusHoney + result.routeBonusHoney)"))
                    if result.honeyFlowActivations > 0 {
                        Text(verbatim: "· \(LN(result.honeyFlowActivations))× " + L(key: "Honey Flow"))
                            .opacity(0.72)
                    }
                }
                .font(.system(size: 12 * textScale, weight: .bold, design: .rounded))
                .foregroundStyle(character.deepColor)
            }

            HStack(spacing: 7 * scale) {
                Text("Mastery")
                    .font(.system(size: 13 * textScale, weight: .bold, design: .rounded))
                ForEach(0..<GameConfig.masteryThresholds.count, id: \.self) { index in
                    Image(systemName: index < masteryStars ? "star.fill" : "star")
                        .foregroundStyle(index < masteryStars ? Color.yellow : character.color.opacity(0.34))
                }
            }
            .foregroundStyle(character.deepColor)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L("\(masteryStars) of \(GameConfig.masteryThresholds.count) mastery stars")))

            HStack(alignment: .top, spacing: 8 * scale) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(character.color)
                Text(verbatim: recommendation)
                    .multilineTextAlignment(.leading)
            }
            .font(.system(size: 14 * textScale, weight: .semibold, design: .rounded))
            .foregroundStyle(character.deepColor.opacity(0.78))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12 * scale)
            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var scoreCapsule: some View {
        Text(verbatim: L("\(levelScore) of \(maximum) correct"))
            // Keep "x / y" from flipping around.
            .font(.system(size: 30 * textScale, weight: .heavy, design: .rounded))
            .foregroundStyle(character.color)
            .padding(.horizontal, 27 * scale)
            .padding(.vertical, 10 * scale)
            .background(character.tintColor, in: Capsule())
            .overlay { Capsule().stroke(character.color.opacity(0.12), lineWidth: 1) }
            // The smaller capsule deliberately sits just beyond the score's
            // trailing top corner, leaving the tally itself unobscured. The
            // alignment follows the reading direction but the offset does not,
            // so the sign has to be turned over with it — otherwise the badge
            // lands *on* the score in Arabic instead of beside it.
            .overlay(alignment: .topTrailing) {
                if showsNewBest {
                    newBestBadge
                        .offset(x: layoutDirection == .rightToLeft ? -30 : 30, y: -16)
                        .scaleEffect(badgeLanded ? 1 : 0.4)
                        .rotationEffect(.degrees(badgeLanded ? 0 : -18))
                        .opacity(badgeLanded ? 1 : 0)
                }
            }
            .accessibilityIdentifier("score")
            .accessibilityLabel(Text(L("game.accessibility.scoreOutOf \(levelScore) \(maximum)")))
    }

    private func resultMetric(title: String, value: String, usesHoney: Bool) -> some View {
        VStack(spacing: 5 * scale) {
            HStack(spacing: 5 * scale) {
                if usesHoney {
                    CurrencyIcon(size: 14 * textScale)
                } else {
                    MasteryIcon(size: 14 * textScale)
                }
                Text(verbatim: title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(size: 12 * textScale, weight: .bold, design: .rounded))
            .foregroundStyle(character.deepColor.opacity(0.66))

            Text(verbatim: value)
                .environment(\.layoutDirection, .leftToRight)
                .font(.system(size: 18 * textScale, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9 * scale)
        .background(character.tintColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var newBestBadge: some View {
        HStack(spacing: 4) {
            Text("game.highScore")
                .lineLimit(1)
            MasteryIcon(size: 13 * textScale)
        }
        // The badge is an overlay pinned to the score capsule's width, so a long
        // translation would wrap; fixedSize lets it grow on one line instead.
        .fixedSize()
        .font(.system(size: 13 * textScale, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10 * textScale)
        .padding(.vertical, 6 * textScale)
        .background(character.color, in: Capsule())
        // A soft diagonal highlight sweeps across once as the badge lands.
        // Clipped to the capsule and starting off-badge, it is invisible before
        // and after that single pass — no fade bookkeeping needed.
        .overlay {
            Capsule()
                .fill(
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 26)
                .rotationEffect(.degrees(18))
                .offset(x: shineSweep ? 90 : -90)
                .allowsHitTesting(false)
        }
        .clipShape(Capsule())
        .accessibilityIdentifier("new-best")
    }

    private var unlockedRow: some View {
        VStack(spacing: 8) {
            Text("result.unlocked")
                .font(.system(size: 15 * textScale, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)
            HStack(spacing: 14) {
                ForEach(result.unlockedCharacterIDs, id: \.self) { id in
                    let animal = CharacterCatalog.character(id: id)
                    VStack(spacing: 4) {
                        animal.thumbArtwork
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50 * scale, height: 50 * scale)
                        Text(verbatim: animal.localizedName)
                            .font(.system(size: 11 * textScale, weight: .bold, design: .rounded))
                            .foregroundStyle(character.deepColor)
                    }
                }
            }
        }
        .padding(12 * scale)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var buttons: some View {
        VStack(spacing: 12 * scale) {
            Button(action: onPlayAgain) {
                Label("game.end.playAgain", systemImage: "arrow.counterclockwise")
                    .font(isPad ? .title3.weight(.bold) : .headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14 * scale)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [character.color, character.deepColor],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("play-again")

            Button(action: onExit) {
                Label("game.end.mainMenu", systemImage: "house.fill")
                    .font(isPad ? .title3.weight(.semibold) : .headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14 * scale)
                    .foregroundStyle(character.deepColor)
                    .background(character.skyColor, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(character.color.opacity(0.24), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("back-to-menu")
        }
    }
}

private extension View {
    func resultCardSurface(character: AnimalCharacter) -> some View {
        self
            .background(
                LinearGradient(colors: [character.skyColor, .white, character.tintColor],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
    }
}

/// A shower of bubbles for a new personal best: they drift down over the card
/// and pop, one after another, instead of the confetti this used to rain.
private struct BubbleRainView: View {
    @State private var bubbles: [RainBubble]

    init() {
        // Keep the reward visible without covering the result card in a dense
        // curtain. The varied timing still makes this feel organic.
        _bubbles = State(initialValue: (0..<18).map { _ in RainBubble() })
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(bubbles) { bubble in
                    FallingBubble(bubble: bubble, area: proxy.size)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct RainBubble: Identifiable {
    let id = UUID()
    /// Share of the width the bubble falls down.
    let x = CGFloat.random(in: 0.08...0.92)
    let diameter = CGFloat.random(in: 8...22)
    /// Share of the height at which it bursts, so they do not all pop in a line.
    let burstY = CGFloat.random(in: 0.34...0.86)
    let fallDuration = Double.random(in: 1.55...2.45)
    let delay = Double.random(in: 0...1.1)
    /// A little sideways wander on the way down.
    let drift = CGFloat.random(in: -14...14)
}

private struct FallingBubble: View {
    let bubble: RainBubble
    let area: CGSize

    @State private var hasFallen = false
    @State private var isBursting = false
    @State private var burstFinished = false

    var body: some View {
        ZStack {
            // A faint ring lingers for a moment after the shell dissolves. It
            // gives each bubble a soft finish instead of a sudden large pop.
            Circle()
                .stroke(.white.opacity(0.62), lineWidth: 0.8)
                .scaleEffect(isBursting ? (burstFinished ? 1.5 : 1.08) : 0.88)
                .opacity(isBursting && !burstFinished ? 0.3 : 0)

            Circle()
                .fill(
                    RadialGradient(colors: [.white.opacity(0.78), .white.opacity(0.16)],
                                   center: UnitPoint(x: 0.34, y: 0.30),
                                   startRadius: 1,
                                   endRadius: bubble.diameter * 0.7)
                )
                .overlay { Circle().stroke(.white.opacity(0.66), lineWidth: 0.9) }
                .scaleEffect(isBursting ? 1.14 : 1)
                .opacity(isBursting ? 0 : 0.78)
        }
        .frame(width: bubble.diameter, height: bubble.diameter)
        .position(x: area.width * bubble.x + (hasFallen ? bubble.drift : 0),
                  y: hasFallen ? area.height * bubble.burstY : -bubble.diameter)
        .onAppear {
            withAnimation(
                .timingCurve(0.32, 0.48, 0.42, 1,
                             duration: bubble.fallDuration)
                    .delay(bubble.delay)
            ) {
                hasFallen = true
            }

            // Let the bubble settle, dissolve its shell, then gently fade
            // the remaining ring. The two short phases avoid a hard cut.
            DispatchQueue.main.asyncAfter(
                deadline: .now() + bubble.delay + bubble.fallDuration + 0.06
            ) {
                withAnimation(.easeOut(duration: 0.18)) { isBursting = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.easeOut(duration: 0.34)) { burstFinished = true }
                }
            }
        }
    }
}

#if DEBUG
enum Phase3ResultPreviewMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-Phase3ResultPreview")
    }
}

/// Deterministic visual-QA entry point for the phase-3 result hierarchy.
struct Phase3ResultPreview: View {
    private let board = LevelBoard(level: MathLevel(topic: .tables, index: 8), mode: .mixed)
    private let result: SessionResult = {
        var result = SessionResult()
        result.correctAnswers = 9
        result.wrongAnswers = 3
        result.cardsEarned = 9
        result.honeyEarned = 9
        result.honeyFlowActivations = 2
        result.honeyFlowBonusHoney = 4
        result.routeBonusHoney = 1
        result.honeyEarned = 14
        result.personalBest = 10
        result.reason = .roundsCompleted
        return result
    }()

    var body: some View {
        ZStack {
            LinearGradient(colors: [.yellow.opacity(0.5), .orange.opacity(0.24)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ResultView(result: result,
                       board: board,
                       character: CharacterCatalog.character(id: "bear"),
                       onPlayAgain: {},
                       onExit: {})
        }
    }
}
#endif
