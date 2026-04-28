import Foundation

struct NJMeetingPersonOption: Codable, Hashable, Identifiable {
    let personID: String
    let displayName: String
    let role: String
    let isFamily: Bool

    var id: String { personID }
}

enum NJMeetingParticipantDirectory {
    private static let containerID = "iCloud.com.CYC.NotionJournal"
    private static let relativePath = "Documents/SharedKnowledge/meeting_participants.json"

    private static let familyDefaults: [NJMeetingPersonOption] = [
        .init(personID: "person:dad", displayName: "Dad", role: "", isFamily: true),
        .init(personID: "person:mom", displayName: "Mom", role: "", isFamily: true),
        .init(personID: "person:zhou_zhou", displayName: "Zhou Zhou", role: "", isFamily: true),
        .init(personID: "person:mushy_mushy", displayName: "Mushy Mushy", role: "", isFamily: true)
    ]

    static func allOptions() -> [NJMeetingPersonOption] {
        var seen = Set<String>()
        var out: [NJMeetingPersonOption] = []
        for option in familyDefaults + loadStored() {
            if seen.insert(option.personID).inserted {
                out.append(option)
            }
        }
        return out.sorted { lhs, rhs in
            if lhs.isFamily != rhs.isFamily { return lhs.isFamily && !rhs.isFamily }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    @discardableResult
    static func add(displayName: String, role: String) -> NJMeetingPersonOption? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        if let existing = allOptions().first(where: {
            $0.displayName.caseInsensitiveCompare(name) == .orderedSame &&
            $0.role.caseInsensitiveCompare(normalizedRole) == .orderedSame
        }) {
            return existing
        }

        let option = NJMeetingPersonOption(
            personID: "person:external:\(slug(from: name, role: normalizedRole))",
            displayName: name,
            role: normalizedRole,
            isFamily: false
        )
        var stored = loadStored()
        stored.append(option)
        saveStored(stored)
        return option
    }

    private static func loadStored() -> [NJMeetingPersonOption] {
        guard let url = storageURL(),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([NJMeetingPersonOption].self, from: data) else { return [] }
        return rows
    }

    private static func saveStored(_ rows: [NJMeetingPersonOption]) {
        guard let url = storageURL() else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(rows)
            try data.write(to: url, options: .atomic)
        } catch {
            print("NJ_MEETING_PARTICIPANTS save_failed path=\(url.path) err=\(error)")
        }
    }

    private static func storageURL() -> URL? {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else { return nil }
        return root.appendingPathComponent(relativePath, isDirectory: false)
    }

    private static func slug(from name: String, role: String) -> String {
        let base = "\(name)|\(role)".lowercased()
        let allowed = CharacterSet.alphanumerics
        let pieces = base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let raw = String(pieces)
        let compact = raw.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return compact.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
