import AppIntents
import Foundation

struct StartListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Cactus listening"
    static var description = IntentDescription(
        "Open Cactus Voice and start listening immediately. Designed to be bound to the Action Button."
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .cactusStartListening, object: nil)
        }
        return .result()
    }
}

struct StopListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Cactus listening"
    static var description = IntentDescription("Stop Cactus Voice recording and finalize the command.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .cactusStopListening, object: nil)
        }
        return .result()
    }
}

struct CactusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartListeningIntent(),
            phrases: [
                "Start \(.applicationName) listening",
                "Listen with \(.applicationName)",
                "Hey \(.applicationName)"
            ],
            shortTitle: "Start listening",
            systemImageName: "mic.circle.fill"
        )
        AppShortcut(
            intent: StopListeningIntent(),
            phrases: [
                "Stop \(.applicationName) listening",
                "Stop \(.applicationName)"
            ],
            shortTitle: "Stop listening",
            systemImageName: "stop.circle.fill"
        )
    }
}

extension Notification.Name {
    static let cactusStartListening = Notification.Name("cactus.startListening")
    static let cactusStopListening = Notification.Name("cactus.stopListening")
}
