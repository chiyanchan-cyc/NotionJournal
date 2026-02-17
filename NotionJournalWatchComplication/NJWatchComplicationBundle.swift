import WidgetKit
import SwiftUI

@main
@available(watchOS 10.0, *)
struct NJWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        NJTimeSlotComplication()
    }
}
