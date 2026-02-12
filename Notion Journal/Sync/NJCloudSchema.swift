import Foundation

enum NJOutlineCloudMapper {
    static let entity = "outline"
    static let recordType = "NJOutline"
}

enum NJOutlineNodeCloudMapper {
    static let entity = "outline_node"
    static let recordType = "NJOutlineNode"
}

enum NJCloudSchema {
    static let syncOrder: [(String, String)] = {
        var a: [(String, String)] = []
        a.append((NJNotebookCloudMapper.entity, NJNotebookCloudMapper.recordType))
        a.append((NJTabCloudMapper.entity, NJTabCloudMapper.recordType))
        a.append((NJNoteCloudMapper.entity, NJNoteCloudMapper.recordType))
        a.append((NJBlockCloudMapper.entity, NJBlockCloudMapper.recordType))
        a.append((NJAttachmentCloudMapper.entity, NJAttachmentCloudMapper.recordType))
        a.append((NJCalendarItemCloudMapper.entity, NJCalendarItemCloudMapper.recordType))
        a.append(("goal", "NJGoal"))
        a.append((NJOutlineCloudMapper.entity, NJOutlineCloudMapper.recordType))
        a.append((NJOutlineNodeCloudMapper.entity, NJOutlineNodeCloudMapper.recordType))
        a.append((NJNoteBlockCloudMapper.entity, NJNoteBlockCloudMapper.recordType))
        return a
    }()
}
