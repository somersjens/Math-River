//
//  AppSettings.swift
//  Elephant Challenge: Math Memory
//
//  The bridge between SwiftUI's `@AppStorage` and the pure-logic `ProgressStore`.
//  Views bind to the key constants declared here; anything that needs a
//  validated, migrated value goes through `Progress` instead.
//

import Foundation
import SwiftUI

/// App-wide access to the migrated progress store, wired to iCloud.
enum Progress {
    static let store: ProgressStore = {
        let store = ProgressStore.shared
        store.cloudMerge = { key, local in
            ProgressSync.shared.mergedScore(for: key, localScore: local)
        }
        store.migrateIfNeeded()
        return store
    }()
}

/// Storage keys and the small settings that are not part of gameplay progress.
enum GameSettings {
    // Keys shared with `@AppStorage` bindings in the views.
    static let characterKey = ProgressStore.Key.characterID
    static let playerNameKey = ProgressStore.Key.playerName
    static let onboardingCompleteKey = ProgressStore.Key.onboardingComplete
    /// A device-local request to show onboarding again. Unlike the durable
    /// completion flag, this must not be merged monotonically through iCloud:
    /// doing so would immediately undo a user's long-press from the home menu.
    static let onboardingReplayRequestedKey = "onboarding.replayRequested"
    /// Set when the welcome flow ends, and spent by the home screen the moment
    /// it opens the first level: the tutorial start card follows straight on
    /// from the last welcome screen, on exactly the exercise the player just chose.
    static let tutorialPendingKey = "tutorial.pending"
    /// Set as soon as a tutorial session starts, and spent by the home screen
    /// when the player comes back to it — that return is the tenth and last
    /// step of the walkthrough, so it must survive the session itself.
    static let tutorialHomeHintPendingKey = "tutorial.homeHintPending"
    static let totalCardsKey = ProgressStore.Key.totalCards
    static let topicKey = ProgressStore.Key.selectedTopic
    static let levelKey = ProgressStore.Key.selectedLevel
    static let mixedVariantKey = ProgressStore.Key.mixedVariant
    static let practiceModeKey = ProgressStore.Key.practiceMode
    static let gameSoundsEnabledKey = ProgressStore.Key.gameSoundsEnabled
    static let musicEnabledKey = ProgressStore.Key.musicEnabled

    /// Reads a stored flag, accepting every shape UserDefaults can hand back.
    /// A plain `as? Bool` silently misses numbers and strings — which is what a
    /// launch argument or a hand-edited plist produces — and would fall through
    /// to the default, quietly ignoring the player's setting.
    private static func storedBool(_ key: String, default fallback: Bool) -> Bool {
        guard let value = UserDefaults.standard.object(forKey: key) else { return fallback }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return (text as NSString).boolValue }
        return fallback
    }
    static let spokenSumsEnabledKey = ProgressStore.Key.spokenSumsEnabled
    static let premiumCacheKey = ProgressStore.Key.premiumCache

    /// Sound effects and background music.
    static var gameSoundsEnabled: Bool {
        get { storedBool(gameSoundsEnabledKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: gameSoundsEnabledKey) }
    }

    static var musicEnabled: Bool {
        get { storedBool(musicEnabledKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: musicEnabledKey) }
    }

    /// Spoken sums. On by default; `AppAudio` silently ignores this when the
    /// selected language has no installed voice.
    static var spokenSumsEnabled: Bool {
        get { storedBool(spokenSumsEnabledKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: spokenSumsEnabledKey) }
    }

    /// Whether the walkthrough still owes the player its closing step on the
    /// home screen. Written by the tutorial itself and cleared once shown.
    static var tutorialHomeHintPending: Bool {
        get { storedBool(tutorialHomeHintPendingKey, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: tutorialHomeHintPendingKey) }
    }

    /// True between the last welcome choice and the moment the first level's
    /// start card is actually on screen.
    static var tutorialPending: Bool {
        get { storedBool(tutorialPendingKey, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: tutorialPendingKey) }
    }

    static var characterID: String {
        get { Progress.store.selectedCharacterID }
        set { Progress.store.selectedCharacterID = newValue }
    }

    static var playerName: String {
        get { UserDefaults.standard.string(forKey: playerNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: playerNameKey) }
    }

    /// Mirror of the Premium entitlement, written by `PremiumStore` and
    /// readable from anywhere without touching StoreKit.
    static var premiumUnlockedCache: Bool {
        get { Progress.store.isPremiumCached }
        set { Progress.store.isPremiumCached = newValue }
    }
}
