import Foundation

final class NJAudioTranscriber {

    static func runOnce(store: AppStore, limit: Int = 3) async {
        #if os(macOS) || targetEnvironment(macCatalyst)
        let rows = await MainActor.run {
            store.notes.listAudioBlocks(limit: max(10, limit * 4))
        }
        if rows.isEmpty { return }

        var picked = 0
        for r in rows {
            if picked >= limit { break }
            if !needsTranscript(payloadJSON: r.payloadJSON) { continue }
            autoreleasepool {
                if let updated = transcribeOne(blockID: r.id, payloadJSON: r.payloadJSON) {
                    Task { @MainActor in
                        store.notes.updateBlockPayloadJSON(blockID: r.id, payloadJSON: updated, updatedAtMs: DBNoteRepository.nowMs())
                        store.sync.schedulePush(debounceMs: 0)
                    }
                }
            }
            picked += 1
        }
        #else
        _ = store
        #endif
    }

    #if os(macOS) || targetEnvironment(macCatalyst)
    private static func transcribeOne(blockID: String, payloadJSON: String) -> String? {
        guard let audioRel = extractAudioPath(from: payloadJSON), !audioRel.isEmpty else {
            print("NJ_AUDIO_TRANSCRIBE missing_audio_path blockID=\(blockID)")
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

        if !runDualpass(scriptURL: scriptURL, audioURL: audioURL, outURL: outURL) {
            print("NJ_AUDIO_TRANSCRIBE run_failed blockID=\(blockID)")
            return nil
        }

        guard let transcript = parseTranscript(from: outURL), !transcript.isEmpty else {
            print("NJ_AUDIO_TRANSCRIBE transcript_empty blockID=\(blockID)")
            return nil
        }

        let updated = mergeTranscript(
            payloadJSON: payloadJSON,
            transcript: transcript,
            updatedAtMs: DBNoteRepository.nowMs()
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
        return existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

        if fm.fileExists(atPath: script.path) { return script }

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
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

    private static func runDualpass(scriptURL: URL, audioURL: URL, outURL: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["python3", scriptURL.path, audioURL.path, outURL.path]

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
            print("NJ_AUDIO_TRANSCRIBE process_failed status=\(task.terminationStatus) msg=\(msg)")
            return false
        } catch {
            print("NJ_AUDIO_TRANSCRIBE process_error err=\(error)")
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

    private static func mergeTranscript(payloadJSON: String, transcript: String, updatedAtMs: Int64) -> String {
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
        audio["v"] = 1
        audio["data"] = audioData
        sections["audio"] = audio

        var proton1 = (sections["proton1"] as? [String: Any]) ?? ["v": 1, "data": [:]]
        var protonData = (proton1["data"] as? [String: Any]) ?? [:]
        protonData["proton_v"] = 1
        if protonData["proton_json"] == nil { protonData["proton_json"] = "" }
        protonData["rtf_base64"] = NJPayloadConverterV1.makeRTFBase64(transcript)
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
        print("usage: dualpass.py <audio> <out>", file=sys.stderr)
        sys.exit(2)

    audio = Path(sys.argv[1])
    out = Path(sys.argv[2])
    if not audio.exists():
        print("missing audio", file=sys.stderr)
        sys.exit(1)

    model = "mlx-community/whisper-medium"
    prompt = "Bilingual audio in Mandarin Chinese and English. Transcribe exactly as spoken. Do NOT translate."
    chunk_sec = 20.0
    overlap_sec = 2.0

    total = probe_duration_sec(audio)

    with out.open("w", encoding="utf-8") as f:
        f.write(f"file: {audio.name}\n")
        f.write(f"model: {model}\n")
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

                zh_segs = transcribe_one(wav_path, model, "zh", prompt)
                en_segs = transcribe_one(wav_path, model, "en", prompt)

                events = []
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
