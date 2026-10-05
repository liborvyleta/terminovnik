import SwiftUI
import WidgetKit

/// Widget „Nejbližší deadliny“ pro plochu i zamčenou obrazovku.
struct DeadlineWidget: Widget {
    static let kind = "DeadlineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DeadlineProvider()) { entry in
            DeadlineWidgetView(entry: entry)
        }
        .configurationDisplayName("Nejbližší deadliny")
        .description("Odpočet do nejbližších zkoušek, zápočtů, projektů a úkolů.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline
        ])
    }
}

// MARK: - Náhledy

#Preview("Malý", as: .systemSmall) {
    DeadlineWidget()
} timeline: {
    DeadlineEntry.sample()
    DeadlineEntry.empty()
}

#Preview("Střední", as: .systemMedium) {
    DeadlineWidget()
} timeline: {
    DeadlineEntry.sample()
    DeadlineEntry.empty()
}

#Preview("Velký", as: .systemLarge) {
    DeadlineWidget()
} timeline: {
    DeadlineEntry.sample()
    DeadlineEntry.empty()
}

#Preview("Obdélník", as: .accessoryRectangular) {
    DeadlineWidget()
} timeline: {
    DeadlineEntry.sample()
    DeadlineEntry.empty()
}

#Preview("Kruh", as: .accessoryCircular) {
    DeadlineWidget()
} timeline: {
    DeadlineEntry.sample()
    DeadlineEntry.empty()
}

#Preview("Řádek", as: .accessoryInline) {
    DeadlineWidget()
} timeline: {
    DeadlineEntry.sample()
    DeadlineEntry.empty()
}
