import SwiftUI

struct NJGoalDetailView: View {
    @EnvironmentObject var store: AppStore

    let goalID: String

    @State private var goal: [String: Any]? = nil
    @State private var name: String = ""
    @State private var goalTag: String = ""
    @State private var status: String = ""
    @State private var reflectCadence: String = ""
    @State private var domainTagsJSON: String = ""
    @State private var originBlockID: String = ""
    @State private var createdAtMs: Int64 = 0
    @State private var updatedAtMs: Int64 = 0

    var body: some View {
        Form {
            Section(header: Text("Name")) {
                Text(name.isEmpty ? "Untitled" : name)
            }

            Section(header: Text("Goal Tag")) {
                Text(goalTag.isEmpty ? "(none)" : goalTag)
            }

            if !domainTagsJSON.isEmpty {
                Section(header: Text("Domain Tags")) {
                    Text(domainTagsJSON)
                        .textSelection(.enabled)
                }
            }

            if !status.isEmpty {
                Section(header: Text("Status")) {
                    Text(status)
                }
            }

            if !reflectCadence.isEmpty {
                Section(header: Text("Reflect Cadence")) {
                    Text(reflectCadence)
                }
            }

            if !originBlockID.isEmpty {
                Section(header: Text("Origin Block")) {
                    Text(originBlockID)
                        .textSelection(.enabled)
                }
            }

            Section(header: Text("Dates")) {
                HStack {
                    Text("Created")
                    Spacer()
                    Text(dateString(createdAtMs))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Updated")
                    Spacer()
                    Text(dateString(updatedAtMs))
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("Goal ID")) {
                Text(goalID)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Goal / Seedling")
        .onAppear { load() }
    }

    private func load() {
        guard let g = store.notes.goalTable.loadNJGoal(goalID: goalID) else {
            goal = nil
            name = ""
            goalTag = ""
            status = ""
            reflectCadence = ""
            domainTagsJSON = ""
            originBlockID = ""
            createdAtMs = 0
            updatedAtMs = 0
            return
        }
        goal = g
        let payloadJSON = (g["payload_json"] as? String) ?? ""
        name = decodeGoalName(payloadJSON: payloadJSON)
        goalTag = (g["goal_tag"] as? String) ?? ""
        status = (g["status"] as? String) ?? ""
        reflectCadence = (g["reflect_cadence"] as? String) ?? ""
        domainTagsJSON = (g["domain_tags_json"] as? String) ?? ""
        originBlockID = (g["origin_block_id"] as? String) ?? ""
        createdAtMs = (g["created_at_ms"] as? Int64) ?? Int64((g["created_at_ms"] as? Int) ?? 0)
        updatedAtMs = (g["updated_at_ms"] as? Int64) ?? Int64((g["updated_at_ms"] as? Int) ?? 0)
    }

    private func decodeGoalName(payloadJSON: String) -> String {
        if let data = payloadJSON.data(using: .utf8),
           let payload = try? JSONDecoder().decode(NJGoalPayloadV1.self, from: data) {
            return payload.name
        }
        if let data = payloadJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = obj["name"] as? String {
            return name
        }
        return ""
    }

    private func dateString(_ ms: Int64) -> String {
        if ms <= 0 { return "-" }
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
