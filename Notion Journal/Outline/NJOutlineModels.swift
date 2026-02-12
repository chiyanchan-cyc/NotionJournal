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
    var isCollapsed: Bool
    var filterJSON: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
}

struct NJOutlineNodeRow: Identifiable, Hashable {
    var id: String { node.nodeID }
    let node: NJOutlineNodeRecord
    let depth: Int
}

struct NJOutlineReconstructedRow: Identifiable, Hashable {
    var id: String { blockID }
    let blockID: String
    let createdAtMs: Int64
    let domainTag: String
    let tags: [String]
    let title: String
}

struct NJOutlineFilterRule: Identifiable, Hashable {
    enum Field: String, CaseIterable, Hashable {
        case domain = "domain"
        case tag = "tag"

        var label: String {
            switch self {
            case .domain: return "Domain"
            case .tag: return "Tag"
            }
        }
    }

    var id: String
    var field: Field
    var value: String

    init(id: String = UUID().uuidString.lowercased(), field: Field, value: String) {
        self.id = id
        self.field = field
        self.value = value
    }
}
