//
//  HomeComponents.swift
//  Math Memory
//
//  The pieces the home screen is built from: the streak module, the goal
//  picker, the name editor, the level grid layout, and the level card itself.
//
//  These are ported from the original menu with their proportions intact. The
//  only change to the level card is that its score is measured in cards
//  instead of trophies.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Goal period

enum GoalPeriod: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }
    var title: String {
        self == .daily ? L("goalPeriod.daily") : L("goalPeriod.weekly")
    }
}

// MARK: - Streak

/// The compact streak module in the top-right of the header: day count, a
/// progress rail toward the goal, and the minutes underneath.
struct CompactStreakView: View {
    let accent: Color
    let action: () -> Void
    @ObservedObject private var tracker = PlaytimeTracker.shared
    @AppStorage("ui.goalPeriod") private var goalPeriodRaw = GoalPeriod.weekly.rawValue

    private var goalPeriod: GoalPeriod { GoalPeriod(rawValue: goalPeriodRaw) ?? .weekly }
    private var isPad: Bool { AppLayout.isPad }

    // One factor drives every dimension, so the widget keeps its proportions
    // when it scales up for the larger iPad layout.
    private var scale: CGFloat { isPad ? 1.55 : 1 }
    private var railWidth: CGFloat { 74 * scale }
    private var rowSpacing: CGFloat { 5 * scale }

    private var progressMinutes: Int {
        goalPeriod == .weekly ? tracker.weekMinutes : tracker.todayMinutes
    }

    private var goalMinutes: Int {
        goalPeriod == .weekly ? tracker.weeklyGoalMinutes : tracker.dailyGoalMinutes
    }

    private var goalProgress: Double {
        min(1, Double(progressMinutes) / Double(max(1, goalMinutes)))
    }

    var body: some View {
        Button(action: action) {
            // Constant spacing between three self-sizing rows: the module has a
            // stable natural height and is centred in the header, so a longer
            // name next to it never squashes or stretches these gaps.
            VStack(spacing: rowSpacing) {
                headline
                    .foregroundStyle(accent)
                progressLine
                Text("common.minutesShort \(progressMinutes) \(goalMinutes)")
                    .font(.system(size: 11.5 * scale, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("streak")
        .accessibilityLabel("streak.accessibility.compact \(goalPeriod.title) \(progressMinutes) \(goalMinutes) \(tracker.streakDays)")
        .accessibilityHint("streak.accessibility.choosePeriod")
    }

    // The day count and its flame — or the day-one badge — read as one unit:
    // matched weights, baseline alignment, and a single tight gap keep the icon
    // from drifting away from the text beside it.
    @ViewBuilder private var headline: some View {
        if tracker.streakDays == 0 {
            HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15 * scale, weight: .bold))
                Text("streak.dayOne")
                    .font(.system(size: 15 * scale, weight: .heavy, design: .rounded))
            }
            .fixedSize()
            // The sparkle carries less visual weight than the text, so a
            // geometric centre reads as shifted right; nudge left to optically
            // centre the badge over the rail below it.
            .offset(x: -4 * scale)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                Text(verbatim: LN(tracker.streakDays))
                    .font(.system(size: 28 * scale, weight: .heavy, design: .rounded))
                Image(systemName: "flame.fill")
                    .font(.system(size: 17 * scale, weight: .bold))
            }
        }
    }

    // Fixed-width rail, so the fill can be sized directly without a
    // GeometryReader and stays perfectly centred under the day count.
    private var progressLine: some View {
        Capsule()
            .fill(accent.opacity(0.15))
            .frame(width: railWidth, height: 7 * scale)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.6), accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6 * scale, railWidth * goalProgress))
                    .animation(.snappy(duration: 0.4), value: goalProgress)
            }
    }
}

// MARK: - Goal picker

struct DailyGoalPicker: View {
    let theme: AnimalCharacter
    @ObservedObject private var tracker = PlaytimeTracker.shared
    @AppStorage("ui.goalPeriod") private var goalPeriodRaw = GoalPeriod.weekly.rawValue

    private var goalPeriod: GoalPeriod { GoalPeriod(rawValue: goalPeriodRaw) ?? .weekly }
    private var isPad: Bool { AppLayout.isPad }
    private let goalOptions = Array(stride(from: 5, through: 60, by: 5))

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("goal.title")
                .font(.headline)
            Picker("goal.period", selection: $goalPeriodRaw) {
                ForEach(GoalPeriod.allCases) { period in
                    Text(period.title).tag(period.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(goalPeriod == .weekly ? "goal.promptWeekly" : "goal.promptDaily")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(goalOptions, id: \.self) { minutes in
                    Button {
                        goalPeriod == .weekly ? tracker.setWeeklyGoal(minutes) : tracker.setDailyGoal(minutes)
                    } label: {
                        Text(verbatim: LN(minutes))
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(selectedGoalMinutes == minutes ? theme.color : .white,
                                in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(selectedGoalMinutes == minutes ? .white : theme.deepColor)
                }
            }
        }
        .frame(width: isPad ? 360 : 280)
    }

    private var selectedGoalMinutes: Int {
        goalPeriod == .weekly ? tracker.weeklyGoalMinutes : tracker.dailyGoalMinutes
    }
}

// MARK: - Name editor

/// Themed sheet for editing the player's name, styled to match the app rather
/// than a plain system alert. Deliberately a short, self-sizing sheet that
/// rises over the menu — a full navigation stack reads far heavier here.
struct NameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let theme: AnimalCharacter
    @Binding var name: String
    let onSave: () -> Void
    @FocusState private var focused: Bool
    @State private var hasRequestedInitialFocus = false
    private var isPad: Bool { AppLayout.isPad }
    private var scale: CGFloat { isPad ? 1.2 : 1 }

    private func save() {
        onSave()
        dismiss()
    }

    var body: some View {
        VStack(spacing: 20 * scale) {
            Spacer(minLength: 0)

            VStack(spacing: 6 * scale) {
                theme.thumbArtwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54 * scale, height: 54 * scale)

                Text("name.whatsYourName")
                    .font(.system(size: 24 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)
            }

            TextField(String(), text: $name, prompt: Text("name.placeholder"))
                .font(.system(size: 22 * scale, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($focused)
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, 16 * scale)
                .padding(.vertical, 13 * scale)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focused ? theme.color : theme.deepColor.opacity(0.15),
                                lineWidth: focused ? 2 : 1)
                )
                .animation(.snappy(duration: 0.2), value: focused)

            HStack(spacing: 12 * scale) {
                Button { dismiss() } label: {
                    Text("common.cancel")
                        .font(isPad ? .title3.weight(.semibold) : .headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13 * scale)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme.deepColor.opacity(0.15), lineWidth: 1)
                        )
                        .foregroundStyle(theme.deepColor)
                }

                Button(action: save) {
                    Text("common.save")
                        .font(isPad ? .title3.weight(.semibold) : .headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13 * scale)
                        .background(
                            LinearGradient(colors: [theme.color, theme.deepColor],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(24 * scale)
        .frame(maxWidth: isPad ? 620 : .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Requesting focus during the sheet's own presentation makes iOS
            // animate the sheet and keyboard in competing passes. Waiting for
            // that transition to settle gives the keyboard one smooth entry.
            guard !hasRequestedInitialFocus else { return }
            hasRequestedInitialFocus = true
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            focused = true
        }
    }
}

// MARK: - Level grid layout

/// Lays the level cards out in equal-width columns, fitting as many as the
/// available width allows without ever going below `minimumCardWidth`.
struct AdaptiveLevelGrid: Layout {
    let spacing: CGFloat
    let minimumCardWidth: CGFloat
    let maximumColumns: Int
    let cardHeight: CGFloat

    init(spacing: CGFloat,
         minimumCardWidth: CGFloat = 104,
         maximumColumns: Int = .max,
         cardHeight: CGFloat = 96) {
        self.spacing = spacing
        self.minimumCardWidth = minimumCardWidth
        self.maximumColumns = maximumColumns
        self.cardHeight = cardHeight
    }

    private func metrics(for width: CGFloat, itemCount: Int) -> (columns: Int, cardWidth: CGFloat) {
        let possibleColumns = max(1, Int((width + spacing) / (minimumCardWidth + spacing)))
        let columns = min(max(1, itemCount), possibleColumns, maximumColumns)
        let cardWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        return (columns, cardWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let fallbackColumns = min(subviews.count, maximumColumns)
        let fallbackWidth = minimumCardWidth * CGFloat(fallbackColumns)
            + spacing * CGFloat(fallbackColumns - 1)
        let width = proposal.width ?? fallbackWidth
        let columns = metrics(for: width, itemCount: subviews.count).columns
        let rows = Int(ceil(Double(subviews.count) / Double(columns)))
        return CGSize(width: width, height: CGFloat(rows) * cardHeight + CGFloat(rows - 1) * spacing)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let grid = metrics(for: bounds.width, itemCount: subviews.count)
        for (index, subview) in subviews.enumerated() {
            let row = index / grid.columns
            let column = index % grid.columns
            let x = bounds.minX + CGFloat(column) * (grid.cardWidth + spacing)
            let y = bounds.minY + CGFloat(row) * (cardHeight + spacing)
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: grid.cardWidth, height: cardHeight))
        }
    }
}

// MARK: - Tier marker shapes

/// The folded, clipped-corner marker used for the middle tier.
private struct CornerFlagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.18),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.54))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.91, y: rect.height * 0.66),
                          control: CGPoint(x: rect.maxX, y: rect.height * 0.61))
        path.addLine(to: CGPoint(x: rect.width * 0.23, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.84),
                          control: CGPoint(x: rect.width * 0.03, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.18))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.18, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The swallowtail ribbon marker used for the highest non-complete tier.
private struct PennantShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.18),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.86))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.87, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.58, y: rect.height * 0.74))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.height * 0.71),
                          control: CGPoint(x: rect.width * 0.54, y: rect.height * 0.71))
        path.addLine(to: CGPoint(x: rect.width * 0.13, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.86),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.18))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.18, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Level card

enum LevelCardStatus: Equatable {
    case locked
    case available
    case recommended
    case completed
}

/// A level card: the big central number, the card score line, a three-dot
/// progress indicator and the top-left tier badge. Reaching the completion
/// score turns it into the gold "completed" card.
struct LevelCardView: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let level: MathLevel
    let status: LevelCardStatus
    let best: Int
    /// What a full score is worth on the board being shown, which depends on
    /// the selected exercise.
    var maximum: Int = GameConfig.levelMaximum
    /// How often this board has been taken to its maximum. From the second time
    /// onward the completed card carries a ×N badge.
    var maxCompletions = 0
    /// Cards banked in the run waiting to be continued, or nil when this level
    /// was not left part-way through.
    var pausedCards: Int?
    /// Set for the level just returned from: its score counts up from the value
    /// the player had before the session, and the card is briefly outlined.
    var celebrationStart: Int?
    var celebrationStartedAt: Date?
    /// iPad cards preserve the iPhone design, scaled as one component.
    var cardHeight: CGFloat = 96
    let theme: AnimalCharacter
    let action: () -> Void

    @State private var scorePulse = false
    @State private var completionRevealed = false

    private var cardScale: CGFloat { cardHeight / 96 }
    private var isLocked: Bool { status == .locked }

    // MARK: Tiers

    /// Achievement tiers, keyed off the card score. Their colors keep the
    /// selected character's hue, stepping from its primary color through its
    /// deep color to a darker finish as the score increases.
    private enum Tier {
        case empty
        case one
        case two
        case three
        case maxed

        func color(for theme: AnimalCharacter) -> Color {
            switch self {
            case .empty:  return Color(white: 0.72)
            case .one:    return theme.color
            case .two:    return theme.deepColor
            case .three:
                return Color(red: theme.deepRGB.0 * 0.76,
                             green: theme.deepRGB.1 * 0.76,
                             blue: theme.deepRGB.2 * 0.76)
            case .maxed:  return Color(red: 0.30, green: 0.62, blue: 0.24)
            }
        }

        /// How many of the three progress dots are active.
        var activeDots: Int {
            switch self {
            case .empty:          return 0
            case .one:            return 1
            case .two:            return 2
            case .three, .maxed:  return 3
            }
        }
    }

    /// Tier boundaries come from the central configuration, so the card art
    /// follows the economy rather than repeating its numbers.
    private func tier(for score: Int) -> Tier {
        if score >= maximum { return .maxed }
        let maximum = Double(maximum)
        let shares = GameConfig.levelTierShares
        switch Double(score) {
        case ..<(maximum * shares[0]): return .empty
        case ..<(maximum * shares[1]): return .one
        case ..<(maximum * shares[2]): return .two
        default:                       return .three
        }
    }

    private var tier: Tier { tier(for: best) }

    /// During a return animation the score still starts at its old value. Keep
    /// every score-coloured detail in that old tier too; otherwise a maxed
    /// bubble turns green before its number has actually reached the maximum.
    private var displayedTier: Tier {
        guard isNewMaximumCelebration, !completionRevealed else { return tier }
        return tier(for: celebrationStart ?? best)
    }

    private var displayedBest: Int {
        isNewMaximumCelebration && !completionRevealed ? (celebrationStart ?? best) : best
    }

    private var showsCompletedAppearance: Bool {
        tier == .maxed && !isLocked && (!isNewMaximumCelebration || completionRevealed)
    }

    /// A level that crosses its maximum on this return stays in its ordinary
    /// card until the bubbles have finished counting. Only then do the gold
    /// card, crown and ferns arrive together.
    private var isNewMaximumCelebration: Bool {
        isNewMaximumCelebration(startedAt: celebrationStartedAt)
    }

    /// Takes the start date as a parameter rather than reading
    /// `celebrationStartedAt` directly: `animateIfCelebrating` needs this
    /// computed against the *new* value while it's still inside the
    /// `onChange` closure, where the property itself reads as the value from
    /// before the update.
    private func isNewMaximumCelebration(startedAt: Date?) -> Bool {
        startedAt != nil && (celebrationStart ?? best) < maximum && best >= maximum
    }

    // MARK: Body

    var body: some View {
        Button {
            AppAudio.shared.playMenuTap()
            action()
        } label: {
            Group {
                if showsCompletedAppearance {
                    completedCard
                        .transition(.opacity.combined(with: .scale(scale: 0.88, anchor: .bottom)))
                } else {
                    standardCard
                        .transition(.opacity)
                }
            }
            .frame(height: cardHeight)
            .opacity(isLocked ? 0.55 : 1)
            .scaleEffect((status == .recommended ? 1.02 : 1) * (scorePulse ? 1.04 : 1))
            .overlay {
                if let celebrationStartedAt {
                    LevelReturnFocusGlow(startedAt: celebrationStartedAt,
                                         cornerRadius: 18 * cardScale,
                                         lineWidth: 4 * cardScale,
                                         glowRadius: 9 * cardScale,
                                         strokeColor: theme.deepColor,
                                         glowColor: theme.color)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .onAppear { animateIfCelebrating(startedAt: celebrationStartedAt) }
        // `onChange(of:perform:)` (needed for the iOS 16.4 floor) runs its
        // closure against the view value from *before* the update, so
        // reading `celebrationStartedAt` in here would still see the old
        // value — nil on the transition that starts the celebration, which
        // skipped the score pulse entirely. Only the value handed to the
        // closure is current.
        .onChange(of: celebrationStartedAt) { newValue in animateIfCelebrating(startedAt: newValue) }
        .accessibilityIdentifier("level-\(level.index)")
        .accessibilityLabel(Text(L("home.levelAccessibility \(level.index)")))
        .accessibilityValue(Text(verbatim: pausedCards.map {
            "\(best), \(L("home.pausedCards \($0)"))"
        } ?? "\(best)"))
    }

    /// A little kick on the glyph at the moment the number lands.
    private func animateIfCelebrating(startedAt: Date?) {
        let isNewMax = isNewMaximumCelebration(startedAt: startedAt)
        completionRevealed = !isNewMax
        guard startedAt != nil, (celebrationStart ?? best) < best else {
            scorePulse = false
            return
        }
        let landing = Self.scoreCountDelay + Self.scoreCountDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + landing) {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.62)) {
                scorePulse = true
                if isNewMax { completionRevealed = true }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + landing + 0.62) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) { scorePulse = false }
        }
    }

    // MARK: Standard card

    private var standardCard: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 4) {
                Spacer(minLength: 2)
                Text(level.cardNumber)
                    .font(.system(size: 34 * cardScale, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(theme.deepColor)
                centerLine
                Spacer(minLength: 2)
                progressDots(active: displayedTier.activeDots,
                             color: displayedTier.color(for: theme))
                    .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8 * cardScale)

            tierBadge
                .padding(.top, 9 * cardScale)
                .padding(.leading, 9 * cardScale)
        }
        .background(cardFill, in: RoundedRectangle(cornerRadius: 18 * cardScale))
        .overlay(
            RoundedRectangle(cornerRadius: 18 * cardScale)
                .stroke(borderColor, lineWidth: (status == .recommended ? 2.5 : 1) * cardScale)
        )
        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 3)
    }

    private var cardFill: Color {
        displayedBest == 0 ? Color.white.opacity(0.6) : .white
    }

    private var borderColor: Color {
        if status == .recommended { return theme.color }
        return displayedBest == 0
            ? Color(white: 0.85)
            : displayedTier.color(for: theme).opacity(0.35)
    }

    // MARK: Center score line

    @ViewBuilder
    private var centerLine: some View {
        if status == .recommended && best == 0 {
            Text("menu.startHere")
                .font(.system(size: 10 * cardScale * 1.2, weight: .bold))
                .foregroundStyle(theme.deepColor)
                // Longer translations shrink to fit rather than truncating.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
        } else if isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 10 * cardScale, weight: .bold))
                .foregroundStyle(theme.deepColor.opacity(0.75))
        } else if let pausedCards {
            // A paused level shows its best score next to what the waiting run
            // has already banked, so the reason to go back is on the card.
            HStack(spacing: 3 * cardScale) {
                cardChip
                Rectangle()
                    .fill(theme.deepColor.opacity(0.25))
                    .frame(width: 1, height: 11 * cardScale)
                HStack(spacing: 2 * cardScale) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 8 * cardScale))
                    Text(verbatim: LN(pausedCards))
                        .font(.system(size: 11 * cardScale, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(theme.deepColor.opacity(0.7))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            cardChip
        }
    }

    /// The score, with its bubble after the number — the way a count is read
    /// aloud ("twelve bubbles"), not the way a price is written.
    private var cardChip: some View {
        HStack(spacing: 3 * cardScale) {
            CountingNumber(from: celebrationStart ?? best,
                           to: best,
                           startedAt: celebrationStartedAt,
                           delay: Self.scoreCountDelay,
                           duration: Self.scoreCountDuration)
                .font(.system(size: 12 * cardScale, weight: .bold))
            CurrencyIcon(size: 9 * cardScale)
                // The launch anchor is read from the unscaled layout frame, so
                // the flying card starts exactly overlapping this glyph.
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: CardGlyphAnchorKey.self,
                                               value: [level.id: proxy.frame(in: .named("home"))])
                    }
                }
                .scaleEffect(scorePulse ? 1.48 : 1)
                .rotationEffect(.degrees(scorePulse ? -12 : 0))
        }
        .foregroundStyle(displayedTier == .empty
                         ? Color(white: 0.6)
                         : displayedTier.color(for: theme))
    }

    /// The level's own score is the first thing that moves on returning: it
    /// counts up here, and only then does the reward fly to the totals.
    static let scoreCountDelay = 0.25
    static let scoreCountDuration = 0.7

    // MARK: Tier badge (top-left)

    @ViewBuilder
    private var tierBadge: some View {
        switch displayedTier {
        case .empty:
            // No score yet: leave the corner empty.
            EmptyView()
        case .one:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(displayedTier.color(for: theme))
                .frame(width: 9 * cardScale, height: 9 * cardScale)
                .rotationEffect(.degrees(45))
                .padding(.leading, 1)
        case .two:
            CornerFlagShape()
                .fill(displayedTier.color(for: theme))
                .frame(width: 12 * cardScale, height: 14 * cardScale)
        case .three, .maxed:
            PennantShape()
                .fill(displayedTier.color(for: theme))
                .frame(width: 12 * cardScale, height: 14 * cardScale)
        }
    }

    // MARK: Progress dots

    private func progressDots(active: Int, color: Color) -> some View {
        HStack(spacing: 6 * cardScale) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(index < active ? color : Color(white: 0.85))
                    .frame(width: 6 * cardScale, height: 6 * cardScale)
            }
        }
    }

    // MARK: Completed card

    /// The completed card celebrates in two colours: a `hero` (number, score,
    /// dots, ribbon behind the crown) and a `metal` (crown, border, glow).
    /// Green would disappear into a green theme, so that one case swaps to
    /// violet — which is what keeps the contrast strong in every theme.
    private var completedPalette: (hero: Color, metal: Color) {
        Self.completedPalette(for: theme)
    }

    static func completedPalette(for theme: AnimalCharacter) -> (hero: Color, metal: Color) {
        let green = Color(red: 0.24, green: 0.60, blue: 0.28)
        let gold = Color(red: 0.87, green: 0.66, blue: 0.12)
        let violet = Color(red: 0.42, green: 0.35, blue: 0.78)
        return (80...175).contains(themeHue(for: theme)) ? (violet, gold) : (green, gold)
    }

    /// Hue (0–360°) of the selected theme, used to keep the completed card's
    /// festive colours distinct from whichever animal is active.
    private static func themeHue(for theme: AnimalCharacter) -> Double {
        let (r, g, b) = theme.primaryRGB
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        guard d > 0 else { return 0 }
        let h: Double
        switch mx {
        case r: h = (g - b) / d
        case g: h = 2 + (b - r) / d
        default: h = 4 + (r - g) / d
        }
        return (h * 60).truncatingRemainder(dividingBy: 360) + (h < 0 ? 360 : 0)
    }

    private var completedCard: some View {
        let (hero, metal) = completedPalette
        return ZStack {
            VStack(spacing: 3) {
                Spacer(minLength: 8)
                Text(level.cardNumber)
                    .font(.system(size: 34 * cardScale, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(hero)
                HStack(spacing: 3 * cardScale) {
                    CountingNumber(from: celebrationStart ?? best,
                                   to: best,
                                   startedAt: celebrationStartedAt,
                                   delay: Self.scoreCountDelay,
                                   duration: Self.scoreCountDuration)
                        .font(.system(size: 12 * cardScale, weight: .bold))
                    CurrencyIcon(size: 9 * cardScale)
                        // Once the max card has been revealed, the flight must
                        // still start on this exact bubble. Without an anchor
                        // here the standard card's disappearing glyph leaves
                        // the return animation with no source point.
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(key: CardGlyphAnchorKey.self,
                                                       value: [level.id: proxy.frame(in: .named("home"))])
                            }
                        }
                        .scaleEffect(scorePulse ? 1.48 : 1)
                }
                .foregroundStyle(hero)
                // The repeat marker is a superscript detail beside the score,
                // not a second item in the centred layout. It appears from the
                // second maximum onward; the first is marked by crown and gold.
                .overlay(alignment: .topTrailing) {
                    if maxCompletions >= 2 {
                        maxCompletionBadge(fill: hero, metal: metal)
                            // The wrapper is only an alignment column: the badge
                            // keeps its natural width and grows to the right, so
                            // a wider label ("MAX") never creeps back over the
                            // number instead of staying pinned beside it.
                            .frame(width: 23 * cardScale, alignment: .leading)
                            // Same story as the alignment above: `topTrailing`
                            // turns over with the reading direction, a raw
                            // offset does not, and an unturned one walks the
                            // badge back across the number it sits beside.
                            .offset(x: (layoutDirection == .rightToLeft ? -20 : 20) * cardScale,
                                    y: -7 * cardScale)
                    }
                }
                Spacer(minLength: 2)
                progressDots(active: 3, color: metal)
                    .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8 * cardScale)
        }
        .background(
            LinearGradient(colors: [Color(red: 1.0, green: 0.96, blue: 0.85),
                                    Color(red: 0.99, green: 0.90, blue: 0.68)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 18 * cardScale)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18 * cardScale)
                .stroke(metal, lineWidth: 2.5 * cardScale)
        )
        .overlay {
            completedFerns(color: hero, highlight: metal)
        }
        .overlay(alignment: .top) {
            completedRibbon(fill: hero, crown: metal)
                .offset(y: -9 * cardScale)
        }
        .shadow(color: metal.opacity(0.35), radius: 6, y: 3)
    }

    /// Ferns curl up both sides of every maxed level. Their stems sit just
    /// outside the card edge while the leaves overlap it slightly, framing the
    /// score without narrowing the number or bubble line.
    private func completedFerns(color _: Color, highlight: Color) -> some View {
        HStack(spacing: 0) {
            CompletionFern(color: highlight, revealStartedAt: fernRevealStartedAt)
                .frame(width: 25 * cardScale, height: 52 * cardScale)
                .rotationEffect(.degrees(-3), anchor: .bottom)
                .offset(x: 9 * cardScale, y: 3 * cardScale)

            Spacer(minLength: 0)

            CompletionFern(color: highlight, revealStartedAt: fernRevealStartedAt)
                .frame(width: 25 * cardScale, height: 52 * cardScale)
                .scaleEffect(x: -1, y: 1)
                .rotationEffect(.degrees(3), anchor: .bottom)
                .offset(x: -9 * cardScale, y: 3 * cardScale)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The completed card is inserted at this exact instant. Giving the ferns
    /// the shared timestamp keeps both sides perfectly synchronized even when
    /// SwiftUI creates one side a frame later than the other.
    private var fernRevealStartedAt: Date? {
        guard isNewMaximumCelebration, let celebrationStartedAt else { return nil }
        return celebrationStartedAt.addingTimeInterval(Self.scoreCountDelay + Self.scoreCountDuration)
    }

    /// A small ribbon overlapping the top edge, carrying the crown. The ribbon
    /// takes the hero colour and the crown the contrasting metal, so the badge
    /// reads as an object sitting on the card rather than a floating glyph.
    private func completedRibbon(fill: Color, crown: Color) -> some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 11 * cardScale, weight: .bold))
            .foregroundStyle(crown)
            .padding(.horizontal, 11 * cardScale)
            .padding(.vertical, 4 * cardScale)
            .background(RoundedRectangle(cornerRadius: 6 * cardScale).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6 * cardScale)
                .stroke(.white.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }

    /// "×3" — or the word for "max" once the tally is capped. Deliberately
    /// smaller than the score: the airy outline is its visual footprint.
    private func maxCompletionBadge(fill: Color, metal: Color) -> some View {
        let isCapped = maxCompletions >= GameConfig.maximumCompletionCount
        let label = isCapped ? L("menu.maximumCount") : "×\(maxCompletions)"
        let cornerRadius = 3.5 * cardScale
        return Text(verbatim: label)
            .fixedSize()
            .font(.system(size: 5.6 * cardScale, weight: .heavy, design: .rounded))
            .foregroundStyle(fill)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 2 * cardScale)
            .padding(.vertical, 1 * cardScale)
            .background(.white.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(metal.opacity(0.8), lineWidth: 1 * cardScale))
            .shadow(color: metal.opacity(0.18), radius: 2, y: 1)
            .accessibilityLabel(Text(verbatim: isCapped
                ? L("menu.maximumCount")
                : L("menu.maximumCount.accessibility \(maxCompletions)")))
    }
}

/// A compact water fern for the sides of a completed level card. Its detached,
/// oval leaves and bowed stem deliberately echo a celebratory laurel, while the
/// irregular spacing keeps it organic enough for the reef setting.
private struct CompletionFern: View {
    let color: Color
    /// Nil means this is an already-completed card and should render fully.
    let revealStartedAt: Date?

    private struct Leaf: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let rotation: Double
    }

    private static let leaves: [Leaf] = [
        Leaf(id: 0, x: 0.63, y: 0.82, width: 0.25, height: 0.12, rotation: 48),
        Leaf(id: 1, x: 0.29, y: 0.75, width: 0.27, height: 0.12, rotation: 27),
        Leaf(id: 2, x: 0.62, y: 0.66, width: 0.28, height: 0.12, rotation: -42),
        Leaf(id: 3, x: 0.18, y: 0.58, width: 0.28, height: 0.12, rotation: 13),
        Leaf(id: 4, x: 0.57, y: 0.49, width: 0.29, height: 0.12, rotation: -52),
        Leaf(id: 5, x: 0.19, y: 0.39, width: 0.27, height: 0.115, rotation: -7),
        Leaf(id: 6, x: 0.62, y: 0.31, width: 0.27, height: 0.115, rotation: -58),
        Leaf(id: 7, x: 0.34, y: 0.20, width: 0.25, height: 0.11, rotation: -25),
        Leaf(id: 8, x: 0.70, y: 0.14, width: 0.23, height: 0.105, rotation: -45)
    ]

    var body: some View {
        Group {
            // Only a fern that is actually growing needs a frame-by-frame
            // redraw. An already-completed card renders its finished fern once
            // and then costs nothing — which matters because the menu can show
            // dozens of completed levels, each carrying two of these.
            if let revealStartedAt {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    fern(at: max(0, context.date.timeIntervalSince(revealStartedAt)))
                }
            } else {
                fern(at: .greatestFiniteMagnitude)
            }
        }
        .shadow(color: color.opacity(0.16), radius: 1, y: 0.5)
    }

    private func fern(at elapsed: TimeInterval) -> some View {
        GeometryReader { proxy in
            ZStack {
                FernStemShape()
                    .trim(from: 0, to: stemProgress(at: elapsed))
                    .stroke(color.opacity(0.62),
                            style: StrokeStyle(lineWidth: max(1, proxy.size.width * 0.05),
                                               lineCap: .round))

                ForEach(Self.leaves) { leaf in
                    let progress = leafProgress(leaf, at: elapsed)
                    let leafX = proxy.size.width * leaf.x
                    let leafY = proxy.size.height * leaf.y

                    // A short petiole connects every leaf to the bowed
                    // stem, so the ornament reads as a growing fern rather
                    // than a loose row of capsules.
                    Path { path in
                        path.move(to: CGPoint(x: proxy.size.width * stemX(at: leaf.y),
                                              y: leafY))
                        path.addLine(to: CGPoint(x: leafX, y: leafY))
                    }
                    .trim(from: 0, to: min(1, progress))
                    .stroke(color.opacity(0.48),
                            style: StrokeStyle(lineWidth: max(0.7, proxy.size.width * 0.025),
                                               lineCap: .round))

                    FernLeafShape()
                        .fill(
                            LinearGradient(colors: [color.opacity(0.95), color.opacity(0.62)],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .frame(width: proxy.size.width * leaf.width,
                               height: proxy.size.height * leaf.height)
                        .scaleEffect(x: progress, y: progress, anchor: .leading)
                        .rotationEffect(.degrees(leaf.rotation
                            + (leaf.x < stemX(at: leaf.y) ? -14 : 14) * (1 - progress)))
                        .opacity(min(1, progress))
                        .position(x: leafX, y: leafY)
                }
            }
        }
    }

    private func stemProgress(at elapsed: TimeInterval) -> CGFloat {
        CGFloat(min(1, max(0, elapsed / 0.48)))
    }

    private func leafProgress(_ leaf: Leaf, at elapsed: TimeInterval) -> CGFloat {
        let delay = 0.16 + Double(leaf.id) * 0.055
        let raw = min(1, max(0, (elapsed - delay) / 0.30))
        // Back ease: each leaf opens with a tiny organic overshoot.
        let c1 = 1.70158
        let c3 = c1 + 1
        return CGFloat(1 + c3 * pow(raw - 1, 3) + c1 * pow(raw - 1, 2))
    }

    /// Approximation of the stem's horizontal position at a leaf's height.
    private func stemX(at y: CGFloat) -> CGFloat {
        let fromBottom = 1 - y
        return 0.76 - 0.10 * fromBottom - 0.34 * sin(fromBottom * .pi)
    }
}

/// A pointed, slightly asymmetric leaf reads more naturally at this tiny size
/// than a capsule, while remaining crisp on both phone and iPad.
private struct FernLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                      control1: CGPoint(x: rect.width * 0.30, y: rect.minY),
                      control2: CGPoint(x: rect.width * 0.78, y: rect.minY + rect.height * 0.08))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                      control1: CGPoint(x: rect.width * 0.72, y: rect.maxY),
                      control2: CGPoint(x: rect.width * 0.22, y: rect.maxY - rect.height * 0.04))
        path.closeSubpath()
        return path
    }
}

private struct FernStemShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.94))
        path.addCurve(to: CGPoint(x: rect.width * 0.66, y: rect.height * 0.10),
                      control1: CGPoint(x: rect.width * 0.34, y: rect.height * 0.80),
                      control2: CGPoint(x: rect.width * 0.08, y: rect.height * 0.34))
        return path
    }
}

// MARK: - Tap-again info pop-out

/// The little themed card shown when the already-selected topic is tapped
/// again. `anchor` is the tapped control's frame in the shared "home" space.
struct InfoPopup: Identifiable {
    let header: String
    let message: String
    let anchor: CGRect
    let id = UUID()
}

struct InfoPopoutCard: View {
    let header: String
    let message: String
    let caretOffset: CGFloat
    let theme: AnimalCharacter
    private var isPad: Bool { AppLayout.isPad }

    /// Width needed for the header or message, including the card's horizontal
    /// padding. Longer messages deliberately use the narrowest width that still
    /// fits them on two lines, instead of making the pop-out screen-wide.
    static func preferredWidth(header: String,
                               message: String,
                               isPad: Bool,
                               maximum: CGFloat) -> CGFloat {
#if canImport(UIKit)
        let headerFont = UIFont.systemFont(ofSize: isPad ? 14 : 11, weight: .heavy)
        let messageFont = UIFont.systemFont(ofSize: isPad ? 21 : 16, weight: .bold)
        // `Text(header)` adds 0.6 points between every pair of letters below.
        // Include that tracking here too, or a heading can be measured a little
        // too narrowly and wrap even when the pop-out has room to grow.
        let uppercasedHeader = header.uppercased()
        let headerTracking = CGFloat(max(0, uppercasedHeader.count - 1)) * 0.6
        let headerWidth = (uppercasedHeader as NSString)
            .size(withAttributes: [.font: headerFont]).width + headerTracking
        let messageString = message as NSString
        let messageWidth = messageString
            .size(withAttributes: [.font: messageFont]).width
        let horizontalPadding: CGFloat = isPad ? 36 : 28
        let maximumContentWidth = max(1, maximum - horizontalPadding)

        // Keep short explanations on one line. For longer translations, find
        // the smallest content width that needs no more than two lines, so the
        // second line does not leave a large empty tail in the card.
        if max(headerWidth, messageWidth) <= maximumContentWidth {
            return ceil(max(headerWidth, messageWidth) + horizontalPadding)
        }

        var lowerBound = min(maximumContentWidth, max(headerWidth, isPad ? 220 : 170))
        var upperBound = maximumContentWidth
        let twoLineHeight = messageFont.lineHeight * 2.05

        for _ in 0..<9 {
            let candidate = (lowerBound + upperBound) / 2
            let measured = messageString.boundingRect(
                with: CGSize(width: candidate, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: messageFont],
                context: nil
            )
            if measured.height <= twoLineHeight {
                upperBound = candidate
            } else {
                lowerBound = candidate
            }
        }

        return ceil(upperBound + horizontalPadding)
#else
        return min(isPad ? 340 : 250, maximum)
#endif
    }

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(.white)
                .frame(width: 18, height: 9)
                .overlay(alignment: .bottom) {
                    // Hide the seam where the caret meets the card body.
                    Rectangle().fill(.white).frame(height: 1).padding(.horizontal, 2)
                }
                .offset(x: caretOffset)

            VStack(alignment: .leading, spacing: isPad ? 5 : 3) {
                Text(header.uppercased())
                    .font(.system(size: isPad ? 14 : 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(theme.deepColor.opacity(0.55))
                Text(message)
                    .font(.system(size: isPad ? 21 : 16, weight: .bold))
                    .foregroundStyle(theme.deepColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isPad ? 18 : 14)
            .padding(.vertical, isPad ? 14 : 11)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.deepColor.opacity(0.18), lineWidth: 1))
        }
        .shadow(color: theme.deepColor.opacity(0.22), radius: 14, y: 6)
    }
}

/// An upward-pointing triangle for the pop-out caret.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A number that counts from one value to another over a fixed window, driven
/// by elapsed time so no change event can be coalesced or missed.
struct CountingNumber: View {
    let from: Int
    let to: Int
    /// Nil renders the final value straight away, with no count-up.
    let startedAt: Date?
    var delay = 0.0
    var duration = 0.78

    var body: some View {
        Group {
            // A `TimelineView(.animation)` subscribes to the display link for as
            // long as it exists, and the menu holds one of these per level card.
            // Without a count-up to run there is nothing for those frames to
            // change, so the settled value is rendered as a plain, static view
            // and the whole screen stops redrawing at 120 Hz while idle.
            if let startedAt {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    numeral(at: context.date.timeIntervalSince(startedAt))
                }
            } else {
                numeral(at: .greatestFiniteMagnitude)
            }
        }
        .accessibilityLabel(Text(verbatim: LN(to)))
    }

    private func numeral(at elapsed: TimeInterval) -> some View {
        let progress = min(1, max(0, (elapsed - delay) / duration))
        let eased = 1 - pow(1 - progress, 3)
        let value = Int((Double(from) + Double(to - from) * eased).rounded())
        return Text(verbatim: LN(value))
            .contentTransition(.numericText())
            .monospacedDigit()
            // A gentle swell that peaks mid-count and settles again.
            .scaleEffect(1 + sin(progress * .pi) * 0.13)
    }
}

// MARK: - Card total / next character

/// The next animal still to be earned and how many cards are missing. Held as a
/// value rather than recomputed on the spot, so the summary line can keep the
/// old count on screen while a return celebration counts the total up.
struct NextCharacterPrompt: Equatable {
    let characterID: String
    let remaining: Int

    var character: AnimalCharacter { CharacterCatalog.character(id: characterID) }
}

private struct CardSummaryWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The quiet line under the player's name. Normally the running card total;
/// once the player has started collecting, the same slot briefly previews the
/// next character to earn, so the menu needs no permanent row for it.
struct AlternatingCardSummary: View {
    let totalFrom: Int
    let totalTo: Int
    /// Nil renders the total straight away, with no count-up.
    let celebrationStartedAt: Date?
    var countDelay = 0.0
    var countDuration = 0.78
    let prompt: NextCharacterPrompt?
    /// Bumped once a level return has fully settled: the new remaining count is
    /// then previewed at once instead of waiting out the ordinary cycle.
    let immediatePreviewID: Int
    /// While the return celebration runs, the total owns the slot.
    let isCelebrationActive: Bool
    /// True for the beat in which a reward has just joined the totals.
    var isHighlighted = false
    let accent: Color
    let isPad: Bool
    let action: () -> Void

    @ObservedObject private var language = LanguageManager.shared
    @State private var showsPreview = false
    @State private var displayedPrompt: NextCharacterPrompt?
    @State private var handledImmediatePreviewID = 0
    @State private var availableWidth: CGFloat = 0

    private var scale: CGFloat { isPad ? 1.5 : 1 }
    private var baseFontSize: CGFloat { isPad ? 22 : 14 }
    private var iconSize: CGFloat { isPad ? 19 : 12 }
    private var artworkSide: CGFloat { 28 * scale }
    /// Both alternatives share this height, so the taller artwork grows around
    /// the text line instead of pushing the player's name upward.
    private var opticalLineHeight: CGFloat { baseFontSize * 1.4 }

    var body: some View {
        HStack(spacing: 4) {
            // The card glyph never takes part in the swap: holding it perfectly
            // still avoids the dip two crossfading icons would produce.
            CurrencyIcon(size: iconSize)
                .scaleEffect(isHighlighted ? 1.32 : 1)
                .rotationEffect(.degrees(isHighlighted ? -10 : 0))

            alternatingValues
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: CardSummaryWidthKey.self,
                                               value: proxy.size.width)
                    }
                }
                .onPreferenceChange(CardSummaryWidthKey.self) { width in
                    guard abs(width - availableWidth) > 0.5 else { return }
                    withTransaction(Transaction(animation: nil)) { availableWidth = width }
                }
        }
        .foregroundStyle(accent)
        .lineLimit(1)
        .task(id: cycleID) { await runPreviewCycle() }
    }

    // MARK: Contents

    private var alternatingValues: some View {
        let contentScale = contentScale
        return ZStack(alignment: .leading) {
            CountingNumber(from: totalFrom,
                           to: totalTo,
                           startedAt: celebrationStartedAt,
                           delay: countDelay,
                           duration: countDuration)
                .font(.system(size: baseFontSize, weight: .heavy, design: .rounded))
                .opacity(showsPreview ? 0 : 1)
                .blur(radius: showsPreview ? 2.2 : 0)
                .scaleEffect(showsPreview ? 0.985 : 1, anchor: .leading)
                .reportAnchor("headerTotal")
                // Deliberately not hidden while the preview shows: the total is
                // the authoritative reading of this line, and a slot that comes
                // and goes would make it unfindable for VoiceOver.
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("card-total")
                .accessibilityLabel(Text(L("game.bubblesCollected \(totalTo)")))

            if let displayedPrompt {
                promptLabel(displayedPrompt, contentScale: contentScale)
            }
        }
        .frame(height: opticalLineHeight, alignment: .leading)
    }

    private func promptLabel(_ prompt: NextCharacterPrompt, contentScale: CGFloat) -> some View {
        let animal = prompt.character
        return Button(action: action) {
            HStack(alignment: .center, spacing: 3 * scale * contentScale) {
                Text(verbatim: remainingText(prompt.remaining))
                    .font(.system(size: baseFontSize * contentScale,
                                  weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                    .allowsTightening(true)
                    // Deliberately *not* fixed-size: this text must be able to
                    // give way. `contentScale` already sizes the group to fit,
                    // and it is measured from the width this row is offered —
                    // a text that refused to compress would widen that offer
                    // instead, and with it the whole menu card.
                    .minimumScaleFactor(0.6)
                Image(systemName: "arrow.forward")
                    .font(.system(size: 10 * scale * contentScale, weight: .bold))
                    // The arrow sits optically a fraction above rounded numerals
                    // at this size.
                    .offset(y: 0.8 * scale * contentScale)
                    .opacity(0.58)
                animal.thumbArtwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: artworkSide * contentScale,
                           height: artworkSide * contentScale)
                    // Keep the full visual size, but let it extend equally above
                    // and below a text-height layout footprint.
                    .frame(height: opticalLineHeight * contentScale)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(showsPreview ? 1 : 0)
        .blur(radius: showsPreview ? 0 : 2.2)
        .scaleEffect(showsPreview ? 1 : 0.985, anchor: .leading)
        .allowsHitTesting(showsPreview)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("next-character")
        .accessibilityLabel(Text(L("home.nextCharacter \(prompt.remaining) \(animal.localizedName)")))
        .accessibilityHidden(!showsPreview)
    }

    private func remainingText(_ remaining: Int) -> String {
        L("home.cardsRemaining \(remaining)")
    }

    // MARK: Fitting

    /// The prompt must never wrap or truncate, so when the header column is too
    /// narrow for the longest translation the whole group shrinks instead.
    private var contentScale: CGFloat {
        guard prompt != nil, availableWidth > 0, naturalPromptWidth > availableWidth else { return 1 }
        // A small rounding margin, so the non-wrapping text never lands exactly
        // on the clipping boundary after pixel quantisation.
        return max(0.01, (availableWidth - 2 * scale) / naturalPromptWidth)
    }

    private var naturalPromptWidth: CGFloat {
        guard let prompt else { return 0 }
        // Two HStack gaps plus the forward arrow, beside the measured text.
        let decoration = 6 * scale + 10 * scale + artworkSide
#if canImport(UIKit)
        let system = UIFont.systemFont(ofSize: baseFontSize, weight: .heavy)
        let font = system.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: baseFontSize) } ?? system
        let text = ceil((remainingText(prompt.remaining) as NSString)
            .size(withAttributes: [.font: font]).width)
        return text + decoration
#else
        return baseFontSize * 4 + decoration
#endif
    }

    // MARK: Cycle

    private var cycleID: String {
        let promptID = prompt.map { "\($0.characterID)-\($0.remaining)" } ?? "total"
        return "\(promptID)-\(immediatePreviewID)-\(isCelebrationActive)"
    }

    @MainActor
    private func runPreviewCycle() async {
        // A returning session owns this line until its card count, flight and
        // total count-up have all settled. Cancelling here also hides a preview
        // that happened to be on screen when the return began.
        guard !isCelebrationActive else {
            withTransaction(Transaction(animation: nil)) { showsPreview = false }
            return
        }

        guard let prompt else {
            showsPreview = false
            displayedPrompt = nil
            handledImmediatePreviewID = immediatePreviewID
            return
        }

        do {
            if displayedPrompt != prompt {
                if immediatePreviewID != handledImmediatePreviewID {
                    // Only a completed level return bumps the trigger; a launch
                    // or an iCloud merge updates the value silently and waits
                    // for the ordinary cycle. Install the *new* remaining
                    // value before fading it in; showing the previous prompt
                    // for a beat made the end of the sequence feel one step
                    // behind the counters.
                    displayedPrompt = prompt
                    withAnimation(.easeInOut(duration: 0.32)) { showsPreview = true }
                    try await Task.sleep(nanoseconds: 2_200_000_000)
                    withAnimation(.easeInOut(duration: 0.32)) { showsPreview = false }
                } else {
                    displayedPrompt = prompt
                    showsPreview = false
                }
            }
            handledImmediatePreviewID = immediatePreviewID

            try await Task.sleep(nanoseconds: 5_000_000_000)
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.55)) { showsPreview = true }
                try await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeInOut(duration: 0.55)) { showsPreview = false }
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
        } catch {
            // SwiftUI cancels this task when the prompt changes or the view goes.
        }
    }
}

/// One card in flight from a level card up to the header total. Its geometry
/// lives in the shared "home" space, so it starts exactly on the level card's
/// glyph and lands exactly on the header's.
struct CardFlight: Identifiable {
    let id = UUID()
    let celebrationID: UUID
    let source: CGRect
    let destination: CGRect
    let sourcePointSize: CGFloat
    let destinationPointSize: CGFloat
    let arcHeight: CGFloat
    let color: Color
    let startedAt: Date
    let duration: TimeInterval
}

/// Draws the flying card from the elapsed time each frame, so the arc is a real
/// curved path — a plain `.position` animation would cut straight across.
struct CardFlightView: View {
    let flight: CardFlight

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(flight.startedAt))
            let t = min(1, elapsed / flight.duration)
            // Ease progress along the path; keep the arc keyed to raw `t` so the
            // lift peaks at the midpoint of the flight.
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let x = flight.source.midX + (flight.destination.midX - flight.source.midX) * eased
            let y = flight.source.midY + (flight.destination.midY - flight.source.midY) * eased
                - CGFloat(sin(Double(t) * .pi)) * flight.arcHeight
            let size = flight.sourcePointSize
                + (flight.destinationPointSize - flight.sourcePointSize) * eased
            // Merge softly into the header glyph over the last stretch.
            let fade = t > 0.88 ? max(0, 1 - (t - 0.88) / 0.12) : 1
            CurrencyIcon(size: size)
                .foregroundStyle(flight.color)
                .shadow(color: flight.color.opacity(0.35), radius: 3, y: 1)
                .opacity(fade)
                .position(x: x, y: y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A time-driven focus outline around the level just returned from. This
/// deliberately has no `@State` or `onChange`: as long as the celebration
/// exists, the current frame can derive the correct glow intensity.
struct LevelReturnFocusGlow: View {
    let startedAt: Date
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let glowRadius: CGFloat
    let strokeColor: Color
    let glowColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(strokeColor, lineWidth: lineWidth)
                .shadow(color: glowColor.opacity(0.85), radius: glowRadius)
                .opacity(glowOpacity(at: elapsed))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glowOpacity(at elapsed: TimeInterval) -> Double {
        if elapsed < 0.28 { return elapsed / 0.28 }
        if elapsed < 1.45 { return 1 }
        if elapsed < 1.98 { return 1 - ((elapsed - 1.45) / 0.53) }
        return 0
    }
}

/// Frames of each level card's card glyph, keyed by level id, in "home" space.
/// These are the launch points for the card that flies up to the header total.
struct CardGlyphAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Frames of the on-screen topic controls, keyed by name, in "home" space.
struct ControlAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Reports this control's frame in the shared "home" coordinate space so a
    /// pop-out can be positioned directly under it.
    func reportAnchor(_ key: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ControlAnchorKey.self,
                                       value: [key: proxy.frame(in: .named("home"))])
            }
        )
    }
}
