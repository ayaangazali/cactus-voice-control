import SwiftUI

struct ModelDownloadView: View {
    @EnvironmentObject var viewModel: AssistantViewModel
    @State private var progress: [String: Double] = [:]
    @State private var statuses: [String: String] = [:]
    @State private var failures: Set<String> = []
    @State private var huggingfaceToken: String = ""
    @State private var working: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("First launch: download required models.")
                    .font(.headline)
                Text("Approx 1.7 GB total. Use Wi-Fi.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(ModelCatalog.allRequired) { model in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.displayName)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: model.approxBytes, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                            if failures.contains(model.id) {
                                Button {
                                    Task { await retry(model) }
                                } label: { Image(systemName: "arrow.clockwise.circle") }
                                .disabled(working)
                            }
                        }
                        ProgressView(value: progress[model.id] ?? 0)
                        if let s = statuses[model.id] {
                            Text(s)
                                .font(.caption2)
                                .foregroundStyle(failures.contains(model.id) ? .red : .secondary)
                        }
                    }
                }

                if ModelCatalog.allRequired.contains(where: { $0.isGated }) {
                    SecureField("Hugging Face token (gated models only)", text: $huggingfaceToken)
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
                failures.remove(model.id)
                continue
            }
            await downloadSingle(model)
        }
        if ModelCatalog.allRequired.allSatisfy({ ModelStorage.isPresent($0) }) {
            await viewModel.ensureModelsLoaded()
        }
    }

    private func retry(_ model: ModelEntry) async {
        working = true
        defer { working = false }
        await downloadSingle(model)
        if ModelCatalog.allRequired.allSatisfy({ ModelStorage.isPresent($0) }) {
            await viewModel.ensureModelsLoaded()
        }
    }

    private func downloadSingle(_ model: ModelEntry) async {
        statuses[model.id] = "downloading"
        failures.remove(model.id)
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
                await MainActor.run {
                    statuses[model.id] = "failed: \(msg)"
                    failures.insert(model.id)
                }
            }
        }
    }
}
