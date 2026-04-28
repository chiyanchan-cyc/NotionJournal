import SwiftUI
import Combine
#if os(iOS)
import UIKit
#endif

struct NJBlockListBottomRunwayRow: View {
    @StateObject private var keyboard = NJKeyboardRunwayModel()

    var body: some View {
        Color.clear
            .frame(height: keyboard.runwayHeight)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityHidden(true)
    }
}

@MainActor
private final class NJKeyboardRunwayModel: ObservableObject {
    @Published var runwayHeight: CGFloat = NJKeyboardRunwayModel.baseRunwayHeight()

    #if os(iOS)
    private var cancellables: Set<AnyCancellable> = []
    #endif

    init() {
        #if os(iOS)
        let nc = NotificationCenter.default
        nc.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: nc.publisher(for: UIResponder.keyboardWillHideNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                self?.handleKeyboard(note)
            }
            .store(in: &cancellables)
        #endif
    }

    private static func baseRunwayHeight() -> CGFloat {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return 260
        case .pad:
            return 220
        default:
            return 180
        }
        #else
        return 180
        #endif
    }

    #if os(iOS)
    private func handleKeyboard(_ note: Notification) {
        let base = Self.baseRunwayHeight()
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            runwayHeight = base
            return
        }

        let keyboardHeight = frame.height
        let safeBottom = Self.keyWindowSafeAreaBottom()
        let visibleKeyboardHeight = max(0, keyboardHeight - safeBottom)
        runwayHeight = base + visibleKeyboardHeight
    }

    private static func keyWindowSafeAreaBottom() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window.safeAreaInsets.bottom
            }
        }
        return UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
    }
    #endif
}
