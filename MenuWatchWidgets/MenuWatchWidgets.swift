import WidgetKit
import SwiftUI

@main
struct MenuWatchWidgets: WidgetBundle {
    var body: some Widget {
        MenuComplication()
        BlankRecordComplication()
        OrderComplication()
        if #available(watchOS 26.0, *) {
            OpenControl()
        }
    }
}

/// A watch-face button that opens the app straight into a recording (`menuapp://record`, answered
/// in WatchContentView). It draws nothing, like StatusHub's: a clear view filling the slot, so the face
/// shows no trace of it and the whole empty slot is still the tap target.
struct MenuComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CapitalGrilleComplication", provider: Provider()) { _ in
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(URL(string: "menuapp://record"))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Menu")
        .description("Menu")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// The same button under a new kind, so a face that cached the first complication's old drawing can
/// take one that has never been drawn any other way. Leave both: a kind that disappears drops off
/// every face that holds it.
struct BlankRecordComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BlankRecordComplication", provider: Provider()) { _ in
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(URL(string: "menuapp://record"))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Menu Blank")
        .description("Menu Blank")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// Opens the app straight into recording an order (`menuapp://order`, answered in WatchContentView),
/// on the order list. Blank like the others: the empty slot is the tap target.
struct OrderComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrderComplication", provider: Provider()) { _ in
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(URL(string: "menuapp://order"))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Menu Order")
        .description("Menu Order")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// The Control Center button (watchOS 26), which also sits in the Smart Stack and on an Ultra's
/// Action button. It only opens the app.
@available(watchOS 26.0, *)
struct OpenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jaredgantt.CapitalGrille.watch.open") {
            ControlWidgetButton(action: OpenAppIntent()) {
                Label("Menu", systemImage: "wineglass.fill")
            }
        }
        .displayName("Menu")
    }
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date())], policy: .never))
    }
}

private struct Entry: TimelineEntry { let date: Date }
