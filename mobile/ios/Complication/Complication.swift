import SwiftUI
import WidgetKit

/// The GupWorks complication (a235): how many things need you, on the watch face and in the Smart Stack. A WidgetKit
/// extension inside the watch app. It reads the data the watch app keeps in the App Group (WatchFace: the iPhone's last
/// list, which the watch app saves whenever the iPhone sends one, and asks for a reload only when the face would look
/// different); a tap opens the cards (WatchComplication.url).
struct FaceEntry: TimelineEntry {
    let date: Date
    let face: WatchComplication
}

struct FaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> FaceEntry {
        FaceEntry(date: .now, face: WatchComplication(nil, now: Date().timeIntervalSince1970))
    }

    func getSnapshot(in context: Context, completion: @escaping (FaceEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// An entry every minute for the next half hour, so "12m" keeps counting by itself; then the system asks again
    /// (and the watch app reloads it at once when the count or the oldest item changes).
    func getTimeline(in context: Context, completion: @escaping (Timeline<FaceEntry>) -> Void) {
        let start = Date()
        let entries = (0..<30).map { entry(at: start.addingTimeInterval(Double($0) * 60)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> FaceEntry {
        let saved = WatchFace.load(UserDefaults(suiteName: WatchFace.group))
        return FaceEntry(date: date, face: WatchComplication(saved.list, now: date.timeIntervalSince1970,
                                                             off: Set(saved.off)))
    }
}

struct FaceView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FaceEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                FaceRectangular(face: entry.face)
            default:
                FaceCircular(face: entry.face)
            }
        }
        .widgetURL(WatchComplication.url)
        .containerBackground(for: .widget) {
            family == .accessoryRectangular ? Color(hex: 0x141218) : Color.clear
        }
    }
}

struct NeedsYouComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.gupworks3.needs-you", provider: FaceProvider()) { entry in
            FaceView(entry: entry)
        }
        .configurationDisplayName("Needs you")
        .description("How many things wait for you, and the oldest one.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main
struct GupWorksComplications: WidgetBundle {
    var body: some Widget {
        NeedsYouComplication()
    }
}
