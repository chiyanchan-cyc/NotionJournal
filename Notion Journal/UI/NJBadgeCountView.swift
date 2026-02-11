import SwiftUI

struct NJBadgeCountView: View {
    let count: Int

    var body: some View {
        if count > 0 {
            let display = min(count, 99)
            Text("\(display)")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, display >= 10 ? 5 : 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red))
                .accessibilityLabel("\(count) items in clipboard")
        }
    }
}
