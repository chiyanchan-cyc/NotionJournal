import Foundation
import CloudKit
import Combine

enum NJCloudKitRuntime {
    static func unavailableReason(containerID: String) -> String? {
        #if targetEnvironment(simulator)
        if FileManager.default.url(forUbiquityContainerIdentifier: containerID) == nil {
            return "iCloud container entitlement unavailable in this simulator runtime"
        }
        #endif

        return nil
    }

    static func container(containerID: String) -> CKContainer {
        CKContainer(identifier: containerID)
    }
}

@MainActor
final class CloudSyncEngine: ObservableObject {
    private static let livePullIntervalNs: UInt64 = 10 * 1_000_000_000

    private let coordinator: NJCloudSyncCoordinator?
    private let pendingDirtyCount: @MainActor () -> Int
    private var scheduledTask: Task<Void, Never>?
    private var initialTask: Task<Void, Never>?
    private var pendingPushAfterInitialPull = false

    @Published private(set) var initialPullCompleted = false
    @Published private(set) var cloudSyncUnavailableReason: String?

    init(
        coordinator: NJCloudSyncCoordinator?,
        pendingDirtyCount: @escaping @MainActor () -> Int,
        cloudSyncUnavailableReason: String? = nil
    ) {
        self.coordinator = coordinator
        self.pendingDirtyCount = pendingDirtyCount
        self.cloudSyncUnavailableReason = cloudSyncUnavailableReason
        self.initialPullCompleted = coordinator == nil
    }

    convenience init(repo: DBNoteRepository, deviceID: String, containerID: String) {
        if let reason = NJCloudKitRuntime.unavailableReason(containerID: containerID) {
            print("NJ_CK_DISABLED reason=\(reason)")
            self.init(
                coordinator: nil,
                pendingDirtyCount: { repo.pendingDirtyCount() },
                cloudSyncUnavailableReason: reason
            )
            return
        }

        let container = NJCloudKitRuntime.container(containerID: containerID)
        let transport = NJCloudKitTransport(
            container: container,
            recordDirtyError: { entity, entityID, code, domain, message, retryAfterSec in
                repo.recordDirtyError(entity: entity, entityID: entityID, code: code, domain: domain, message: message, retryAfterSec: retryAfterSec)
            }
        )
        let coordinator = NJCloudSyncCoordinator(repo: repo, transport: transport)
        self.init(coordinator: coordinator, pendingDirtyCount: { repo.pendingDirtyCount() })
    }

    func start() {
        if initialTask != nil { return }
        guard coordinator != nil else {
            initialPullCompleted = true
            NotificationCenter.default.post(name: .njPullCompleted, object: nil)
            return
        }

        initialTask = Task { [weak self] in
            guard let self else { return }
            guard let coordinator = self.coordinator else {
                self.initialPullCompleted = true
                NotificationCenter.default.post(name: .njPullCompleted, object: nil)
                return
            }

            await DBDirtyQueueTable.withPullScopeAsync {
                await coordinator.pullAll(forceSinceZero: false)
            }
            NotificationCenter.default.post(name: .njPullCompleted, object: nil)

            self.initialPullCompleted = true

            NotificationCenter.default.addObserver(
                forName: .njDirtyEnqueued,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.schedulePush(debounceMs: 150)
                }
            }

            if self.pendingPushAfterInitialPull || self.pendingDirtyCount() > 0 {
                self.pendingPushAfterInitialPull = false
                self.schedulePush(debounceMs: 1500)
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.livePullIntervalNs)
                if Task.isCancelled { break }
                print("NJ_CK_LIVE_PULL tick")
                await DBDirtyQueueTable.withPullScopeAsync {
                    await coordinator.pullAll(forceSinceZero: false)
                }
                NotificationCenter.default.post(name: .njPullCompleted, object: nil)
            }
        }
    }

    func forcePullNow(forceSinceZero: Bool = true) async {
        guard let coordinator else {
            initialPullCompleted = true
            NotificationCenter.default.post(name: .njPullCompleted, object: nil)
            return
        }

        await DBDirtyQueueTable.withPullScopeAsync {
            await coordinator.pullAll(forceSinceZero: forceSinceZero)
        }
        NotificationCenter.default.post(name: .njPullCompleted, object: nil)
    }

    func forceSyncNow() async {
        guard let coordinator else {
            initialPullCompleted = true
            NotificationCenter.default.post(name: .njPullCompleted, object: nil)
            return
        }

        scheduledTask?.cancel()
        scheduledTask = nil
        await coordinator.syncOnce()
        NotificationCenter.default.post(name: .njPullCompleted, object: nil)
    }

    func schedulePush(debounceMs: Int) {
        guard let coordinator else { return }

        guard initialPullCompleted else {
            pendingPushAfterInitialPull = true
            return
        }
        guard pendingDirtyCount() > 0 else {
            scheduledTask?.cancel()
            scheduledTask = nil
            return
        }
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            guard self != nil else { return }
            if debounceMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            }
            await coordinator.pushPendingOnly()
        }
    }

    private func runOnce() async {
        guard let coordinator else {
            initialPullCompleted = true
            NotificationCenter.default.post(name: .njPullCompleted, object: nil)
            return
        }

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
