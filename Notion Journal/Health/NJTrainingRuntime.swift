import Foundation

@MainActor
final class NJTrainingRuntime {
    static let shared = NJTrainingRuntime()

    private init() {}

    func reload(referenceDate: Date) {
        // The old MBA calendar expected a runtime refresher here.
        // Keep the hook alive without reintroducing the removed training subsystem.
    }
}
