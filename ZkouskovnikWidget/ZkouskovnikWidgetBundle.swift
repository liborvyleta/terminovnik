import SwiftUI
import WidgetKit

/// Vstupní bod rozšíření s widgety aplikace Termínovník.
@main
struct ZkouskovnikWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeadlineWidget()
        NextClassWidget()
    }
}
