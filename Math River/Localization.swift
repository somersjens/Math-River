//
//  Localization.swift
//  Elephant Challenge: Math Memory
//
//  Runtime language switching + the little flag-and-chevron picker shown on
//  the welcome screens and the premium menu.
//
//  SwiftUI's `Text` resolves its strings from the *main bundle*, not from the
//  environment locale, so changing `\.locale` alone is not enough to swap the
//  language while the app is running. We install a tiny Bundle subclass that
//  redirects `localizedString(...)` to a chosen `.lproj`. Changing the
//  environment locale at the root then re-renders every `Text`, which now
//  reads the redirected strings — a live, no-restart language change.
//

import SwiftUI
import Combine
import ObjectiveC

// MARK: - Supported languages

/// A language the app can present, identified by its ISO code and shown in the
/// picker with a flag and its own-language name (endonym). This is a plain data
/// model rather than an enum with per-case switches, so the full language list
/// below is the single place to add a language — no code branches to touch.
///
/// The string catalog carries the actual translations for each `code`; until a
/// language is fully translated the runtime falls back to English (see the
/// bundle redirection further down).
struct AppLanguage: Identifiable, Hashable, Sendable {
    /// ISO 639 code, matching the language's `.lproj` and its column in the
    /// string catalog.
    let code: String
    /// Flag shown in the picker.
    let flag: String
    /// The language's name in its own language — the convention for a picker.
    let displayName: String
    /// The English name, so the search field finds "German" as readily as
    /// "Deutsch". Nothing is ever shown to the player from this.
    let searchName: String

    var id: String { code }

    /// A flag and an English name are the only things the system cannot supply;
    /// the endonym is read from the language's own locale unless a row
    /// overrides it.
    init(code: String, flag: String, searchName: String, displayName: String? = nil) {
        self.code = code
        self.flag = flag
        self.searchName = searchName
        self.displayName = displayName ?? Self.endonym(for: code)
    }

    /// The language's name written in that language, capitalized the way that
    /// language capitalizes it (Dutch lowercases "nederlands", so the first
    /// letter is raised using the language's own casing rules rather than the
    /// device's).
    private static func endonym(for code: String) -> String {
        let locale = Locale(identifier: code)
        guard let name = locale.localizedString(forLanguageCode: code), !name.isEmpty else {
            return code.uppercased()
        }
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    /// True for Arabic, Hebrew, Persian, Urdu and Uyghur — read from the
    /// language itself rather than a hand-kept list, so a language added later
    /// lays itself out correctly without anyone remembering to say so.
    var isRightToLeft: Bool {
        Locale(identifier: code).language.characterDirection == .rightToLeft
    }

    /// The writing system, from CLDR: "Latn", "Cyrl", "Arab", "Deva"…
    ///
    /// Used to order the picker. Grouping by script puts the languages a given
    /// reader can even recognise next to each other, which at this length
    /// matters more than one long alphabetical run — the alphabet a name is
    /// written in is the first thing you can tell about it.
    var script: String {
        Locale(identifier: code).language.script?.identifier ?? "Zzzz"
    }

    /// What CLDR considers this language, ignoring spelling differences between
    /// codes for the same tongue: `no` and `nb` both canonicalize to `nb`, so a
    /// Norwegian device matches the roster's `no` row. Used only for matching,
    /// never for a bundle path.
    private var canonicalCode: String { AppLanguage.canonical(code) }

    /// CLDR's name for a language, folding the legacy spellings together.
    /// `Locale.Language(identifier:)` alone does *not* do this — only going
    /// through a full `Locale` maps "no" to "nb" and "iw" to "he" — and getting
    /// it wrong silently strands a language on English.
    fileprivate static func canonical(_ identifier: String) -> String {
        Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
    }

    /// Every language the app offers, in the order the picker lists them.
    ///
    /// This roster is the single place to add a language: one row here, plus
    /// its column in the string catalog. Nothing else in the app branches on a
    /// language code. A language whose translations have not landed yet is
    /// still offered and simply reads in English — see `LanguageManager.bundle`.
    static let all: [AppLanguage] = [
        AppLanguage(code: "af", flag: "\u{1F1FF}\u{1F1E6}", searchName: "Afrikaans"),
        AppLanguage(code: "sq", flag: "\u{1F1E6}\u{1F1F1}", searchName: "Albanian"),
        AppLanguage(code: "am", flag: "\u{1F1EA}\u{1F1F9}", searchName: "Amharic"),
        AppLanguage(code: "ar", flag: "\u{1F1F8}\u{1F1E6}", searchName: "Arabic"),
        AppLanguage(code: "hy", flag: "\u{1F1E6}\u{1F1F2}", searchName: "Armenian"),
        AppLanguage(code: "as", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Assamese"),
        AppLanguage(code: "az", flag: "\u{1F1E6}\u{1F1FF}", searchName: "Azerbaijani"),
        AppLanguage(code: "eu", flag: "\u{1F1EA}\u{1F1F8}", searchName: "Basque"),
        AppLanguage(code: "bn", flag: "\u{1F1E7}\u{1F1E9}", searchName: "Bengali"),
        AppLanguage(code: "my", flag: "\u{1F1F2}\u{1F1F2}", searchName: "Burmese"),
        AppLanguage(code: "bs", flag: "\u{1F1E7}\u{1F1E6}", searchName: "Bosnian"),
        AppLanguage(code: "bg", flag: "\u{1F1E7}\u{1F1EC}", searchName: "Bulgarian"),
        AppLanguage(code: "ca", flag: "\u{1F1EA}\u{1F1F8}", searchName: "Catalan"),
        AppLanguage(code: "zh", flag: "\u{1F1E8}\u{1F1F3}", searchName: "Chinese"),
        AppLanguage(code: "da", flag: "\u{1F1E9}\u{1F1F0}", searchName: "Danish"),
        AppLanguage(code: "de", flag: "\u{1F1E9}\u{1F1EA}", searchName: "German"),
        AppLanguage(code: "en", flag: "\u{1F1EC}\u{1F1E7}", searchName: "English"),
        AppLanguage(code: "et", flag: "\u{1F1EA}\u{1F1EA}", searchName: "Estonian"),
        AppLanguage(code: "fo", flag: "\u{1F1EB}\u{1F1F4}", searchName: "Faroese"),
        AppLanguage(code: "fi", flag: "\u{1F1EB}\u{1F1EE}", searchName: "Finnish"),
        AppLanguage(code: "fr", flag: "\u{1F1EB}\u{1F1F7}", searchName: "French"),
        AppLanguage(code: "gl", flag: "\u{1F1EA}\u{1F1F8}", searchName: "Galician"),
        AppLanguage(code: "ka", flag: "\u{1F1EC}\u{1F1EA}", searchName: "Georgian"),
        AppLanguage(code: "el", flag: "\u{1F1EC}\u{1F1F7}", searchName: "Greek"),
        AppLanguage(code: "gu", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Gujarati"),
        AppLanguage(code: "he", flag: "\u{1F1EE}\u{1F1F1}", searchName: "Hebrew"),
        AppLanguage(code: "hi", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Hindi"),
        AppLanguage(code: "hu", flag: "\u{1F1ED}\u{1F1FA}", searchName: "Hungarian"),
        AppLanguage(code: "ga", flag: "\u{1F1EE}\u{1F1EA}", searchName: "Irish"),
        AppLanguage(code: "is", flag: "\u{1F1EE}\u{1F1F8}", searchName: "Icelandic"),
        AppLanguage(code: "id", flag: "\u{1F1EE}\u{1F1E9}", searchName: "Indonesian"),
        AppLanguage(code: "it", flag: "\u{1F1EE}\u{1F1F9}", searchName: "Italian"),
        AppLanguage(code: "ja", flag: "\u{1F1EF}\u{1F1F5}", searchName: "Japanese"),
        AppLanguage(code: "kn", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Kannada"),
        AppLanguage(code: "kk", flag: "\u{1F1F0}\u{1F1FF}", searchName: "Kazakh"),
        AppLanguage(code: "km", flag: "\u{1F1F0}\u{1F1ED}", searchName: "Khmer"),
        AppLanguage(code: "ko", flag: "\u{1F1F0}\u{1F1F7}", searchName: "Korean"),
        AppLanguage(code: "hr", flag: "\u{1F1ED}\u{1F1F7}", searchName: "Croatian"),
        AppLanguage(code: "lo", flag: "\u{1F1F1}\u{1F1E6}", searchName: "Lao"),
        AppLanguage(code: "lv", flag: "\u{1F1F1}\u{1F1FB}", searchName: "Latvian"),
        AppLanguage(code: "lt", flag: "\u{1F1F1}\u{1F1F9}", searchName: "Lithuanian"),
        AppLanguage(code: "mk", flag: "\u{1F1F2}\u{1F1F0}", searchName: "Macedonian"),
        AppLanguage(code: "ms", flag: "\u{1F1F2}\u{1F1FE}", searchName: "Malay"),
        AppLanguage(code: "ml", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Malayalam"),
        AppLanguage(code: "mr", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Marathi"),
        AppLanguage(code: "mn", flag: "\u{1F1F2}\u{1F1F3}", searchName: "Mongolian"),
        AppLanguage(code: "nl", flag: "\u{1F1F3}\u{1F1F1}", searchName: "Dutch"),
        AppLanguage(code: "ne", flag: "\u{1F1F3}\u{1F1F5}", searchName: "Nepali"),
        AppLanguage(code: "no", flag: "\u{1F1F3}\u{1F1F4}", searchName: "Norwegian"),
        AppLanguage(code: "uk", flag: "\u{1F1FA}\u{1F1E6}", searchName: "Ukrainian"),
        AppLanguage(code: "or", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Odia"),
        AppLanguage(code: "ug", flag: "\u{1F1E8}\u{1F1F3}", searchName: "Uyghur"),
        AppLanguage(code: "uz", flag: "\u{1F1FA}\u{1F1FF}", searchName: "Uzbek"),
        AppLanguage(code: "fa", flag: "\u{1F1EE}\u{1F1F7}", searchName: "Persian"),
        AppLanguage(code: "pl", flag: "\u{1F1F5}\u{1F1F1}", searchName: "Polish"),
        AppLanguage(code: "pt", flag: "\u{1F1F5}\u{1F1F9}", searchName: "Portuguese"),
        AppLanguage(code: "pa", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Punjabi"),
        AppLanguage(code: "ro", flag: "\u{1F1F7}\u{1F1F4}", searchName: "Romanian"),
        AppLanguage(code: "ru", flag: "\u{1F1F7}\u{1F1FA}", searchName: "Russian"),
        AppLanguage(code: "sr", flag: "\u{1F1F7}\u{1F1F8}", searchName: "Serbian"),
        AppLanguage(code: "si", flag: "\u{1F1F1}\u{1F1F0}", searchName: "Sinhala"),
        AppLanguage(code: "sk", flag: "\u{1F1F8}\u{1F1F0}", searchName: "Slovak"),
        AppLanguage(code: "sl", flag: "\u{1F1F8}\u{1F1EE}", searchName: "Slovenian"),
        AppLanguage(code: "es", flag: "\u{1F1EA}\u{1F1F8}", searchName: "Spanish"),
        AppLanguage(code: "sw", flag: "\u{1F1F0}\u{1F1EA}", searchName: "Swahili"),
        AppLanguage(code: "ta", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Tamil"),
        AppLanguage(code: "te", flag: "\u{1F1EE}\u{1F1F3}", searchName: "Telugu"),
        AppLanguage(code: "th", flag: "\u{1F1F9}\u{1F1ED}", searchName: "Thai"),
        AppLanguage(code: "bo", flag: "\u{1F1E8}\u{1F1F3}", searchName: "Tibetan"),
        AppLanguage(code: "cs", flag: "\u{1F1E8}\u{1F1FF}", searchName: "Czech"),
        AppLanguage(code: "tr", flag: "\u{1F1F9}\u{1F1F7}", searchName: "Turkish"),
        AppLanguage(code: "ur", flag: "\u{1F1F5}\u{1F1F0}", searchName: "Urdu"),
        AppLanguage(code: "vi", flag: "\u{1F1FB}\u{1F1F3}", searchName: "Vietnamese"),
        AppLanguage(code: "cy", flag: "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}", searchName: "Welsh"),
        AppLanguage(code: "be", flag: "\u{1F1E7}\u{1F1FE}", searchName: "Belarusian"),
        AppLanguage(code: "zu", flag: "\u{1F1FF}\u{1F1E6}", searchName: "Zulu"),
        AppLanguage(code: "sv", flag: "\u{1F1F8}\u{1F1EA}", searchName: "Swedish")
    ]

    /// Look up a language by code, tolerating regional and script variants and
    /// the legacy spellings CLDR folds together ("nb-NO" finds "no").
    static func named(_ identifier: String) -> AppLanguage? {
        if let exact = all.first(where: { $0.code == identifier }) { return exact }
        let wanted = canonical(identifier)
        return all.first { $0.canonicalCode == wanted }
    }

    /// The source language, and what every other language falls back to. Falls
    /// back to a synthesised row in the (impossible) case of an empty roster.
    static let english = all.first { $0.code == "en" }
        ?? AppLanguage(code: "en", flag: "\u{1F1EC}\u{1F1E7}", searchName: "English")
}

// MARK: - Language manager

/// Holds the user's language choice. `nil` means "follow the device", which is
/// the default at first launch; picking a flag pins the app to that language.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    private static let overrideKey = "settings.languageOverride"

    @Published var override: AppLanguage? {
        didSet {
            let defaults = UserDefaults.standard
            if let override {
                defaults.set(override.code, forKey: Self.overrideKey)
            } else {
                defaults.removeObject(forKey: Self.overrideKey)
            }
            Bundle.setLanguage(override?.code)
            // The chosen language is the only thing everything below is derived
            // from, and this is the only place it can change.
            resolved = nil
        }
    }

    /// The chosen language and everything resolved from it, worked out once.
    ///
    /// Every one of these used to be recomputed on each access: `effective`
    /// walks `Bundle.main.preferredLocalizations` matching each entry against
    /// the roster, and `locale` then builds a `Locale` from the result. A single
    /// `L(...)` asks for both — and the menu resolves hundreds of strings and
    /// numbers per redraw, with the game asking again inside its frame loop.
    private struct Resolved {
        let language: AppLanguage
        let locale: Locale
        let bundle: Bundle
        let layoutDirection: LayoutDirection
        /// Every standalone number on screen goes through `LN`, which built a
        /// fresh format style each time. It only depends on the locale.
        let numberStyle: IntegerFormatStyle<Int>
    }

    private var resolved: Resolved?

    private var current: Resolved {
        if let resolved { return resolved }
        let language = resolveEffective()
        let locale = Locale(identifier: language.code)
        let value = Resolved(
            language: language,
            locale: locale,
            bundle: Self.fallbackBundles.value(for: language.code),
            layoutDirection: language.isRightToLeft ? .rightToLeft : .leftToRight,
            numberStyle: IntegerFormatStyle<Int>().locale(locale)
        )
        resolved = value
        return value
    }

    /// How this language writes a plain number. See `LN`.
    var numberStyle: IntegerFormatStyle<Int> { current.numberStyle }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.overrideKey) {
            override = AppLanguage.named(raw)
        }
        Bundle.setLanguage(override?.code)
    }

    /// The language actually shown: the pinned choice, or the device's best
    /// match among the languages we support. Matching is generic over
    /// `AppLanguage.all`, so adding a language to the roster (and the string
    /// catalog) is all it takes to have the device follow it automatically.
    var effective: AppLanguage { current.language }

    private func resolveEffective() -> AppLanguage {
        if let override { return override }
        for identifier in Bundle.main.preferredLocalizations {
            // `preferredLocalizations` can hand back a regional or script
            // variant ("nl-BE", "zh-Hans-CN"), and CLDR folds some codes
            // together ("nb" for the roster's "no"). `named(_:)` handles both.
            if let match = AppLanguage.named(identifier) { return match }
        }
        return .english
    }

    /// Drives the environment locale, which both formats numbers correctly and
    /// forces every `Text` to re-render when the language changes.
    var locale: Locale { current.locale }

    /// Which way the chosen language reads. Set explicitly at the app root:
    /// SwiftUI derives layout direction from the *bundle's* language, which the
    /// in-app switch deliberately overrides, so it would otherwise stay
    /// left-to-right when the player picks Arabic or Hebrew.
    var layoutDirection: LayoutDirection { current.layoutDirection }

    /// The bundle strings are resolved from. `String(localized:)` ignores the
    /// runtime redirection installed on `Bundle.main`, so any string resolved in
    /// code must be pointed at this bundle explicitly (see `L`). It falls back
    /// to English for anything the chosen language has not translated, and is
    /// English outright for a language whose `.lproj` has not shipped at all.
    var bundle: Bundle { current.bundle }

    /// The English `.lproj`, the last-resort fallback for every other language,
    /// and the locale to format its arguments with.
    static let englishBundle: Bundle? = plainLprojBundle(for: "en")
    static let englishLocale = Locale(identifier: AppLanguage.english.code)

    /// One prepared bundle per language, built on first use. Each is a real
    /// `.lproj` bundle whose class has been swapped so misses reach English.
    private static let fallbackBundles = BundleCache()

    /// The `.lproj` holding a language's strings.
    ///
    /// The folder is not always named after the roster's code: Xcode writes the
    /// canonical CLDR name, so the catalog's `no` column ships as `nb.lproj`.
    /// Rather than keep a table of such renames, ask the bundle which of its
    /// localizations is the same language.
    fileprivate static func plainLprojBundle(for code: String) -> Bundle? {
        for name in lprojNames(for: code) {
            if let path = Bundle.main.path(forResource: name, ofType: "lproj") {
                return Bundle(path: path)
            }
        }
        return nil
    }

    private static func lprojNames(for code: String) -> [String] {
        let canonical = AppLanguage.canonical(code)
        var names = [code]
        if canonical != code { names.append(canonical) }
        names += Bundle.main.localizations.filter { shipped in
            shipped != code && shipped != canonical
                && AppLanguage.canonical(shipped) == canonical
        }
        return names
    }

    /// Lazily built, then reused: `Bundle(path:)` re-reads the `.strings` file,
    /// and the game asks for strings inside its frame loop.
    private final class BundleCache {
        private var bundles: [String: Bundle] = [:]

        func value(for code: String) -> Bundle {
            if let cached = bundles[code] { return cached }
            let resolved: Bundle
            if let lproj = plainLprojBundle(for: code) {
                resolved = lproj
            } else {
                // A roster language whose translations have not landed yet has
                // no `.lproj` at all. Reading English is right; reading the
                // device's language — which is what doing nothing would give —
                // is not.
                resolved = englishBundle ?? .main
            }
            bundles[code] = resolved
            return resolved
        }
    }

    func select(_ language: AppLanguage) {
        withAnimation(.easeInOut(duration: 0.2)) { override = language }
    }
}

/// Resolve a localized string in the language the user has chosen. Use this
/// everywhere instead of `String(localized:)`, which always follows the system
/// language regardless of the in-app switch.
///
/// The English fallback has to live here rather than in the bundle:
/// `String(localized:bundle:)` reads the string table directly and never calls
/// `Bundle.localizedString(forKey:value:table:)`, so a `Bundle` subclass cannot
/// intercept it — verified, not assumed. An untranslated language's table holds
/// an empty placeholder for every key, and an empty result is the signal.
func L(_ key: String.LocalizationValue) -> String {
    let manager = LanguageManager.shared
    let value = String(localized: key, bundle: manager.bundle, locale: manager.locale)
    guard value.isEmpty, let english = LanguageManager.englishBundle else { return value }
    return String(localized: key, bundle: english, locale: LanguageManager.englishLocale)
}

/// Resolve a localized string from a key that is only known at runtime (for
/// example an indexed key like `game.encouragement.3`). Routes through the same
/// bundle as `L(_:)` so the in-app language switch applies consistently instead
/// of relying on `Bundle.main`'s redirection.
func L(key: String) -> String {
    let manager = LanguageManager.shared
    let value = manager.bundle.localizedString(forKey: key, value: key, table: nil)
    // Fall back to English so an untranslated key never surfaces as a raw
    // identifier or, worse, as a blank label.
    if !isTranslated(value, forKey: key), let english = LanguageManager.englishBundle {
        return english.localizedString(forKey: key, value: key, table: nil)
    }
    return value
}

/// Write a number the way the chosen language writes it.
///
/// A bare `"\(total)"` always produces Western digits with no grouping, so a
/// four-figure bubble total reads "3000" in every language instead of "3,000"
/// or "3.000" — and would stay Western in a language that uses its own
/// numerals. Every standalone number the player sees goes through here, so a
/// new language gets the right shape without touching the views.
func LN(_ value: Int) -> String {
    value.formatted(LanguageManager.shared.numberStyle)
}

// MARK: - Bundle redirection (the mechanism behind a live switch)

private var languageBundleKey: UInt8 = 0

/// Whether a lookup found a real translation.
///
/// A key that resolves to itself was not in the table at all. A key that
/// resolves to an empty string *is* in the table, but only as the placeholder
/// the string catalog writes for a language nobody has translated yet — which
/// on screen would be a blank label, the one failure mode worse than English.
/// Both count as a miss.
private func isTranslated(_ result: String, forKey key: String) -> Bool {
    result != key && !result.isEmpty
}

/// A Bundle that, when asked for a localized string, forwards the request to a
/// specific `.lproj` bundle if one has been set. Installed on `Bundle.main`,
/// which is what plain `Text("some.key")` reads from.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let redirected = objc_getAssociatedObject(self, &languageBundleKey) as? Bundle {
            let result = redirected.localizedString(forKey: key, value: key, table: tableName)
            // Fall back to English for any key the chosen language is missing,
            // so a partial translation never leaves a raw key or a blank on
            // screen.
            if !isTranslated(result, forKey: key),
               let english = LanguageManager.englishBundle,
               english !== redirected {
                return english.localizedString(forKey: key, value: value, table: tableName)
            }
            return result
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Swap `Bundle.main`'s class exactly once so it can redirect lookups.
    private static let installLanguageBundle: Void = {
        object_setClass(Bundle.main, LanguageBundle.self)
    }()

    /// Point `Bundle.main` at a language's `.lproj`, or pass `nil` to fall back
    /// to the device's normal resolution.
    ///
    /// A roster language with no `.lproj` yet is pointed at English rather than
    /// left unredirected: the player picked a language, and falling through to
    /// whatever the device happens to be set to would be a different answer to
    /// a different question.
    static func setLanguage(_ language: String?) {
        _ = installLanguageBundle
        let target: Bundle?
        if let language {
            target = LanguageManager.plainLprojBundle(for: language)
                ?? LanguageManager.englishBundle
        } else {
            target = nil
        }
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

// MARK: - Liquid glass styling with an iOS 16 fallback

private struct LiquidGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
    }
}

extension View {
    /// Liquid-glass capsule background (with an iOS 16 material fallback),
    /// shared by the language picker and the onboarding back button so they
    /// match exactly.
    func liquidGlassCapsule() -> some View { modifier(LiquidGlassCapsule()) }
}

// MARK: - Re-applying the language environment across modal boundaries

/// Re-applies the app's locale. Modal presentations (`sheet`,
/// `fullScreenCover`) begin a fresh environment and do not inherit the values
/// set at the app root, so any full-screen surface presented that way (the game
/// and result screens) must opt back in.
private struct GameEnvironment: ViewModifier {
    @ObservedObject private var language = LanguageManager.shared
    func body(content: Content) -> some View {
        content
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
            // Palettes and copy are authored for light surfaces. Sheets and
            // full-screen covers start a fresh environment, so Dark Mode would
            // otherwise invert system fills and labels on those screens.
            .preferredColorScheme(.light)
    }
}

extension View {
    /// Carry the chosen language's locale and reading direction into a modally
    /// presented surface.
    func gameEnvironment() -> some View { modifier(GameEnvironment()) }
}

// MARK: - The picker

/// A flag with a chevron. Tap to open the language list.
///
/// The list is a sheet rather than a menu: at this many languages a pull-down
/// menu is a single unsearchable column taller than the screen, and several
/// languages share a flag (four are spoken in Spain, ten in India), so the
/// name — not the flag — is what a player actually picks by.
struct LanguagePicker: View {
    @ObservedObject private var language = LanguageManager.shared

    /// Colour for the chevron so it can sit on light or dark backgrounds.
    var tint: Color = .secondary
    /// Callers can opt into the larger, touch-friendly iPad treatment while
    /// preserving the compact control on iPhone.
    var scale: CGFloat = 1

    var body: some View {
        Menu {
            LanguageMenuContent()
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: language.effective.flag)
                    .font(.system(size: 20 * scale))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 8 * scale)
            .liquidGlassCapsule()
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text("language.select"))
        .accessibilityValue(Text(verbatim: language.effective.displayName))
    }
}

/// The menu behind the flag button.
///
/// A pull-down menu rather than a sheet. Seventy-seven rows is a lot for one,
/// but it scrolls, it costs one tap instead of two, and it puts the list right
/// under the button that opened it — which is what the rest of the family of
/// apps does, so a player moving between them meets the same control.
///
/// Deliberately *not* localized into the language being left behind: a player
/// who cannot read the current language is exactly the one who came here, so
/// every row is written in its own language and there is no chrome to read.
private struct LanguageMenuContent: View {
    @ObservedObject private var language = LanguageManager.shared

    /// Latin script first, then each remaining script as its own block, so the
    /// alphabets a given reader cannot even tell apart are not interleaved
    /// with the ones they can. Within a block the rows run alphabetically by
    /// endonym — including English and Dutch, which the app is written in but
    /// which sit in the list like any other language rather than pinned above
    /// it, so scanning for a name never has to account for an exception.
    private static let ordered: [AppLanguage] = {
        let collator = Locale(identifier: "en")
        return AppLanguage.all.sorted { a, b in
            if a.script != b.script {
                if a.script == "Latn" { return true }
                if b.script == "Latn" { return false }
                return a.script < b.script
            }
            return a.displayName.compare(b.displayName,
                                         options: [.caseInsensitive, .diacriticInsensitive],
                                         range: nil,
                                         locale: collator) == .orderedAscending
        }
    }()

    var body: some View {
        ForEach(Self.ordered) { option in
            Button {
                language.select(option)
            } label: {
                // Flag and endonym are already runtime strings and must not be
                // treated as a localizable key, so compose them verbatim.
                let title = Text(verbatim: "\(option.flag)  \(option.displayName)")
                if language.effective == option {
                    Label { title } icon: { Image(systemName: "checkmark") }
                } else {
                    title
                }
            }
        }
    }
}
