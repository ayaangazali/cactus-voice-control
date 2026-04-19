import SwiftUI
import AVFoundation

@main
struct CactusVoiceApp: App {
    @StateObject private var viewModel = AssistantViewModel()

    init() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
                .task {
                    if ModelCatalog.allRequired.allSatisfy({ ModelStorage.isPresent($0) }) {
                        await viewModel.ensureModelsLoaded()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var viewModel: AssistantViewModel

    var body: some View {
        let allPresent = ModelCatalog.allRequired.allSatisfy { ModelStorage.isPresent($0) }
        if !allPresent {
            ModelDownloadView()
        } else {
            ContentView()
        }
    }
}
