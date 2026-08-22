//
//  ProgressSync.swift
//  Jumping Fox
//
//  Keeps durable game progress in iCloud's key-value store. Counters and
//  scores are monotonic: if two devices update independently, progress can
//  only move forwards.
//
//  The player's name rides along in the same store so that — like the scores —
//  it survives deleting and reinstalling the app. A restored account then shows
//  its name again instead of coming back nameless.
//

import Foundation
import Combine

final class ProgressSync: ObservableObject {
    static let shared = ProgressSync()

    @Published private(set) var revision = 0

    private let cloudStore = NSUbiquitousKeyValueStore.default
    private var notificationToken: NSObjectProtocol?
    private var defaultsToken: NSObjectProtocol?

    /// A local mirror of the iCloud store. Every personal best is merged on the
    /// way out of `ProgressStore`, so drawing the menu asks for hundreds of
    /// cloud values in a single redraw; going through `NSUbiquitousKeyValueStore`
    /// each time is what made scrolling and switching topics feel heavy. The
    /// mirror is refreshed whenever iCloud reports a change and updated in place
    /// on every write, so it can never serve a value the store has moved past.
    private var cloudSnapshot: [String: Any]?

    private func cloudValue(forKey key: String) -> Any? {
        if cloudSnapshot == nil {
            cloudSnapshot = cloudStore.dictionaryRepresentation
        }
        return cloudSnapshot?[key]
    }

    private func setCloudValue(_ value: Any, forKey key: String) {
        cloudStore.set(value, forKey: key)
        cloudSnapshot?[key] = value
    }

    /// iCloud key for the player's name. Kept distinct from the local
    /// UserDefaults key so the mirroring below is always explicit.
    private let playerNameCloudKey = "profile.playerName.cloud"
    /// The last name we reconciled, so a UserDefaults change can be checked
    /// cheaply and we never echo our own restore back to the cloud.
    private var lastKnownPlayerName = ""

    private init() {
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            // Values arrived from another device: the mirror is stale.
            self?.cloudSnapshot = nil
            self?.reconcileAllProgress()
            self?.restorePlayerNameFromCloudIfNeeded()
        }

        // @AppStorage writes progress straight to UserDefaults, so watching the
        // store catches card rewards, unlocks, onboarding and name edits at
        // their source without every view needing sync-specific code.
        defaultsToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            self?.reconcileDurableProfile()
            self?.pushPlayerNameToCloudIfChanged()
        }

        cloudStore.synchronize()
        lastKnownPlayerName = UserDefaults.standard.string(forKey: GameSettings.playerNameKey) ?? ""
        // Let the singleton finish initializing before ProgressStore accesses it.
        DispatchQueue.main.async { [weak self] in
            self?.reconcileAllProgress()
            self?.syncPlayerNameAtLaunch()
        }
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
        if let defaultsToken {
            NotificationCenter.default.removeObserver(defaultsToken)
        }
    }

    /// Merges a local score with iCloud and writes the winner to both stores.
    /// This is intentionally a maximum, rather than last-write-wins, so a
    /// score earned on either device can never erase a better score elsewhere.
    /// `NSUbiquitousKeyValueStore` propagates `set` operations automatically;
    /// forcing `synchronize()` here can block the gameplay/main thread for
    /// several seconds on a slow iCloud connection.
    func mergedScore(for key: String, localScore: Int) -> Int {
        let cloudScore = (cloudValue(forKey: key) as? NSNumber)?.intValue ?? 0
        let winner = max(localScore, cloudScore)

        if cloudScore < winner {
            setCloudValue(NSNumber(value: winner), forKey: key)
        }
        return winner
    }

    /// Re-reads every durable value after launch, an account change or an
    /// incoming iCloud update. Writing the winner to both stores makes this
    /// safe to call repeatedly and lets @AppStorage update the visible UI.
    private func reconcileAllProgress() {
        // This is the one route by which a score can move without the store
        // itself writing it, so its read cache has to be dropped first — the
        // sweep below is what refills it with the merged values.
        Progress.store.invalidateCaches()
        for topic in MathTopic.allCases {
            for level in LevelCatalog.levels(for: topic) {
                _ = Progress.store.bestScoreAcrossBoards(level: level)
            }
        }
        reconcileDurableProfile()
        revision &+= 1
    }

    /// Progress outside the per-level scoreboards also needs to survive an app
    /// deletion. Total cards drives character unlocks, announced unlocks stops
    /// old rewards being presented twice, and onboarding completion lets a
    /// restored player return directly to the game.
    private func reconcileDurableProfile() {
        mergeMonotonicInteger(forKey: ProgressStore.Key.totalCards)
        mergeStringSet(forKey: ProgressStore.Key.announcedUnlocks)
        mergeTrueFlag(forKey: ProgressStore.Key.onboardingComplete)
    }

    private func mergeMonotonicInteger(forKey key: String) {
        let local = max(0, UserDefaults.standard.integer(forKey: key))
        let cloud = max(0, (cloudValue(forKey: key) as? NSNumber)?.intValue ?? 0)
        let winner = max(local, cloud)

        if cloud < winner {
            setCloudValue(NSNumber(value: winner), forKey: key)
        }
        if local < winner {
            UserDefaults.standard.set(winner, forKey: key)
        }
    }

    private func mergeTrueFlag(forKey key: String) {
        let local = UserDefaults.standard.bool(forKey: key)
        let cloud = (cloudValue(forKey: key) as? NSNumber)?.boolValue ?? false
        guard local || cloud else { return }

        if !cloud { setCloudValue(true, forKey: key) }
        if !local { UserDefaults.standard.set(true, forKey: key) }
    }

    private func mergeStringSet(forKey key: String) {
        let local = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let cloud = Set(cloudValue(forKey: key) as? [String] ?? [])
        let merged = local.union(cloud)
        guard !merged.isEmpty else { return }
        let value = Array(merged).sorted()

        if cloud != merged { setCloudValue(value, forKey: key) }
        if local != merged { UserDefaults.standard.set(value, forKey: key) }
    }

    // MARK: - Player name

    /// On launch, reconcile the local name with iCloud: a name saved in the
    /// cloud (e.g. from before a reinstall) is restored locally; otherwise an
    /// existing local name seeds the cloud for the first time.
    private func syncPlayerNameAtLaunch() {
        let localName = UserDefaults.standard.string(forKey: GameSettings.playerNameKey) ?? ""
        let cloudName = cloudPlayerName

        if !cloudName.isEmpty, cloudName != localName {
            UserDefaults.standard.set(cloudName, forKey: GameSettings.playerNameKey)
            lastKnownPlayerName = cloudName
        } else if !localName.isEmpty, cloudName != localName {
            setCloudValue(localName, forKey: playerNameCloudKey)
            lastKnownPlayerName = localName
        }
    }

    private var cloudPlayerName: String {
        cloudValue(forKey: playerNameCloudKey) as? String ?? ""
    }

    /// Applies a name that arrived from another device — or synced down after a
    /// reinstall — but never overwrites a local name with an empty one.
    private func restorePlayerNameFromCloudIfNeeded() {
        let cloudName = cloudPlayerName
        guard !cloudName.isEmpty else { return }
        let localName = UserDefaults.standard.string(forKey: GameSettings.playerNameKey) ?? ""
        guard cloudName != localName else { return }
        UserDefaults.standard.set(cloudName, forKey: GameSettings.playerNameKey)
        lastKnownPlayerName = cloudName
    }

    /// Mirrors a local name edit up to iCloud. Any UserDefaults change triggers
    /// this, so a cheap guard limits the work to real name changes and stops a
    /// restore from being echoed straight back.
    private func pushPlayerNameToCloudIfChanged() {
        let localName = UserDefaults.standard.string(forKey: GameSettings.playerNameKey) ?? ""
        guard localName != lastKnownPlayerName else { return }
        lastKnownPlayerName = localName
        guard !localName.isEmpty else { return }
        setCloudValue(localName, forKey: playerNameCloudKey)
    }
}
