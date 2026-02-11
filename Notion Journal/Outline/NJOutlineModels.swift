import Foundation

enum NJOutlineStatus: String, CaseIterable, Codable, Identifiable {
    case none
    case active
    case hold
    case done

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .active: return "Active"
        case .hold: return "Hold"
        case .done: return "Done"
        }
    }
}

struct NJOutlineNode: Identifiable, Codable, Hashable {
    var id: String
    var parentID: String?
    var order: Int
    var title: String
    var comment: String
    var isChecked: Bool
    var status: NJOutlineStatus
    var dateMs: Int64?
    var isCollapsed: Bool
    var homeNoteID: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
}

struct NJOutlinePin: Identifiable, Codable, Hashable {
    var id: String
    var nodeID: String
    var blockID: String
    var createdAtMs: Int64
}

struct NJOutlineStoreSnapshot: Codable {
    var nodes: [NJOutlineNode]
    var pins: [NJOutlinePin]
}

struct NJOutlineRow: Identifiable, Hashable {
    let node: NJOutlineNode
    let depth: Int
    let isDimmed: Bool

    var id: String { node.id }
}
