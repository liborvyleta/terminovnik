import SwiftUI

/// Stránka s dnešním rozvrhem.
///
/// Zobrazuje dnešní hodiny z rozvrhu, který ``WatchStore`` dekódoval z kontextu přijatého
/// z iPhonu přes WatchConnectivity; seznam se přepočítává každou minutu a skončené hodiny
/// jsou potlačené.
struct TodayScheduleView: View {
    /// Zdroj dat přijatých z iPhonu.
    let store: WatchStore

    /// Seznam dnešních hodin, nebo prázdný stav „Dnes volno“.
    var body: some View {
        TimelineView(.everyMinute) { context in
            let lessons = store.todayLessons(now: context.date)
            if lessons.isEmpty {
                ContentUnavailableView {
                    Label("Dnes volno", systemImage: "sun.max")
                } description: {
                    if store.timetable == nil {
                        Text("Rozvrh se načte po přihlášení do STAGu na iPhonu.")
                    } else {
                        Text("Dnes nemáš žádnou výuku.")
                    }
                }
            } else {
                List(lessons) { lesson in
                    LessonRow(lesson: lesson, now: context.date)
                }
            }
        }
    }
}

/// Řádek dnešního rozvrhu.
///
/// Zobrazuje barevný proužek předmětu, čas, název, typ a místnost. Probíhající hodina má
/// zvýrazněný čas a ikonu, skončená hodina je zprůhledněná.
struct LessonRow: View {
    /// Zobrazovaný výskyt hodiny.
    let lesson: TimetableOccurrence
    /// Aktuální čas, ke kterému se určuje stav hodiny.
    let now: Date

    /// Udává, zda hodina už skončila.
    private var isFinished: Bool { lesson.end <= now }
    /// Udává, zda hodina právě probíhá.
    private var isOngoing: Bool { lesson.start <= now && now < lesson.end }

    /// Obsah řádku.
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(lesson.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: lesson.timeRangeText)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(isOngoing ? lesson.color : .secondary)
                    if isOngoing {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption2)
                            .foregroundStyle(lesson.color)
                            .accessibilityLabel(Text("Právě probíhá"))
                    }
                }
                Text(lesson.event.subjectName)
                    .font(.headline)
                    .lineLimit(2)
                Text(verbatim: [lesson.event.typeName, lesson.event.locationText]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isFinished ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Dnešní rozvrh") {
    TodayScheduleView(store: WatchStore(timetable: .sample, deadlines: []))
}
