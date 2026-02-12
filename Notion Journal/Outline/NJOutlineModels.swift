import Foundation

struct NJOutlineSummary: Identifiable, Hashable {
    var id: String { outlineID }
    let outlineID: String
    var title: String
    var category: String
    var status: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
}

struct NJOutlineNodeRecord: Identifiable, Hashable {
    var id: String { nodeID }
    let nodeID: String
    let outlineID: String
    var parentNodeID: String?
    var ord: Int
    var title: String
    var comment: String
    var domainTag: String
    var isChecklist: Bool
    var isChecked: Bool
    var createdAtMs: Int64
    var updatedAtMs: Int64
}

struct NJOutlineNodeRow: Identifiable, Hashable {
    var id: String { node.nodeID }
    let node: NJOutlineNodeRecord
    let depth: Int
}
