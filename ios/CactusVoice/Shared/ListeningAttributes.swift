import Foundation
import ActivityKit

struct ListeningAttributes: ActivityAttributes {
    public typealias ListeningStatus = ContentState

    public struct ContentState: Codable, Hashable {
        public enum Phase: String, Codable, Hashable, CaseIterable {
            case listening
            case transcribing
            case thinking
            case sending
            case running
            case succeeded
            case failed
        }

        public var phase: Phase
        public var preview: String
        public var resultPreview: String?

        public init(phase: Phase, preview: String, resultPreview: String? = nil) {
            self.phase = phase
            self.preview = preview
            self.resultPreview = resultPreview
        }

        public var iconSystemName: String {
            switch phase {
            case .listening:    return "mic.circle.fill"
            case .transcribing: return "waveform"
            case .thinking:     return "brain.head.profile"
            case .sending:      return "paperplane.fill"
            case .running:      return "gearshape.2.fill"
            case .succeeded:    return "checkmark.circle.fill"
            case .failed:       return "exclamationmark.triangle.fill"
            }
        }

        public var label: String {
            switch phase {
            case .listening:    return "Listening"
            case .transcribing: return "Transcribing"
            case .thinking:     return "Thinking"
            case .sending:      return "Sending to Mac"
            case .running:      return "Running on Simulator"
            case .succeeded:    return "Done"
            case .failed:       return "Failed"
            }
        }
    }

    public var sessionId: UUID

    public init(sessionId: UUID = UUID()) {
        self.sessionId = sessionId
    }
}
