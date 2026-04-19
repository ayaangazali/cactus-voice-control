import ActivityKit
import WidgetKit
import SwiftUI

struct ListeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ListeningAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: context.state.iconSystemName)
                        .font(.title3)
                        .foregroundStyle(.tint)
                    Text(context.state.label)
                        .font(.headline)
                    Spacer()
                }
                if !context.state.preview.isEmpty {
                    Text(context.state.preview)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                if let result = context.state.resultPreview, !result.isEmpty {
                    Text(result)
                        .font(.footnote)
                        .lineLimit(2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.4))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.iconSystemName)
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.label)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.preview.isEmpty {
                        Text(context.state.preview)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.iconSystemName)
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Text(context.state.label)
                    .font(.caption2)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: context.state.iconSystemName)
                    .foregroundStyle(.tint)
            }
            .keylineTint(.green)
        }
    }
}
