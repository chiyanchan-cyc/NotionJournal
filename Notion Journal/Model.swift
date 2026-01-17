import Foundation

struct NJNoteID: Hashable, Codable, Identifiable {
    let raw: String
    var id: String { raw }
    init(_ raw: String) { self.raw = raw }
}

struct NJNote: Identifiable, Codable, Hashable {
    var id: NJNoteID
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var notebook: String
    var tabDomain: String
    var title: String
    var rtfData: Data
    var deleted: Int64

    init(
        id: NJNoteID,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        notebook: String,
        tabDomain: String,
        title: String,
        rtfData: Data,
        deleted: Int64
    ) {
        self.id = id
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.notebook = notebook
        self.tabDomain = tabDomain
        self.title = title
        self.rtfData = rtfData
        self.deleted = deleted
    }

    init(
        id: NJNoteID,
        notebook: String,
        tabDomain: String,
        title: String,
        createdAtMs: Int64,
        updatedAtMs: Int64
    ) {
        self.id = id
        self.notebook = notebook
        self.tabDomain = tabDomain
        self.title = title
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.rtfData = Data()
        self.deleted = 0
    }
}
