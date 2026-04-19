import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var viewModel: AssistantViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var port: String = "8731"
    @State private var token: String = ""
    @State private var pairResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac Gateway") {
                    TextField("Host or IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    SecureField("Bearer token", text: $token)
                        .textInputAutocapitalization(.never)
                    Button("Pair") {
                        if let p = Int(port), !host.isEmpty, !token.isEmpty {
                            let pair = PairedMac(host: host, port: p, token: token)
                            if PairingStore.save(pair) {
                                viewModel.reloadPairing()
                                pairResult = "Paired with \(host):\(p)"
                            } else {
                                pairResult = "Save failed"
                            }
                        } else {
                            pairResult = "Fill all fields"
                        }
                    }
                    if let pairResult {
                        Text(pairResult).font(.footnote).foregroundStyle(.secondary)
                    }
                    if viewModel.pairedMac != nil {
                        Button("Unpair", role: .destructive) {
                            PairingStore.clear()
                            viewModel.reloadPairing()
                            pairResult = "Unpaired"
                        }
                    }
                }

                Section("Models") {
                    ForEach(ModelCatalog.allRequired) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                                Text(ByteCountFormatter.string(fromByteCount: model.approxBytes, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: ModelStorage.isPresent(model) ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundStyle(ModelStorage.isPresent(model) ? .green : .secondary)
                        }
                    }
                }

                Section("Permissions") {
                    Button("Request microphone permission") {
                        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let p = viewModel.pairedMac {
                    host = p.host
                    port = String(p.port)
                    token = p.token
                }
            }
        }
    }
}
