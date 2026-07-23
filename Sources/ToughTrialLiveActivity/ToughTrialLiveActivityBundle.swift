import ActivityKit
import SwiftUI
import ToughTrialActivityShared
import WidgetKit

@main
struct ToughTrialLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        V2FocusLiveActivity()
    }
}

private struct V2FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: V2FocusActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.isRunning ? "play.fill" : "pause.fill")
                    .foregroundStyle(context.state.isRunning ? Color.green : Color.orange)
                    .frame(width: 30, height: 30)
                    .background(.thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                    elapsedText(context.state)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }

                Spacer(minLength: 0)
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .systemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "toughtrial://today"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isRunning ? "play.fill" : "pause.fill")
                        .foregroundStyle(context.state.isRunning ? .green : .orange)
                        .accessibilityLabel(context.state.isRunning ? "进行中" : "已暂停")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    elapsedText(context.state)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: context.state.isRunning ? "play.fill" : "pause.fill")
                    .foregroundStyle(context.state.isRunning ? .green : .orange)
            } compactTrailing: {
                elapsedText(context.state)
                    .font(.caption2)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.isRunning ? "play.fill" : "pause.fill")
                    .foregroundStyle(context.state.isRunning ? .green : .orange)
            }
            .widgetURL(URL(string: "toughtrial://today"))
        }
    }

    @ViewBuilder
    private func elapsedText(
        _ state: V2FocusActivityAttributes.ContentState
    ) -> some View {
        if state.isRunning, let startedAt = state.segmentStartedAt {
            Text(startedAt, style: .timer)
        } else {
            Text(Self.duration(state.accumulatedSeconds))
        }
    }

    private static func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
