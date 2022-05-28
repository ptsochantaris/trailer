//
//  PocketTrailer_Widget.swift
//  PocketTrailer Widget
//
//  Created by Paul Tsochantaris on 24/05/2022.
//

import WidgetKit
import SwiftUI

struct Summary: TimelineEntry {
    let date = Date()
    let data: [AnyHashable: Any]?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Summary {
        Summary(data: nil)
    }
    
    private var currentEntry: Summary {
        let data = NSDictionary(contentsOf: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Trailer")!.appendingPathComponent("overview.plist"))
        return Summary(data: data as Dictionary?)
    }

    func getSnapshot(in context: Context, completion: @escaping (Summary) -> Void) {
        let data = NSDictionary(contentsOf: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Trailer")!.appendingPathComponent("overview.plist"))
        let entry = Summary(data: data as Dictionary?)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Summary>) -> Void) {
        let timeline = Timeline(entries: [currentEntry], policy: .never)
        completion(timeline)
    }
}

@main
struct PocketTrailer_Widget: Widget {
    let kind: String = "PocketTrailer_Widget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MainView(entry: entry)
        }
        .configurationDisplayName("Trailer")
        .description("Summary of items in Trailer")
    }
}

struct PocketTrailer_Widget_Previews: PreviewProvider {
    static var previews: some View {
        MainView(entry: Summary(data: nil))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
