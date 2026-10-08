import SwiftUI

/// Dnešní rozvrh – seznam hodin, skončené hodiny jsou potlačené.
struct TodayScheduleView: View {
    let store: WatchStore

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

/// Řádek hodiny: barevný proužek předmětu, čas, název, typ a místnost
struct LessonRow: View {
    let lesson: TimetableOccurrence
    let now: Date

    private var isFinished: Bool { lesson.end <= now }
    private var isOngoing: Bool { lesson.start <= now && now < lesson.end }

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
