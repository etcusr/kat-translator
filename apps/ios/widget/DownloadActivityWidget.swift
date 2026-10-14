import ActivityKit
import WidgetKit
import SwiftUI

@main struct DownloadActivityBundle: WidgetBundle {
    var body: some Widget { ModelDownloadActivity() }
}
struct ModelDownloadActivity: Widget {
    private let accent = KatTheme.accent
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(context.state.title, systemImage: context.state.symbol).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
                Text(context.state.detail).font(.caption).lineLimit(1)
                DownloadActivityProgress(fraction: context.state.fraction)
                HStack {
                    Text(context.state.bytes).monospacedDigit()
                    Spacer()
                    Text("Kat translator")
                }.font(.caption).foregroundStyle(.secondary)
                if context.isStale && !context.state.finished {
                    Text(context.attributes.staleMessage).font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(12)
                .activityBackgroundTint(KatTheme.background)
                .activitySystemActionForegroundColor(.white)
                .foregroundStyle(.white)
                .widgetURL(URL(string: "kattranslator://downloads"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Kat translator", systemImage: context.state.symbol).font(.headline).foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.detail).font(.caption).lineLimit(1)
                        DownloadActivityProgress(fraction: context.state.fraction)
                        Text(context.state.bytes).font(.caption2).monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(accent)
            } compactTrailing: {
                Text(context.state.fraction, format: .percent.precision(.fractionLength(0))).font(.caption2).monospacedDigit()
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(accent)
            }.widgetURL(URL(string: "kattranslator://downloads")).keylineTint(accent)
        }
    }
}

/// A plain, bounded progress bar also works when Live Activity updates are infrequent.
struct DownloadActivityProgress: View {
    let fraction: Double
    private var progress: Double { fraction.isFinite ? min(1, max(0, fraction)) : 0 }
    var body: some View {
        ProgressView(value: progress).tint(KatTheme.accent)
    }
}
