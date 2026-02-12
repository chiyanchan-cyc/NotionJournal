import Foundation
import Combine

@MainActor
final class NJOutlineStore: ObservableObject {
    @Published private(set) var categories: [String] = []
    @Published private(set) var outlines: [NJOutlineSummary] = []
    @Published private(set) var nodes: [NJOutlineNodeRecord] = []

    private let repo: DBNoteRepository

    init(repo: DBNoteRepository) {
        self.repo = repo
    }

    func reloadOutlines(category: String?) {
        categories = repo.listOutlineCategories()
        outlines = repo.listOutlines(category: category)
    }

    func createOutline(title: String, category: String) -> NJOutlineSummary? {
        let created = repo.createOutline(title: title, category: category)
        categories = repo.listOutlineCategories()
        return created
    }

    func loadNodes(outlineID: String) {
        nodes = repo.listOutlineNodes(outlineID: outlineID)
    }

    func createRootNode(outlineID: String) -> NJOutlineNodeRecord {
        let node = repo.createOutlineNode(outlineID: outlineID, parentNodeID: nil, title: "")
        loadNodes(outlineID: outlineID)
        return node
    }

    func createSiblingNode(nodeID: String) -> NJOutlineNodeRecord? {
        guard let n = node(nodeID) else { return nil }
        let new = repo.createOutlineNode(outlineID: n.outlineID, parentNodeID: n.parentNodeID, title: "")
        var siblingIDs = siblings(of: n).map { $0.nodeID }
        let insertAt: Int = {
            guard let currentIndex = siblingIDs.firstIndex(of: n.nodeID) else { return siblingIDs.count }
            return min(currentIndex + 1, siblingIDs.count)
        }()
        siblingIDs.insert(new.nodeID, at: insertAt)
        for (idx, id) in siblingIDs.enumerated() {
            repo.moveOutlineNode(nodeID: id, parentNodeID: n.parentNodeID, ord: idx)
        }
        loadNodes(outlineID: n.outlineID)
        return node(new.nodeID) ?? new
    }

    func createChildNode(nodeID: String) -> NJOutlineNodeRecord? {
        guard let n = node(nodeID) else { return nil }
        let new = repo.createOutlineNode(outlineID: n.outlineID, parentNodeID: n.nodeID, title: "")
        var childIDs = children(parentNodeID: n.nodeID).map { $0.nodeID }
        childIDs.insert(new.nodeID, at: 0)
        for (idx, id) in childIDs.enumerated() {
            repo.moveOutlineNode(nodeID: id, parentNodeID: n.nodeID, ord: idx)
        }
        if n.isCollapsed {
            repo.updateOutlineNodeCollapsed(nodeID: n.nodeID, isCollapsed: false)
        }
        loadNodes(outlineID: n.outlineID)
        return node(new.nodeID) ?? new
    }

    func reorderNodeWithinParent(nodeID: String, toSiblingIndex newIndex: Int) {
        guard let moving = node(nodeID) else { return }
        let parentID = moving.parentNodeID
        var sibs = nodes
            .filter { $0.outlineID == moving.outlineID && $0.parentNodeID == parentID }
            .sorted { a, b in
                if a.ord != b.ord { return a.ord < b.ord }
                return a.createdAtMs < b.createdAtMs
            }
        guard let oldIndex = sibs.firstIndex(where: { $0.nodeID == nodeID }) else { return }
        let bounded = min(max(newIndex, 0), max(sibs.count - 1, 0))
        if oldIndex == bounded { return }

        let item = sibs.remove(at: oldIndex)
        sibs.insert(item, at: bounded)

        for (idx, sib) in sibs.enumerated() {
            if sib.ord == idx { continue }
            repo.moveOutlineNode(nodeID: sib.nodeID, parentNodeID: sib.parentNodeID, ord: idx)
        }
        loadNodes(outlineID: moving.outlineID)
    }

    func updateNodeTitle(nodeID: String, title: String) {
        guard var n = node(nodeID) else { return }
        n.title = title
        persistNodeAndPatchLocal(n)
    }

    func updateNodeComment(nodeID: String, comment: String) {
        guard var n = node(nodeID) else { return }
        n.comment = comment
        persistNodeAndPatchLocal(n)
    }

    func updateNodeDomain(nodeID: String, domainTag: String) {
        guard var n = node(nodeID) else { return }
        n.domainTag = domainTag
        persistNodeAndPatchLocal(n)
    }

    func toggleChecklist(nodeID: String) {
        guard var n = node(nodeID) else { return }
        n.isChecklist.toggle()
        if !n.isChecklist { n.isChecked = false }
        persistNodeAndPatchLocal(n)
    }

    func toggleChecked(nodeID: String) {
        guard var n = node(nodeID) else { return }
        guard n.isChecklist else { return }
        n.isChecked.toggle()
        persistNodeAndPatchLocal(n)
    }

    func toggleCollapsed(nodeID: String) {
        guard let n = node(nodeID) else { return }
        repo.updateOutlineNodeCollapsed(nodeID: nodeID, isCollapsed: !n.isCollapsed)
        loadNodes(outlineID: n.outlineID)
    }

    func promote(nodeID: String) {
        guard let n = node(nodeID), let parentID = n.parentNodeID, let parent = node(parentID) else { return }
        let newParent = parent.parentNodeID
        reparent(nodeID: n.nodeID, to: newParent)
    }

    func demote(nodeID: String) {
        guard let n = node(nodeID) else { return }
        let siblings = siblings(of: n)
        guard let idx = siblings.firstIndex(where: { $0.nodeID == n.nodeID }), idx > 0 else { return }
        let newParent = siblings[idx - 1].nodeID
        reparent(nodeID: n.nodeID, to: newParent)
    }

    func nodeRows(outlineID: String) -> [NJOutlineNodeRow] {
        let scoped = nodes.filter { $0.outlineID == outlineID }
        var out: [NJOutlineNodeRow] = []
        for root in children(parentNodeID: nil, scoped: scoped) {
            appendRows(node: root, depth: 0, scoped: scoped, out: &out)
        }
        return out
    }

    func nodeFilter(nodeID: String) -> [String: Any] {
        guard let n = node(nodeID) else { return [:] }
        return decodeObject(n.filterJSON)
    }

    func setNodeFilter(nodeID: String, filter: [String: Any]) {
        guard let n = node(nodeID) else { return }
        repo.updateOutlineNodeFilter(nodeID: nodeID, filterJSON: encodeObject(filter))
        loadNodes(outlineID: n.outlineID)
    }

    func canDeleteNode(nodeID: String) -> Bool {
        repo.canDeleteOutlineNode(nodeID: nodeID)
    }

    func deleteNode(nodeID: String) {
        guard let n = node(nodeID) else { return }
        guard repo.canDeleteOutlineNode(nodeID: nodeID) else { return }
        repo.deleteOutlineNode(nodeID: nodeID)
        if let idx = nodes.firstIndex(where: { $0.nodeID == nodeID }) {
            nodes.remove(at: idx)
        }
        reorderSiblings(outlineID: n.outlineID, parentNodeID: n.parentNodeID)
        loadNodes(outlineID: n.outlineID)
    }

    func reconstructedRows(
        domain: String,
        tagsCSV: String,
        op: String,
        startMs: Int64?,
        endMs: Int64?,
        limit: Int = 300
    ) -> [NJOutlineReconstructedRow] {
        let tags = tagsCSV
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return repo.listOutlineReconstructedBlocks(
            domain: domain,
            tags: tags,
            op: op,
            startMs: startMs,
            endMs: endMs,
            limit: limit
        )
    }

    func reconstructedBlockIDs(
        rules: [NJOutlineFilterRule],
        op: String,
        startMs: Int64?,
        endMs: Int64?,
        limit: Int = 300
    ) -> [String] {
        repo.listOutlineReconstructedBlockIDs(
            rules: rules,
            op: op,
            startMs: startMs,
            endMs: endMs,
            limit: limit
        )
    }

    func node(_ nodeID: String) -> NJOutlineNodeRecord? {
        nodes.first(where: { $0.nodeID == nodeID })
    }

    private func appendRows(node: NJOutlineNodeRecord, depth: Int, scoped: [NJOutlineNodeRecord], out: inout [NJOutlineNodeRow]) {
        out.append(NJOutlineNodeRow(node: node, depth: depth))
        if node.isCollapsed { return }
        for c in children(parentNodeID: node.nodeID, scoped: scoped) {
            appendRows(node: c, depth: depth + 1, scoped: scoped, out: &out)
        }
    }

    private func children(parentNodeID: String?, scoped: [NJOutlineNodeRecord]? = nil) -> [NJOutlineNodeRecord] {
        let src = scoped ?? nodes
        return src.filter { $0.parentNodeID == parentNodeID }
            .sorted { a, b in
                if a.ord != b.ord { return a.ord < b.ord }
                return a.createdAtMs < b.createdAtMs
            }
    }

    private func siblings(of node: NJOutlineNodeRecord) -> [NJOutlineNodeRecord] {
        nodes.filter { $0.outlineID == node.outlineID && $0.parentNodeID == node.parentNodeID }
            .sorted { $0.ord < $1.ord }
    }

    private func persistNodeAndPatchLocal(_ n: NJOutlineNodeRecord) {
        repo.updateOutlineNodeBasics(
            nodeID: n.nodeID,
            title: n.title,
            comment: n.comment,
            domainTag: n.domainTag,
            isChecklist: n.isChecklist,
            isChecked: n.isChecked
        )
        guard let i = nodes.firstIndex(where: { $0.nodeID == n.nodeID }) else { return }
        var arr = nodes
        var patched = n
        patched.updatedAtMs = DBNoteRepository.nowMs()
        arr[i] = patched
        nodes = arr
    }

    private func reparent(nodeID: String, to newParent: String?) {
        guard let n = node(nodeID) else { return }
        let targetSiblings = nodes.filter { $0.outlineID == n.outlineID && $0.parentNodeID == newParent && $0.nodeID != nodeID }
            .sorted { $0.ord < $1.ord }

        repo.moveOutlineNode(nodeID: nodeID, parentNodeID: newParent, ord: targetSiblings.count)

        let oldSiblings = nodes.filter { $0.outlineID == n.outlineID && $0.parentNodeID == n.parentNodeID && $0.nodeID != nodeID }
            .sorted { $0.ord < $1.ord }

        for (idx, sib) in oldSiblings.enumerated() {
            repo.moveOutlineNode(nodeID: sib.nodeID, parentNodeID: sib.parentNodeID, ord: idx)
        }
        loadNodes(outlineID: n.outlineID)
    }

    private func reorderSiblings(outlineID: String, parentNodeID: String?) {
        let siblings = nodes
            .filter { $0.outlineID == outlineID && $0.parentNodeID == parentNodeID }
            .sorted { $0.ord < $1.ord }
        for (idx, sib) in siblings.enumerated() {
            if sib.ord == idx { continue }
            repo.moveOutlineNode(nodeID: sib.nodeID, parentNodeID: sib.parentNodeID, ord: idx)
        }
    }

    private func decodeObject(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private func encodeObject(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}
