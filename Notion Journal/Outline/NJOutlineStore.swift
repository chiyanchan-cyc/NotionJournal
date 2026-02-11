import Foundation
import Combine
final class NJOutlineStore: ObservableObject {
    @Published private(set) var nodes: [NJOutlineNode] = []
    @Published private(set) var pins: [NJOutlinePin] = []

    private var saveWork: DispatchWorkItem? = nil
    private let saveDelay: TimeInterval = 0.4

    init() {
        load()
    }

    func load() {
        let url = storageURL()
        guard
            let data = try? Data(contentsOf: url),
            let snap = try? JSONDecoder().decode(NJOutlineStoreSnapshot.self, from: data)
        else {
            nodes = []
            pins = []
            return
        }
        nodes = snap.nodes
        pins = snap.pins
    }

    func saveNow() {
        let snap = NJOutlineStoreSnapshot(nodes: nodes, pins: pins)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        let url = storageURL()
        try? data.write(to: url, options: [.atomic])
    }

    func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: w)
    }

    func createNode(parentID: String?, title: String, homeNoteID: String) -> NJOutlineNode {
        let now = nowMs()
        let node = NJOutlineNode(
            id: UUID().uuidString.lowercased(),
            parentID: parentID,
            order: nextOrder(parentID: parentID),
            title: title,
            comment: "",
            isChecked: false,
            status: .none,
            dateMs: nil,
            isCollapsed: false,
            homeNoteID: homeNoteID,
            createdAtMs: now,
            updatedAtMs: now
        )
        nodes.append(node)
        scheduleSave()
        return node
    }

    func updateNode(_ node: NJOutlineNode) {
        guard let i = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        nodes[i] = node
        scheduleSave()
    }

    func deleteNode(nodeID: String) {
        let descendantIDs = collectDescendantIDs(nodeID: nodeID)
        let removeSet = Set([nodeID] + descendantIDs)
        nodes.removeAll { removeSet.contains($0.id) }
        pins.removeAll { removeSet.contains($0.nodeID) }
        scheduleSave()
    }

    func toggleCollapsed(nodeID: String) {
        guard let i = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[i].isCollapsed.toggle()
        nodes[i].updatedAtMs = nowMs()
        scheduleSave()
    }

    func toggleChecked(nodeID: String) {
        guard let i = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[i].isChecked.toggle()
        nodes[i].updatedAtMs = nowMs()
        scheduleSave()
    }

    func setTitle(nodeID: String, title: String) {
        guard let i = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[i].title = title
        nodes[i].updatedAtMs = nowMs()
        scheduleSave()
    }

    func setComment(nodeID: String, comment: String) {
        guard let i = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[i].comment = comment
        nodes[i].updatedAtMs = nowMs()
        scheduleSave()
    }

    func setStatus(nodeID: String, status: NJOutlineStatus) {
        guard let i = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[i].status = status
        nodes[i].updatedAtMs = nowMs()
        scheduleSave()
    }

    func setDate(nodeID: String, date: Date?) {
        guard let i = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        if let d = date {
            nodes[i].dateMs = Int64(d.timeIntervalSince1970 * 1000.0)
        } else {
            nodes[i].dateMs = nil
        }
        nodes[i].updatedAtMs = nowMs()
        scheduleSave()
    }

    func moveNodeAfter(draggedID: String, targetID: String) {
        guard let dragged = node(draggedID), let target = node(targetID) else { return }
        if dragged.id == target.id { return }
        if isDescendant(nodeID: target.id, of: dragged.id) { return }

        let newParent = target.parentID
        let oldParent = dragged.parentID
        var siblings = children(parentID: newParent)
        siblings.removeAll { $0.id == dragged.id }
        let insertIndex = min((siblings.firstIndex(where: { $0.id == target.id }) ?? (siblings.count - 1)) + 1, siblings.count)
        siblings.insert(dragged.withParent(newParent), at: max(insertIndex, 0))
        normalizeOrder(parentID: newParent, siblings: siblings)
        if oldParent != newParent {
            normalizeOrder(parentID: oldParent, siblings: children(parentID: oldParent))
        }
    }

    func moveNodeAsChild(draggedID: String, parentID: String) {
        guard let dragged = node(draggedID) else { return }
        if dragged.id == parentID { return }
        if isDescendant(nodeID: parentID, of: dragged.id) { return }

        let newParent = parentID
        var siblings = children(parentID: newParent)
        siblings.removeAll { $0.id == dragged.id }
        siblings.append(dragged.withParent(newParent))
        normalizeOrder(parentID: newParent, siblings: siblings)
        normalizeOrder(parentID: dragged.parentID, siblings: children(parentID: dragged.parentID))
    }

    func moveNodeToRoot(draggedID: String) {
        guard let dragged = node(draggedID) else { return }
        let newParent: String? = nil
        var siblings = children(parentID: newParent)
        siblings.removeAll { $0.id == dragged.id }
        siblings.append(dragged.withParent(newParent))
        normalizeOrder(parentID: newParent, siblings: siblings)
        normalizeOrder(parentID: dragged.parentID, siblings: children(parentID: dragged.parentID))
    }

    func addPin(nodeID: String, blockID: String) {
        guard !pins.contains(where: { $0.nodeID == nodeID && $0.blockID == blockID }) else { return }
        let pin = NJOutlinePin(
            id: UUID().uuidString.lowercased(),
            nodeID: nodeID,
            blockID: blockID,
            createdAtMs: nowMs()
        )
        pins.append(pin)
        scheduleSave()
    }

    func removePin(pinID: String) {
        pins.removeAll { $0.id == pinID }
        scheduleSave()
    }

    func node(_ id: String) -> NJOutlineNode? {
        nodes.first(where: { $0.id == id })
    }

    func children(parentID: String?) -> [NJOutlineNode] {
        nodes.filter { $0.parentID == parentID }
            .sorted { $0.order < $1.order }
    }

    func hasChildren(_ nodeID: String) -> Bool {
        nodes.contains(where: { $0.parentID == nodeID })
    }

    func pinsForNode(_ nodeID: String) -> [NJOutlinePin] {
        pins.filter { $0.nodeID == nodeID }
            .sorted { $0.createdAtMs > $1.createdAtMs }
    }

    func flatten(filter: NJOutlineFilter) -> [NJOutlineRow] {
        var out: [NJOutlineRow] = []
        for n in children(parentID: nil) {
            appendVisible(node: n, depth: 0, filter: filter, out: &out)
        }
        return out
    }

    func isDescendant(nodeID: String, of ancestorID: String) -> Bool {
        var cur = nodeID
        var seen: Set<String> = []
        while let n = node(cur), let p = n.parentID {
            if p == ancestorID { return true }
            if seen.contains(p) { break }
            seen.insert(p)
            cur = p
        }
        return false
    }

    private func collectDescendantIDs(nodeID: String) -> [String] {
        var out: [String] = []
        var stack = [nodeID]
        while let cur = stack.popLast() {
            let kids = nodes.filter { $0.parentID == cur }.map { $0.id }
            out.append(contentsOf: kids)
            stack.append(contentsOf: kids)
        }
        return out
    }

    private func appendVisible(node: NJOutlineNode, depth: Int, filter: NJOutlineFilter, out: inout [NJOutlineRow]) {
        let matches = filter.matches(node: node)
        let kids = children(parentID: node.id)
        var childRows: [NJOutlineRow] = []
        if !node.isCollapsed {
            for k in kids {
                appendVisible(node: k, depth: depth + 1, filter: filter, out: &childRows)
            }
        }

        if matches || !childRows.isEmpty {
            out.append(NJOutlineRow(node: node, depth: depth, isDimmed: !matches))
            out.append(contentsOf: childRows)
        }
    }

    private func normalizeOrder(parentID: String?, siblings: [NJOutlineNode]) {
        var updated = siblings
        for i in 0..<updated.count {
            updated[i].order = i
            updated[i].updatedAtMs = nowMs()
        }

        for node in updated {
            if let idx = nodes.firstIndex(where: { $0.id == node.id }) {
                nodes[idx] = node
            } else {
                nodes.append(node)
            }
        }
        scheduleSave()
    }

    private func nextOrder(parentID: String?) -> Int {
        let maxOrder = nodes.filter { $0.parentID == parentID }.map { $0.order }.max() ?? -1
        return maxOrder + 1
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private func storageURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("nj_outline_v1.json", isDirectory: false)
    }
}

struct NJOutlineFilter: Hashable {
    var status: NJOutlineStatus? = nil
    var fromDate: Date? = nil
    var toDate: Date? = nil
    var onlyDated: Bool = false

    func matches(node: NJOutlineNode) -> Bool {
        if let s = status, node.status != s { return false }
        if onlyDated, node.dateMs == nil { return false }
        if let fromDate {
            let fromMs = Int64(fromDate.timeIntervalSince1970 * 1000.0)
            if (node.dateMs ?? -1) < fromMs { return false }
        }
        if let toDate {
            let toMs = Int64(toDate.timeIntervalSince1970 * 1000.0)
            if (node.dateMs ?? Int64.max) > toMs { return false }
        }
        return true
    }
}

private extension NJOutlineNode {
    func withParent(_ parentID: String?) -> NJOutlineNode {
        var copy = self
        copy.parentID = parentID
        copy.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        return copy
    }
}
