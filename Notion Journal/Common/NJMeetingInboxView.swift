import SwiftUI
import Combine

private struct NJManualSpeakerAssignmentPayload: Codable {
    let speakerLabel: String
    let personID: String?
    let displayName: String
    let assignedAtMs: Int64
}

struct NJMeetingInboxView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("nj_meetings_show_completed") private var showCompleted = false
    @State private var rows: [Row] = []
    @State private var editorRow: Row? = nil
    @State private var resultRow: Row? = nil

    struct Row: Identifiable, Equatable {
        let id: String
        let createdAtMs: Int64
        let title: String
        let audioPath: String
        let transcript: String
        let meetingRecordedAtMs: Int64
        let meetingLocation: String
        let meetingTopic: String
        let meetingParticipants: [NJMeetingParticipant]
        let summaryTitle: String
        let summaryText: String
        let languageMode: String
        let transcriptState: String
        let transcriptRequestedAtMs: Int64
        let transcriptErrorText: String

        var meetingContextReady: Bool {
            !meetingLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !meetingTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !meetingParticipants.isEmpty
        }

        var transcriptReady: Bool {
            !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        List {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Shared Audio Yet",
                    systemImage: "waveform.badge.mic",
                    description: Text("Shared meeting recordings will stay here until you fill in the meeting details and send them to transcription.")
                )
            } else {
                ForEach(rows) { row in
                    Button {
                        if row.transcriptReady {
                            resultRow = row
                        } else {
                            editorRow = row
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(formattedDate(row.meetingRecordedAtMs > 0 ? row.meetingRecordedAtMs : row.createdAtMs))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(transcriptStatusLabel(for: row))
                                    .font(.caption)
                                    .foregroundStyle(transcriptStatusColor(for: row))
                            }
                            Text(row.title.isEmpty ? "(untitled audio)" : row.title)
                                .font(.body)
                                .lineLimit(2)
                            Text(statusLine(for: row))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Transcribe") {
                            sendForTranscribe(row)
                        }
                        .tint(.blue)
                        .disabled(!row.meetingContextReady || row.transcriptReady)

                        Button("Delete", role: .destructive) {
                            deleteMeeting(row)
                        }
                    }
                }
            }
        }
        .navigationTitle("Meetings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Toggle("Show Completed", isOn: $showCompleted)
                        .labelsHidden()
                    Button("Refresh") { reload() }
                }
            }
        }
        .onAppear {
            reload()
        }
        .onReceive(store.objectWillChange) { _ in
            reload()
        }
        .onChange(of: showCompleted) { _, _ in
            reload()
        }
        .sheet(item: $editorRow) { row in
            NJMeetingContextEditorSheet(
                row: row,
                onSave: { updatedRow, sendForTranscribeNow in
                    saveMeetingContext(for: updatedRow)
                    if sendForTranscribeNow {
                        sendForTranscribe(updatedRow)
                    } else {
                        reload()
                    }
                }
            )
        }
        .sheet(item: $resultRow) { row in
            NJMeetingResultSheet(
                row: row,
                onEditDetails: {
                    resultRow = nil
                    editorRow = row
                },
                onApplySpeakerAssignments: { assignments in
                    applySpeakerAssignments(for: row, assignments: assignments)
                }
            )
        }
    }

    private func reload() {
        let raw = store.notes.listOrphanAudioBlocks(limit: 1000)
        let newRows = raw.map { record in
            let reconciledPayload = reconcilePayloadWithArtifacts(blockID: record.id, payloadJSON: record.payloadJSON) ?? record.payloadJSON
            let meta = parseAudioPayload(reconciledPayload, fallbackCreatedAtMs: record.createdAtMs)
            return Row(
                id: record.id,
                createdAtMs: record.createdAtMs,
                title: meta.title,
                audioPath: meta.audioPath,
                transcript: meta.transcript,
                meetingRecordedAtMs: meta.meetingRecordedAtMs,
                meetingLocation: meta.meetingLocation,
                meetingTopic: meta.meetingTopic,
                meetingParticipants: meta.meetingParticipants,
                summaryTitle: meta.summaryTitle,
                summaryText: meta.summaryText,
                languageMode: meta.languageMode,
                transcriptState: meta.transcriptState,
                transcriptRequestedAtMs: meta.transcriptRequestedAtMs,
                transcriptErrorText: meta.transcriptErrorText
            )
        }
        .filter { showCompleted || !$0.transcriptReady }
        .sorted { lhs, rhs in
            let leftMs = lhs.meetingRecordedAtMs > 0 ? lhs.meetingRecordedAtMs : lhs.createdAtMs
            let rightMs = rhs.meetingRecordedAtMs > 0 ? rhs.meetingRecordedAtMs : rhs.createdAtMs
            return leftMs > rightMs
        }

        rows = newRows

        if let current = resultRow,
           let refreshed = newRows.first(where: { $0.id == current.id }) {
            resultRow = refreshed
        }

        if let current = editorRow,
           let refreshed = newRows.first(where: { $0.id == current.id }) {
            editorRow = refreshed
        }
    }

    private func reconcilePayloadWithArtifacts(blockID: String, payloadJSON: String) -> String? {
        guard
            let data = payloadJSON.data(using: .utf8),
            var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var sections = root["sections"] as? [String: Any],
            var audio = sections["audio"] as? [String: Any],
            var audioData = audio["data"] as? [String: Any]
        else { return nil }

        let existingTranscript = ((audioData["transcript_txt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let currentState = ((audioData["transcript_state"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let audioPath = (audioData["audio_path"] as? String) ?? ""

        var changed = false

        if let participantsText = normalizeParticipantsJSON(audioData["meeting_persons_json"]), participantsText != (audioData["meeting_persons_json"] as? String ?? "") {
            audioData["meeting_persons_json"] = participantsText
            changed = true
        }

        if !existingTranscript.isEmpty {
            if currentState != "done" {
                audioData["transcript_state"] = "done"
                audioData["transcript_error_txt"] = ""
                audioData["transcript_state_updated_ms"] = DBNoteRepository.nowMs()
                changed = true
            }
        } else {
            if currentState == "waiting_for_audio_upload",
               !audioPath.isEmpty,
               audioArtifactExists(audioRelativePath: audioPath),
               ((audioData["meeting_context_complete"] as? NSNumber)?.intValue ?? 0) != 0 {
                let nowMs = DBNoteRepository.nowMs()
                audioData["transcript_state"] = "queued"
                audioData["transcript_requested_ms"] = nowMs
                audioData["transcript_error_txt"] = ""
                audioData["transcript_state_updated_ms"] = nowMs
                changed = true
            }
            var jsonPath = (audioData["json_path"] as? String) ?? ""
            if jsonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !audioPath.isEmpty {
                jsonPath = ((audioPath as NSString).deletingPathExtension + ".json")
            }
            if let jsonURL = resolveICloudDocumentsPath(jsonPath),
               FileManager.default.fileExists(atPath: jsonURL.path),
               let transcript = parseTranscriptArtifact(at: jsonURL),
               !transcript.isEmpty {
                audioData["json_path"] = jsonPath
                audioData["transcript_txt"] = transcript
                let updatedMs = fileTimestampMs(jsonURL) ?? DBNoteRepository.nowMs()
                audioData["transcript_updated_ms"] = updatedMs
                audioData["transcript_state"] = "done"
                audioData["transcript_error_txt"] = ""
                audioData["transcript_state_updated_ms"] = updatedMs
                changed = true
            }
        }

        if !audioPath.isEmpty,
           let context = NJMeetingContextStore.load(audioRelativePath: audioPath) {
            if ((audioData["meeting_location_txt"] as? String) ?? "").isEmpty {
                audioData["meeting_location_txt"] = context.locationText
                changed = true
            }
            if ((audioData["meeting_topic_txt"] as? String) ?? "").isEmpty {
                audioData["meeting_topic_txt"] = context.topicText
                changed = true
            }
            if (((audioData["meeting_persons_json"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ((audioData["meeting_persons_json"] as? String) ?? "") == "[]"),
               let encoded = try? JSONEncoder().encode(context.participants),
               let text = String(data: encoded, encoding: .utf8) {
                audioData["meeting_persons_json"] = text
                changed = true
            }
            if ((audioData["meeting_context_complete"] as? NSNumber)?.intValue ?? 0) == 0 {
                audioData["meeting_context_complete"] = 1
                changed = true
            }
        }

        guard changed else { return nil }
        audio["data"] = audioData
        sections["audio"] = audio
        root["sections"] = sections
        guard let out = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: out, encoding: .utf8) else { return nil }
        store.notes.updateBlockPayloadJSON(blockID: blockID, payloadJSON: text, updatedAtMs: DBNoteRepository.nowMs())
        store.sync.schedulePush(debounceMs: 0)
        return text
    }

    private func saveMeetingContext(for row: Row) {
        guard let raw = store.notes.loadBlock(blockID: row.id),
              let payloadJSON = raw["payload_json"] as? String,
              let updatedPayload = mergeMeetingContext(payloadJSON: payloadJSON, row: row, queueTranscription: false)
        else { return }

        store.notes.updateBlockPayloadJSON(blockID: row.id, payloadJSON: updatedPayload, updatedAtMs: DBNoteRepository.nowMs())
        store.sync.schedulePush(debounceMs: 0)

        let record = NJMeetingContextRecord(
            recordingID: row.id,
            audioRelativePath: row.audioPath,
            recordedAtMs: row.meetingRecordedAtMs > 0 ? row.meetingRecordedAtMs : row.createdAtMs,
            locationText: row.meetingLocation,
            topicText: row.meetingTopic,
            participants: row.meetingParticipants,
            createdAtMs: row.createdAtMs,
            updatedAtMs: DBNoteRepository.nowMs()
        )
        _ = NJMeetingContextStore.write(record)
    }

    private func sendForTranscribe(_ row: Row) {
        guard row.meetingContextReady else {
            editorRow = row
            return
        }
        let audioReady = audioArtifactExists(audioRelativePath: row.audioPath)
        let record = NJMeetingContextRecord(
            recordingID: row.id,
            audioRelativePath: row.audioPath,
            recordedAtMs: row.meetingRecordedAtMs > 0 ? row.meetingRecordedAtMs : row.createdAtMs,
            locationText: row.meetingLocation,
            topicText: row.meetingTopic,
            participants: row.meetingParticipants,
            createdAtMs: row.createdAtMs,
            updatedAtMs: DBNoteRepository.nowMs()
        )
        _ = NJMeetingContextStore.write(record)
        guard let raw = store.notes.loadBlock(blockID: row.id),
              let payloadJSON = raw["payload_json"] as? String,
              let updatedPayload = mergeMeetingContext(
                payloadJSON: payloadJSON,
                row: row,
                queueTranscription: audioReady,
                requestedState: audioReady ? "queued" : "waiting_for_audio_upload"
              )
        else { return }
        store.notes.updateBlockPayloadJSON(blockID: row.id, payloadJSON: updatedPayload, updatedAtMs: DBNoteRepository.nowMs())
        store.sync.schedulePush(debounceMs: 0)
        Task { @MainActor in
            await store.sync.forceSyncNow()
        }
        reload()
    }

    private func deleteMeeting(_ row: Row) {
        store.notes.markBlockDeleted(blockID: row.id)
        store.sync.schedulePush(debounceMs: 0)
        Task { @MainActor in
            await store.sync.forceSyncNow()
        }

        deleteMeetingFiles(audioPath: row.audioPath)

        rows.removeAll { $0.id == row.id }
        if editorRow?.id == row.id { editorRow = nil }
        if resultRow?.id == row.id { resultRow = nil }
    }

    private func deleteMeetingFiles(audioPath: String) {
        guard !audioPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fm = FileManager.default
        let audioURL = resolveICloudDocumentsPath(audioPath)
        let pdfURL = resolveICloudDocumentsPath((audioPath as NSString).deletingPathExtension + ".pdf")
        let jsonURL = resolveICloudDocumentsPath((audioPath as NSString).deletingPathExtension + ".json")
        let meetingURL = NJMeetingContextStore.sidecarURL(audioRelativePath: audioPath)

        if let audioURL { try? fm.removeItem(at: audioURL) }
        if let pdfURL { try? fm.removeItem(at: pdfURL) }
        if let jsonURL { try? fm.removeItem(at: jsonURL) }
        if let meetingURL { try? fm.removeItem(at: meetingURL) }

        if let dir = (audioURL ?? pdfURL ?? jsonURL ?? meetingURL)?.deletingLastPathComponent() {
            pruneEmptyDirs(start: dir)
        }
    }

    private func applySpeakerAssignments(for row: Row, assignments: [String: String]) {
        let cleanedAssignments = assignments.reduce(into: [String: String]()) { partial, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            partial[key] = value
        }
        guard !cleanedAssignments.isEmpty else { return }
        guard let raw = store.notes.loadBlock(blockID: row.id),
              let payloadJSON = raw["payload_json"] as? String,
              let jsonRel = extractJSONPath(from: payloadJSON) ?? inferredJSONRelativePath(audioRelativePath: row.audioPath),
              let jsonURL = resolveICloudDocumentsPath(jsonRel),
              var jsonRoot = loadTranscriptJSON(at: jsonURL)
        else { return }

        let updatedSegments = remapTranscriptSegments(in: jsonRoot, assignments: cleanedAssignments)
        guard !updatedSegments.isEmpty else { return }
        jsonRoot["segments"] = updatedSegments
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonRoot, options: [.prettyPrinted]),
              let transcript = renderTranscript(from: updatedSegments),
              let updatedPayload = mergeSpeakerAssignments(
                payloadJSON: payloadJSON,
                transcript: transcript,
                jsonRel: jsonRel,
                assignments: cleanedAssignments,
                participants: row.meetingParticipants
              )
        else { return }

        do {
            try jsonData.write(to: jsonURL, options: [.atomic])
        } catch {
            return
        }

        let now = DBNoteRepository.nowMs()
        store.notes.updateBlockPayloadJSON(blockID: row.id, payloadJSON: updatedPayload, updatedAtMs: now)
        store.sync.schedulePush(debounceMs: 0)
        Task { @MainActor in
            await store.sync.forceSyncNow()
        }
        reload()
    }

    private func pruneEmptyDirs(start: URL) {
        let fm = FileManager.default
        var current = start

        while true {
            if current.lastPathComponent == "Documents" { break }
            let contents = (try? fm.contentsOfDirectory(atPath: current.path)) ?? []
            if contents.isEmpty {
                try? fm.removeItem(at: current)
                current.deleteLastPathComponent()
            } else {
                break
            }
        }
    }

    private func formattedDate(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func statusLine(for row: Row) -> String {
        var parts: [String] = []
        if !row.meetingParticipants.isEmpty {
            parts.append(row.meetingParticipants.map(\.displayName).joined(separator: ", "))
        }
        if !row.meetingLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(row.meetingLocation)
        }
        if !row.meetingTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(row.meetingTopic)
        }
        if !row.languageMode.isEmpty {
            parts.append(languageLabel(for: row.languageMode))
        }
        if row.transcriptReady, !row.summaryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(row.summaryTitle)
        }
        return parts.isEmpty ? "Tap to fill meeting details" : parts.joined(separator: " • ")
    }

    private func languageLabel(for mode: String) -> String {
        switch mode.lowercased() {
        case "zh":
            return "Chinese"
        case "en":
            return "English"
        default:
            return "Bilingual"
        }
    }

    private func transcriptStatusLabel(for row: Row) -> String {
        if row.transcriptReady { return "Transcribed" }
        switch row.transcriptState.lowercased() {
        case "waiting_for_audio_upload":
            return "Audio Upload Pending"
        case "waiting_for_icloud":
            return "Waiting for iCloud"
        case "queued":
            return "Queued"
        case "transcribing":
            return "Transcribing"
        case "failed":
            return "Failed"
        case "ready":
            return "Ready to send"
        default:
            return "Needs details"
        }
    }

    private func transcriptStatusColor(for row: Row) -> Color {
        if row.transcriptReady { return .green }
        switch row.transcriptState.lowercased() {
        case "waiting_for_audio_upload":
            return .orange
        case "waiting_for_icloud":
            return .orange
        case "queued":
            return .blue
        case "transcribing":
            return .purple
        case "failed":
            return .red
        case "ready":
            return .blue
        default:
            return .orange
        }
    }

    private func parseAudioPayload(_ payload: String, fallbackCreatedAtMs: Int64) -> (
        title: String,
        audioPath: String,
        transcript: String,
        meetingRecordedAtMs: Int64,
        meetingLocation: String,
        meetingTopic: String,
        meetingParticipants: [NJMeetingParticipant],
        summaryTitle: String,
        summaryText: String,
        languageMode: String,
        transcriptState: String,
        transcriptRequestedAtMs: Int64,
        transcriptErrorText: String
    ) {
        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = obj["sections"] as? [String: Any],
            let audio = sections["audio"] as? [String: Any],
            let audioData = audio["data"] as? [String: Any]
        else {
            return (
                "Audio Recording",
                "",
                "",
                fallbackCreatedAtMs,
                "",
                "",
                [],
                "",
                "",
                "bilingual",
                "needs_details",
                0,
                ""
            )
        }

        let title = (audioData["title"] as? String) ?? "Audio Recording"
        let audioPath = (audioData["audio_path"] as? String) ?? ""
        let transcript = ((audioData["transcript_txt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadRecordedAtMs = ((audioData["meeting_recorded_at_ms"] as? NSNumber)?.int64Value)
            ?? ((audioData["recorded_at_ms"] as? NSNumber)?.int64Value)
        let inferredRecordedAtMs = resolveICloudDocumentsPath(audioPath).flatMap(fileTimestampMs)
        let meetingRecordedAtMs = payloadRecordedAtMs
            ?? inferredRecordedAtMs
            ?? fallbackCreatedAtMs
        let meetingLocation = (audioData["meeting_location_txt"] as? String) ?? ""
        let meetingTopic = (audioData["meeting_topic_txt"] as? String) ?? ""
        let summaryTitle = (audioData["summary_title"] as? String) ?? ""
        let summaryText = (audioData["summary_txt"] as? String) ?? ""
        let languageMode = (audioData["meeting_language_mode"] as? String) ?? "bilingual"
        let transcriptState = (audioData["transcript_state"] as? String) ?? "needs_details"
        let transcriptRequestedAtMs = ((audioData["transcript_requested_ms"] as? NSNumber)?.int64Value) ?? 0
        let transcriptErrorText = (audioData["transcript_error_txt"] as? String) ?? ""
        let participants = decodeParticipants(fromAny: audioData["meeting_persons_json"])
        return (title, audioPath, transcript, meetingRecordedAtMs, meetingLocation, meetingTopic, participants, summaryTitle, summaryText, languageMode, transcriptState, transcriptRequestedAtMs, transcriptErrorText)
    }

    private func decodeParticipants(from json: String) -> [NJMeetingParticipant] {
        guard let data = json.data(using: .utf8),
              let participants = try? JSONDecoder().decode([NJMeetingParticipant].self, from: data) else { return [] }
        return participants
    }

    private func decodeParticipants(fromAny raw: Any?) -> [NJMeetingParticipant] {
        if let text = raw as? String {
            return decodeParticipants(from: text)
        }
        if let normalized = normalizeParticipantsJSON(raw) {
            return decodeParticipants(from: normalized)
        }
        return []
    }

    private func normalizeParticipantsJSON(_ raw: Any?) -> String? {
        guard let raw else { return nil }
        if let text = raw as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let array = raw as? [[String: Any]] else { return nil }
        let normalized: [[String: Any]] = array.map { item in
            [
                "personID": (item["personID"] as? String) ?? (item["person_id"] as? String) ?? "",
                "displayName": (item["displayName"] as? String) ?? (item["display_name"] as? String) ?? "",
                "role": (item["role"] as? String) ?? "",
                "isFamily": (item["isFamily"] as? Bool) ?? (item["is_family"] as? Bool) ?? false
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: normalized),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func parseTranscriptArtifact(at url: URL) -> String? {
        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let segments = root["segments"] as? [[String: Any]]
        else { return nil }

        let sorted = segments.sorted {
            let ls = ($0["start"] as? NSNumber)?.doubleValue ?? 0
            let rs = ($1["start"] as? NSNumber)?.doubleValue ?? 0
            if ls != rs { return ls < rs }
            let le = ($0["end"] as? NSNumber)?.doubleValue ?? 0
            let re = ($1["end"] as? NSNumber)?.doubleValue ?? 0
            return le < re
        }

        let lines: [String] = sorted.compactMap { segment in
            let text = ((segment["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let speaker = ((segment["speaker"] as? String) ?? "SPEAKER_1").trimmingCharacters(in: .whitespacesAndNewlines)
            let start = numberValue(segment["start"]).doubleValue
            let end = numberValue(segment["end"]).doubleValue
            return "[\(fmtTS(start)) -> \(fmtTS(end))] \(speaker): \(text)"
        }
        let transcript = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? nil : transcript
    }

    private func loadTranscriptJSON(at url: URL) -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return root
    }

    private func remapTranscriptSegments(in root: [String: Any], assignments: [String: String]) -> [[String: Any]] {
        let rawSegments = (root["segments"] as? [[String: Any]]) ?? []
        return rawSegments.map { segment in
            var updated = segment
            let speaker = ((segment["speaker"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let mapped = assignments[speaker], !mapped.isEmpty {
                updated["speaker"] = mapped
            }
            return updated
        }
    }

    private func renderTranscript(from segments: [[String: Any]]) -> String? {
        let sorted = segments.sorted {
            let ls = numberValue($0["start"]).doubleValue
            let rs = numberValue($1["start"]).doubleValue
            if ls != rs { return ls < rs }
            let le = numberValue($0["end"]).doubleValue
            let re = numberValue($1["end"]).doubleValue
            return le < re
        }
        let lines = sorted.compactMap { segment -> String? in
            let text = ((segment["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let speaker = ((segment["speaker"] as? String) ?? "SPEAKER_1").trimmingCharacters(in: .whitespacesAndNewlines)
            let start = numberValue(segment["start"]).doubleValue
            let end = numberValue(segment["end"]).doubleValue
            return "[\(fmtTS(start)) -> \(fmtTS(end))] \(speaker): \(text)"
        }
        let transcript = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? nil : transcript
    }

    private func inferredJSONRelativePath(audioRelativePath: String) -> String? {
        let trimmed = audioRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed as NSString).deletingPathExtension + ".json"
    }

    private func fileTimestampMs(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) else { return nil }
        if let date = values.contentModificationDate ?? values.creationDate {
            return Int64(date.timeIntervalSince1970 * 1000.0)
        }
        return nil
    }

    private func fmtTS(_ sec: Double) -> String {
        let totalMs = Int((sec * 1000.0).rounded())
        let hours = totalMs / 3_600_000
        let minutes = (totalMs / 60_000) % 60
        let seconds = (totalMs / 1000) % 60
        let millis = totalMs % 1000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }

    private func numberValue(_ value: Any?) -> NSNumber {
        if let n = value as? NSNumber { return n }
        if let s = value as? String, let d = Double(s) { return NSNumber(value: d) }
        return NSNumber(value: 0)
    }

    private func resolveICloudDocumentsPath(_ relative: String) -> URL? {
        var rel = relative
        if rel.hasPrefix("/") { rel.removeFirst() }
        guard !rel.isEmpty else { return nil }
        let fm = FileManager.default
        if let root = fm.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal") {
            return root.appendingPathComponent(rel, isDirectory: false)
        }
        if let fallback = fm.url(forUbiquityContainerIdentifier: nil) {
            return fallback.appendingPathComponent(rel, isDirectory: false)
        }
        return nil
    }

    private func audioArtifactExists(audioRelativePath: String) -> Bool {
        guard let url = resolveICloudDocumentsPath(audioRelativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func encodeParticipants(_ participants: [NJMeetingParticipant]) -> String {
        guard let data = try? JSONEncoder().encode(participants),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private func mergeMeetingContext(payloadJSON: String, row: Row, queueTranscription: Bool, requestedState: String? = nil) -> String? {
        guard
            let data = payloadJSON.data(using: .utf8),
            let rootAny = try? JSONSerialization.jsonObject(with: data),
            var root = rootAny as? [String: Any]
        else { return nil }

        var sections = (root["sections"] as? [String: Any]) ?? [:]
        var audio = (sections["audio"] as? [String: Any]) ?? ["v": 1, "data": [:]]
        var audioData = (audio["data"] as? [String: Any]) ?? [:]
        audioData["meeting_recorded_at_ms"] = row.meetingRecordedAtMs > 0 ? row.meetingRecordedAtMs : row.createdAtMs
        audioData["meeting_location_txt"] = row.meetingLocation
        audioData["meeting_topic_txt"] = row.meetingTopic
        audioData["meeting_persons_json"] = encodeParticipants(row.meetingParticipants)
        audioData["meeting_language_mode"] = row.languageMode
        audioData["meeting_context_complete"] = row.meetingContextReady ? 1 : 0
        audioData["meeting_context_path"] = NJMeetingContextStore.sidecarRelativePath(audioRelativePath: row.audioPath)
        audioData["transcript_state"] = requestedState ?? (queueTranscription ? "queued" : (row.meetingContextReady ? "ready" : "needs_details"))
        audioData["transcript_requested_ms"] = queueTranscription ? DBNoteRepository.nowMs() : row.transcriptRequestedAtMs
        if queueTranscription {
            audioData["transcript_error_txt"] = ""
        } else if requestedState == "waiting_for_audio_upload" {
            audioData["transcript_error_txt"] = "Audio has not finished landing in iCloud yet."
        }
        audio["data"] = audioData
        sections["audio"] = audio
        root["sections"] = sections

        guard let out = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: out, encoding: .utf8) else { return nil }
        return text
    }

    private func extractJSONPath(from payloadJSON: String) -> String? {
        guard
            let data = payloadJSON.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["sections"] as? [String: Any],
            let audio = sections["audio"] as? [String: Any],
            let audioData = audio["data"] as? [String: Any]
        else { return nil }
        let jsonPath = ((audioData["json_path"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return jsonPath.isEmpty ? nil : jsonPath
    }

    private func mergeSpeakerAssignments(
        payloadJSON: String,
        transcript: String,
        jsonRel: String,
        assignments: [String: String],
        participants: [NJMeetingParticipant]
    ) -> String? {
        guard
            let data = payloadJSON.data(using: .utf8),
            let rootAny = try? JSONSerialization.jsonObject(with: data),
            var root = rootAny as? [String: Any]
        else { return nil }

        var sections = (root["sections"] as? [String: Any]) ?? [:]
        var audio = (sections["audio"] as? [String: Any]) ?? ["v": 1, "data": [:]]
        var audioData = (audio["data"] as? [String: Any]) ?? [:]
        let now = DBNoteRepository.nowMs()
        let participantsByName = Dictionary(uniqueKeysWithValues: participants.map {
            ($0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0)
        })
        let manualAssignments = assignments.keys.sorted().compactMap { speakerLabel -> NJManualSpeakerAssignmentPayload? in
            let cleanSpeakerLabel = speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = assignments[speakerLabel]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cleanSpeakerLabel.isEmpty, !displayName.isEmpty else { return nil }
            let participant = participantsByName[displayName.lowercased()]
            return NJManualSpeakerAssignmentPayload(
                speakerLabel: cleanSpeakerLabel,
                personID: participant?.personID,
                displayName: displayName,
                assignedAtMs: now
            )
        }
        audioData["json_path"] = jsonRel
        audioData["transcript_txt"] = transcript
        audioData["summary_title"] = ""
        audioData["summary_txt"] = ""
        audioData["summary_updated_ms"] = NSNumber(value: 0)
        audioData["pdf_format"] = 0
        audioData["transcript_state"] = "queued"
        audioData["transcript_requested_ms"] = now
        audioData["transcript_error_txt"] = ""
        audioData["transcript_state_updated_ms"] = now
        if let assignmentsData = try? JSONEncoder().encode(manualAssignments),
           let assignmentsText = String(data: assignmentsData, encoding: .utf8) {
            audioData["manual_speaker_assignments_json"] = assignmentsText
            audioData["manual_speaker_assignments_updated_ms"] = now
        }
        audio["data"] = audioData
        sections["audio"] = audio
        root["sections"] = sections

        guard let out = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: out, encoding: .utf8) else { return nil }
        return text
    }
}

private struct NJMeetingResultSheet: View {
    @Environment(\.dismiss) private var dismiss

    let row: NJMeetingInboxView.Row
    let onEditDetails: () -> Void
    let onApplySpeakerAssignments: ([String: String]) -> Void

    @State private var speakerAssignments: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.title.isEmpty ? "(untitled audio)" : row.title)
                            .font(.title3.weight(.semibold))
                        Button(action: onEditDetails) {
                            Text(formattedRecordingDate(row.meetingRecordedAtMs > 0 ? row.meetingRecordedAtMs : row.createdAtMs))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if !row.meetingParticipants.isEmpty || !row.meetingLocation.isEmpty || !row.meetingTopic.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if !row.meetingParticipants.isEmpty {
                                labeledValue("Participants", row.meetingParticipants.map(\.displayName).joined(separator: ", "))
                            }
                            if !row.meetingLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                labeledValue("Location", row.meetingLocation)
                            }
                            if !row.meetingTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                labeledValue("Topic", row.meetingTopic)
                            }
                            labeledValue("Language", languageLabel(for: row.languageMode))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.headline)
                        if !row.summaryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(row.summaryTitle)
                                .font(.subheadline.weight(.semibold))
                        }
                        if !row.summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(row.summaryText)
                                .textSelection(.enabled)
                        } else {
                            Text("Summary not available yet.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcript")
                            .font(.headline)
                        if row.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Transcript not available yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(row.transcript)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }

                    if !unresolvedSpeakerLabels.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Resolve Speakers")
                                .font(.headline)
                            if row.meetingParticipants.isEmpty {
                                Text("Add meeting participants first, then come back here to map unresolved speaker labels.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Assign each unresolved speaker label. We’ll update the transcript now and requeue PDF + summary regeneration with the corrected names.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(unresolvedSpeakerLabels, id: \.self) { label in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(label)
                                            .font(.subheadline.weight(.semibold))
                                        Picker(label, selection: binding(for: label)) {
                                            Text("Select person").tag("")
                                            ForEach(row.meetingParticipants) { participant in
                                                Text(participant.displayName).tag(participant.displayName)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }
                                }
                                Button("Apply Speaker Names") {
                                    onApplySpeakerAssignments(speakerAssignments)
                                }
                                .disabled(!canApplySpeakerAssignments)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Meeting Result")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { onEditDetails() }
                }
            }
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func formattedRecordingDate(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func languageLabel(for mode: String) -> String {
        switch mode.lowercased() {
        case "zh":
            return "Chinese"
        case "en":
            return "English"
        default:
            return "Bilingual"
        }
    }

    private var unresolvedSpeakerLabels: [String] {
        let matches = row.transcript.matches(of: /SPEAKER_\d+/).map { String($0.output) }
        return Array(Set(matches)).sorted()
    }

    private var canApplySpeakerAssignments: Bool {
        guard !unresolvedSpeakerLabels.isEmpty else { return false }
        return unresolvedSpeakerLabels.allSatisfy { label in
            !(speakerAssignments[label] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func binding(for label: String) -> Binding<String> {
        Binding(
            get: { speakerAssignments[label] ?? "" },
            set: { speakerAssignments[label] = $0 }
        )
    }
}

private struct NJMeetingContextEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let row: NJMeetingInboxView.Row
    let onSave: (NJMeetingInboxView.Row, Bool) -> Void

    @State private var location: String
    @State private var topic: String
    @State private var selectedParticipants: [NJMeetingParticipant]
    @State private var availableOptions: [NJMeetingPersonOption]
    @State private var languageMode: String
    @State private var meetingDate: Date
    @State private var showParticipantPicker = false
    @State private var showAddParticipantSheet = false
    @State private var validationMessage: String? = nil
    @State private var pendingTranscribe = false

    init(row: NJMeetingInboxView.Row, onSave: @escaping (NJMeetingInboxView.Row, Bool) -> Void) {
        self.row = row
        self.onSave = onSave
        _location = State(initialValue: row.meetingLocation)
        _topic = State(initialValue: row.meetingTopic)
        _selectedParticipants = State(initialValue: row.meetingParticipants)
        _availableOptions = State(initialValue: NJMeetingParticipantDirectory.allOptions())
        _languageMode = State(initialValue: row.languageMode.isEmpty ? "bilingual" : row.languageMode)
        let seedMs = row.meetingRecordedAtMs > 0 ? row.meetingRecordedAtMs : row.createdAtMs
        _meetingDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(seedMs) / 1000.0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    Text(row.title)
                    DatePicker(
                        "Date & Time",
                        selection: $meetingDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Summary") {
                    if !row.summaryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(row.summaryTitle)
                            .font(.headline)
                    }
                    if !row.summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(row.summaryText)
                            .textSelection(.enabled)
                    } else {
                        Text("Summary not available yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !row.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Transcript") {
                        ScrollView {
                            Text(row.transcript)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 180, maxHeight: 320)
                    }
                }

                Section("Meeting Details") {
                    TextField("Location", text: $location)
                    TextField("Topic", text: $topic, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Language", selection: $languageMode) {
                        Text("Bilingual").tag("bilingual")
                        Text("Chinese").tag("zh")
                        Text("English").tag("en")
                    }
                }

                Section("Participants") {
                    if selectedParticipants.isEmpty {
                        Text("No participants selected yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(selectedParticipants) { participant in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(participant.displayName)
                                    if !participant.role.isEmpty {
                                        Text(participant.role)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    selectedParticipants.removeAll { $0.id == participant.id }
                                }
                            }
                        }
                    }

                    Button("Add Participant") {
                        availableOptions = NJMeetingParticipantDirectory.allOptions()
                        showParticipantPicker = true
                    }

                    Button("Add New Person") {
                        showAddParticipantSheet = true
                    }
                }

                Section("Actions") {
                    Button("Save Meeting Details") {
                        guard validateForSave() else { return }
                        onSave(updatedRow(), false)
                        dismiss()
                    }

                    Button("Send for Transcribe") {
                        guard validateForSave() else { return }
                        pendingTranscribe = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Meeting Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Missing Meeting Information", isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button("OK", role: .cancel) { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "")
            }
            .confirmationDialog(
                "Send this meeting for transcription now?",
                isPresented: $pendingTranscribe,
                titleVisibility: .visible
            ) {
                Button("Send for Transcribe") {
                    onSave(updatedRow(), true)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    pendingTranscribe = false
                }
            } message: {
                Text("We’ll save the meeting details first, then queue this recording for transcription.")
            }
            .sheet(isPresented: $showParticipantPicker) {
                NavigationStack {
                    List {
                        ForEach(availableOptions) { option in
                            Button {
                                appendParticipant(option)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.displayName)
                                        if !option.role.isEmpty {
                                            Text(option.role)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selectedParticipants.contains(where: { $0.personID == option.personID }) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .navigationTitle("Pick Participant")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showParticipantPicker = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddParticipantSheet, onDismiss: {
                availableOptions = NJMeetingParticipantDirectory.allOptions()
            }) {
                NJNewMeetingParticipantSheet { option in
                    availableOptions = NJMeetingParticipantDirectory.allOptions()
                    appendParticipant(option)
                }
            }
        }
    }

    private func validateForSave() -> Bool {
        if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = "Location is required before saving or transcribing."
            return false
        }
        if topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = "Topic is required before saving or transcribing."
            return false
        }
        if selectedParticipants.isEmpty {
            validationMessage = "Add at least one participant before saving or transcribing."
            return false
        }
        validationMessage = nil
        return true
    }

    private func appendParticipant(_ option: NJMeetingPersonOption) {
        guard !selectedParticipants.contains(where: { $0.personID == option.personID }) else {
            showParticipantPicker = false
            return
        }
        selectedParticipants.append(
            NJMeetingParticipant(
                personID: option.personID,
                displayName: option.displayName,
                role: option.role,
                isFamily: option.isFamily
            )
        )
        showParticipantPicker = false
    }

    private func updatedRow() -> NJMeetingInboxView.Row {
        NJMeetingInboxView.Row(
            id: row.id,
            createdAtMs: row.createdAtMs,
            title: row.title,
            audioPath: row.audioPath,
            transcript: row.transcript,
            meetingRecordedAtMs: Int64(meetingDate.timeIntervalSince1970 * 1000.0),
            meetingLocation: location.trimmingCharacters(in: .whitespacesAndNewlines),
            meetingTopic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
            meetingParticipants: selectedParticipants,
            summaryTitle: row.summaryTitle,
            summaryText: row.summaryText,
            languageMode: languageMode,
            transcriptState: row.transcriptState,
            transcriptRequestedAtMs: row.transcriptRequestedAtMs,
            transcriptErrorText: row.transcriptErrorText
        )
    }

    private func formattedRecordingDate(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct NJNewMeetingParticipantSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (NJMeetingPersonOption) -> Void

    @State private var name: String = ""
    @State private var role: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Role", text: $role, axis: .vertical)
                    .lineLimit(1...3)
            }
            .navigationTitle("Add Participant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let option = NJMeetingParticipantDirectory.add(
                            displayName: name,
                            role: role
                        ) {
                            onSave(option)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
