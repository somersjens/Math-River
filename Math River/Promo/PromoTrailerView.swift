#if DEBUG
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PromoTrailerRoot: View {
    var body: some View {
        PromoTrailerView(
            format: PromoMode.format,
            onFinished: {
                Task { await PromoCaptureController.shared.finish() }
            }
        )
        .statusBarHidden(true)
        .onAppear {
            AppLayout.promoForcePad = PromoMode.format.isPad
            PromoCaptureController.shared.prepareAudio()
        }
    }
}

struct PromoTrailerView: View {
    let format: PromoFormat
    var onFinished: (() -> Void)?

    @StateObject private var model: GameViewModel
    @StateObject private var director: PromoDirector
    @State private var scoreIconCenter: CGPoint?
    @State private var showsStreakBanner = false
    @State private var streakBannerToken = 0
    @State private var playsLevelCompletion = false
    @State private var showsFinale = false
    @State private var iconRotation: Double = -26
    @State private var iconScale: CGFloat = 0.42
    @State private var sampledTop: CGFloat = 0
    @State private var sampledBottom: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(format: PromoFormat,
         onFinished: (() -> Void)? = nil) {
        self.format = format
        self.onFinished = onFinished
        let model = GameViewModel(request: PromoScript.sessionRequest)
        _model = StateObject(wrappedValue: model)
        _director = StateObject(wrappedValue: PromoDirector(model: model))
    }

    private var isPad: Bool { format.isPad }
    private var character: AnimalCharacter {
        CharacterCatalog.character(id: director.characterID)
    }
    private var hudHeight: CGFloat { isPad ? 44 : 34 }
    private var insets: ScreenSafeArea {
        ScreenSafeArea(top: max(sampledTop, format.safeTop),
                       bottom: max(sampledBottom, format.safeBottom),
                       leading: 0, trailing: 0)
    }

    var body: some View {
        let topInset = insets.top
        ZStack {
            LinearGradient(colors: [character.skyColor, character.tintColor],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            playfield(topInset: topInset)
                .blur(radius: director.blursPlayfield ? 7 : 0)
                .animation(.easeOut(duration: 0.5), value: director.blursPlayfield)

            hud(topInset: topInset)
                .opacity(showsFinale || director.showsIcon ? 0 : 1)
                .animation(.easeOut(duration: 0.22), value: showsFinale)

            if showsStreakBanner, !director.showsIcon {
                StreakBoostBanner(character: character, isPad: isPad)
                    .padding(.top, speechBubbleTop(topInset: topInset)
                             + (isPad ? 96 : 74) + (isPad ? 8 : 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.scale(scale: 0.65).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if let headline = director.headline, !director.showsIcon, !showsFinale {
                PromoSpeechBubble(text: headline, character: character, isPad: isPad)
                    .padding(.horizontal, isPad ? 36 : 18)
                    .padding(.top, speechBubbleTop(topInset: topInset))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .animation(.easeInOut(duration: 0.28), value: director.headline)
                    .allowsHitTesting(false)
            }

            if director.showsIcon {
                iconOverlay
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .statusBarHidden(true)
        .onChange(of: model.streakAnnouncementID) { id in
            guard id > 0, director.revealsStreakBoost else { return }
            showStreakBanner(for: id)
        }
        .onChange(of: director.revealsStreakBoost) { reveal in
            if reveal, model.streakAnnouncementID > 0 {
                showStreakBanner(for: model.streakAnnouncementID)
            }
        }
        .onChange(of: model.isGameOver) { isOver in
            if isOver, model.result.reason == .roundsCompleted {
                playsLevelCompletion = true
            }
        }
        .onChange(of: director.showsIcon) { showing in
            if showing {
                withAnimation(.spring(response: 0.78, dampingFraction: 0.82)) {
                    iconRotation = 0
                    iconScale = 1
                }
            }
        }
        .onChange(of: director.isFinished) { finished in
            if finished { onFinished?() }
        }
        .onPreferenceChange(ScoreIconCenterPreferenceKey.self) { center in
            scoreIconCenter = center
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        sampledTop = proxy.safeAreaInsets.top
                        sampledBottom = proxy.safeAreaInsets.bottom
                    }
                    .onChange(of: proxy.safeAreaInsets.top) { value in
                        sampledTop = value
                    }
            }
        }
        .onAppear {
            director.onGameplayReady = {
                PromoCaptureController.shared.markReady()
            }
        }
        .persistentSystemOverlays(.hidden)
    }

    private func playfield(topInset: CGFloat) -> some View {
        KingCrabPlayfield(round: model.round,
                          missedSum: nil,
                          maximumRounds: model.maximumRounds,
                          character: character,
                          isPad: isPad,
                          isLive: model.acceptsInput,
                          isRunning: true,
                          playsKingEntrance: false,
                          hasBonusPower: model.hasBonusFishPower,
                          isLifeCrabAvailable: false,
                          isStreakBoostActive: director.revealsStreakBoost,
                          playsLevelCompletion: playsLevelCompletion,
                          reduceMotion: false,
                          reservesTutorialMessage: true,
                          topReserve: topInset + hudHeight + (isPad ? 22 : 18),
                          bottomReserve: insets.bottom,
                          scoreTarget: scoreIconCenter,
                          onGuardedArrival: { model.select(optionID: $0) },
                          onSmashedGuard: model.smashGuardedAnswer,
                          onBreach: { _ = model.absorbBreach() },
                          onSmash: { _ in model.crabSmashed() },
                          onSweep: model.kingSweeps,
                          onShellArrived: model.scoreBubbleArrived,
                          onBonusCrabCaught: model.catchBonusFish,
                          onLifeCrabArrived: model.catchLifeCrab,
                          onKingEntranceComplete: {},
                          onLevelCompletionStarted: {
                              showsFinale = true
                              director.markFinaleStarted()
                          },
                          onLevelCompletionFinished: {
                              director.markCompletionFinished()
                          },
                          onPromoArenaReady: { arena in
                              director.attach(arena)
                          })
            .ignoresSafeArea()
    }

    private func hud(topInset: CGFloat) -> some View {
        ZStack {
            HStack(alignment: .center, spacing: isPad ? 7 : 5) {
                Text(verbatim: LN(model.cards))
                    .font(.system(size: isPad ? 32 : 24, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .modifier(NumericCountTransition(value: Double(model.cards)))
                CurrencyIcon(size: isPad ? 34 : 26)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScoreIconCenterPreferenceKey.self,
                                value: CGPoint(x: proxy.frame(in: .global).midX,
                                               y: proxy.frame(in: .global).midY)
                            )
                        }
                    }
            }
            .frame(height: hudHeight, alignment: .center)
            .foregroundStyle(character.deepColor)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.cards)

            HStack(spacing: 10) {
                Circle()
                    .fill(character.deepColor)
                    .frame(width: hudHeight, height: hudHeight)
                    .overlay {
                        Image(systemName: "pause.fill")
                            .font(.system(size: isPad ? 22 : 16, weight: .bold))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()

                Spacer(minLength: 0)

                LivesView(lives: model.livesRemaining,
                          character: character,
                          isPad: isPad,
                          glyphSize: isPad ? 34 : 26,
                          rowHeight: hudHeight)
            }
        }
        .padding(.leading, isPad ? 28 : 16)
        .padding(.trailing, isPad ? 28 : 16)
        .padding(.top, topInset + (isPad ? 12 : 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private var iconOverlay: some View {
        let side = min(format.pointSize.width, format.pointSize.height) * (isPad ? 0.42 : 0.48)
        return ZStack {
            Color.black.opacity(0.12)
            Image("app_icon_trailer")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
                .rotationEffect(.degrees(iconRotation))
                .scaleEffect(iconScale)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func questionBandTop(topInset: CGFloat) -> CGFloat {
        topInset + hudHeight + (isPad ? 16 : 12) + (isPad ? 12 : 8)
    }

    private func speechBubbleTop(topInset: CGFloat) -> CGFloat {
        questionBandTop(topInset: topInset)
            + ArenaConfig.bannerHeight(isPad: isPad) + (isPad ? 10 : 8)
    }

    private func showStreakBanner(for token: Int) {
        guard token > 0, token != streakBannerToken || !showsStreakBanner else { return }
        streakBannerToken = token
        withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
            showsStreakBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard streakBannerToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showsStreakBanner = false
            }
        }
    }
}

private struct PromoSpeechBubble: View {
    let text: String
    let character: AnimalCharacter
    let isPad: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: text)
                .font(.system(size: isPad ? 22 : 16, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(character.deepColor)
                .padding(.horizontal, isPad ? 22 : 16)
                .padding(.vertical, isPad ? 14 : 10)
                .frame(maxWidth: isPad ? 560 : 360)
                .background(
                    RoundedRectangle(cornerRadius: isPad ? 22 : 18, style: .continuous)
                        .fill(.white.opacity(0.96))
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isPad ? 22 : 18, style: .continuous)
                        .stroke(character.deepColor.opacity(0.18), lineWidth: 1.5)
                )

            PromoBubbleTail()
                .fill(Color.white.opacity(0.96))
                .frame(width: isPad ? 26 : 20, height: isPad ? 14 : 11)
                .offset(y: -1)
        }
    }
}

private struct PromoBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

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

#endif
