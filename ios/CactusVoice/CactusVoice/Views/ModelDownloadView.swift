import SwiftUI

struct ModelDownloadView: View {
    @EnvironmentObject var viewModel: AssistantViewModel
    @State private var progress: [String: Double] = [:]
    @State private var statuses: [String: String] = [:]
    @State private var huggingfaceToken: String = ""
    @State private var working: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("First launch: download required models.")
                    .font(.headline)

                ForEach(ModelCatalog.allRequired) { model in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.displayName)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: model.approxBytes, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress[model.id] ?? 0)
                        if let s = statuses[model.id] {
                            Text(s).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                if ModelCatalog.allRequired.contains(where: { $0.isGated }) {
                    SecureField("Hugging Face token (for gated models)", text: $huggingfaceToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(8)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }

                Button {
                    Task { await downloadAll() }
                } label: {
                    Text(working ? "Downloading…" : "Download all").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Models")
        }
    }

    private func downloadAll() async {
        working = true
        defer { working = false }
        for model in ModelCatalog.allRequired {
            if ModelStorage.isPresent(model) {
                progress[model.id] = 1.0
                statuses[model.id] = "ready"
                continue
            }
            statuses[model.id] = "downloading"
            let token = model.isGated ? huggingfaceToken : nil
            let downloader = ModelDownloader(model: model, huggingfaceToken: token)
            for await event in downloader.download() {
                switch event {
                case .progress(let p):
                    await MainActor.run { progress[model.id] = p }
                case .extracting:
                    await MainActor.run { statuses[model.id] = "extracting…" }
                case .completed:
                    await MainActor.run {
                        progress[model.id] = 1.0
                        statuses[model.id] = "ready"
                    }
                case .failed(let msg):
                    await MainActor.run { statuses[model.id] = "failed: \(msg)" }
                }
            }
        }
        if ModelCatalog.allRequired.allSatisfy({ ModelStorage.isPresent($0) }) {
            await viewModel.ensureModelsLoaded()
        }
    }
}
