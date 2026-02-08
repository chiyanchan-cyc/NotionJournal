import Foundation
import CloudKit
import Combine

@MainActor
final class CloudSyncEngine: ObservableObject {
    private let coordinator: NJCloudSyncCoordinator
    private var scheduledTask: Task<Void, Never>?
    private var initialTask: Task<Void, Never>?

    @Published private(set) var initialPullCompleted = false

    init(coordinator: NJCloudSyncCoordinator) {
        self.coordinator = coordinator
    }

    convenience init(repo: DBNoteRepository, deviceID: String, containerID: String) {
        let container = CKContainer(identifier: containerID)
        let transport = NJCloudKitTransport(
            container: container,
            recordDirtyError: { entity, entityID, code, domain, message, retryAfterSec in
                repo.recordDirtyError(entity: entity, entityID: entityID, code: code, domain: domain, message: message, retryAfterSec: retryAfterSec)
            }
        )
        let coordinator = NJCloudSyncCoordinator(repo: repo, transport: transport)
        self.init(coordinator: coordinator)
    }

    func start() {
        if initialTask != nil { return }

        initialTask = Task { [weak self] in
            guard let self else { return }

            await DBDirtyQueueTable.withPullScopeAsync {
                await self.coordinator.pullAll(forceSinceZero: true)
            }
            NotificationCenter.default.post(name: .njPullCompleted, object: nil)

            self.initialPullCompleted = true

            NotificationCenter.default.addObserver(
                forName: .njDirtyEnqueued,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.schedulePush(debounceMs: 150)
            }

            self.schedulePush(debounceMs: 150)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await DBDirtyQueueTable.withPullScopeAsync {
                    await self.coordinator.pullAll(forceSinceZero: false)
                }
                NotificationCenter.default.post(name: .njPullCompleted, object: nil)
            }
        }
    }

    func forcePullNow(forceSinceZero: Bool = true) async {
        await DBDirtyQueueTable.withPullScopeAsync {
            await coordinator.pullAll(forceSinceZero: forceSinceZero)
        }
        NotificationCenter.default.post(name: .njPullCompleted, object: nil)
    }

    func schedulePush(debounceMs: Int) {
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            guard let self else { return }
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            }
            await self.coordinator.syncOnce()
        }
    }

    private func runOnce() async {
        if !initialPullCompleted {
            await coordinator.pullAll(forceSinceZero: false)
            initialPullCompleted = true
        }
        NotificationCenter.default.post(name: .njPullCompleted, object: nil)
        await coordinator.pushAll()
        await coordinator.pullAll(forceSinceZero: false)
        NotificationCenter.default.post(name: .njPullCompleted, object: nil)
    }

}
