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
    var pinned: Int64

    init(
        id: NJNoteID,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        notebook: String,
        tabDomain: String,
        title: String,
        rtfData: Data,
        deleted: Int64,
        pinned: Int64 = 0
    ) {
        self.id = id
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.notebook = notebook
        self.tabDomain = tabDomain
        self.title = title
        self.rtfData = rtfData
        self.deleted = deleted
        self.pinned = pinned
    }

    init(
        id: NJNoteID,
        notebook: String,
        tabDomain: String,
        title: String,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        pinned: Int64 = 0
    ) {
        self.id = id
        self.notebook = notebook
        self.tabDomain = tabDomain
        self.title = title
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.rtfData = Data()
        self.deleted = 0
        self.pinned = pinned
    }
}

struct NJCalendarItem: Identifiable, Codable, Hashable {
    var dateKey: String
    var title: String
    var photoAttachmentID: String
    var photoLocalID: String
    var photoThumbPath: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int

    var id: String { dateKey }

    init(
        dateKey: String,
        title: String,
        photoAttachmentID: String,
        photoLocalID: String,
        photoThumbPath: String,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        deleted: Int
    ) {
        self.dateKey = dateKey
        self.title = title
        self.photoAttachmentID = photoAttachmentID
        self.photoLocalID = photoLocalID
        self.photoThumbPath = photoThumbPath
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.deleted = deleted
    }

    static func empty(dateKey: String, nowMs: Int64) -> NJCalendarItem {
        NJCalendarItem(
            dateKey: dateKey,
            title: "",
            photoAttachmentID: "",
            photoLocalID: "",
            photoThumbPath: "",
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            deleted: 0
        )
    }
}

struct NJGoalSummary: Identifiable, Hashable {
    let goalID: String
    let name: String
    let goalTag: String
    let status: String
    let createdAtMs: Int64
    let updatedAtMs: Int64

    var id: String { goalID }
}
