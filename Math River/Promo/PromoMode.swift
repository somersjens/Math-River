#if DEBUG
import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Launch-argument trailer capture. Production Release builds never compile
/// this file's types into the app entry path.
enum PromoMode {
    static let launchArgument = "-KingCrabPromo"
    static let iPadFormatArgument = "-KingCrabPromoFormat-ipad"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var format: PromoFormat {
        ProcessInfo.processInfo.arguments.contains(iPadFormatArgument)
            ? .iPad
            : .iPhone
    }
}

enum PromoFormat: String {
    case iPhone = "iphone"
    case iPad = "ipad"

    var isPad: Bool { self == .iPad }

    /// Layout size the live game is composed at. Capture then samples this
    /// view into the App Store pixel size, so neither export is a crop of
    /// the other.
    var pointSize: CGSize {
        switch self {
        case .iPhone: return CGSize(width: 443, height: 960)
        case .iPad:   return CGSize(width: 750, height: 1000)
        }
    }

    var outputPixels: CGSize {
        switch self {
        case .iPhone: return CGSize(width: 886, height: 1920)
        case .iPad:   return CGSize(width: 1200, height: 1600)
        }
    }

    var fileName: String {
        switch self {
        case .iPhone: return "king-crab-app-store-teaser-886x1920.mp4"
        case .iPad:   return "king-crab-app-store-teaser-1200x1600.mp4"
        }
    }

    var safeTop: CGFloat { isPad ? 24 : 47 }
    var safeBottom: CGFloat { isPad ? 20 : 34 }

    var framesPerSecond: Int { 30 }
}

/// Timestamps of production SFX, measured from capture start, so the render
/// script can mix the real CAF files onto the picture.
enum PromoAudioLog {
    private static let lock = NSLock()
    private static var start: TimeInterval?
    private static var events: [(time: Double, key: String)] = []

    static func reset() {
        lock.lock()
        start = nil
        events = []
        lock.unlock()
    }

    static func markStart() {
        lock.lock()
        start = CACurrentMediaTime()
        events = []
        lock.unlock()
    }

    static func record(_ key: String) {
        lock.lock()
        let origin = start ?? CACurrentMediaTime()
        if start == nil { start = origin }
        events.append((CACurrentMediaTime() - origin, key))
        lock.unlock()
    }

    static func snapshot() -> [[String: Any]] {
        lock.lock()
        let copy = events
        lock.unlock()
        return copy.map { ["t": $0.time, "key": $0.key] }
    }

    static var elapsed: Double {
        lock.lock()
        let origin = start
        lock.unlock()
        guard let origin else { return 0 }
        return CACurrentMediaTime() - origin
    }
}

enum PromoScript {
    /// 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right.
    static let entryAssignment: [String: Int] = [
        "16": 0, "14": 1, "24": 2, "15": 3,
        "63": 0, "56": 1, "48": 2, "49": 3,
        "21": 0, "28": 1, "29": 2, "35": 3
    ]

    static let q1Wrong = ["16", "14", "24"]
    static let q2LowerWrong = ["48", "49"]
    static let q2TopWrong = "63"
    static let q3Wrong = ["21", "35", "29"]

    static let characterIDs = ["crab", "elephant", "bear", "penguin", "crab"]

    static let headlineThrow = "Throw sand at the wrong answers"
    static let headlineUnlock = "Unlock special crabs"
    static let headlineShells = "Pick up as many shells as you can"

    static var rounds: [GameRound] {
        [
            makeRound(number: 1,
                      prompt: "9 + 6 = ?",
                      correct: "15",
                      distractors: ["16", "14", "24"],
                      kind: .addition),
            makeRound(number: 2,
                      prompt: "7 × 8 = ?",
                      correct: "56",
                      distractors: ["48", "49", "63"],
                      kind: .multiplication),
            makeRound(number: 3,
                      prompt: "35 − 7 = ?",
                      correct: "28",
                      distractors: ["21", "29", "35"],
                      kind: .subtraction)
        ]
    }

    static var sessionRequest: GameSessionRequest {
        GameSessionRequest(level: MathLevel(topic: .addition, index: 9),
                           mode: .mixed)
    }

    private static func makeRound(number: Int,
                                  prompt: String,
                                  correct: String,
                                  distractors: [String],
                                  kind: QuestionKind) -> GameRound {
        let question = MathQuestion(prompt: prompt,
                                    correctAnswer: correct,
                                    distractors: distractors,
                                    sourceLevel: 1,
                                    kind: kind)
        var options = [AnswerOption(text: correct, isCorrect: true)]
        options.append(contentsOf: distractors.map {
            AnswerOption(text: $0, isCorrect: false)
        })
        return GameRound(number: number, question: question, options: options)
    }
}
#endif
