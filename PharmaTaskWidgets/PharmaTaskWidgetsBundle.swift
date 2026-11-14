import WidgetKit
import SwiftUI

@main
struct PharmaTaskWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShiftLiveActivityView()
        PharmaTaskLockScreenWidget()
    }
}
