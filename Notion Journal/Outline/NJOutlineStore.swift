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
        loadNodes(outlineID: n.outlineID)
        return new
    }

    func createChildNode(nodeID: String) -> NJOutlineNodeRecord? {
        guard let n = node(nodeID) else { return nil }
        let new = repo.createOutlineNode(outlineID: n.outlineID, parentNodeID: n.nodeID, title: "")
        loadNodes(outlineID: n.outlineID)
        return new
    }

    func updateNodeTitle(nodeID: String, title: String) {
        guard var n = node(nodeID) else { return }
        n.title = title
        persistNode(n)
    }

    func updateNodeComment(nodeID: String, comment: String) {
        guard var n = node(nodeID) else { return }
        n.comment = comment
        persistNode(n)
    }

    func updateNodeDomain(nodeID: String, domainTag: String) {
        guard var n = node(nodeID) else { return }
        n.domainTag = domainTag
        persistNode(n)
    }

    func toggleChecklist(nodeID: String) {
        guard var n = node(nodeID) else { return }
        n.isChecklist.toggle()
        if !n.isChecklist { n.isChecked = false }
        persistNode(n)
    }

    func toggleChecked(nodeID: String) {
        guard var n = node(nodeID) else { return }
        guard n.isChecklist else { return }
        n.isChecked.toggle()
        persistNode(n)
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

    func node(_ nodeID: String) -> NJOutlineNodeRecord? {
        nodes.first(where: { $0.nodeID == nodeID })
    }

    private func appendRows(node: NJOutlineNodeRecord, depth: Int, scoped: [NJOutlineNodeRecord], out: inout [NJOutlineNodeRow]) {
        out.append(NJOutlineNodeRow(node: node, depth: depth))
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

    private func persistNode(_ n: NJOutlineNodeRecord) {
        repo.updateOutlineNodeBasics(
            nodeID: n.nodeID,
            title: n.title,
            comment: n.comment,
            domainTag: n.domainTag,
            isChecklist: n.isChecklist,
            isChecked: n.isChecked
        )
        loadNodes(outlineID: n.outlineID)
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
}
