//
//  RoundFactory.swift
//  Elephant Challenge: Math Memory
//
//  Builds one complete round: the question, the answer cards in their final
//  shuffled positions.
//
//  Answer positions are decided here, once, before the cards become visible —
//  the UI never re-orders them afterwards.
//

import Foundation

// MARK: - Answer card

nonisolated public struct AnswerOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let isCorrect: Bool

    public init(id: UUID = UUID(), text: String, isCorrect: Bool) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
    }
}

// MARK: - Round

nonisolated public struct GameRound: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 1-based position in the session.
    public let number: Int
    public let question: MathQuestion
    /// Exactly one option has `isCorrect == true`.
    public let options: [AnswerOption]
    public init(id: UUID = UUID(),
                number: Int,
                question: MathQuestion,
                options: [AnswerOption]) {
        self.id = id
        self.number = number
        self.question = question
        self.options = options
    }

    public var correctOption: AnswerOption? {
        options.first { $0.isCorrect }
    }
}

// MARK: - Factory

nonisolated public final class RoundFactory {
    private let generator: QuestionGenerator
    private let random: RandomSource

    public init(level: MathLevel,
                mixedVariant: MixedVariant = .all,
                mode: PracticeMode = .mixed,
                seed: UInt64? = nil) {
        let random = RandomSource(seed: seed)
        self.random = random
        self.generator = QuestionGenerator(level: level,
                                           mode: mode,
                                           mixedVariant: mixedVariant,
                                           random: random)
    }

    public func reset() {
        generator.reset()
    }

    /// Builds the round for a given 1-based round number.
    public func makeRound(number: Int) -> GameRound {
        let question = generator.next(requiredDistractors: GameConfig.distractorCount)
        return GameRound(number: number,
                         question: question,
                         options: makeOptions(for: question))
    }

    /// One correct card plus the required number of unique wrong cards, laid
    /// out in ascending order. Ordered cards are far easier to hold in mind
    /// than scattered ones, which is the point of the memorising beat.
    ///
    /// The correct answer's position still varies from round to round, because
    /// where it lands depends on how the distractors compare to it — but it
    /// never moves once the round is built.
    private func makeOptions(for question: MathQuestion) -> [AnswerOption] {
        var options = [AnswerOption(text: question.correctAnswer, isCorrect: true)]
        var used: Set<AnswerValue> = [AnswerValue(question.correctAnswer)]
        for candidate in question.distractors {
            guard options.count <= GameConfig.distractorCount else { break }
            let value = AnswerValue(candidate)
            guard !used.contains(value) else { continue }
            used.insert(value)
            options.append(AnswerOption(text: candidate, isCorrect: false))
        }
        return options.sorted { AnswerValue($0.text) < AnswerValue($1.text) }
    }
}
