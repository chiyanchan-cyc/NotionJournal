#!/usr/bin/env python3

import base64
import json
import sqlite3
import textwrap
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path


DB_PATH = Path("/Users/mac/Library/Containers/FA955BEC-40DE-460A-84C5-691E7BAB14F9/Data/Documents/notion_journal.sqlite")
SOURCE_ROOT = Path("/Users/mac/Library/Mobile Documents/iCloud~com~CYC~NotionJournal/Documents/2026/04/codex")
NOTE_TITLE = "20260428 Codex Summary"
NOTE_DATE = "2026-04-28"
NOTEBOOK = "Me"
TAB_DOMAIN = "Dev"
PRIMARY_DOMAIN = "me.dev"
DELETE_TITLES = ["(20260428) Codex Summary", "20260428 Codex Summary"]

SESSION_ROOT = Path("/Users/mac/.codex/sessions/2026/04/28")
LOCAL_TZ = timezone(timedelta(hours=8))
DAY_START_LOCAL = datetime(2026, 4, 28, 0, 0, 0, tzinfo=LOCAL_TZ)
DAY_END_LOCAL = datetime(2026, 4, 29, 0, 0, 0, tzinfo=LOCAL_TZ)
DAY_START_MS = int(DAY_START_LOCAL.timestamp() * 1000)
DAY_END_MS = int(DAY_END_LOCAL.timestamp() * 1000)

BLOCKS = [
    {
        "topic": "Notion Journal: hardened the rich-text persistence pipeline so cross-device stale saves stop flattening or overwriting structured Proton content",
        "timeslot_title": "Codex: Proton V2 save hardening",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-28T11-11-30-019dd212-0993-76f2-890f-06b4b92ede81.jsonl",
        "request": "Audit the entire note-editor save pipeline, find the real overwrite and v1/v2 downgrade bugs, then patch the system cleanly so multiple devices stop flattening or reverting live blocks.",
        "summary": (
            "This was the major engineering thread of the day. "
            "We traced the overwrite problem through stale-save guards, live editor hydration, duplicate editor handles, passive snapshots, fallback RTF precedence, and mixed Proton schema paths. From there the work moved from analysis into a full persistence cleanup: active editors stopped accepting remote hydrates, stale devices lost the ability to save over newer DB versions without verified local edits, new content normalized to Proton V2, top-level fallback RTF stopped acting as a second source of truth, legacy V1 payloads were migrated, and the local database was normalized so CloudKit would push the repaired format forward."
        ),
        "outcome": (
            "The practical result is that Notion Journal now has a much stricter write model for structured blocks. The dangerous path where an idle or stale device could flatten a section-bearing block back into plain rich text was explicitly targeted instead of being treated as a vague sync issue."
        ),
        "files": [
            "Notion Journal/Notes/NoteEditor/NJNoteEditorContainerPersistence.swift",
            "Notion Journal/Notes/NoteEditor/Rescontruct/NJReconstructedNotePersistence.swift",
            "Notion Journal/Proton/NJProtonEditorBridge.swift",
            "Notion Journal/NJPayloadSchema.swift",
            "Notion Journal/DB/DBBlockPayloadStore.swift",
            "Notion Journal/DB/DBBlockTable.swift",
            "Notion Journal/Common/NJQuickNotePayload.swift",
            "Notion Journal/Common/NJAudioTranscriber.swift",
        ],
    },
    {
        "topic": "LLMJournal: removed the worst save/reload latency in weekly goals by cutting redundant CloudKit work",
        "timeslot_title": "Codex: Weekly goal save latency",
        "domains": ["me.dev", "dev.llm"],
        "repo": "LLMJournal",
        "session_file": "rollout-2026-04-28T12-42-59-019dd265-cb3d-7580-8242-b7a719651351.jsonl",
        "request": "Find out why weekly goal loading and saving feels extremely slow in LLMJournal and patch the hot path instead of just describing it.",
        "summary": (
            "We isolated the lag to avoidable CloudKit churn in the weekly-goal flow. "
            "Saving a single goal was doing a pre-fetch, a save, a full reload of all weekly goals, and repeated progress recomputation. The fix made saves update local state immediately, skip the pre-fetch, prevent duplicate taps, and avoid recomputing progress twice when CloudKit returned data identical to the cache."
        ),
        "outcome": (
            "That converted the weekly-goal editor from a round-trip-heavy path into a much tighter local-first save flow, which should remove the most visible 'this takes forever' behavior without changing the feature itself."
        ),
        "files": [
            "journal/LLMJournal/WeeklyReview/WeeklyGoalSettingView.swift",
        ],
    },
    {
        "topic": "Notion Journal: stopped several launch-time resurrection and schema loops that were making startup noisy and expensive",
        "timeslot_title": "Codex: Startup loop cleanup",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-28T19-43-25-019dd3e6-b4ae-7240-99e6-bdf1fc106d5d.jsonl",
        "request": "Fix the bad launch loop where old clipboard or audio material can come back and repeated startup work keeps happening even when the content is already ingested or the schema is not deployed.",
        "summary": (
            "This thread focused on launch-time cleanup rather than editor persistence. "
            "We made clip and audio ingestors delete stale inbox folders once their content was already archived or already exists as a live block, gated the expensive payload migration behind a real legacy-data check instead of scanning everything every launch, and stopped querying CloudKit record types that are not actually deployed yet."
        ),
        "outcome": (
            "The effect is a cleaner startup path with fewer pointless launch-time loops, less resurrection of already-handled inbox content, and less noise from unavailable CloudKit schema."
        ),
        "files": [
            "Notion Journal/Common/NJClipIngestor.swift",
            "Notion Journal/Common/NJAudioIngestor.swift",
            "Notion Journal/DB/DBNoteRepository.swift",
            "Notion Journal/Sync/NJCloudSchema.swift",
        ],
    },
    {
        "topic": "Notion Journal: trimmed no-op startup churn by making snapshot seeds and personal-ID generation idempotent",
        "timeslot_title": "Codex: Startup no-op sync fixes",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-28T19-47-54-019dd3ea-d0c8-7753-b88e-548b4809c1e9.jsonl",
        "request": "Look into why startup still feels slow and stop the app from re-dirtying and pushing the same finance and personal-ID records on every launch.",
        "summary": (
            "After the broader launch-loop cleanup, we tightened the remaining no-op write paths. "
            "The US market snapshot seed now inserts only missing rows, the generated personal-ID note blocks skip rewrites when they already match, and the parent personal-identification note avoids being touched when nothing changed. This directly targets the repeated dirty-queue churn that was making startup look like real sync work even when the app was mostly doing self-inflicted rewrites."
        ),
        "outcome": (
            "Startup should now spend less time manufacturing fake sync work. Any remaining first-launch delay is more likely to be real queued rows from older builds rather than repeated local reseeding."
        ),
        "files": [
            "Notion Journal/AppStore.swift",
            "Notion Journal/DB/DBNoteRepository.swift",
        ],
    },
]


def new_uuid() -> str:
    return str(uuid.uuid4())


def parse_iso_ms(value: str) -> int:
    return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)


def pdf_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def rtf_escape(text: str) -> str:
    out = []
    for ch in text:
        code = ord(ch)
        if ch == "\\":
            out.append(r"\\")
        elif ch == "{":
            out.append(r"\{")
        elif ch == "}":
            out.append(r"\}")
        elif ch == "\n":
            out.append(r"\par " + "\n")
        elif 32 <= code <= 126:
            out.append(ch)
        else:
            signed = code if code < 32768 else code - 65536
            out.append(rf"\u{signed}?")
    return "".join(out)


def make_rtf_base64(plain_text: str) -> str:
    rtf = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 " + rtf_escape(plain_text) + "}"
    return base64.b64encode(rtf.encode("utf-8")).decode("ascii")


def write_minimal_text_pdf(path: Path, title: str, body: str) -> None:
    lines = [title, ""] + body.splitlines()
    content_lines = ["BT", "/F1 11 Tf", "50 770 Td", "14 TL"]
    first = True
    for raw_line in lines:
        line = raw_line if raw_line else " "
        wrapped = textwrap.wrap(line, width=92) or [" "]
        for segment in wrapped:
            if first:
                content_lines.append(f"({pdf_escape(segment)}) Tj")
                first = False
            else:
                content_lines.append(f"T* ({pdf_escape(segment)}) Tj")
    content_lines.append("ET")
    stream = "\n".join(content_lines).encode("latin-1", errors="replace")
    objects = []
    objects.append(b"1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n")
    objects.append(b"2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n")
    objects.append(b"3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj\n")
    objects.append(b"4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n")
    objects.append(f"5 0 obj << /Length {len(stream)} >> stream\n".encode("latin-1") + stream + b"\nendstream endobj\n")
    out = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for obj in objects:
        offsets.append(len(out))
        out.extend(obj)
    xref_start = len(out)
    out.extend(f"xref\n0 {len(offsets)}\n".encode("latin-1"))
    out.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        out.extend(f"{offset:010d} 00000 n \n".encode("latin-1"))
    out.extend(f"trailer << /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref_start}\n%%EOF\n".encode("latin-1"))
    path.write_bytes(out)


def session_snapshot(session_file: str) -> dict:
    path = SESSION_ROOT / session_file
    start_ms = 0
    end_ms = 0
    user_times = []
    cwd = ""
    first_user = ""
    final_message = ""
    ts_ms = 0
    for raw_line in path.open(encoding="utf-8"):
        obj = json.loads(raw_line)
        timestamp = obj.get("timestamp")
        if timestamp:
            ts_ms = parse_iso_ms(timestamp)
            if DAY_START_MS <= ts_ms < DAY_END_MS:
                if start_ms == 0 or ts_ms < start_ms:
                    start_ms = ts_ms
                if ts_ms > end_ms:
                    end_ms = ts_ms
        if obj.get("type") == "session_meta":
            cwd = (obj.get("payload") or {}).get("cwd", cwd)
        payload = obj.get("payload") or {}
        if payload.get("type") == "user_message" and timestamp and DAY_START_MS <= ts_ms < DAY_END_MS and not first_user:
            msg = (payload.get("message") or "").strip()
            if msg:
                first_user = " ".join(msg.split())
        if payload.get("type") == "user_message" and timestamp and DAY_START_MS <= ts_ms < DAY_END_MS:
            user_times.append(ts_ms)
        if payload.get("type") == "task_complete":
            msg = (payload.get("last_agent_message") or "").strip()
            if msg:
                final_message = " ".join(msg.split())
    prompt_ranges = []
    if user_times:
        burst_start = user_times[0]
        burst_end = user_times[0]
        gap_ms = 30 * 60 * 1000
        min_burst_ms = 5 * 60 * 1000
        for ts in user_times[1:]:
            if ts - burst_end <= gap_ms:
                burst_end = ts
            else:
                prompt_ranges.append((burst_start, max(burst_end, burst_start + min_burst_ms)))
                burst_start = ts
                burst_end = ts
        prompt_ranges.append((burst_start, max(burst_end, burst_start + min_burst_ms)))
    else:
        fallback_start = start_ms or DAY_START_MS
        fallback_end = end_ms or fallback_start
        if fallback_end <= fallback_start:
            fallback_end = fallback_start + 5 * 60 * 1000
        prompt_ranges.append((fallback_start, fallback_end))
    return {
        "path": str(path),
        "cwd": cwd,
        "start_ms": start_ms or prompt_ranges[0][0],
        "end_ms": end_ms or prompt_ranges[-1][1],
        "prompt_ranges": prompt_ranges,
        "first_user": first_user,
        "final_message": final_message,
    }


def render_visible_text(block: dict, rel_pdf: str, rel_txt: str, rel_json: str) -> str:
    lines = [
        block["topic"], "", "What We Did", block["summary"], "", "Outcome", block["outcome"], "", "Request", block["request"]
    ]
    if block.get("files"):
        lines.extend(["", "Files"])
        lines.extend(f"- {item}" for item in block["files"])
    lines.extend(["", "Source", f"- PDF: {rel_pdf}", f"- Text: {rel_txt}", f"- JSON: {rel_json}"])
    return "\n".join(lines).strip()


def make_payload(block: dict, snapshot: dict, rel_pdf: str, rel_txt: str, rel_json: str) -> str:
    visible_text = render_visible_text(block, rel_pdf, rel_txt, rel_json)
    payload = {
        "v": 1,
        "sections": {
            "proton1": {"v": 1, "data": {"proton_v": 1, "proton_json": "", "rtf_base64": make_rtf_base64(visible_text)}},
            "codex_summary": {"v": 1, "data": {
                "date": NOTE_DATE,
                "primary_domain": PRIMARY_DOMAIN,
                "repo": block["repo"],
                "topic": block["topic"],
                "domains": block["domains"],
                "request": block["request"],
                "summary": block["summary"],
                "outcome": block["outcome"],
                "files": block["files"],
                "source_session_path": snapshot["path"],
                "source_cwd": snapshot["cwd"],
                "source_first_user": snapshot["first_user"],
                "source_final_message": snapshot["final_message"],
                "source_pdf_path": rel_pdf,
                "source_text_path": rel_txt,
                "source_json_path": rel_json,
            }},
        },
    }
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def insert_dirty(cur, entity: str, entity_id: str, updated_at_ms: int) -> None:
    cur.execute(
        """
        INSERT OR REPLACE INTO nj_dirty(
            entity, entity_id, op, updated_at_ms, attempts, last_error, last_error_at_ms,
            last_error_code, last_error_domain, next_retry_at_ms, ignore
        ) VALUES (?, ?, 'upsert', ?, 0, '', 0, 0, '', 0, 0)
        """,
        (entity, entity_id, updated_at_ms),
    )


def main() -> None:
    SOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    enriched_blocks = []
    for block in BLOCKS:
        snap = session_snapshot(block["session_file"])
        b = dict(block)
        b["snapshot"] = snap
        enriched_blocks.append(b)
    earliest_start = min(b["snapshot"]["start_ms"] for b in enriched_blocks)
    latest_end = max(b["snapshot"]["end_ms"] for b in enriched_blocks)

    txt_path = SOURCE_ROOT / "20260428-codex-source.txt"
    json_path = SOURCE_ROOT / "20260428-codex-source.json"
    pdf_path = SOURCE_ROOT / "20260428-codex-source.pdf"

    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "tab_domain": TAB_DOMAIN,
        "primary_domain": PRIMARY_DOMAIN,
        "source": "Codex session history from local desktop session JSONL files for 2026-04-28",
        "blocks": [
            {
                "topic": b["topic"],
                "repo": b["repo"],
                "domains": b["domains"],
                "request": b["request"],
                "summary": b["summary"],
                "outcome": b["outcome"],
                "files": b["files"],
                "session_path": b["snapshot"]["path"],
                "cwd": b["snapshot"]["cwd"],
                "start_ms": b["snapshot"]["start_ms"],
                "end_ms": b["snapshot"]["end_ms"],
                "prompt_ranges": b["snapshot"]["prompt_ranges"],
                "first_user": b["snapshot"]["first_user"],
                "final_message": b["snapshot"]["final_message"],
            }
            for b in enriched_blocks
        ],
    }
    json_path.write_text(json.dumps(source_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    text_sections = [NOTE_TITLE, f"Date: {NOTE_DATE}", f"Primary domain: {PRIMARY_DOMAIN}", ""]
    for i, b in enumerate(enriched_blocks, start=1):
        s = b["snapshot"]
        text_sections.extend([
            f"{i}. {b['topic']}",
            f"Repo: {b['repo']}",
            f"Domains: {', '.join(b['domains'])}",
            f"Request: {b['request']}",
            f"Summary: {b['summary']}",
            f"Outcome: {b['outcome']}",
            f"Files: {', '.join(b['files']) if b['files'] else 'None'}",
            f"Session file: {s['path']}",
            f"CWD: {s['cwd']}",
            f"First user: {s['first_user']}",
            f"Final message: {s['final_message']}",
            "",
        ])
    text_body = "\n".join(text_sections).strip() + "\n"
    txt_path.write_text(text_body, encoding="utf-8")
    write_minimal_text_pdf(pdf_path, NOTE_TITLE, text_body)

    rel_pdf = f"Documents/{str(pdf_path).split('/Documents/', 1)[1]}"
    rel_txt = f"Documents/{str(txt_path).split('/Documents/', 1)[1]}"
    rel_json = f"Documents/{str(json_path).split('/Documents/', 1)[1]}"

    note_id = new_uuid()
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    for title in DELETE_TITLES:
        existing_ids = cur.execute(
            "SELECT note_id FROM nj_note WHERE title = ? AND notebook = ? AND tab_domain = ? AND deleted = 0",
            (title, NOTEBOOK, TAB_DOMAIN),
        ).fetchall()
        cur.execute(
            "UPDATE nj_note SET deleted = 1, updated_at_ms = ? WHERE title = ? AND notebook = ? AND tab_domain = ? AND deleted = 0",
            (latest_end, title, NOTEBOOK, TAB_DOMAIN),
        )
        for row in existing_ids:
            insert_dirty(cur, "note", row[0], latest_end)

    existing_slots = cur.execute(
        """
        SELECT time_slot_id FROM nj_time_slot
        WHERE owner_scope = 'ME' AND deleted = 0 AND title LIKE 'Codex:%' AND notes LIKE ?
        """,
        ("%/Users/mac/.codex/sessions/2026/04/28/%",),
    ).fetchall()
    cur.execute(
        """
        UPDATE nj_time_slot SET deleted = 1, updated_at_ms = ?
        WHERE owner_scope = 'ME' AND deleted = 0 AND title LIKE 'Codex:%' AND notes LIKE ?
        """,
        (latest_end, "%/Users/mac/.codex/sessions/2026/04/28/%"),
    )
    for row in existing_slots:
        insert_dirty(cur, "time_slot", row[0], latest_end)

    cur.execute(
        """
        INSERT INTO nj_note(
            note_id, notebook, tab_domain, title, created_at_ms, updated_at_ms, pinned, deleted,
            dominance_mode, is_checklist, favorited, note_type, card_id, card_category, card_area,
            card_context, card_status, card_priority
        ) VALUES (?, ?, ?, ?, ?, ?, 0, 0, 'block', 0, 0, '', '', '', '', '', '', '')
        """,
        (note_id, NOTEBOOK, TAB_DOMAIN, NOTE_TITLE, earliest_start, latest_end),
    )
    insert_dirty(cur, "note", note_id, latest_end)

    for idx, b in enumerate(sorted(enriched_blocks, key=lambda item: item["snapshot"]["start_ms"]), start=1):
        s = b["snapshot"]
        block_id = new_uuid()
        instance_id = str(uuid.uuid4()).upper()
        block_ms = s["end_ms"] or s["start_ms"]
        tag_json = json.dumps(b["domains"], ensure_ascii=False, separators=(",", ":"))
        payload_json = make_payload(b, s, rel_pdf, rel_txt, rel_json)
        cur.execute(
            """
            INSERT INTO nj_block(
                block_id, block_type, payload_json, domain_tag, tag_json, goal_id, lineage_id, parent_block_id,
                created_at_ms, updated_at_ms, deleted, dirty_bl
            ) VALUES (?, 'text', ?, ?, ?, '', '', '', ?, ?, 0, 1)
            """,
            (block_id, payload_json, TAB_DOMAIN, tag_json, block_ms, block_ms),
        )
        cur.execute(
            """
            INSERT INTO nj_note_block(
                instance_id, note_id, block_id, order_key, view_state_json, created_at_ms, updated_at_ms,
                deleted, is_checked, card_row_id, card_priority, card_category, card_area, card_context,
                card_title, card_status
            ) VALUES (?, ?, ?, ?, '', ?, ?, 0, 0, '', '', '', '', '', '', '')
            """,
            (instance_id, note_id, block_id, float(idx * 1000), block_ms, block_ms),
        )
        insert_dirty(cur, "block", block_id, block_ms)
        insert_dirty(cur, "note_block", instance_id, block_ms)
        for tag in b["domains"]:
            cur.execute(
                "INSERT OR REPLACE INTO nj_block_tag(block_id, tag, dirty_bl, created_at_ms, updated_at_ms) VALUES (?, ?, 1, ?, ?)",
                (block_id, tag, block_ms, block_ms),
            )

        for range_idx, (slot_start, slot_end) in enumerate(s["prompt_ranges"], start=1):
            time_slot_id = new_uuid()
            slot_title = b["timeslot_title"]
            if len(s["prompt_ranges"]) > 1:
                slot_title = f"{slot_title} ({range_idx})"
            slot_notes = "\n".join([
                f"Topic: {b['topic']}",
                f"Repo: {b['repo']}",
                f"Domains: {', '.join(b['domains'])}",
                f"Request: {b['request']}",
                f"Summary: {b['summary']}",
                f"Outcome: {b['outcome']}",
                f"Session: {s['path']}",
            ])
            cur.execute(
                """
                INSERT INTO nj_time_slot(
                    time_slot_id, owner_scope, title, category, start_at_ms, end_at_ms, notes,
                    created_at_ms, updated_at_ms, deleted
                ) VALUES (?, 'ME', ?, 'programming', ?, ?, ?, ?, ?, 0)
                """,
                (time_slot_id, slot_title, slot_start, slot_end, slot_notes, slot_start, slot_end),
            )
            insert_dirty(cur, "time_slot", time_slot_id, slot_end)

    conn.commit()
    conn.close()
    print(json.dumps({
        "note_id": note_id,
        "title": NOTE_TITLE,
        "tab_domain": TAB_DOMAIN,
        "primary_domain": PRIMARY_DOMAIN,
        "block_count": len(enriched_blocks),
        "timeslot_count": sum(len(b["snapshot"]["prompt_ranges"]) for b in enriched_blocks),
        "source_pdf": str(pdf_path),
        "source_txt": str(txt_path),
        "source_json": str(json_path),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
