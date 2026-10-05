import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity pro nadcházející / probíhající hodinu z rozvrhu nebo zkoušku (deadline).
/// Spouští ji aplikace (`Activity<StudyActivityAttributes>.request`), widget ji jen kreslí.
struct StudyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyActivityAttributes.self) { context in
            StudyActivityLockScreenContainer(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            let model = StudyActivityModel(attributes: context.attributes, state: context.state)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StudyIslandLeadingView(model: model)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StudyIslandTrailingView(model: model)
                }
                DynamicIslandExpandedRegion(.center) {
                    StudyIslandCenterView(model: model)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    StudyIslandBottomView(model: model)
                }
            } compactLeading: {
                StudyIslandCompactLeadingView(model: model)
            } compactTrailing: {
                StudyIslandCompactTrailingView(model: model)
            } minimal: {
                StudyIslandMinimalView(model: model)
            }
            .keylineTint(StudyActivityStyle.vivid(context.attributes.hexColor))
        }
    }
}

/// Obal zamčené obrazovky: jemně tónované pozadí podle barvy předmětu a režimu
/// a barva systémových tlačítek. Samotný obsah je `StudyActivityLockScreenView`.
struct StudyActivityLockScreenContainer: View {
    @Environment(\.colorScheme) private var colorScheme

    let attributes: StudyActivityAttributes
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        StudyActivityLockScreenView(attributes: attributes, state: state)
            .activityBackgroundTint(StudyActivityStyle.background(attributes.hexColor, scheme: colorScheme))
            .activitySystemActionForegroundColor(StudyActivityStyle.accent(attributes.hexColor, scheme: colorScheme))
    }
}

// MARK: - Ukázková data (#Preview, snímky obrazovky)

extension StudyActivityAttributes {
    /// AP9PT – cvičení v 52/202
    static let previewLesson = StudyActivityAttributes(
        kind: .lesson,
        subjectCode: "AP9PT",
        title: "Pokročilé mobilní technologie",
        typeName: "Cvičení",
        hexColor: "#3E63DD"
    )

    /// AP9DM – zkouška (deadline bez délky)
    static let previewExam = StudyActivityAttributes(
        kind: .exam,
        subjectCode: "AP9DM",
        title: "Datamining – písemná zkouška",
        typeName: "Zkouška",
        hexColor: "#12A594"
    )
}

extension StudyActivityAttributes.ContentState {
    /// Cvičení začíná za 12 minut (10:00–12:00 posunuto k aktuálnímu času)
    static var previewUpcoming: Self {
        let start = Date.now.addingTimeInterval(12 * 60)
        return Self(start: start, end: start.addingTimeInterval(110 * 60), location: "52/202")
    }

    /// Cvičení probíhá 35 minut
    static var previewOngoing: Self {
        let start = Date.now.addingTimeInterval(-35 * 60)
        return Self(start: start, end: start.addingTimeInterval(110 * 60), location: "52/202")
    }

    /// Zkouška za 2 h 15 min, end == start
    static var previewExam: Self {
        let start = Date.now.addingTimeInterval(135 * 60)
        return Self(start: start, end: start, location: "54/110")
    }
}

// MARK: - Náhledy

#Preview("Zamčená obrazovka", as: .content, using: StudyActivityAttributes.previewLesson) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.previewUpcoming
    StudyActivityAttributes.ContentState.previewOngoing
}

#Preview("Zkouška – zamčená obrazovka", as: .content, using: StudyActivityAttributes.previewExam) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.previewExam
}

#Preview("Dynamic Island – rozbalený", as: .dynamicIsland(.expanded), using: StudyActivityAttributes.previewLesson) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.previewUpcoming
    StudyActivityAttributes.ContentState.previewOngoing
}

#Preview("Dynamic Island – zkouška", as: .dynamicIsland(.expanded), using: StudyActivityAttributes.previewExam) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.previewExam
}

#Preview("Dynamic Island – kompaktní", as: .dynamicIsland(.compact), using: StudyActivityAttributes.previewLesson) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.previewUpcoming
    StudyActivityAttributes.ContentState.previewOngoing
}

#Preview("Dynamic Island – minimální", as: .dynamicIsland(.minimal), using: StudyActivityAttributes.previewLesson) {
    StudyLiveActivity()
} contentStates: {
    StudyActivityAttributes.ContentState.previewUpcoming
    StudyActivityAttributes.ContentState.previewOngoing
}
