//
//  PremiumView.swift
//  Elephant Challenge: Math Memory
//
//  Character collection and one-time Premium purchase sheet. The first half of
//  the catalog is earned by collecting cards; the second half is Premium-only,
//  which also opens levels 13–99 of every topic.
//

import SwiftUI
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// Every size on the sheet is derived from the height the device actually
/// offers, so the hero, the offer and the whole cast fit on one landscape
/// screen instead of pushing the buy button below the fold. The base numbers
/// are tuned for an iPhone in landscape; `unit` stretches them for iPad.
private struct PremiumMetrics {
    let unit: CGFloat

    init(height: CGFloat, isPad: Bool) {
        let designHeight: CGFloat = isPad ? 515 : 390
        let raw = height / designHeight
        unit = min(isPad ? 1.55 : 1.15, max(0.72, raw))
    }

    private func s(_ value: CGFloat) -> CGFloat { value * unit }

    var cardPadding: CGFloat { s(13) }
    var stackSpacing: CGFloat { s(11) }
    var columnSpacing: CGFloat { s(14) }
    var heroSize: CGFloat { s(168) }
    var nameSize: CGFloat { s(26) }
    var badgeSize: CGFloat { s(13) }
    var panelPadding: CGFloat { s(14) }
    var featureSpacing: CGFloat { s(8) }
    var featureTitle: CGFloat { s(16) }
    var featureSubtitle: CGFloat { s(13) }
    var buttonFont: CGFloat { 17 * min(unit, 1.15) }
    var buttonPadding: CGFloat { s(10) }
    var footnote: CGFloat { s(12) }
    var stripPadding: CGFloat { s(8) }
    var tileSpacing: CGFloat { s(5) }
    var tileArt: CGFloat { s(40) }
}

struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var premium = PremiumStore.shared
    @ObservedObject private var language = LanguageManager.shared
    @AppStorage(GameSettings.characterKey) private var characterID = CharacterCatalog.freeCharacterID
    @AppStorage(GameSettings.totalCardsKey) private var totalCards = 0

    /// Set when the sheet was opened to celebrate a character the player just
    /// earned; the celebration plays once on appear.
    let celebratedUnlockCharacterID: String?

    @State private var previewCharacterID: String
    @State private var showsParentApproval = false
    @State private var showsUnlockCelebration = false
    @State private var unlockGlow = false
    @State private var unlockCharacterScale: CGFloat = 0.18
    @State private var unlockCharacterRotation = -18.0
    @State private var unlockBurstRotation = -14.0
    @State private var unlockTitleScale: CGFloat = 0.72
    @State private var unlockPulse = false
    @State private var unlockCharacterFloating = false
    @State private var activeUnlockCharacterID: String?
    @State private var pendingUnlockCharacterIDs: [String] = []
    @State private var unlockCelebrationGeneration = 0

    init(initialCharacterID: String? = nil,
         celebratedUnlockCharacterID: String? = nil) {
        self.celebratedUnlockCharacterID = celebratedUnlockCharacterID
        _previewCharacterID = State(initialValue: initialCharacterID ?? GameSettings.characterID)
    }

    private var character: AnimalCharacter { CharacterCatalog.character(id: previewCharacterID) }
    private var unlockedCharacter: AnimalCharacter? {
        activeUnlockCharacterID.map { CharacterCatalog.character(id: $0) }
    }
    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.4 : 1 }

    var body: some View {
        let _ = totalCards
        ZStack(alignment: .top) {
            LinearGradient(colors: [character.skyColor, character.tintColor],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            GeometryReader { proxy in
                let available = min(AppLayout.landscapeContentWidth,
                                    max(0, proxy.size.width - AppLayout.landscapeGutter * 2))
                let metrics = PremiumMetrics(height: proxy.size.height, isPad: isPad)

                ScrollView {
                    VStack(spacing: metrics.stackSpacing) {
                        HStack(alignment: .top, spacing: metrics.columnSpacing) {
                            heroPanel(metrics)
                                .frame(maxWidth: .infinity)
                            offerPanel(metrics)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        characterStrip(metrics)
                    }
                    .padding(metrics.cardPadding)
                    .background(.white.opacity(0.52),
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: character.deepColor.opacity(0.1), radius: 16, y: 7)
                    .padding(AppLayout.landscapeGutter)
                    .frame(width: available + AppLayout.landscapeGutter * 2)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
            }

            if showsUnlockCelebration, let unlockedCharacter {
                unlockCelebration(animal: unlockedCharacter)
                    .transition(.opacity)
                    .zIndex(10)
            } else if activeUnlockCharacterID != nil {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: previewCharacterID)
        .animation(.spring(response: 0.42, dampingFraction: 0.7), value: premium.isPremium)
        .onAppear {
            if let celebratedUnlockCharacterID {
                previewCharacterID = celebratedUnlockCharacterID
                playUnlockCelebration(characterID: celebratedUnlockCharacterID)
            }
        }
        .task { await premium.refresh() }
        .sheet(isPresented: $showsParentApproval) {
            ParentApprovalGate(
                accent: character.color,
                deepColor: character.deepColor,
                onApproved: {
                    showsParentApproval = false
                    startPurchase()
                }
            )
            .gameEnvironment()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func closeButton(metrics: PremiumMetrics) -> some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: metrics.badgeSize + 3, weight: .bold))
                .foregroundStyle(character.deepColor)
                .frame(width: metrics.badgeSize * 2.6, height: metrics.badgeSize * 2.6)
                .background(.white.opacity(0.7), in: Circle())
                .shadow(color: character.deepColor.opacity(0.15), radius: 6, y: 3)
        }
    }

    /// Left half: the character being previewed, with the close button and the
    /// language picker tucked into the top of the column.
    private func heroPanel(_ metrics: PremiumMetrics) -> some View {
        VStack(spacing: metrics.stackSpacing * 0.45) {
            HStack {
                if activeUnlockCharacterID == nil {
                    closeButton(metrics: metrics)
                    Spacer()
                    LanguagePicker(tint: character.deepColor.opacity(0.7),
                                   scale: isPad ? 1.05 : 0.82)
                } else {
                    Spacer()
                }
            }

            let heroSize = metrics.heroSize
            ZStack {
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
                    .frame(width: heroSize * 0.88, height: heroSize * 0.88)
                    .shadow(color: character.deepColor.opacity(0.25), radius: 14, y: 8)
                    .id(previewCharacterID)
                    .transition(.scale.combined(with: .opacity))
            }
            .frame(maxWidth: .infinity)

            Text(character.localizedName)
                .font(.system(size: metrics.nameSize, weight: .heavy, design: .rounded))
                .foregroundStyle(character.deepColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            availabilityBadge(for: character, metrics: metrics)
            Spacer(minLength: 0)
        }
    }

    /// Right half: the perks and the purchase, in one card so they read as a
    /// single offer instead of a portrait stack.
    private func offerPanel(_ metrics: PremiumMetrics) -> some View {
        VStack(spacing: metrics.featureSpacing) {
            featureList(metrics)
            purchaseSection(metrics)
        }
        .padding(metrics.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(.white.opacity(0.42),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [character.color, character.deepColor],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.75
                )
                .opacity(0.55)
        )
    }

    /// The whole cast in one row along the bottom. Honey prices and crowns
    /// stay on the tiles, so the two groups no longer need their own cards.
    private func characterStrip(_ metrics: PremiumMetrics) -> some View {
        HStack(spacing: metrics.tileSpacing) {
            ForEach(CharacterCatalog.all) { animal in
                characterCell(for: animal, metrics: metrics)
            }
        }
        .padding(metrics.stripPadding)
        .background(.white.opacity(0.34),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func availabilityBadge(for animal: AnimalCharacter, metrics: PremiumMetrics) -> some View {
        if animal.id == CharacterCatalog.freeCharacterID {
            badge(text: L(key: "premium.availableFromStart"), icon: nil, metrics: metrics)
        } else if let cards = CharacterUnlockStore.requirement(for: animal.id) {
            if totalCards >= cards {
                badge(text: L("You’ve earned \(cards) honey"),
                      icon: "checkmark.circle.fill", metrics: metrics)
            } else if premium.isPremium {
                badge(text: L(key: "premium.unlockedWithPremium"), icon: "crown.fill", metrics: metrics)
            } else {
                badge(text: L("Available from \(cards) honey"),
                      icon: Currency.icon, metrics: metrics)
            }
        } else {
            badge(
                text: L(key: premium.isPremium ? "premium.unlockedWithPremium" : "premium.exclusiveWithPremium"),
                icon: "crown.fill",
                metrics: metrics
            )
        }
    }

    private func badge(text: String, icon: String?, metrics: PremiumMetrics) -> some View {
        HStack(spacing: 6) {
            if let icon {
                if icon == Currency.icon {
                    CurrencyIcon(size: metrics.badgeSize)
                } else {
                    Image(systemName: icon)
                }
            }
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .font(.system(size: metrics.badgeSize, weight: .bold, design: .rounded))
        .foregroundStyle(character.deepColor)
        .padding(.horizontal, metrics.badgeSize)
        .padding(.vertical, metrics.badgeSize * 0.45)
        .background(.white.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(character.color.opacity(0.38), lineWidth: 1))
    }

    private func featureList(_ metrics: PremiumMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.featureSpacing) {
            // The level and animal counts travel as arguments rather than being
            // written into the sentence, so a translation never has to be
            // revisited when the catalog grows.
            featureRow(icon: "square.grid.3x3.fill",
                       title: L("premium.feature.levels.title \(GameConfig.maximumLevel)"),
                       subtitle: L("premium.feature.levels.subtitle"),
                       metrics: metrics)
            featureRow(icon: "pawprint.fill",
                       title: L("premium.feature.animals.title"),
                       subtitle: L("premium.feature.animals.subtitle \(CharacterUnlocks.orderedCharacterIDs.count)"),
                       metrics: metrics)
            featureRow(icon: "nosign",
                       title: L("premium.feature.noAds.title"),
                       subtitle: L("premium.feature.noAds.subtitle"),
                       metrics: metrics)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func characterCell(for animal: AnimalCharacter, metrics: PremiumMetrics) -> some View {
        let isSelected = previewCharacterID == animal.id
        let isAccessible = canUse(animal)
        return Button {
            AppAudio.shared.playMenuTap()
            previewCharacterID = animal.id
            if isAccessible { characterID = animal.id }
        } label: {
            VStack(spacing: metrics.tileSpacing) {
                animal.thumbArtwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: metrics.tileArt, height: metrics.tileArt)
                characterCellChip(for: animal, metrics: metrics)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.vertical, metrics.tileSpacing)
            .background(isSelected ? character.color.opacity(0.16) : .white.opacity(0.78),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? character.color : character.color.opacity(0.18),
                            lineWidth: isSelected ? 2.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("character-cell")
        .accessibilityLabel(animal.localizedName)
        .accessibilityValue(Text(isAccessible ? "common.unlocked" : "common.locked"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func characterCellChip(for animal: AnimalCharacter, metrics: PremiumMetrics) -> some View {
        let chipScale = metrics.unit * 0.85
        if animal.id == CharacterCatalog.freeCharacterID {
            if totalCards >= (CharacterUnlockStore.requirement(for: "frog") ?? 500) {
                Image(systemName: "checkmark.circle.fill")
                    .characterChipStyle(character: character, scale: chipScale)
            } else {
                Text(verbatim: L(key: "premium.start"))
                    .characterChipStyle(character: character, scale: chipScale)
            }
        } else if canUse(animal) {
            Image(systemName: "checkmark.circle.fill")
                .characterChipStyle(character: character, scale: chipScale)
        } else if let cards = CharacterUnlockStore.requirement(for: animal.id) {
            Text(verbatim: LN(cards))
                .characterChipStyle(character: character, scale: chipScale)
        } else {
            Image(systemName: "crown.fill")
                .characterChipStyle(character: character, scale: chipScale)
        }
    }

    private func canUse(_ animal: AnimalCharacter) -> Bool {
        CharacterUnlockStore.canUse(characterID: animal.id, isPremium: premium.isPremium)
    }

    @ViewBuilder
    private func purchaseSection(_ metrics: PremiumMetrics) -> some View {
        if premium.isPremium {
            Button { dismiss() } label: {
                Text("common.done")
                    .font(.system(size: metrics.buttonFont, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.buttonPadding)
                    .background(character.color, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: metrics.footnote * 0.35) {
                Button { showsParentApproval = true } label: {
                    HStack(spacing: 8) {
                        if premium.isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "crown.fill")
                                .font(.system(size: metrics.buttonFont, weight: .bold))
                            Text(purchaseButtonTitle)
                                .font(.system(size: metrics.buttonFont, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.buttonPadding)
                    .background(
                        LinearGradient(colors: [character.color, character.deepColor],
                                       startPoint: .top, endPoint: .bottom),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                    .shadow(color: character.deepColor.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(premium.isPurchasing)
                .accessibilityIdentifier("premium-purchase")
                .accessibilityLabel(Text(verbatim: purchaseButtonTitle))

                Text("premium.oneTime")
                    .font(.system(size: metrics.footnote))
                    .foregroundStyle(character.deepColor.opacity(0.7))
                    .multilineTextAlignment(.center)

                Button("premium.restore") {
                    Task { await premium.restorePurchases() }
                }
                .font(.system(size: metrics.footnote * 0.92))
                .foregroundStyle(character.deepColor.opacity(0.7))

                if let error = premium.lastError {
                    Text(error)
                        .font(.system(size: metrics.footnote * 0.92))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var purchaseButtonTitle: String {
        if let price = premium.product?.displayPrice {
            return L("premium.unlockWithPrice \(price)")
        }
        return L("premium.unlock")
    }

    private func startPurchase() {
        let lockedCharacterIDs = CharacterCatalog.all
            .filter {
                !CharacterUnlockStore.canUse(characterID: $0.id, isPremium: false)
            }
            .map(\.id)

        Task {
            await premium.purchase()
            guard premium.isPremium else { return }

            if let firstCharacterID = lockedCharacterIDs.first {
                pendingUnlockCharacterIDs = Array(lockedCharacterIDs.dropFirst())
                playUnlockCelebration(characterID: firstCharacterID)
            } else {
                characterID = previewCharacterID
            }
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String,
                            metrics: PremiumMetrics) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: metrics.featureTitle, weight: .bold))
                .foregroundStyle(character.color)
                .frame(width: metrics.featureTitle + 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: metrics.featureTitle, weight: .bold))
                    .foregroundStyle(character.deepColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: metrics.featureSubtitle))
                    .foregroundStyle(character.deepColor.opacity(0.7))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private func unlockCelebration(animal: AnimalCharacter) -> some View {
        GeometryReader { proxy in
            let horizontalMargin: CGFloat = isPad ? 80 : 32
            let maximumWidth: CGFloat = isPad ? 500 : 340
            let cardWidth = min(maximumWidth, max(280, proxy.size.width - horizontalMargin))
            let stageSize = cardWidth
            let particleRadius = stageSize * 0.39

            ZStack {
                Color.black.opacity(0.28)

                VStack(spacing: 0) {
                    ZStack {
                        Rectangle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        .white.opacity(unlockPulse ? 0.46 : 0.32),
                                        animal.tintColor.opacity(unlockPulse ? 0.42 : 0.28),
                                        animal.color.opacity(unlockPulse ? 0.12 : 0.07),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 8,
                                    endRadius: stageSize * 0.52
                                )
                            )

                        ZStack {
                            ForEach(0..<16, id: \.self) { index in
                                let angle = Double(index) * (.pi * 2 / 16)
                                let radiusVariation: CGFloat = index.isMultiple(of: 2) ? 0.92 : 1.04
                                Group {
                                    if index.isMultiple(of: 4) {
                                        CurrencyIcon(size: CGFloat(11 + (index % 3) * 3) * scale)
                                    } else {
                                        Image(systemName: "sparkle")
                                            .font(.system(
                                                size: CGFloat(11 + (index % 3) * 3) * scale,
                                                weight: .bold
                                            ))
                                    }
                                }
                                    .foregroundStyle(
                                        index.isMultiple(of: 4) ? animal.deepColor : animal.color
                                    )
                                    // Cancel the ring's rotation on each glyph so
                                    // the cards and sparkles keep orbiting but stay
                                    // upright rather than tumbling.
                                    .rotationEffect(.degrees(-unlockBurstRotation))
                                    .offset(
                                        x: CGFloat(cos(angle)) * particleRadius * radiusVariation,
                                        y: CGFloat(sin(angle)) * particleRadius * radiusVariation
                                    )
                                    .scaleEffect(unlockGlow ? (unlockPulse ? 1.08 : 0.78) : 0.12)
                                    .opacity(unlockGlow ? (unlockPulse ? 1 : 0.68) : 0)
                            }
                        }
                        .rotationEffect(.degrees(unlockBurstRotation))

                        animal.artwork
                            .resizable()
                            .scaledToFit()
                            .frame(width: stageSize * 0.72, height: stageSize * 0.72)
                            .scaleEffect(unlockCharacterScale)
                            .rotationEffect(.degrees(unlockCharacterRotation))
                            .offset(y: unlockCharacterFloating ? -7 * scale : 7 * scale)
                            .shadow(color: animal.deepColor.opacity(0.35), radius: 18, y: 9)
                    }
                    .frame(width: stageSize, height: stageSize)
                    .clipped()

                    Text(verbatim: L("premium.unlockBanner"))
                        .font(.system(size: 19 * scale, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(animal.deepColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .scaleEffect(unlockTitleScale)
                        .opacity(unlockGlow ? 1 : 0)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 22 * scale)
                        .padding(.vertical, 24 * scale)
                }
                .frame(width: cardWidth)
                .background(animal.skyColor)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(animal.color.opacity(0.6), lineWidth: 4)
                )
                .shadow(color: animal.deepColor.opacity(0.28), radius: 28, y: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { finishUnlockCelebration() }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(L("premium.characterUnlocked \(animal.localizedName)"))
    }

    private func playUnlockCelebration(characterID unlockedCharacterID: String) {
        unlockCelebrationGeneration += 1
        let generation = unlockCelebrationGeneration

        activeUnlockCharacterID = unlockedCharacterID
        previewCharacterID = unlockedCharacterID
        unlockGlow = false
        unlockCharacterScale = 0.18
        unlockCharacterRotation = -18
        unlockBurstRotation = -14
        unlockTitleScale = 0.72
        unlockPulse = false
        unlockCharacterFloating = false

        withAnimation(.easeIn(duration: 0.18)) { showsUnlockCelebration = true }
        // Keep audio owned by the celebration itself. This covers characters
        // earned with cards as well as every character unlocked by Premium,
        // without duplicate or prematurely timed playback.
        AppAudio.shared.playCharacterUnlock()
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
        withAnimation(.spring(response: 0.72, dampingFraction: 0.55)) {
            unlockGlow = true
            unlockCharacterScale = 1
            unlockCharacterRotation = 0
            unlockTitleScale = 1
        }
        withAnimation(.easeOut(duration: 0.8)) {
            unlockBurstRotation = 18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            guard generation == unlockCelebrationGeneration,
                  showsUnlockCelebration else { return }
#if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
#endif
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            guard generation == unlockCelebrationGeneration,
                  showsUnlockCelebration else { return }
#if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
#endif
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard generation == unlockCelebrationGeneration,
                  showsUnlockCelebration else { return }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                unlockBurstRotation = 378
            }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                unlockPulse = true
                unlockCharacterFloating = true
            }
        }
    }

    private func finishUnlockCelebration() {
        guard showsUnlockCelebration,
              let completedCharacterID = activeUnlockCharacterID else { return }

        unlockCelebrationGeneration += 1
        withAnimation(.easeOut(duration: 0.3)) { showsUnlockCelebration = false }

        let completedCharacter = CharacterCatalog.character(id: completedCharacterID)
        if canUse(completedCharacter) {
            characterID = completedCharacterID
        }

        if let nextCharacterID = pendingUnlockCharacterIDs.first {
            pendingUnlockCharacterIDs.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                playUnlockCelebration(characterID: nextCharacterID)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                guard !showsUnlockCelebration else { return }
                activeUnlockCharacterID = nil
            }
        }
    }

}

private extension View {
    /// `scale` mirrors the factor `PremiumView` applies to every other metric so
    /// the chip grows with the cell on iPad instead of staying at iPhone size.
    func characterChipStyle(character: AnimalCharacter, scale: CGFloat = 1) -> some View {
        self
            .font(.system(size: 10 * scale, weight: .heavy, design: .rounded))
            .foregroundStyle(character.deepColor)
            .lineLimit(1)
            // Card requirements are at most four digits and always fit at full
            // size, so every chip renders identically. Shrinking is kept as a
            // safety net for a long translated label.
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .padding(.horizontal, 5 * scale)
            .padding(.vertical, 4 * scale)
            .frame(maxWidth: .infinity)
            .background(character.color.opacity(0.16), in: Capsule())
    }
}

extension View {
    @ViewBuilder
    /// A sheet begins a fresh environment and inherits nothing from the app
    /// root, so the chosen language and its reading direction have to be handed
    /// back in here — otherwise the premium screen follows the device instead
    /// of the picker, and never mirrors for Arabic or Hebrew.
    func premiumSheetPresentation() -> some View {
        if #available(iOS 18.0, *) {
            self
                .gameEnvironment()
                .presentationSizing(.page)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
                .gameEnvironment()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    PremiumView(initialCharacterID: "frog", celebratedUnlockCharacterID: "frog")
}
