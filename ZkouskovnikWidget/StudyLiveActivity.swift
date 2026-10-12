import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity pro nadcházející / probíhající hodinu z rozvrhu nebo zkoušku (deadline).
///
/// Spouští ji aplikace (`Activity<StudyActivityAttributes>.request`), widget ji jen kreslí.
/// Na zamčené obrazovce a v banneru ukáže štítek předmětu, typ, název, místnost, velký živý
/// odpočet a u probíhající hodiny průběh. V Dynamic Island ukáže v rozbaleném stavu štítek
/// a typ, odpočet, název a místnost s časem; v kompaktním typ s kódem a krátký odpočet;
/// v minimálním kroužek v barvě předmětu s ikonou.
struct StudyLiveActivity: Widget {
    /// Konfigurace Live Activity pro zamčenou obrazovku a všechny stavy Dynamic Island.
    ///
    /// - Returns: `ActivityConfiguration` pro `StudyActivityAttributes`.
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

/// Obal Live Activity na zamčené obrazovce.
///
/// Nastaví jemně tónované pozadí podle barvy předmětu a režimu a barvu systémových
/// tlačítek. Samotný obsah je `StudyActivityLockScreenView`.
struct StudyActivityLockScreenContainer: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Neměnné údaje aktivity (předmět, typ, barva).
    let attributes: StudyActivityAttributes
    /// Proměnný stav aktivity (čas a místnost).
    let state: StudyActivityAttributes.ContentState

    /// Obsah zamčené obrazovky s tónovaným pozadím.
    ///
    /// - Returns: `StudyActivityLockScreenView` s modifikátory Live Activity.
    var body: some View {
        StudyActivityLockScreenView(attributes: attributes, state: state)
            .activityBackgroundTint(StudyActivityStyle.background(attributes.hexColor, scheme: colorScheme))
            .activitySystemActionForegroundColor(StudyActivityStyle.accent(attributes.hexColor, scheme: colorScheme))
    }
}

// MARK: - Ukázková data (#Preview, snímky obrazovky)

extension StudyActivityAttributes {
    /// Ukázkové cvičení AP9PT pro náhledy a snímky obrazovky.
    static let previewLesson = StudyActivityAttributes(
        kind: .lesson,
        subjectCode: "AP9PT",
        title: "Pokročilé mobilní technologie",
        typeName: "Cvičení",
        hexColor: "#3E63DD"
    )

    /// Ukázková zkouška AP9DM (deadline bez délky) pro náhledy a snímky obrazovky.
    static let previewExam = StudyActivityAttributes(
        kind: .exam,
        subjectCode: "AP9DM",
        title: "Datamining – písemná zkouška",
        typeName: "Zkouška",
        hexColor: "#12A594"
    )
}

extension StudyActivityAttributes.ContentState {
    /// Cvičení začínající za 12 minut, délka 110 minut, místnost 52/202.
    ///
    /// - Returns: Stav posunutý k aktuálnímu času.
    static var previewUpcoming: Self {
        let start = Date.now.addingTimeInterval(12 * 60)
        return Self(start: start, end: start.addingTimeInterval(110 * 60), location: "52/202")
    }

    /// Cvičení probíhající 35 minut, délka 110 minut, místnost 52/202.
    ///
    /// - Returns: Stav posunutý k aktuálnímu času.
    static var previewOngoing: Self {
        let start = Date.now.addingTimeInterval(-35 * 60)
        return Self(start: start, end: start.addingTimeInterval(110 * 60), location: "52/202")
    }

    /// Zkouška za 2 h 15 min v místnosti 54/110, `end == start`.
    ///
    /// - Returns: Stav posunutý k aktuálnímu času.
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
