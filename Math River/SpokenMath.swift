//
//  SpokenMath.swift
//  Number Reef
//
//  Compact, language-native wording for the sums read aloud by AppAudio.
//
//  Everything a language needs lives in one row of `lexicons` — the words, how
//  it says a fraction, and which system voice should say it. Adding a language
//  is adding a row; no algorithm below branches on a language code.
//

import Foundation

/// Converts the language-neutral question shown by the game into a short
/// utterance. Numerals deliberately remain numerals: the selected system voice
/// already knows how to pronounce them in its own language.
enum SpokenMath {

    /// How a language says "1/20".
    ///
    /// Most languages read a fraction as a count of parts, which a single
    /// pattern covers. A language whose school form is genuinely different gets
    /// its own case — but only when a pattern really cannot express it.
    enum FractionStyle: Sendable {
        /// `%n` is the numerator, `%d` the denominator — "1 of 20 parts".
        case pattern(String)
        /// Numeric ordinal, the Dutch school form: "1 twintigste". Writing the
        /// ordinal as digits plus a suffix keeps even a denominator of 128
        /// short, while still prompting the voice to say it in full.
        case dutchOrdinal
    }

    struct Lexicon: Sendable {
        let plus: String
        let minus: String
        let times: String
        let dividedBy: String
        /// `%p` is the percentage — "40 percent".
        let percentPattern: String
        /// `%p` is the percentage, `%w` the whole — "40 percent of 60".
        let percentOfPattern: String
        let equals: String
        /// How the language asks for the missing value — "how many".
        let unknown: String
        let fractionStyle: FractionStyle
        /// The language part of the voice identifier to search for, when it
        /// differs from the app's language code (Norwegian ships as `nb`).
        let voiceLanguage: String
        /// A specific voice locale to prefer when a language has several and
        /// one of them is the one children hear at school.
        let preferredVoiceLocale: String?

        init(code: String,
             plus: String,
             minus: String,
             times: String,
             dividedBy: String,
             percentPattern: String,
             percentOfPattern: String,
             equals: String,
             unknown: String,
             fractionStyle: FractionStyle,
             voiceLanguage: String? = nil,
             preferredVoiceLocale: String? = nil) {
            self.plus = plus
            self.minus = minus
            self.times = times
            self.dividedBy = dividedBy
            self.percentPattern = percentPattern
            self.percentOfPattern = percentOfPattern
            self.equals = equals
            self.unknown = unknown
            self.fractionStyle = fractionStyle
            self.voiceLanguage = voiceLanguage ?? code
            self.preferredVoiceLocale = preferredVoiceLocale
        }

        func percent(_ value: String) -> String {
            percentPattern.replacingOccurrences(of: "%p", with: value)
        }

        func percentOf(_ value: String, whole: String) -> String {
            percentOfPattern
                .replacingOccurrences(of: "%p", with: value)
                .replacingOccurrences(of: "%w", with: whole)
        }
    }

    /// The languages the sums can be spoken in.
    ///
    /// A language belongs here once Apple supplies an AVSpeech voice for it on
    /// its platforms; a runtime voice check still decides whether speech is
    /// offered on the particular device. A language present in the string
    /// catalog but absent here simply plays no spoken sums — the rest of the
    /// app is unaffected.
    static let lexicons: [String: Lexicon] = [
        "en": Lexicon(code: "en",
                      plus: "plus", minus: "minus", times: "times",
                      dividedBy: "divided by",
                      percentPattern: "%p percent",
                      percentOfPattern: "%p percent of %w",
                      equals: "is", unknown: "how many",
                      fractionStyle: .pattern("%n of %d parts")),
        "nl": Lexicon(code: "nl",
                      plus: "plus", minus: "min", times: "keer",
                      dividedBy: "gedeeld door",
                      percentPattern: "%p procent",
                      percentOfPattern: "%p procent van %w",
                      equals: "is", unknown: "hoeveel",
                      fractionStyle: .dutchOrdinal,
                      preferredVoiceLocale: "nl-NL")
    ]

    static func text(for prompt: String, languageCode: String) -> String? {
        guard let lexicon = lexicons[languageCode] else { return nil }
        let sides = prompt.components(separatedBy: "=")
        if sides.count == 2 {
            let lhs = expression(sides[0], lexicon: lexicon)
            let rhs = sides[1].trimmingCharacters(in: .whitespaces)
            if rhs == "?" {
                return lhs
            }
            return "\(lhs) \(lexicon.equals) \(expression(rhs, lexicon: lexicon))"
        }
        return expression(prompt, lexicon: lexicon)
    }

    private static func expression(_ expression: String, lexicon: Lexicon) -> String {
        let tokens = expression.split(separator: " ").map(String.init)

        // Percent questions are said in the natural order of the language,
        // rather than literally reading “percent times”.
        if tokens.count == 3,
           tokens[0].hasSuffix("%"),
           tokens[1] == "×" {
            let percent = String(tokens[0].dropLast())
            return lexicon.percentOf(number(percent, lexicon: lexicon),
                                     whole: term(tokens[2], lexicon: lexicon))
        }

        return tokens.map { token in
            switch token {
            case "+": return lexicon.plus
            case "−", "-": return lexicon.minus
            case "×": return lexicon.times
            case "÷": return lexicon.dividedBy
            case "=": return lexicon.equals
            default: return term(token, lexicon: lexicon)
            }
        }.joined(separator: " ")
    }

    private static func term(_ token: String, lexicon: Lexicon) -> String {
        if token.hasSuffix("%") {
            return lexicon.percent(number(String(token.dropLast()), lexicon: lexicon))
        }
        if token.contains("/") {
            let parts = token.components(separatedBy: "/")
            if parts.count == 2 {
                return fraction(numerator: number(parts[0], lexicon: lexicon),
                                denominator: number(parts[1], lexicon: lexicon),
                                lexicon: lexicon)
            }
        }
        return number(token, lexicon: lexicon)
    }

    private static func fraction(numerator: String, denominator: String,
                                 lexicon: Lexicon) -> String {
        switch lexicon.fractionStyle {
        case .pattern(let pattern):
            return pattern
                .replacingOccurrences(of: "%n", with: numerator)
                .replacingOccurrences(of: "%d", with: denominator)
        case .dutchOrdinal:
            let ordinal = dutchOrdinal(denominator, unknown: lexicon.unknown)
            // "hoeveel twintigsten" — an unknown numerator takes a plural.
            return numerator == lexicon.unknown
                ? "\(numerator) \(ordinal)n"
                : "\(numerator) \(ordinal)"
        }
    }

    /// "20" becomes "20ste", which the Dutch voice reads as
    /// “twintigste”. An unknown denominator is left as the question word.
    private static func dutchOrdinal(_ denominator: String, unknown: String) -> String {
        guard denominator != unknown, let value = Int(denominator) else {
            return denominator
        }
        let suffix = value == 8 || value >= 20 ? "ste" : "de"
        return "\(value)\(suffix)"
    }

    private static func number(_ text: String, lexicon: Lexicon) -> String {
        text == "?" ? lexicon.unknown : text
    }
}
