import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AssistantViewModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                pairingBadge
                modelPicker
                transcriptCard
                Spacer()
                micButton
                statusLabel
            }
            .padding(20)
            .navigationTitle("Cactus Voice")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gear") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(viewModel)
            }
        }
    }

    private var pairingBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.pairedMac == nil ? "wifi.slash" : "wifi")
            Text(viewModel.pairedMac.map { "\($0.host):\($0.port)" } ?? "No Mac paired")
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.15), in: Capsule())
    }

    private var modelPicker: some View {
        Picker("Model", selection: Binding(
            get: { viewModel.activeLLM.id },
            set: { id in
                if let m = ModelCatalog.llmModels.first(where: { $0.id == id }) {
                    Task { await viewModel.swapLLM(to: m) }
                }
            }
        )) {
            ForEach(ModelCatalog.llmModels) { model in
                Text(model.displayName).tag(model.id)
            }
        }
        .pickerStyle(.segmented)
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.partialTranscript.isEmpty || !viewModel.finalTranscript.isEmpty {
                Label("Transcript", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.finalTranscript.isEmpty ? viewModel.partialTranscript : viewModel.finalTranscript)
                    .font(.body)
            }
            if let intent = viewModel.lastIntent {
                Divider()
                Label("Intent", systemImage: "wand.and.stars")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(intent.instruction).font(.callout.weight(.medium))
                if let desc = intent.outputDescription {
                    Text("→ \(desc)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let status = viewModel.lastStatus {
                Divider()
                Label("Mac", systemImage: "desktopcomputer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(status.phase.rawValue.capitalized)\(status.message.map { " — \($0)" } ?? "")")
                    .font(.callout)
                if let result = status.result {
                    Text(result)
                        .font(.footnote.monospaced())
                        .padding(8)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var micButton: some View {
        Button {
            Task {
                if case .listening = viewModel.phase {
                    await viewModel.stopListening()
                } else {
                    await viewModel.startListening()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isListening ? Color.red : Color.accentColor)
                    .frame(width: 96, height: 96)
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.pairedMac == nil)
    }

    private var statusLabel: some View {
        Text(phaseLabel)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var isListening: Bool {
        if case .listening = viewModel.phase { return true } else { return false }
    }

    private var phaseLabel: String {
        switch viewModel.phase {
        case .idle:                  return "Tap to speak, or press the Action Button."
        case .loadingModel:          return "Loading models…"
        case .listening:             return "Listening — pause to send."
        case .transcribing:          return "Transcribing…"
        case .thinking:              return "Building intent…"
        case .sending:               return "Sending to Mac…"
        case .running:               return "Running on Simulator…"
        case .succeeded:             return "Done."
        case .failed(let msg):       return "Error: \(msg)"
        }
    }
}
