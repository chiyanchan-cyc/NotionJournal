import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appStore: AppStore

    var body: some View {
        VStack(spacing: 0) {
            RootView()

            Divider()
            .frame(maxHeight: 180)
        }
    }
}
