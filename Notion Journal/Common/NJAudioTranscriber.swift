import Foundation

final class NJAudioTranscriber {

    static func runRepairPass(store: AppStore, limit: Int = 12) async -> Int {
        #if os(macOS) || targetEnvironment(macCatalyst)
        let rows = await MainActor.run {
            store.notes.listAudioBlocks(limit: max(20, limit * 4))
        }
        if rows.isEmpty { return 0 }

        var repaired = 0
        for row in rows {
            if repaired >= limit { break }
            guard let updated = repairedPayloadJSON(payloadJSON: row.payloadJSON) else { continue }
            await MainActor.run {
                store.notes.updateBlockPayloadJSON(blockID: row.id, payloadJSON: updated, updatedAtMs: DBNoteRepository.nowMs())
                store.sync.schedulePush(debounceMs: 0)
            }
            repaired += 1
        }
        return repaired
        #else
        _ = store
        return 0
        #endif
    }

    static func runOnce(store: AppStore, limit: Int = 3) async -> Int {
        #if os(macOS) || targetEnvironment(macCatalyst)
        let rows = await MainActor.run {
            store.notes.listAudioBlocks(limit: max(10, limit * 4))
        }
        if rows.isEmpty { return 0 }

        var picked = 0
        for r in rows {
            if picked >= limit { break }
            if !needsTranscript(payloadJSON: r.payloadJSON) { continue }
            let transcribing = markTranscriptState(payloadJSON: r.payloadJSON, state: "transcribing", errorText: nil, requestedAtMs: nil, updatedAtMs: DBNoteRepository.nowMs())
            await MainActor.run {
                store.notes.updateBlockPayloadJSON(blockID: r.id, payloadJSON: transcribing, updatedAtMs: DBNoteRepository.nowMs())
                store.sync.schedulePush(debounceMs: 0)
            }
            if let updated = await transcribeOne(blockID: r.id, payloadJSON: r.payloadJSON) {
                await MainActor.run {
                    store.notes.updateBlockPayloadJSON(blockID: r.id, payloadJSON: updated, updatedAtMs: DBNoteRepository.nowMs())
                    store.sync.schedulePush(debounceMs: 0)
                }
            } else {
                let failed = markTranscriptState(payloadJSON: r.payloadJSON, state: "failed", errorText: "transcribe_failed", requestedAtMs: nil, updatedAtMs: DBNoteRepository.nowMs())
                await MainActor.run {
                    store.notes.updateBlockPayloadJSON(blockID: r.id, payloadJSON: failed, updatedAtMs: DBNoteRepository.nowMs())
                    store.sync.schedulePush(debounceMs: 0)
                }
            }
            picked += 1
        }
        return picked
        #else
        _ = store
        return 0
        #endif
    }

    #if os(macOS) || targetEnvironment(macCatalyst)
    private static func transcribeOne(blockID: String, payloadJSON: String) async -> String? {
        guard let audioRel = extractAudioPath(from: payloadJSON), !audioRel.isEmpty else {
            print("NJ_AUDIO_TRANSCRIBE missing_audio_path blockID=\(blockID)")
            return nil
        }

        guard let meetingContext = extractMeetingContext(from: payloadJSON, audioRelativePath: audioRel) else {
            print("NJ_AUDIO_TRANSCRIBE waiting_for_context blockID=\(blockID)")
            return nil
        }

        guard let audioURL = resolveICloudDocumentsPath(audioRel) else {
            print("NJ_AUDIO_TRANSCRIBE resolve_audio_failed blockID=\(blockID) rel=\(audioRel)")
            return nil
        }

        if !waitForICloudFile(audioURL, maxWaitSeconds: 12.0) {
            print("NJ_AUDIO_TRANSCRIBE audio_not_ready blockID=\(blockID) url=\(audioURL.path)")
            return nil
        }

        guard let scriptURL = ensureDualpassScript() else {
            print("NJ_AUDIO_TRANSCRIBE script_missing blockID=\(blockID)")
            return nil
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nj_transcribe_\(blockID).txt", isDirectory: false)

        let languageMode = extractLanguageMode(from: payloadJSON)

        if !runDualpass(scriptURL: scriptURL, audioURL: audioURL, outURL: outURL, languageMode: languageMode) {
            print("NJ_AUDIO_TRANSCRIBE run_failed blockID=\(blockID)")
            return nil
        }

        guard let transcript = parseTranscript(from: outURL), !transcript.isEmpty else {
            print("NJ_AUDIO_TRANSCRIBE transcript_empty blockID=\(blockID)")
            return nil
        }

        let audioTitle = extractAudioTitle(from: payloadJSON)
        let summary = await summarizeTranscript(title: audioTitle, transcript: transcript, meetingContext: meetingContext)

        let updated = mergeTranscript(
            payloadJSON: payloadJSON,
            transcript: transcript,
            updatedAtMs: DBNoteRepository.nowMs(),
            audioTitle: audioTitle,
            summaryTitle: summary?.title,
            summaryText: summary?.summary,
            meetingContext: meetingContext
        )
        print("NJ_AUDIO_TRANSCRIBE done blockID=\(blockID) chars=\(transcript.count)")
        return updated
    }

    private static func extractAudioPath(from payload: String) -> String? {
        guard
            let data = payload.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["sections"] as? [String: Any],
            let audio = sections["audio"] as? [String: Any],
            let audioData = audio["data"] as? [String: Any]
        else { return nil }
        return (audioData["audio_path"] as? String) ?? ""
    }

    private static func needsTranscript(payloadJSON: String) -> Bool {
        guard
            let data = payloadJSON.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["sections"] as? [String: Any],
            let audio = sections["audio"] as? [String: Any],
            let audioData = audio["data"] as? [String: Any]
        else { return false }

        let existing = (audioData["transcript_txt"] as? String) ?? ""
        guard existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let state = ((audioData["transcript_state"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !(state.isEmpty || state == "queued" || state == "transcribing" || state == "failed") {
            return false
        }
        let location = ((audioData["meeting_location_txt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = ((audioData["meeting_topic_txt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let personsJSON = ((audioData["meeting_persons_json"] as? String) ?? "[]").trimmingCharacters(in: .whitespacesAndNewlines)
        let people = decodeParticipants(from: personsJSON)
        return !location.isEmpty && !topic.isEmpty && !people.isEmpty
    }

    private static func resolveICloudDocumentsPath(_ relative: String) -> URL? {
        var rel = relative
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { return nil }

        let fm = FileManager.default

        if let root = fm.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal") {
            return root.appendingPathComponent(rel)
        }

        if let root2 = fm.url(forUbiquityContainerIdentifier: nil) {
            return root2.appendingPathComponent(rel)
        }

        return nil
    }

    private static func waitForICloudFile(_ u: URL, maxWaitSeconds: Double) -> Bool {
        let fm = FileManager.default
        try? fm.startDownloadingUbiquitousItem(at: u)

        let deadline = Date().timeIntervalSince1970 + maxWaitSeconds

        while Date().timeIntervalSince1970 < deadline {
            if fm.fileExists(atPath: u.path) {
                return true
            }
            if let st = try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus {
                if st == .current { return true }
            }
            usleep(250_000)
        }

        return fm.fileExists(atPath: u.path)
    }

    private static func ensureDualpassScript() -> URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent("NotionJournal", isDirectory: true)
        let script = dir.appendingPathComponent("dualpass.py", isDirectory: false)

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: script.path),
               let existing = try? String(contentsOf: script, encoding: .utf8),
               existing == dualpassScriptText {
                return script
            }
            try dualpassScriptText.write(to: script, atomically: true, encoding: .utf8)
            var attrs = try fm.attributesOfItem(atPath: script.path)
            attrs[.posixPermissions] = 0o755
            try fm.setAttributes(attrs, ofItemAtPath: script.path)
            return script
        } catch {
            print("NJ_AUDIO_TRANSCRIBE write_script_failed err=\(error)")
            return nil
        }
    }

    private static func runDualpass(scriptURL: URL, audioURL: URL, outURL: URL, languageMode: String) -> Bool {
        let pythonURL = resolvePythonExecutable()
        let task = Process()
        task.executableURL = pythonURL
        task.arguments = [scriptURL.path, audioURL.path, outURL.path, languageMode]

        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { return true }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? ""
            print("NJ_AUDIO_TRANSCRIBE process_failed python=\(pythonURL.path) status=\(task.terminationStatus) msg=\(msg)")
            return false
        } catch {
            print("NJ_AUDIO_TRANSCRIBE process_error python=\(pythonURL.path) err=\(error)")
            return false
        }
    }

    private static func resolvePythonExecutable() -> URL {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            if pythonHasModule(path: path, module: "mlx_whisper") {
                return URL(fileURLWithPath: path)
            }
        }
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }

    private static func pythonHasModule(path: String, module: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["-c", "import \(module)"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func parseTranscript(from url: URL) -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var out: [String] = []
        var started = false

        for lineSub in lines {
            let line = String(lineSub)
            if !started {
                if line.hasPrefix("[") { started = true; out.append(line); continue }
                continue
            }
            out.append(line)
        }

        let joined = out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func mergeTranscript(
        payloadJSON: String,
        transcript: String,
        updatedAtMs: Int64,
        audioTitle: String,
        summaryTitle: String?,
        summaryText: String?,
        meetingContext: NJMeetingContextRecord
    ) -> String {
        guard
            let data = payloadJSON.data(using: .utf8),
            let rootAny = try? JSONSerialization.jsonObject(with: data),
            var root = rootAny as? [String: Any]
        else { return payloadJSON }

        var sections = (root["sections"] as? [String: Any]) ?? [:]

        var audio = (sections["audio"] as? [String: Any]) ?? ["v": 1, "data": [:]]
        var audioData = (audio["data"] as? [String: Any]) ?? [:]
        audioData["transcript_txt"] = transcript
        audioData["transcript_updated_ms"] = updatedAtMs
        audioData["meeting_recorded_at_ms"] = meetingContext.recordedAtMs
        audioData["meeting_location_txt"] = meetingContext.locationText
        audioData["meeting_topic_txt"] = meetingContext.topicText
        audioData["meeting_persons_json"] = encodeParticipants(meetingContext.participants)
        audioData["meeting_context_complete"] = 1
        audioData["summary_title"] = summaryTitle ?? ""
        audioData["summary_txt"] = summaryText ?? ""
        audioData["transcript_state"] = "done"
        audioData["transcript_error_txt"] = ""
        audio["v"] = 1
        audio["data"] = audioData
        sections["audio"] = audio

        var proton1 = (sections["proton1"] as? [String: Any]) ?? ["v": 1, "data": [:]]
        var protonData = (proton1["data"] as? [String: Any]) ?? [:]
        protonData["proton_v"] = 1
        let renderedRTF = NJPayloadConverterV1.makeRTFBase64(
            renderTranscriptDocument(
                audioTitle: audioTitle,
                summaryTitle: summaryTitle,
                summaryText: summaryText,
                transcript: transcript,
                meetingContext: meetingContext
            )
        )
        protonData["proton_json"] = makeRichProtonJSONString(rtfBase64: renderedRTF)
        protonData.removeValue(forKey: "rtf_base64")
        proton1["v"] = 1
        proton1["data"] = protonData
        sections["proton1"] = proton1

        root["sections"] = sections

        if let out = try? JSONSerialization.data(withJSONObject: root),
           let s = String(data: out, encoding: .utf8) {
            return s
        }
        return payloadJSON
    }

    private static func extractAudioTitle(from payload: String) -> String {
        guard
            let data = payload.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["sections"] as? [String: Any],
            let audio = sections["audio"] as? [String: Any],
            let audioData = audio["data"] as? [String: Any]
        else { return "Meeting Recording" }
        return ((audioData["title"] as? String) ?? "Meeting Recording").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMeetingContext(from payload: String, audioRelativePath: String) -> NJMeetingContextRecord? {
        guard
            let data = payload.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["sections"] as? [String: Any],
            let audio = sections["audio"] as? [String: Any],
            let audioData = audio["data"] as? [String: Any]
        else { return nil }

        let recordedAtMs = ((audioData["meeting_recorded_at_ms"] as? NSNumber)?.int64Value)
            ?? ((audioData["recorded_at_ms"] as? NSNumber)?.int64Value)
            ?? DBNoteRepository.nowMs()
        let location = ((audioData["meeting_location_txt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = ((audioData["meeting_topic_txt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let personsJSON = (audioData["meeting_persons_json"] as? String) ?? "[]"
        let participants = decodeParticipants(from: personsJSON)
        guard !location.isEmpty, !topic.isEmpty, !participants.isEmpty else { return nil }
        let stored = NJMeetingContextStore.load(audioRelativePath: audioRelativePath)
        return NJMeetingContextRecord(
            recordingID: stored?.recordingID ?? UUID().uuidString.lowercased(),
            audioRelativePath: audioRelativePath,
            recordedAtMs: stored?.recordedAtMs ?? recordedAtMs,
            locationText: location,
            topicText: topic,
            participants: participants,
            createdAtMs: stored?.createdAtMs ?? DBNoteRepository.nowMs(),
            updatedAtMs: stored?.updatedAtMs ?? DBNoteRepository.nowMs()
        )
    }

    private static func extractLanguageMode(from payload: String) -> String {
        guard
            let data = payload.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["sections"] as? [String: Any],
            let audio = sections["audio"] as? [String: Any],
            let audioData = audio["data"] as? [String: Any]
        else { return "bilingual" }
        let mode = ((audioData["meeting_language_mode"] as? String) ?? "bilingual").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch mode {
        case "zh", "chinese":
            return "zh"
        case "en", "english":
            return "en"
        default:
            return "bilingual"
        }
    }

    private static func markTranscriptState(
        payloadJSON: String,
        state: String,
        errorText: String?,
        requestedAtMs: Int64?,
        updatedAtMs: Int64
    ) -> String {
        guard
            let data = payloadJSON.data(using: .utf8),
            let rootAny = try? JSONSerialization.jsonObject(with: data),
            var root = rootAny as? [String: Any]
        else { return payloadJSON }
        var sections = (root["sections"] as? [String: Any]) ?? [:]
        var audio = (sections["audio"] as? [String: Any]) ?? ["v": 1, "data": [:]]
        var audioData = (audio["data"] as? [String: Any]) ?? [:]
        audioData["transcript_state"] = state
        if let requestedAtMs {
            audioData["transcript_requested_ms"] = requestedAtMs
        }
        audioData["transcript_error_txt"] = errorText ?? ""
        audioData["transcript_state_updated_ms"] = updatedAtMs
        audio["data"] = audioData
        sections["audio"] = audio
        root["sections"] = sections
        guard let out = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: out, encoding: .utf8) else { return payloadJSON }
        return text
    }

    private static func decodeParticipants(from json: String) -> [NJMeetingParticipant] {
        guard let data = json.data(using: .utf8),
              let people = try? JSONDecoder().decode([NJMeetingParticipant].self, from: data) else { return [] }
        return people
    }

    private static func encodeParticipants(_ participants: [NJMeetingParticipant]) -> String {
        guard let data = try? JSONEncoder().encode(participants),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private static func summarizeTranscript(title: String, transcript: String, meetingContext: NJMeetingContextRecord) async -> (title: String?, summary: String?)? {
        let people = meetingContext.participants.map { participant in
            let role = participant.role.trimmingCharacters(in: .whitespacesAndNewlines)
            return role.isEmpty ? participant.displayName : "\(participant.displayName) (\(role))"
        }.joined(separator: ", ")
        let recorded = Date(timeIntervalSince1970: TimeInterval(meetingContext.recordedAtMs) / 1000.0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let prompt = """
        Meeting title hint: \(title)
        Recording time: \(formatter.string(from: recorded))
        Location: \(meetingContext.locationText)
        Topic: \(meetingContext.topicText)
        Participants: \(people)

        Transcript:
        \(transcript)
        """
        let result = await NJAppleIntelligenceSummarizer.summarizeAuto(text: prompt)
        let trimmedSummary = (result.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = (result.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty || !trimmedTitle.isEmpty else { return nil }
        return (trimmedTitle, trimmedSummary)
    }

    private static func repairedPayloadJSON(payloadJSON: String) -> String? {
        guard
            let data = payloadJSON.data(using: .utf8),
            let rootAny = try? JSONSerialization.jsonObject(with: data),
            var root = rootAny as? [String: Any],
            var sections = root["sections"] as? [String: Any],
            var audio = sections["audio"] as? [String: Any],
            var audioData = audio["data"] as? [String: Any]
        else { return nil }

        let transcript = ((audioData["transcript_txt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }

        let audioTitle = ((audioData["title"] as? String) ?? "Audio Recording").trimmingCharacters(in: .whitespacesAndNewlines)
        let audioPath = ((audioData["audio_path"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryTitle = ((audioData["summary_title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryText = ((audioData["summary_txt"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let meetingContext = looseMeetingContext(audioData: audioData, audioRelativePath: audioPath)

        var changed = false
        if ((audioData["transcript_state"] as? String) ?? "").lowercased() != "done" {
            audioData["transcript_state"] = "done"
            changed = true
        }
        if !((audioData["transcript_error_txt"] as? String) ?? "").isEmpty {
            audioData["transcript_error_txt"] = ""
            changed = true
        }
        if meetingContext != nil && (audioData["meeting_context_complete"] as? NSNumber)?.intValue != 1 {
            audioData["meeting_context_complete"] = 1
            changed = true
        }

        let desiredRTF = NJPayloadConverterV1.makeRTFBase64(
            renderTranscriptDocument(
                audioTitle: audioTitle.isEmpty ? "Audio Recording" : audioTitle,
                summaryTitle: summaryTitle.isEmpty ? nil : summaryTitle,
                summaryText: summaryText.isEmpty ? nil : summaryText,
                transcript: transcript,
                meetingContext: meetingContext
            )
        )
        let desiredProtonJSON = makeRichProtonJSONString(rtfBase64: desiredRTF)

        var proton1 = (sections["proton1"] as? [String: Any]) ?? ["v": 1, "data": [:]]
        var protonData = (proton1["data"] as? [String: Any]) ?? [:]
        if (protonData["proton_v"] as? NSNumber) == nil {
            protonData["proton_v"] = 1
            changed = true
        }
        if (protonData["proton_json"] as? String) != desiredProtonJSON {
            protonData["proton_json"] = desiredProtonJSON
            changed = true
        }
        if protonData["rtf_base64"] != nil {
            protonData.removeValue(forKey: "rtf_base64")
            changed = true
        }

        guard changed else { return nil }
        audio["data"] = audioData
        sections["audio"] = audio
        proton1["v"] = 1
        proton1["data"] = protonData
        sections["proton1"] = proton1
        root["sections"] = sections
        guard let out = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: out, encoding: .utf8) else { return nil }
        return text
    }

    private static func looseMeetingContext(audioData: [String: Any], audioRelativePath: String) -> NJMeetingContextRecord? {
        let stored = audioRelativePath.isEmpty ? nil : NJMeetingContextStore.load(audioRelativePath: audioRelativePath)
        let recordedAtMs = ((audioData["meeting_recorded_at_ms"] as? NSNumber)?.int64Value)
            ?? ((audioData["recorded_at_ms"] as? NSNumber)?.int64Value)
            ?? stored?.recordedAtMs
            ?? DBNoteRepository.nowMs()
        let location = ((audioData["meeting_location_txt"] as? String) ?? stored?.locationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = ((audioData["meeting_topic_txt"] as? String) ?? stored?.topicText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadParticipants = decodeParticipants(from: (audioData["meeting_persons_json"] as? String) ?? "[]")
        let participants = payloadParticipants.isEmpty ? (stored?.participants ?? []) : payloadParticipants

        if location.isEmpty && topic.isEmpty && participants.isEmpty && stored == nil {
            return nil
        }

        return NJMeetingContextRecord(
            recordingID: stored?.recordingID ?? UUID().uuidString.lowercased(),
            audioRelativePath: audioRelativePath,
            recordedAtMs: recordedAtMs,
            locationText: location,
            topicText: topic,
            participants: participants,
            createdAtMs: stored?.createdAtMs ?? DBNoteRepository.nowMs(),
            updatedAtMs: stored?.updatedAtMs ?? DBNoteRepository.nowMs()
        )
    }

    private static func makeRichProtonJSONString(rtfBase64: String) -> String {
        let root: [String: Any] = [
            "schema": "nj_proton_doc_v2",
            "doc": [
                [
                    "type": "rich",
                    "rtf_base64": rtfBase64
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    private static func renderTranscriptDocument(
        audioTitle: String,
        summaryTitle: String?,
        summaryText: String?,
        transcript: String,
        meetingContext: NJMeetingContextRecord?
    ) -> String {
        var lines: [String] = []
        let title = audioTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(title.isEmpty ? "Audio Recording" : title)
        let header = (summaryTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !header.isEmpty && header != title {
            lines.append(header)
        }
        let topic = meetingContext?.topicText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !topic.isEmpty {
            lines.append("Topic: \(topic)")
        }
        let location = meetingContext?.locationText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !location.isEmpty {
            lines.append("Location: \(location)")
        }
        let people = (meetingContext?.participants ?? []).map { participant in
            let role = participant.role.trimmingCharacters(in: .whitespacesAndNewlines)
            return role.isEmpty ? participant.displayName : "\(participant.displayName) (\(role))"
        }.joined(separator: ", ")
        if !people.isEmpty {
            lines.append("Participants: \(people)")
        }
        lines.append("")
        lines.append("Summary")
        let summary = (summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty {
            lines.append("Summary pending.")
        } else {
            lines.append(summary)
        }
        _ = transcript
        return lines.joined(separator: "\n")
    }

    private static let dualpassScriptText = #"""
from pathlib import Path
import subprocess, tempfile, sys, re
import mlx_whisper

CJK_RE = re.compile(r"[\u4e00-\u9fff]")
LATIN_RE = re.compile(r"[A-Za-z]")

def fmt_ts(sec: float) -> str:
    ms = int(round(sec * 1000))
    h = ms // 3600000
    ms -= h * 3600000
    m = ms // 60000
    ms -= m * 60000
    s = ms // 1000
    ms -= s * 1000
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"

def probe_duration_sec(path: Path) -> float:
    cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(path)]
    out = subprocess.check_output(cmd).decode("utf-8").strip()
    return float(out)

def make_wav_chunk(src: Path, start: float, dur: float, out_wav: Path):
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error",
        "-ss", f"{start:.3f}", "-t", f"{dur:.3f}",
        "-i", str(src),
        "-vn", "-ac", "1", "-ar", "16000",
        "-y", str(out_wav)
    ]
    subprocess.run(cmd, check=True)

def pick_text(seg_text: str, want: str) -> str:
    t = (seg_text or "").strip()
    if not t:
        return ""
    if want == "zh":
        return t if CJK_RE.search(t) else ""
    if want == "en":
        return t if LATIN_RE.search(t) else ""
    return t

def transcribe_one(wav_path: Path, model: str, lang: str, prompt: str):
    res = mlx_whisper.transcribe(
        str(wav_path),
        path_or_hf_repo=model,
        language=lang,
        task="transcribe",
        initial_prompt=prompt
    )
    out = []
    for s in res.get("segments", []):
        out.append({
            "start": float(s.get("start", 0.0)),
            "end": float(s.get("end", 0.0)),
            "text": (s.get("text") or "").strip()
        })
    return out

def main():
    if len(sys.argv) < 3:
        print("usage: dualpass.py <audio> <out> [bilingual|zh|en]", file=sys.stderr)
        sys.exit(2)

    audio = Path(sys.argv[1])
    out = Path(sys.argv[2])
    mode = (sys.argv[3] if len(sys.argv) >= 4 else "bilingual").strip().lower()
    if not audio.exists():
        print("missing audio", file=sys.stderr)
        sys.exit(1)

    model = "mlx-community/whisper-small-mlx"
    if mode == "zh":
        prompt = "Mandarin or Chinese audio. Transcribe exactly as spoken. Do NOT translate."
    elif mode == "en":
        prompt = "English audio. Transcribe exactly as spoken."
    else:
        mode = "bilingual"
        prompt = "Bilingual audio in Mandarin Chinese and English. Transcribe exactly as spoken. Do NOT translate."
    chunk_sec = 15.0
    overlap_sec = 1.5

    total = probe_duration_sec(audio)

    with out.open("w", encoding="utf-8") as f:
        f.write(f"file: {audio.name}\n")
        f.write(f"model: {model}\n")
        f.write(f"mode: {mode}\n")
        f.write(f"chunk_sec: {chunk_sec} overlap_sec: {overlap_sec}\n\n")

        t = 0.0
        idx = 0
        while t < total:
            dur = min(chunk_sec, total - t)
            if dur <= 0:
                break

            with tempfile.TemporaryDirectory() as td:
                wav_path = Path(td) / f"chunk_{idx:04d}.wav"
                make_wav_chunk(audio, t, dur, wav_path)

                events = []
                if mode == "zh":
                    zh_segs = transcribe_one(wav_path, model, "zh", prompt)
                    for s in zh_segs:
                        txt = pick_text(s["text"], "zh")
                        if txt:
                            events.append((t + s["start"], t + s["end"], "ZH", txt))
                elif mode == "en":
                    en_segs = transcribe_one(wav_path, model, "en", prompt)
                    for s in en_segs:
                        txt = pick_text(s["text"], "en")
                        if txt:
                            events.append((t + s["start"], t + s["end"], "EN", txt))
                else:
                    zh_segs = transcribe_one(wav_path, model, "zh", prompt)
                    en_segs = transcribe_one(wav_path, model, "en", prompt)
                    for s in zh_segs:
                        txt = pick_text(s["text"], "zh")
                        if txt:
                            events.append((t + s["start"], t + s["end"], "ZH", txt))
                    for s in en_segs:
                        txt = pick_text(s["text"], "en")
                        if txt:
                            events.append((t + s["start"], t + s["end"], "EN", txt))

                events.sort(key=lambda x: (x[0], x[1], x[2]))

                for a, b, tag, txt in events:
                    f.write(f"[{fmt_ts(a)} -> {fmt_ts(b)}] {tag}: {txt}\n")

            t += max(0.1, chunk_sec - overlap_sec)
            idx += 1

if __name__ == "__main__":
    main()
"""#

    #endif
}
