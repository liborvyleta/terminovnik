import SwiftUI
import WidgetKit

/// Widget „Další hodina“ – nejbližší přednáška nebo cvičení z rozvrhu ve STAGu.
///
/// Podporuje rodiny `.systemSmall`, `.systemMedium`, `.accessoryRectangular`, `.accessoryInline`
/// a `.accessoryCircular`. Data dodává `NextClassProvider` z rozvrhu uloženého aplikací
/// v App Group; časová osa se plánuje na 2 dny dopředu s politikou `.atEnd`.
struct NextClassWidget: Widget {
    /// Identifikátor widgetu, podle kterého aplikace obnovuje jeho časovou osu.
    static let kind = "NextClassWidget"

    /// Statická konfigurace widgetu s poskytovatelem, názvem, popisem a podporovanými rodinami.
    ///
    /// - Returns: Konfigurace vykreslující `NextClassWidgetView`.
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
