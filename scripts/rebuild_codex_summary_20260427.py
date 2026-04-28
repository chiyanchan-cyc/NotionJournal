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
NOTE_TITLE = "20260427 Codex Summary"
NOTE_DATE = "2026-04-27"
NOTEBOOK = "Me"
TAB_DOMAIN = "Dev"
PRIMARY_DOMAIN = "me.dev"
DELETE_TITLES = ["(20260427) Codex Summary", "20260427 Codex Summary"]

SESSION_ROOT = Path("/Users/mac/.codex/sessions/2026/04/27")
LOCAL_TZ = timezone(timedelta(hours=8))
DAY_START_LOCAL = datetime(2026, 4, 27, 0, 0, 0, tzinfo=LOCAL_TZ)
DAY_END_LOCAL = datetime(2026, 4, 28, 0, 0, 0, tzinfo=LOCAL_TZ)
DAY_START_MS = int(DAY_START_LOCAL.timestamp() * 1000)
DAY_END_MS = int(DAY_END_LOCAL.timestamp() * 1000)

BLOCKS = [
    {
        "topic": "Audio Focus: built the new ZZ Journal writing module with CloudKit-backed text sync and local photo handling",
        "timeslot_title": "Codex: ZZ Journal module",
        "domains": ["me.dev", "dev.af"],
        "repo": "Audio Focus",
        "session_file": "rollout-2026-04-27T10-33-42-019dccc9-0fa3-7810-ad3e-2252a8ebe2ab.jsonl",
        "request": "Create a new ZZ Journal card with a calendar-based writing flow, store the written work so it can be graded outside Zhou Zhou's personal iCloud, and keep photos in his own storage space.",
        "summary": (
            "We turned the rough ZZ Journal idea into a real student-writing module. "
            "The session added a dedicated Journal surface with calendar navigation, weather, memory and food blocks, star-photo support, and local-first persistence, then reshaped the storage model so the written and gradable content syncs through public CloudKit while photos stay in Zhou Zhou's own iCloud documents area instead of being pushed into shared CK assets."
        ),
        "outcome": (
            "By the end, the module was no longer just a local note toy: it had a grading-friendly data model, a clean split between text metadata and photo ownership, and raw writing fields that preserve spelling and grammar for later coaching."
        ),
        "files": [
            "audio_focus/Audio_Focus/AudioFocusRevampView.swift",
            "audio_focus/Audio_Focus/ZZJournalView.swift",
            "audio_focus/Audio_Focus.xcodeproj/project.pbxproj",
        ],
    },
    {
        "topic": "Audio Focus: upgraded the ZZ Research flow into a real Taiwan Fruit project with CloudKit-synced field data",
        "timeslot_title": "Codex: Taiwan Fruit research",
        "domains": ["me.dev", "dev.af"],
        "repo": "Audio Focus",
        "session_file": "rollout-2026-04-27T10-44-02-019dccd2-866e-74f0-9e32-d583d5320435.jsonl",
        "request": "Replace the generic research area with project selection, start with a Taiwan Fruit workflow, and sync the written measurement data like the journal module while leaving photos for later.",
        "summary": (
            "This thread made the research side much more concrete. "
            "We changed the main Research entry into a project chooser, built a Taiwan Fruit data-collection workflow with sample counts, ratings, averages, and saved records, then added CloudKit syncing for the structured text and measurement fields while keeping local JSON as an offline cache."
        ),
        "outcome": (
            "The result was a more opinionated student project module that can hold actual fruit-study records, sync the important written data across accounts, and preserve raw student spelling by disabling Apple autocorrect on the author-facing text inputs."
        ),
        "files": [
            "audio_focus/Audio_Focus/AudioFocusRevampView.swift",
            "audio_focus/Audio_Focus/ZZJournalView.swift",
        ],
    },
    {
        "topic": "Notion Journal: replaced the weak generic research direction with the first real Investment module skeleton",
        "timeslot_title": "Codex: Investment module skeleton",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-27T13-23-27-019dcd64-7b0d-7722-af32-5ff4f3cb13ca.jsonl",
        "request": "Scrap the vague research-module idea, introduce a dedicated Investment or Macro Outlook module, seed important calendar events, and shape the app around active market views rather than passive note collection.",
        "summary": (
            "We used this session to pivot the product direction. "
            "Instead of keeping a generic research area, we added a top-level Investment module with market filters, a large macro calendar, weekly observations, tracking maps, and an initial trade-thesis structure, then seeded 2026 market-event data into the existing finance macro-event store so the calendar had real content to render."
        ),
        "outcome": (
            "That gave Notion Journal its first real investment-thinking workspace: a concrete shell for macro events, market interpretation, and trade framing instead of an unfocused dumping ground."
        ),
        "files": [
            "Notion Journal/UI/NJInvestmentModuleView.swift",
            "Notion Journal/AppStore.swift",
            "Notion Journal/UI/UIRootView.swift",
            "Notion Journal/UI/UISidebar.swift",
        ],
    },
    {
        "topic": "Notion Journal: hardened the macro refresh path, market-line visuals, and yield formatting for the Investment workflow",
        "timeslot_title": "Codex: Macro refresh wiring",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-27T15-58-43-019dcdf2-a06b-7081-a0e6-34676ac2bc69.jsonl",
        "request": "Turn the investment heartbeat into something operational, fix misleading market displays like US10Y, add the missing visual lines, and make the investment views better aligned with the daily macro workflow.",
        "summary": (
            "This block was all about making the new investment surface less fake and more maintainable. "
            "We refined the heartbeat/runbook direction, switched calendar layouts to Sunday starts, replaced the line-item table view with an actual Swift Charts macro-line chart, seeded and corrected US10Y yield history, fixed the bad `0.43%` formatting into a real `4.30%` yield display, and added missing lines like VIX and STOXX Europe 600 so the macro views stop implying completeness while hiding obvious gaps."
        ),
        "outcome": (
            "The user-facing effect is that the Investment module now reads much more like a real market dashboard and much less like a fragile placeholder, while the automation instructions are clearer about how to store yields, changes, and backfills."
        ),
        "files": [
            "Notion Journal/UI/NJInvestmentModuleView.swift",
            "Notion Journal/UI/NJCalendarView.swift",
            "Notion Journal/AppStore.swift",
            "Notion Journal/Docs/Investment_Macro_Daily_Refresh_Automation.md",
        ],
    },
    {
        "topic": "Notion Journal: refreshed the macro note and added real trade-thesis workspaces for China AI and global AI infrastructure",
        "timeslot_title": "Codex: Trade thesis workspaces",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-27T20-31-08-019dceec-0779-71b2-ba3b-861247a2d775.jsonl",
        "request": "Run the investment heartbeat, explain why the watch list was not refreshing, and turn the newer trade theses into actual structured workspaces inside the app rather than leaving them as static text.",
        "summary": (
            "We used the late session to close the loop between automation and the new UI structure. "
            "The Asia-close macro note was rebuilt with sourced values and scenario tables, then we traced the watch-list problem back to hard-coded placeholder rows in the current trade screen. From there we promoted newer ideas like China AI and Global AI Infrastructure into real trade-thesis tabs with watch lists, KPI/checklist sections, exit conditions, and movement-log placeholders, while documenting that live quote refresh still needs proper storage wiring."
        ),
        "outcome": (
            "That means yesterday ended with a stronger split between what is already a live structured workspace and what still needs data plumbing, which should make the next round of investment tooling much less ambiguous."
        ),
        "files": [
            "Notion Journal/UI/NJInvestmentModuleView.swift",
            "Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-04-27.md",
            "/Users/mac/.codex/automations/investment-macro-daily-refresh/memory.md",
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

    txt_path = SOURCE_ROOT / "20260427-codex-source.txt"
    json_path = SOURCE_ROOT / "20260427-codex-source.json"
    pdf_path = SOURCE_ROOT / "20260427-codex-source.pdf"

    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "tab_domain": TAB_DOMAIN,
        "primary_domain": PRIMARY_DOMAIN,
        "source": "Codex session history from local desktop session JSONL files for 2026-04-27",
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
        ("%/Users/mac/.codex/sessions/2026/04/27/%",),
    ).fetchall()
    cur.execute(
        """
        UPDATE nj_time_slot SET deleted = 1, updated_at_ms = ?
        WHERE owner_scope = 'ME' AND deleted = 0 AND title LIKE 'Codex:%' AND notes LIKE ?
        """,
        (latest_end, "%/Users/mac/.codex/sessions/2026/04/27/%"),
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
