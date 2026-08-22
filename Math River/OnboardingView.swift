//
//  OnboardingView.swift
//  Elephant Challenge: Math Memory
//
//  Welcome flow: name → topic → starting point.
//
//  The last step asks exactly the same question as the three order buttons in
//  the menu, only in children's language — it is literally a pre-selection of
//  `PracticeMode`. Pick the star on step two and there is no order to set, so
//  the same answer is mapped onto the star's simplest and most complete button
//  instead.
//

import SwiftUI
import UIKit

/// Onboarding runs before the player has a character of their own, so the whole
/// flow is themed by the starter. Reading the colours from the catalog rather
/// than hardcoding them means the welcome screen follows the roster: change who
/// greets a new player and the text, buttons and highlights move with them.
private enum OnboardingTheme {
    static var character: AnimalCharacter {
        CharacterCatalog.character(id: CharacterCatalog.freeCharacterID)
    }
    /// Body and heading text.
    static var ink: Color { character.deepColor }
    /// Buttons, icons and the selected row.
    static var accent: Color { character.color }
}

struct OnboardingView: View {
    @AppStorage(GameSettings.playerNameKey) private var playerName = ""
    @AppStorage(GameSettings.onboardingCompleteKey) private var isComplete = false
    @AppStorage(GameSettings.onboardingReplayRequestedKey) private var replayRequested = false
    @AppStorage(GameSettings.topicKey) private var topicRaw = MathTopic.allCases[0].rawValue
    @AppStorage(GameSettings.practiceModeKey) private var practiceModeRaw = PracticeMode.fallback.rawValue
    @AppStorage(GameSettings.mixedVariantKey) private var mixedVariantRaw = MixedVariant.allCases[0].rawValue
    @AppStorage(GameSettings.tutorialPendingKey) private var tutorialPending = false
    @ObservedObject private var language = LanguageManager.shared
    @State private var step = 0
    @FocusState private var isNameFieldFocused: Bool

    private var isPad: Bool { AppLayout.isPad }
    private var contentWidth: CGFloat { isPad ? 640 : 500 }

    var body: some View {
        ZStack {
            onboardingBackground

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        let portrait: CGFloat = isPad
                            ? (step == 1 ? 160 : 210)
                            : (step == 1 ? 112 : 150)
                        welcomeCharacter.artwork
                            .resizable()
                            .scaledToFit()
                            .frame(width: portrait, height: portrait)
                            .padding(.bottom, isPad ? (step == 1 ? 20 : 30) : (step == 1 ? 14 : 22))
                            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: step)

                        Group {
                            let availableWidth = min(
                                contentWidth,
                                max(0, proxy.size.width - (isPad ? 72 : 48))
                            )
                            switch step {
                            case 0: nameStep
                            case 1:
                                subjectStep(usesTwoColumns: isPad && proxy.size.width > proxy.size.height)
                            default: practiceModeStep(availableWidth: availableWidth)
                            }
                        }
                        .id(step)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .frame(maxWidth: contentWidth)
                        .padding(.horizontal, isPad ? 36 : 24)
                    }
                    .padding(.vertical, isPad ? 40 : 28)
                    // On normal-height screens this fills the viewport and
                    // centres the welcome content. On smaller screens the
                    // content simply grows taller and remains scrollable.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(OnboardingTheme.ink)
        .overlay(alignment: .topLeading) {
            // Steps 2 and 3 can step back to correct a wrong choice. Mirrors
            // the language flag: same glass style, same top inset, left corner.
            if step > 0 {
                backButton
                    .padding(.top, isPad ? 20 : 8)
                    .padding(.leading, isPad ? 28 : 16)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            LanguagePicker(tint: OnboardingTheme.ink.opacity(0.6),
                           scale: isPad ? 1.25 : 1)
                .padding(.top, isPad ? 20 : 8)
                .padding(.trailing, isPad ? 28 : 16)
        }
    }

    private var backButton: some View {
        Button {
            advance(to: step - 1)
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: isPad ? 26 : 22, weight: .semibold))
                .foregroundStyle(OnboardingTheme.ink.opacity(0.6))
                .padding(.horizontal, isPad ? 16 : 13)
                .padding(.vertical, isPad ? 11 : 8)
                .liquidGlassCapsule()
                .contentShape(Capsule())
        }
        .accessibilityLabel(Text("common.back"))
    }

    /// The welcome screen is shown before anything has been earned, so it is
    /// always the starter character that greets the player.
    private var welcomeCharacter: AnimalCharacter {
        CharacterCatalog.character(id: CharacterCatalog.freeCharacterID)
    }

    private var onboardingBackground: some View {
        AmbientReefBackground(character: welcomeCharacter, showsSeaFloor: true)
    }

    private var nameStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                OnboardingTitle(
                    text: L("onboarding.name.title"),
                    fontSize: isPad ? 44 : 35
                )

                Text("onboarding.name.subtitle")
                    .font(isPad ? .title2.weight(.medium) : .title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            TextField(String(), text: $playerName, prompt: Text("name.placeholder"))
                .font(.system(size: isPad ? 34 : 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($isNameFieldFocused)
                .textContentType(.name)
                .submitLabel(.next)
                .onSubmit { goToSubjects() }
                .padding(.horizontal, isPad ? 22 : 16)
                .padding(.vertical, isPad ? 18 : 14)
                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isNameFieldFocused ? OnboardingTheme.accent : OnboardingTheme.ink.opacity(0.18),
                                lineWidth: isNameFieldFocused ? 2 : 1)
                )
                .frame(maxWidth: isPad ? 400 : 300)
                .animation(.snappy(duration: 0.2), value: isNameFieldFocused)

            Button("common.continue") { goToSubjects() }
                .buttonStyle(OnboardingButtonStyle(isPad: isPad))
                .frame(maxWidth: isPad ? 360 : .infinity)
        }
    }

    private func subjectStep(usesTwoColumns: Bool) -> some View {
        VStack(spacing: 14) {
            OnboardingTitle(
                text: L("onboarding.subject.title"),
                fontSize: isPad ? 42 : 32
            )

            Text("onboarding.subject.subtitle")
                .font(isPad ? .title3 : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12),
                    count: usesTwoColumns ? 2 : 1
                ),
                spacing: usesTwoColumns ? 12 : 8
            ) {
                ForEach(MathTopic.allCases) { option in
                    Button {
                        topicRaw = option.rawValue
                        advance(to: 2)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.symbolName)
                                .font(.system(size: isPad ? 28 : 21, weight: .bold))
                                .frame(width: isPad ? 44 : 30)
                            Text(verbatim: L(key: option.titleKey))
                                .font(isPad ? .title3.weight(.semibold) : .title3.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, isPad ? 26 : 16)
                        .frame(maxWidth: .infinity, minHeight: isPad ? 72 : 54)
                        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(OnboardingOptionStyle())
                    .accessibilityIdentifier("onboarding-topic-\(option.rawValue)")
                    .foregroundStyle(OnboardingTheme.accent)
                }
            }
        }
    }

    private var topic: MathTopic { MathTopic(rawValue: topicRaw) ?? MathTopic.allCases[0] }

    /// The three starting points, in the same order as the buttons in the menu.
    private static let modeChoices:
        [(mode: PracticeMode, titleKey: String, subtitleKey: String)] = [
        (.order,  "onboarding.level.beginner.title",     "onboarding.level.beginner.subtitle"),
        (.random, "onboarding.level.intermediate.title", "onboarding.level.intermediate.subtitle"),
        (.mixed,  "onboarding.level.advanced.title",     "onboarding.level.advanced.subtitle")
    ]

    /// The last step: how far along the player already is. This is the same
    /// question the three order buttons ask, phrased for a child — answering it
    /// leaves the menu already set the way they said, and hands over to it.
    private func practiceModeStep(availableWidth: CGFloat) -> some View {
        let sizing = choiceSizing(
            titles: Self.modeChoices.map { L(key: $0.titleKey) },
            subtitles: Self.modeChoices.map { L(key: $0.subtitleKey) },
            availableWidth: availableWidth
        )
        let topicName = L(key: topic.titleKey)

        return VStack(spacing: 14) {
            OnboardingTitle(
                text: L("onboarding.level.title"),
                fontSize: isPad ? 42 : 32
            )

            Text(verbatim: L("onboarding.level.subtitle \(topicName)"))
                .font(isPad ? .title3 : .body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            ForEach(Self.modeChoices, id: \.mode) { choice in
                Button { select(choice.mode) } label: {
                    OnboardingChoiceLabel(
                        title: L(key: choice.titleKey),
                        subtitle: L(key: choice.subtitleKey),
                        icon: choice.mode.symbolName,
                        textScale: sizing.scale,
                        allowsTwoLines: sizing.allowsTwoLines,
                        rowHeight: sizing.rowHeight,
                        isSelected: choice.mode.rawValue == practiceModeRaw
                    )
                }
                .buttonStyle(OnboardingOptionStyle())
                .accessibilityIdentifier("onboarding-mode-\(choice.mode.rawValue)")
            }
        }
    }

    /// Stores the chosen starting point and hands over to the first level.
    /// Supermix has no order buttons of its own, so the same answer is mapped
    /// onto its ladder: the most confident choice opens the most complete
    /// combination, the other two start on the simplest.
    ///
    /// The selection lands first, so the tick is visible for the moment the
    /// welcome flow fades out rather than the screen swapping out under the tap.
    private func select(_ mode: PracticeMode) {
        withAnimation(.snappy(duration: 0.18)) {
            practiceModeRaw = mode.rawValue
        }
        if topic.usesSupermixGrid {
            let target = mode == .mixed ? MixedVariant.allCases.last : MixedVariant.allCases.first
            if let target { mixedVariantRaw = target.rawValue }
        }
        AppAudio.shared.playMenuTap()
        // The welcome flow hands straight over to the start card of the first
        // level of the exercise just chosen. The menu is already underneath,
        // hidden, so the player's first sight of the game is being taught it.
        tutorialPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isComplete = true
            replayRequested = false
        }
    }

    /// Uses one shared scale for every row of a choice step, based on the
    /// widest title or subtitle in the active language, so the rows look
    /// identical in every language. If a modest scale-down is not enough, all
    /// three rows grow equally and may use a second line.
    private func choiceSizing(
        titles: [String],
        subtitles: [String],
        availableWidth: CGFloat
    ) -> (scale: CGFloat, allowsTwoLines: Bool, rowHeight: CGFloat) {
        let titleSize: CGFloat = isPad ? 20 : 20
        let subtitleSize: CGFloat = isPad ? 17 : 16
        let titleFont = UIFont.systemFont(ofSize: titleSize, weight: .semibold)
        let subtitleFont = UIFont.systemFont(ofSize: subtitleSize)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [.font: subtitleFont]

        let widestTitle = titles.map {
            ($0 as NSString).size(withAttributes: titleAttributes).width
        }.max() ?? 0
        let widestSubtitle = subtitles.map {
            ($0 as NSString).size(withAttributes: subtitleAttributes).width
        }.max() ?? 0
        let widestText = max(widestTitle, widestSubtitle)

        // Space occupied by the row padding, icon, trailing glyph and HStack
        // gaps. The trailing glyph is measured at its widest: the selected row
        // carries a tick rather than a chevron, and reserving only the chevron
        // is what used to truncate the longest subtitle on exactly that row.
        // A small safety inset avoids wrapping caused by fractional glyph
        // measurements at different display scales.
        let reservedWidth: CGFloat = isPad ? 190 : 146
        let textWidth = max(1, availableWidth - reservedWidth)
        let requiredScale = min(1, textWidth / max(1, widestText))
        let minimumComfortableScale: CGFloat = isPad ? 0.82 : 0.78
        let allowsTwoLines = requiredScale < minimumComfortableScale
        let scale = max(requiredScale, minimumComfortableScale)
        let rowHeight: CGFloat = isPad
            ? (allowsTwoLines ? 120 : 94)
            : (allowsTwoLines ? 96 : 70)

        return (scale, allowsTwoLines, rowHeight)
    }

    private func goToSubjects() {
        let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        playerName = trimmedName.isEmpty ? CharacterCatalog.defaultPlayerName : trimmedName
        isNameFieldFocused = false
        advance(to: 1)
    }

    private func advance(to newStep: Int) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            step = newStep
        }
    }
}

/// Keeps translated onboarding headings compact without leaving an orphaned
/// word on the second line. A short heading is allowed to remain on one line;
/// otherwise the fallback inserts the most visually even word-boundary break.
private struct OnboardingTitle: View {
    let text: String
    let fontSize: CGFloat

    private var normalizedText: String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var balancedText: String {
        Self.balancedTwoLineText(normalizedText, fontSize: fontSize)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // `fixedSize` makes this candidate report its true one-line width,
            // so ViewThatFits only chooses it when it genuinely fits.
            titleText(normalizedText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)

            titleText(balancedText)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(verbatim: normalizedText))
    }

    private func titleText(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
    }

    private static func balancedTwoLineText(_ text: String, fontSize: CGFloat) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return text }

        let baseFont = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        let font = baseFont.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: fontSize) } ?? baseFont
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        var bestIndex = 1
        var smallestDifference = CGFloat.greatestFiniteMagnitude

        for index in 1..<words.count {
            let firstLine = words[..<index].joined(separator: " ")
            let secondLine = words[index...].joined(separator: " ")
            let firstWidth = (firstLine as NSString).size(withAttributes: attributes).width
            let secondWidth = (secondLine as NSString).size(withAttributes: attributes).width
            let difference = abs(firstWidth - secondWidth)

            if difference < smallestDifference {
                smallestDifference = difference
                bestIndex = index
            }
        }

        return words[..<bestIndex].joined(separator: " ")
            + "\n"
            + words[bestIndex...].joined(separator: " ")
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    let isPad: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isPad ? .title3.weight(.bold) : .headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, isPad ? 22 : 15)
            .background(OnboardingTheme.accent, in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct OnboardingOptionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.52 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct OnboardingChoiceLabel: View {
    let title: String
    let subtitle: String
    let icon: String
    let textScale: CGFloat
    let allowsTwoLines: Bool
    let rowHeight: CGFloat
    /// The topic step has no persisted choice yet, so it opts out.
    var isSelected = false
    private var isPad: Bool { AppLayout.isPad }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
            .font(isPad ? .title2 : .title3)
            .frame(width: isPad ? 44 : 30)
                .foregroundStyle(OnboardingTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20 * textScale, weight: .semibold))
                    .lineLimit(allowsTwoLines ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: (isPad ? 17 : 16) * textScale))
                    .lineLimit(allowsTwoLines ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // A tick on the active choice, a chevron on the rest, so the
            // selected option is unmistakable.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.forward")
                .font(isSelected ? .title3.weight(.bold) : .footnote.weight(.bold))
                .foregroundStyle(isSelected ? AnyShapeStyle(OnboardingTheme.accent) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, isPad ? 26 : 16)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(isSelected ? AnyShapeStyle(OnboardingTheme.accent.opacity(0.16))
                               : AnyShapeStyle(.white.opacity(0.78)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OnboardingTheme.accent.opacity(isSelected ? 0.9 : 0), lineWidth: 2.5)
        )
        .foregroundStyle(OnboardingTheme.ink)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
