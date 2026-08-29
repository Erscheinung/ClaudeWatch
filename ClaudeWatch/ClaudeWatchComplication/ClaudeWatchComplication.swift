import SwiftUI
import WidgetKit

struct ClaudeWatchComplicationEntry: TimelineEntry {
    let date: Date
}

struct ClaudeWatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudeWatchComplicationEntry {
        ClaudeWatchComplicationEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeWatchComplicationEntry) -> Void) {
        completion(ClaudeWatchComplicationEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeWatchComplicationEntry>) -> Void) {
        completion(Timeline(entries: [ClaudeWatchComplicationEntry(date: .now)], policy: .never))
    }
}

struct ClaudeWatchComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Link(destination: URL(string: "claudewatch://voice")!) {
            switch family {
            case .accessoryInline:
                Label("Ask mAI", systemImage: "mic.fill")
            case .accessoryCorner:
                Image(systemName: "mic.fill")
                    .widgetLabel("Ask mAI")
            default:
                Image(systemName: "mic.fill")
                    .font(.title3.weight(.bold))
            }
        }
        .widgetAccentable()
    }
}

struct ClaudeWatchComplication: Widget {
    static let kind = "com.Erscheinung.ClaudeWatch.complication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ClaudeWatchComplicationProvider()) { _ in
            ClaudeWatchComplicationView()
        }
        .configurationDisplayName("Claude Watch")
        .description("Open Claude Watch to ask a voice question.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct ClaudeWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        ClaudeWatchComplication()
    }
}
