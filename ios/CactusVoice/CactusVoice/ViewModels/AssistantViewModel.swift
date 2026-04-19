import Foundation
import SwiftUI
import ActivityKit

@MainActor
final class AssistantViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loadingModel
        case listening
        case transcribing
        case thinking
        case sending
        case running
        case succeeded
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var partialTranscript: String = ""
    @Published var finalTranscript: String = ""
    @Published var lastIntent: CommandIntent?
    @Published var lastStatus: CommandStatus?
    @Published var pairedMac: PairedMac?
    @Published var activeLLM: ModelEntry = ModelCatalog.qwen3_1_7b
    @Published var modelsReady: Bool = false

    private let llmEngine = CactusEngine()
    private let whisperEngine = CactusEngine()
    private var transcribeService: TranscribeService?
    private let commandClient = CommandClient()
    private var transcribeTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var liveActivity: Activity<ListeningAttributes>?

    init() {
        self.pairedMac = PairingStore.load()
        observeNotifications()
    }

    // MARK: - Observation

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            forName: .cactusStartListening, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.startListening() }
        }
        NotificationCenter.default.addObserver(
            forName: .cactusStopListening, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.stopListening() }
        }
    }

    // MARK: - Model lifecycle

    func ensureModelsLoaded() async {
        guard !modelsReady else { return }
        phase = .loadingModel
        do {
            let whisperPath = ModelStorage.localURL(for: ModelCatalog.whisperBase).path
            let llmPath = ModelStorage.localURL(for: activeLLM).path
            try await whisperEngine.load(modelPath: whisperPath)
            try await llmEngine.load(modelPath: llmPath)
            modelsReady = true
            phase = .idle
        } catch {
            phase = .failed("Model load failed: \(error.localizedDescription)")
        }
    }

    func swapLLM(to model: ModelEntry) async {
        activeLLM = model
        await llmEngine.unload()
        do {
            try await llmEngine.load(modelPath: ModelStorage.localURL(for: model).path)
        } catch {
            phase = .failed("Swap failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pairing

    func reloadPairing() {
        self.pairedMac = PairingStore.load()
    }

    // MARK: - Pipeline

    func startListening() async {
        guard pairedMac != nil else {
            phase = .failed("Pair a Mac in Settings first.")
            return
        }
        await ensureModelsLoaded()
        guard modelsReady else { return }

        partialTranscript = ""
        finalTranscript = ""
        lastIntent = nil
        lastStatus = nil
        phase = .listening
        await startLiveActivity()

        let svc = TranscribeService(cactus: whisperEngine)
        transcribeService = svc

        do {
            let stream = try await svc.start()
            transcribeTask = Task { [weak self] in
                guard let self else { return }
                for await event in stream {
                    await self.handle(event)
                }
            }
        } catch {
            phase = .failed("Mic start failed: \(error.localizedDescription)")
            await endLiveActivity()
        }
    }

    private func handle(_ event: TranscribeEvent) async {
        switch event {
        case .partial(let text):
            partialTranscript = (partialTranscript + " " + text).trimmingCharacters(in: .whitespaces)
            await updateLiveActivity(.transcribing, preview: partialTranscript)
        case .silenceDetected:
            await stopListening()
        case .final(let text):
            finalTranscript = text
        case .error(let msg):
            phase = .failed(msg)
            await endLiveActivity()
        }
    }

    func stopListening() async {
        guard case .listening = phase else { return }
        phase = .transcribing
        await transcribeService?.stop()
        transcribeTask?.cancel()
        transcribeTask = nil

        let transcript = finalTranscript.isEmpty ? partialTranscript : finalTranscript
        guard !transcript.isEmpty else {
            phase = .failed("No speech detected.")
            await endLiveActivity()
            return
        }

        await runIntentPipeline(transcript: transcript)
    }

    private func runIntentPipeline(transcript: String) async {
        phase = .thinking
        await updateLiveActivity(.thinking, preview: transcript)
        let intentService = IntentService(cactus: llmEngine, modelId: activeLLM.id)
        let intent: CommandIntent
        do {
            intent = try await intentService.intent(from: transcript)
            lastIntent = intent
        } catch {
            phase = .failed("Intent: \(error.localizedDescription)")
            await endLiveActivity()
            return
        }

        phase = .sending
        await updateLiveActivity(.sending, preview: intent.instruction)
        let initialStatus: CommandStatus
        do {
            initialStatus = try await commandClient.send(intent: intent)
            lastStatus = initialStatus
        } catch {
            phase = .failed("Send: \(error.localizedDescription)")
            await endLiveActivity()
            return
        }

        phase = .running
        await updateLiveActivity(.running, preview: intent.instruction)
        statusTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await status in await self.commandClient.statusStream(for: intent.id) {
                    await MainActor.run { self.lastStatus = status }
                    if status.phase == .succeeded {
                        await MainActor.run { self.phase = .succeeded }
                        await self.updateLiveActivity(.succeeded, preview: intent.instruction, result: status.result)
                        await self.endLiveActivityAfter(seconds: 8)
                        return
                    } else if status.phase == .failed || status.phase == .cancelled {
                        await MainActor.run { self.phase = .failed(status.message ?? "failed") }
                        await self.updateLiveActivity(.failed, preview: status.message ?? "failed")
                        await self.endLiveActivityAfter(seconds: 8)
                        return
                    }
                }
            } catch {
                await MainActor.run { self.phase = .failed("Stream: \(error.localizedDescription)") }
                await self.endLiveActivity()
            }
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = ListeningAttributes(sessionId: UUID())
        let initial = ListeningAttributes.ContentState(phase: .listening, preview: "")
        do {
            liveActivity = try Activity<ListeningAttributes>.request(
                attributes: attrs,
                content: .init(state: initial, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Activity unavailable; ignore
        }
    }

    private func updateLiveActivity(_ phase: ListeningAttributes.ContentState.Phase, preview: String, result: String? = nil) async {
        guard let activity = liveActivity else { return }
        let state = ListeningAttributes.ContentState(phase: phase, preview: preview, resultPreview: result)
        await activity.update(.init(state: state, staleDate: nil))
    }

    private func endLiveActivity() async {
        guard let activity = liveActivity else { return }
        let final = ListeningAttributes.ContentState(phase: .succeeded, preview: "")
        await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        liveActivity = nil
    }

    private func endLiveActivityAfter(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        await endLiveActivity()
    }
}
