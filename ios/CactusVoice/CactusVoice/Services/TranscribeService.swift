import Foundation
import AVFoundation

enum TranscribeEvent: Equatable {
    case partial(String)
    case final(String)
    case silenceDetected
    case error(String)
}

struct VADConfig {
    var rmsThreshold: Float = 0.012
    var hangoverMillis: Int = 800
    var minSpeechMillis: Int = 300
}

@MainActor
final class TranscribeService: NSObject {
    private let engine = AVAudioEngine()
    private let cactus: CactusEngine
    private let targetSampleRate: Double = 16_000
    private let chunkMillis: Int = 320
    private let vad: VADConfig
    private var continuation: AsyncStream<TranscribeEvent>.Continuation?
    private var hasSpeechStarted = false
    private var lastSpeechAt: Date = .distantPast
    private var firstSpeechAt: Date = .distantPast
    private var pcmBuffer = Data()
    private let chunkBytes: Int

    init(cactus: CactusEngine, vad: VADConfig = VADConfig()) {
        self.cactus = cactus
        self.vad = vad
        self.chunkBytes = Int(targetSampleRate) * 2 * chunkMillis / 1000
        super.init()
    }

    func start() async throws -> AsyncStream<TranscribeEvent> {
        try await cactus.startStreamTranscribe(language: "en")

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try session.setPreferredSampleRate(targetSampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "TranscribeService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot create target format"])
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "TranscribeService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot create converter"])
        }

        return AsyncStream { cont in
            self.continuation = cont
            self.hasSpeechStarted = false
            self.lastSpeechAt = .distantPast
            self.pcmBuffer.removeAll(keepingCapacity: true)

            let bufferSize: AVAudioFrameCount = 4096
            input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
                guard let self else { return }
                self.handleInput(buffer: buffer, converter: converter, target: targetFormat)
            }

            do {
                try self.engine.start()
            } catch {
                cont.yield(.error("engine start failed: \(error.localizedDescription)"))
                cont.finish()
            }

            cont.onTermination = { [weak self] _ in
                Task { @MainActor in self?.teardown() }
            }
        }
    }

    func stop() async {
        teardown()
        if let final = try? await cactus.stopStreamTranscribe() {
            continuation?.yield(.final(final))
        }
        continuation?.finish()
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private nonisolated func handleInput(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat) {
        let frameCapacity = AVAudioFrameCount(target.sampleRate * Double(buffer.frameLength) / buffer.format.sampleRate)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frameCapacity) else { return }
        outBuffer.frameLength = frameCapacity

        var error: NSError?
        var feed = false
        let _ = converter.convert(to: outBuffer, error: &error) { _, status in
            if feed {
                status.pointee = .noDataNow
                return nil
            }
            feed = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        guard let int16 = outBuffer.int16ChannelData?[0] else { return }
        let frames = Int(outBuffer.frameLength)
        let data = Data(bytes: int16, count: frames * MemoryLayout<Int16>.size)

        let rms = Self.rms(int16Pointer: int16, count: frames)
        Task { @MainActor in
            self.consume(pcm: data, rms: rms)
        }
    }

    nonisolated private static func rms(int16Pointer: UnsafePointer<Int16>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var sum: Double = 0
        for i in 0..<count {
            let v = Double(int16Pointer[i]) / Double(Int16.max)
            sum += v * v
        }
        return Float((sum / Double(count)).squareRoot())
    }

    private func consume(pcm: Data, rms: Float) {
        pcmBuffer.append(pcm)

        let now = Date()
        if rms >= vad.rmsThreshold {
            if !hasSpeechStarted { firstSpeechAt = now }
            hasSpeechStarted = true
            lastSpeechAt = now
        }

        while pcmBuffer.count >= chunkBytes {
            let chunk = pcmBuffer.prefix(chunkBytes)
            pcmBuffer.removeFirst(chunkBytes)
            let chunkData = Data(chunk)
            Task.detached { [weak self] in
                guard let self else { return }
                if let partial = try? await self.cactus.processStreamChunk(pcm: chunkData), !partial.isEmpty {
                    await self.emit(.partial(partial))
                }
            }
        }

        let speechDuration = now.timeIntervalSince(firstSpeechAt) * 1000
        let silenceDuration = now.timeIntervalSince(lastSpeechAt) * 1000
        if hasSpeechStarted,
           speechDuration > Double(vad.minSpeechMillis),
           silenceDuration > Double(vad.hangoverMillis) {
            continuation?.yield(.silenceDetected)
            hasSpeechStarted = false
        }
    }

    private func emit(_ event: TranscribeEvent) {
        continuation?.yield(event)
    }

    nonisolated static func vadFires(rms: Float, config: VADConfig) -> Bool {
        rms >= config.rmsThreshold
    }
}
