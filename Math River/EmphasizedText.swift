//
//  EmphasizedText.swift
//  Number Reef
//
//  Turns the emphasis markers inside localized copy into one attributed string.
//  Keeping the result as a single text value lets SwiftUI wrap a bold span
//  across lines without treating each styled part as a separate view.
//
//  The catalog marks emphasis with Markdown (`**bold**`) — the notation every
//  translation tool already understands, and the one Apple's own string
//  catalogs and `AttributedString` speak natively. A translator therefore never
//  has to learn a house convention, and can move the emphasis to wherever the
//  stressed words land in their language.
//

import Foundation

/// Parses the Markdown emphasis in a localized string.
///
/// Only inline Markdown is interpreted, and whitespace is preserved verbatim,
/// so a translation is never silently reflowed. Anything that is not valid
/// Markdown is rendered as plain text rather than dropped.
func emphasizedAttributedString(_ copy: String) -> AttributedString {
    let markdown = copy.contains("|") ? legacyPipeMarkersAsMarkdown(copy) : copy

    if let parsed = try? AttributedString(
        markdown: markdown,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
        return parsed
    }

    return AttributedString(copy)
}

/// Bridges the older `|emphasis|` notation to Markdown.
///
/// Translations that predate the switch — or a memory-matched suggestion from a
/// translation tool — can still arrive with pipes around the stressed words.
/// Converting them here keeps such a string readable instead of showing the
/// bare markers on screen. An odd number of pipes is left untouched, since a
/// lone pipe is far more likely to be literal punctuation than a broken marker.
private func legacyPipeMarkersAsMarkdown(_ copy: String) -> String {
    let parts = copy.components(separatedBy: "|")
    guard parts.count > 2, parts.count.isMultiple(of: 2) == false else { return copy }

    return parts.enumerated()
        .map { $0.offset.isMultiple(of: 2) ? $0.element : "**\($0.element)**" }
        .joined()
}
