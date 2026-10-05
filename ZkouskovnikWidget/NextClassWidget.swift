import SwiftUI
import WidgetKit

/// Widget „Další hodina“ – nejbližší přednáška nebo cvičení z rozvrhu ve STAGu.
struct NextClassWidget: Widget {
    static let kind = "NextClassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NextClassProvider()) { entry in
            NextClassWidgetView(entry: entry)
        }
        .configurationDisplayName("Další hodina")
        .description("Nejbližší přednáška nebo cvičení z rozvrhu – čas, místnost a odpočet do začátku.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryInline, .accessoryCircular
        ])
    }
}

// MARK: - Náhledy

#Preview("Další hodina – malý", as: .systemSmall) {
    NextClassWidget()
} timeline: {
    NextClassEntry.sample()
    NextClassEntry.sampleUpcoming()
    NextClassEntry.sampleOngoing()
    NextClassEntry.sampleFree()
    NextClassEntry.noTimetable()
}

#Preview("Další hodina – střední", as: .systemMedium) {
    NextClassWidget()
} timeline: {
    NextClassEntry.sample()
    NextClassEntry.sampleUpcoming()
    NextClassEntry.sampleOngoing()
    NextClassEntry.sampleFree()
    NextClassEntry.noTimetable()
}

#Preview("Další hodina – obdélník", as: .accessoryRectangular) {
    NextClassWidget()
} timeline: {
    NextClassEntry.sample()
    NextClassEntry.sampleOngoing()
    NextClassEntry.sampleFree()
    NextClassEntry.noTimetable()
}

#Preview("Další hodina – řádek", as: .accessoryInline) {
    NextClassWidget()
} timeline: {
    NextClassEntry.sample()
    NextClassEntry.sampleOngoing()
    NextClassEntry.sampleFree()
    NextClassEntry.noTimetable()
}

#Preview("Další hodina – kruh", as: .accessoryCircular) {
    NextClassWidget()
} timeline: {
    NextClassEntry.sample()
    NextClassEntry.sampleOngoing()
    NextClassEntry.sampleFree()
    NextClassEntry.noTimetable()
}
