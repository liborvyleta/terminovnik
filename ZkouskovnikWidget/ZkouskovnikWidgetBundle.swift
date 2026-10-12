import SwiftUI
import WidgetKit

/// Vstupní bod rozšíření s widgety aplikace Termínovník.
///
/// Registruje widgety „Nejbližší deadliny“ a „Další hodina“ a Live Activity pro hodinu či zkoušku.
@main
struct ZkouskovnikWidgetBundle: WidgetBundle {
    /// Widgety a Live Activity poskytované rozšířením.
    ///
    /// - Returns: `DeadlineWidget`, `NextClassWidget` a `StudyLiveActivity`.
    var body: some Widget {
        DeadlineWidget()
        NextClassWidget()
        StudyLiveActivity()
    }
}
