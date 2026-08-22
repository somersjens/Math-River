#if DEBUG
import AVFoundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Captures the live trailer view into an H.264 file at the App Store pixel size.
@MainActor
final class PromoRecorder: NSObject {
    let format: PromoFormat
    private let view: UIView
    private var displayLink: CADisplayLink?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startedAt: CFTimeInterval?
    private var frameIndex = 0
    private var isStopping = false
    var outputURL: URL

    init(view: UIView, format: PromoFormat, outputURL: URL) {
        self.view = view
        self.format = format
        self.outputURL = outputURL
        super.init()
    }

    func start() throws {
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let width = Int(format.outputPixels.width)
        let height = Int(format.outputPixels.height)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 6,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: format.framesPerSecond * 2
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else {
            throw NSError(domain: "PromoRecorder", code: 1)
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "PromoRecorder", code: 2)
        }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        PromoAudioLog.markStart()
        let link = CADisplayLink(target: self, selector: #selector(captureFrame))
        link.preferredFramesPerSecond = format.framesPerSecond
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func captureFrame(_ link: CADisplayLink) {
        guard !isStopping, let input, let adaptor, input.isReadyForMoreMediaData else { return }
        if startedAt == nil { startedAt = link.timestamp }
        let elapsed = link.timestamp - (startedAt ?? link.timestamp)
        let time = CMTime(seconds: elapsed, preferredTimescale: 600)
        guard let buffer = makePixelBuffer() else { return }
        adaptor.append(buffer, withPresentationTime: time)
        if frameIndex % 15 == 0 {
            saveSnapshot(elapsed: elapsed)
        }
        frameIndex += 1
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        displayLink?.invalidate()
        displayLink = nil
        input?.markAsFinished()
        await writer?.finishWriting()
    }

    private func saveSnapshot(elapsed: Double) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("promo-frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ms = Int((elapsed * 1000).rounded())
        let url = folder.appendingPathComponent(String(format: "t-%05d.jpg", ms))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = self.format.outputPixels
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            let scaleX = size.width / max(1, view.bounds.width)
            let scaleY = size.height / max(1, view.bounds.height)
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.scaleBy(x: scaleX, y: scaleY)
            view.layer.render(in: context)
        }
        try? image.jpegData(compressionQuality: 0.72)?.write(to: url)
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        let width = Int(format.outputPixels.width)
        let height = Int(format.outputPixels.height)
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let data = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { _ in
            guard let renderContext = UIGraphicsGetCurrentContext() else { return }
            let scaleX = CGFloat(width) / max(1, view.bounds.width)
            let scaleY = CGFloat(height) / max(1, view.bounds.height)
            renderContext.scaleBy(x: scaleX, y: scaleY)
            view.layer.render(in: renderContext)
        }
        if let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }
}

@MainActor
final class PromoCaptureController {
    static let shared = PromoCaptureController()

    private var didMarkReady = false

    func prepareAudio() {
        if !AppAudio.shared.gameSoundsEnabled { AppAudio.shared.toggleGameSounds() }
        if !AppAudio.shared.musicEnabled { AppAudio.shared.toggleMusic() }
        if AppAudio.shared.spokenSumsEnabled { AppAudio.shared.toggleSpokenSums() }
        UIApplication.shared.isStatusBarHidden = true
    }

    func markReady() {
        guard !didMarkReady else { return }
        didMarkReady = true
        PromoAudioLog.markStart()
        var extra: [String: Any] = [
            "format": PromoMode.format.rawValue,
            "width": PromoMode.format.outputPixels.width,
            "height": PromoMode.format.outputPixels.height
        ]
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            let height = max(1, window.bounds.height)
            extra["cropTop"] = window.safeAreaInsets.top / height
            extra["cropBottom"] = window.safeAreaInsets.bottom / height
        } else {
            extra["cropTop"] = PromoMode.format.isPad ? 0.0 : 0.068
            extra["cropBottom"] = 0.0
        }
        writeMarker(name: "king-crab-promo-ready.json", status: "ready", extra: extra)
    }

    func finish() async {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cuesURL = documents.appendingPathComponent("king-crab-promo-cues.json")
        let cues = PromoAudioLog.snapshot()
        if let data = try? JSONSerialization.data(withJSONObject: cues, options: [.prettyPrinted]) {
            try? data.write(to: cuesURL)
        }
        writeMarker(name: "king-crab-promo-done.json", status: "done", extra: [
            "cues": cuesURL.lastPathComponent,
            "format": PromoMode.format.rawValue,
            "width": PromoMode.format.outputPixels.width,
            "height": PromoMode.format.outputPixels.height,
            "elapsed": PromoAudioLog.elapsed,
            "muxed": false
        ])
    }

    private func writeMarker(name: String, status: String, extra: [String: Any] = [:]) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var payload: [String: Any] = [
            "status": status,
            "format": PromoMode.format.rawValue
        ]
        extra.forEach { payload[$0.key] = $0.value }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: documents.appendingPathComponent(name))
        }
    }
}

#if canImport(UIKit)
private final class PromoHostController<Content: View>: UIHostingController<Content> {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}
#endif

enum PromoAudioMux {
    private static let sfxFiles: [String: (file: String, volume: Float)] = [
        "correct": ("sfx_correct", 0.14),
        "wrong": ("sfx_wrong", 0.11),
        "cardFlip": ("sfx_card_flip", 0.10),
        "cardReveal": ("sfx_card_reveal", 0.19),
        "doubleCard": ("sfx_double_card", 0.18),
        "doubleScore": ("sfx_double_score", 0.15),
        "flamethrower": ("sfx_flamethrower", 0.31),
        "sessionComplete": ("sfx_level_complete", 0.10),
        "cardTotal": ("score_increase", 1.0),
        "sessionStart": ("sfx_session_start", 0.16)
    ]

    static func mix(video: URL, cues: [[String: Any]], output: URL) async -> Bool {
        try? FileManager.default.removeItem(at: output)
        let videoAsset = AVURLAsset(url: video)
        let duration = videoAsset.duration
        guard duration.isNumeric, CMTimeGetSeconds(duration) > 0.2 else { return false }
        guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else { return false }

        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(withMediaType: .video,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return false }
        do {
            try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                                 of: videoTrack,
                                                 at: .zero)
        } catch {
            return false
        }

        var mixParams: [AVMutableAudioMixInputParameters] = []

        if let musicURL = Bundle.main.url(forResource: "music_background", withExtension: "m4a"),
           let musicTrack = composition.addMutableTrack(withMediaType: .audio,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid) {
            let musicAsset = AVURLAsset(url: musicURL)
            if let source = musicAsset.tracks(withMediaType: .audio).first {
                var cursor = CMTime.zero
                let musicDuration = musicAsset.duration
                while cursor < duration, musicDuration.isNumeric, CMTimeGetSeconds(musicDuration) > 0 {
                    let remaining = CMTimeSubtract(duration, cursor)
                    let slice = CMTimeMinimum(musicDuration, remaining)
                    try? musicTrack.insertTimeRange(CMTimeRange(start: .zero, duration: slice),
                                                    of: source,
                                                    at: cursor)
                    cursor = CMTimeAdd(cursor, slice)
                }
                let params = AVMutableAudioMixInputParameters(track: musicTrack)
                params.setVolume(0.22, at: .zero)
                mixParams.append(params)
            }
        }

        for cue in cues {
            guard let key = cue["key"] as? String,
                  let time = cue["t"] as? Double,
                  let spec = sfxFiles[key],
                  let url = Bundle.main.url(forResource: spec.file, withExtension: "caf"),
                  let sfxTrack = composition.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let asset = AVURLAsset(url: url)
            guard let source = asset.tracks(withMediaType: .audio).first else { continue }
            let start = CMTime(seconds: max(0, time), preferredTimescale: 600)
            guard start < duration else { continue }
            let available = CMTimeSubtract(duration, start)
            let slice = CMTimeMinimum(asset.duration, available)
            try? sfxTrack.insertTimeRange(CMTimeRange(start: .zero, duration: slice),
                                          of: source,
                                          at: start)
            let params = AVMutableAudioMixInputParameters(track: sfxTrack)
            params.setVolume(spec.volume, at: .zero)
            mixParams.append(params)
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = mixParams

        guard let exporter = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetHighestQuality)
        else { return false }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        exporter.audioMix = mix
        exporter.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        return exporter.status == .completed && FileManager.default.fileExists(atPath: output.path)
    }
}
#endif
