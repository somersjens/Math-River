//
//  PausedSessionStore.swift
//  Math Memory
//
//  Leaving a level part-way through pauses it rather than throwing it away.
//  The cards collected so far, the lives left and the round reached are kept,
//  so re-entering that level continues where the player stopped.
//
//  Only one session per level is kept, and it is cleared the moment the level
//  is actually finished (out of lives, or the last round played).
//

import Foundation

/// A session frozen mid-play. Everything here is plain, validated data: a
/// corrupt or outdated record is discarded rather than resumed.
nonisolated public struct PausedSession: Codable, Equatable, Sendable {
    /// The scoreboard this run belongs to — see `LevelBoard.storageID`. A run
    /// paused on one Supermix combination must not resume onto another, where
    /// its cards would be banked against the wrong best.
    public let boardID: String
    public let roundNumber: Int
    public let cards: Int
    public let lifeHalves: Int
    public let correctAnswers: Int
    public let wrongAnswers: Int
    public let doubleCardsAnswered: Int
    public let bonusCards: Int
    public let flamethrowersUsed: Int
    /// Optional so sessions written before the in-level streak feature remain
    /// decodable and simply resume without an active streak/aura.
    public let correctStreak: Int?
    public let hasBonusFishPower: Bool?
    /// Optional for compatibility with sessions saved before the comeback
    /// crab. The names are the ones these fields were first written under; they
    /// now carry the life crab's meter.
    public let heartFishProgress: Int?
    public let heartFishTarget: Int?
    public let isHeartFishAvailable: Bool?
    /// Whether this run has already had its one comeback.
    public let hasSpentLifeCrab: Bool?

    public init(boardID: String,
                roundNumber: Int,
                cards: Int,
                lifeHalves: Int,
                correctAnswers: Int,
                wrongAnswers: Int,
                doubleCardsAnswered: Int,
                bonusCards: Int,
                flamethrowersUsed: Int,
                correctStreak: Int? = nil,
                hasBonusFishPower: Bool? = nil,
                heartFishProgress: Int? = nil,
                heartFishTarget: Int? = nil,
                isHeartFishAvailable: Bool? = nil,
                hasSpentLifeCrab: Bool? = nil) {
        self.boardID = boardID
        self.roundNumber = roundNumber
        self.cards = cards
        self.lifeHalves = lifeHalves
        self.correctAnswers = correctAnswers
        self.wrongAnswers = wrongAnswers
        self.doubleCardsAnswered = doubleCardsAnswered
        self.bonusCards = bonusCards
        self.flamethrowersUsed = flamethrowersUsed
        self.correctStreak = correctStreak
        self.hasBonusFishPower = hasBonusFishPower
        self.heartFishProgress = heartFishProgress
        self.heartFishTarget = heartFishTarget
        self.isHeartFishAvailable = isHeartFishAvailable
        self.hasSpentLifeCrab = hasSpentLifeCrab
    }

    /// A record is only usable if it describes a session that can still be
    /// played: lives left, rounds left, and counts that are not nonsense.
    public var isResumable: Bool {
        lifeHalves > 0
            && roundNumber >= 1
            && roundNumber <= GameConfig.maximumRoundCeiling
            && lifeHalves <= GameConfig.startingLifeHalves
            && cards >= 0
            && correctAnswers >= 0
            && wrongAnswers >= 0
            && (correctStreak ?? 0) >= 0
            && (heartFishProgress ?? 0) >= 0
            && (heartFishTarget ?? GameConfig.lifeCrabCorrectAnswers) >= 1
    }
}

public final class PausedSessionStore {
    public static let shared = PausedSessionStore(defaults: UserDefaults.standard)

    static let key = "paused.sessions.v3"

    private let defaults: KeyValueStore
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    /// The last blob that was decoded, with its result. Every level card on the
    /// menu asks for its own paused session, so without this the same record set
    /// is decoded from scratch a hundred times over during a single redraw. The
    /// raw data is the cache key, so a write from anywhere — including a direct
    /// `removeObject` during migration — is picked up on the next read.
    private var cachedData: Data?
    private var cachedSessions: [String: PausedSession] = [:]

    public init(defaults: KeyValueStore) {
        self.defaults = defaults
    }

    // MARK: - Reading

    /// The paused session for a board, or nil when there is none to resume.
    /// Anything that fails validation is treated as absent.
    public func session(forBoardID boardID: String) -> PausedSession? {
        guard let session = all()[boardID], session.isResumable else { return nil }
        return session
    }

    public func session(_ board: LevelBoard) -> PausedSession? {
        session(forBoardID: board.storageID)
    }

    public func hasPausedSession(forBoardID boardID: String) -> Bool {
        session(forBoardID: boardID) != nil
    }

    // MARK: - Writing

    public func save(_ session: PausedSession) {
        // A session with nothing left to play is finished, not paused.
        guard session.isResumable else {
            clear(boardID: session.boardID)
            return
        }
        var sessions = all()
        sessions[session.boardID] = session
        write(sessions)
    }

    public func clear(boardID: String) {
        var sessions = all()
        guard sessions.removeValue(forKey: boardID) != nil else { return }
        write(sessions)
    }

    public func clear(_ board: LevelBoard) { clear(boardID: board.storageID) }

    public func clearAll() {
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: - Storage

    private func all() -> [String: PausedSession] {
        guard let data = defaults.object(forKey: Self.key) as? Data else {
            cachedData = nil
            cachedSessions = [:]
            return [:]
        }
        if data == cachedData { return cachedSessions }
        // Unreadable data is dropped rather than allowed to fail a launch.
        let sessions = (try? Self.decoder.decode([String: PausedSession].self, from: data)) ?? [:]
        cachedData = data
        cachedSessions = sessions
        return sessions
    }

    private func write(_ sessions: [String: PausedSession]) {
        guard let data = try? Self.encoder.encode(sessions) else { return }
        defaults.set(data, forKey: Self.key)
        cachedData = data
        cachedSessions = sessions
    }
}
