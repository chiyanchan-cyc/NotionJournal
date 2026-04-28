#!/usr/bin/env python3

import base64
import json
import sqlite3
import textwrap
import uuid
from datetime import datetime, timezone
from pathlib import Path


DB_PATH = Path("/Users/mac/Library/Containers/FA955BEC-40DE-460A-84C5-691E7BAB14F9/Data/Documents/notion_journal.sqlite")
SOURCE_ROOT = Path("/Users/mac/Library/Mobile Documents/iCloud~com~CYC~NotionJournal/Documents/2026/04/codex")
NOTE_TITLE = "20260422 Codex Summary"
NOTE_DATE = "2026-04-22"
NOTEBOOK = "Me"
TAB_DOMAIN = "Dev"
PRIMARY_DOMAIN = "me.dev"
DELETE_TITLES = ["(20260422) Codex Summary", "20260422 Codex Summary"]

SESSION_ROOT = Path("/Users/mac/.codex/sessions/2026/04/22")

BLOCKS = [
    {
        "topic": "Journal for Mac: restored LifeDB sync without forcing a calendar migration",
        "timeslot_title": "Codex: LifeDB sync fix",
        "domains": ["me.dev", "dev.jm"],
        "repo": "Journal for Mac",
        "session_file": "rollout-2026-04-22T07-12-10-019db250-c1c2-7130-98cd-ea7af06aee5b.jsonl",
        "request": "Re-check the broken LifeDB calendar sync path and see whether it can be fixed instead of moving to another calendar.",
        "summary": (
            "We traced the LifeDB pipeline end to end, verified that the calendar actually exists on this Mac, and isolated the real issue to the app's permissions and write path rather than missing data. "
            "The fix landed in the backend sync layer so the app can write to the intended calendar cleanly instead of failing early and making the whole calendar look unusable."
        ),
        "outcome": (
            "The practical result was that you did not need to abandon LifeDB. We turned a scary migration question into a contained backend bug fix."
        ),
        "files": [
            "Journal for Mac/Journal for Mac/Backend/BackendService.swift",
        ],
    },
    {
        "topic": "LLMJournal: reduced Weekly Goal screen slowness by cutting unnecessary fetch work",
        "timeslot_title": "Codex: Weekly Goals performance",
        "domains": ["me.dev", "dev.llm"],
        "repo": "LLMJournal",
        "session_file": "rollout-2026-04-22T07-31-15-019db262-3a83-7070-9201-1e0ffb869910.jsonl",
        "request": "Figure out why Weekly Goal opens so slowly and speed it up.",
        "summary": (
            "We found that the screen was doing too much work on open: broad CloudKit fetches, local filtering, and render-time state work that amplified the delay. "
            "The pass tightened the data loading path so the view asks for less, leans on cached/local data sooner, and avoids repeating expensive work during render."
        ),
        "outcome": (
            "This changed the problem from \"the screen feels frozen when opened\" to a more targeted, cache-first and query-bounded load path."
        ),
        "files": [
            "LLMJournal/journal/LLMJournal/WeeklyReview/WeeklyGoalSettingView.swift",
        ],
    },
    {
        "topic": "Journal Ingest Mac: fixed false-success staging when iCloud storage is unavailable",
        "timeslot_title": "Codex: Ingest staging reliability",
        "domains": ["me.dev", "dev.jm"],
        "repo": "Journal for Mac",
        "session_file": "rollout-2026-04-22T12-17-03-019db367-e26f-7080-a686-c25be547df55.jsonl",
        "request": "Improve ingest UX and fix the weird folder-scan behavior so staged media reflects reality.",
        "summary": (
            "We followed the ingest path and found a subtle reliability bug: photo and RAW imports could be marked as successfully staged even when the iCloud container was unavailable and the files only fell back to local staging. "
            "The fix corrected the status model, improved the visible messaging, and added a compatibility path so older false-success ledger rows can be retried instead of being treated as permanently done."
        ),
        "outcome": (
            "The ingest flow now reports what really happened and gives you a recovery path when cloud staging was never actually achieved."
        ),
        "files": [
            "Journal Ingest Shared/IngestSettings.swift",
            "Journal Ingest Shared/IngestStager.swift",
        ],
    },
    {
        "topic": "Notion Journal: mapped a real import path for Alipay, WeChat Pay, and Octopus spending",
        "timeslot_title": "Codex: Spending import design",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-22T14-17-53-019db3d6-8561-7e63-9ef6-83f99fb93362.jsonl",
        "request": "Work out the easiest way to capture Octopus, WeChat Pay, and Alipay transactions into the finance module.",
        "summary": (
            "This block was more architecture and importer design than finished UI work. We checked the export reality of all three payment systems, confirmed that WeChat Pay and Alipay are workable with semi-structured exports, and identified Octopus as the weakest source that will probably need OCR or looser normalization. "
            "From there we mapped the proper product shape inside Notion Journal: a dedicated synced transaction entity plus importer plumbing rather than a one-off script."
        ),
        "outcome": (
            "By the end of the session the problem had been reduced to a concrete ingestion plan instead of a vague \"finance capture\" wish."
        ),
        "files": [
            "Notion Journal/UI/NJCalendarView.swift",
            "Notion Journal/DB/DBSchemaInstaller.swift",
        ],
    },
    {
        "topic": "Notion Journal: reworked card-header filtering so resize no longer blocks the filter action",
        "timeslot_title": "Codex: Card filter interaction",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-22T14-41-24-019db3ec-0ab9-7670-b0b5-3957e729f88d.jsonl",
        "request": "Fix the card interface so the filter remains clickable even when column-width dragging is enabled.",
        "summary": (
            "We treated this as an interaction conflict between the resize affordance and the filter control. "
            "The fix moved the filter away from a fragile menu-under-drag arrangement and replaced it with a more explicit interaction model, including a cleaner popover path and double-click support on the header."
        ),
        "outcome": (
            "The header now behaves like a tool instead of a hit-target gamble, especially on narrow columns."
        ),
        "files": [
            "Notion Journal/Notes/NoteEditor/NJNoteEditorContainerView.swift",
        ],
    },
    {
        "topic": "Notion Journal: made section strikethrough edits persist by flushing the live body state",
        "timeslot_title": "Codex: Section strikethrough save fix",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-22T16-23-01-019db449-1286-7032-9417-fa437dd1d930.jsonl",
        "request": "Fix the case where applying strikethrough inside a section does not register as an edit unless extra typing happens afterward.",
        "summary": (
            "We narrowed the bug to the export/save path rather than the formatting shortcut itself. Strikethrough changed the visual text, but the section body was not being promoted into a real content-change event unless later text mutations happened. "
            "The patch forced the pipeline to prefer and flush the live `UITextView` attributed text so formatting-only changes still become durable Proton content."
        ),
        "outcome": (
            "That closed the gap between what the editor shows and what the sync/save layer considers to be a real edit."
        ),
        "files": [
            "Notion Journal/Proton/NJProtonAttachments.swift",
        ],
    },
    {
        "topic": "Notion Journal: moved passport and ID-card renewals into the calendar-driven flow",
        "timeslot_title": "Codex: Renewal calendar grouping",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-22T19-59-52-019db50f-9be7-7c53-a5d3-28ef54ed6cb0.jsonl",
        "request": "Put personal ID-card and passport expiry items with the calendar/renewal flow instead of leaving them in the earlier personal grouping.",
        "summary": (
            "We followed the renewal rows through the family view, sidebar grouping, and calendar usage so the change stayed consistent across surfaces instead of hiding rows in only one place. "
            "The implementation treated passports and identity cards as calendar-managed renewal items, which makes the UI match the mental model that these are date-driven obligations rather than generic personal info cards."
        ),
        "outcome": (
            "The result was cleaner grouping and less duplication between the personal info area and the calendar-based reminder flow."
        ),
        "files": [
            "Notion Journal/UI/NJCalendarView.swift",
            "Notion Journal/UI/UIRootView.swift",
            "Notion Journal/UI/UISidebar.swift",
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
    out: list[str] = []
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
    user_times: list[int] = []
    cwd = ""
    first_user = ""
    final_message = ""
    for raw_line in path.open(encoding="utf-8"):
        obj = json.loads(raw_line)
        timestamp = obj.get("timestamp")
        if timestamp:
            ts_ms = parse_iso_ms(timestamp)
            if start_ms == 0 or ts_ms < start_ms:
                start_ms = ts_ms
            if ts_ms > end_ms:
                end_ms = ts_ms
        if obj.get("type") == "session_meta":
            cwd = (obj.get("payload") or {}).get("cwd", cwd)
        payload = obj.get("payload") or {}
        if payload.get("type") == "user_message" and not first_user:
            msg = (payload.get("message") or "").strip()
            if msg:
                first_user = " ".join(msg.split())
        if payload.get("type") == "user_message" and timestamp:
            user_times.append(parse_iso_ms(timestamp))
        if payload.get("type") == "task_complete":
            msg = (payload.get("last_agent_message") or "").strip()
            if msg:
                final_message = " ".join(msg.split())
    prompt_ranges: list[tuple[int, int]] = []
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
        fallback_start = start_ms
        fallback_end = end_ms or fallback_start
        if fallback_end <= fallback_start:
            fallback_end = fallback_start + 5 * 60 * 1000
        prompt_ranges.append((fallback_start, fallback_end))

    prompt_start_ms = prompt_ranges[0][0]
    prompt_end_ms = prompt_ranges[-1][1]
    return {
        "path": str(path),
        "cwd": cwd,
        "start_ms": start_ms,
        "end_ms": end_ms or start_ms,
        "prompt_start_ms": prompt_start_ms,
        "prompt_end_ms": prompt_end_ms,
        "prompt_ranges": prompt_ranges,
        "first_user": first_user,
        "final_message": final_message,
    }


def render_visible_text(block: dict, rel_pdf: str, rel_txt: str, rel_json: str) -> str:
    lines = [
        block["topic"],
        "",
        "What We Did",
        block["summary"],
        "",
        "Outcome",
        block["outcome"],
        "",
        "Request",
        block["request"],
    ]
    if block.get("files"):
        lines.extend(["", "Files"])
        lines.extend(f"- {item}" for item in block["files"])
    lines.extend([
        "",
        "Source",
        f"- PDF: {rel_pdf}",
        f"- Text: {rel_txt}",
        f"- JSON: {rel_json}",
    ])
    return "\n".join(lines).strip()


def make_payload(block: dict, snapshot: dict, rel_pdf: str, rel_txt: str, rel_json: str) -> str:
    visible_text = render_visible_text(block, rel_pdf, rel_txt, rel_json)
    payload = {
        "v": 1,
        "sections": {
            "proton1": {
                "v": 1,
                "data": {
                    "proton_v": 1,
                    "proton_json": "",
                    "rtf_base64": make_rtf_base64(visible_text),
                },
            },
            "codex_summary": {
                "v": 1,
                "data": {
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
                },
            },
        },
    }
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def insert_dirty(cur: sqlite3.Cursor, entity: str, entity_id: str, updated_at_ms: int) -> None:
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

    enriched_blocks: list[dict] = []
    for block in BLOCKS:
        snapshot = session_snapshot(block["session_file"])
        enriched = dict(block)
        enriched["snapshot"] = snapshot
        enriched_blocks.append(enriched)

    earliest_start = min(block["snapshot"]["start_ms"] for block in enriched_blocks)
    latest_end = max(block["snapshot"]["end_ms"] for block in enriched_blocks)

    txt_path = SOURCE_ROOT / "20260422-codex-source.txt"
    json_path = SOURCE_ROOT / "20260422-codex-source.json"
    pdf_path = SOURCE_ROOT / "20260422-codex-source.pdf"

    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "tab_domain": TAB_DOMAIN,
        "primary_domain": PRIMARY_DOMAIN,
        "source": "Codex session history from local desktop session JSONL files for 2026-04-22",
        "blocks": [
            {
                "topic": block["topic"],
                "repo": block["repo"],
                "domains": block["domains"],
                "request": block["request"],
                "summary": block["summary"],
                "outcome": block["outcome"],
                "files": block["files"],
                "session_path": block["snapshot"]["path"],
                "cwd": block["snapshot"]["cwd"],
                "start_ms": block["snapshot"]["start_ms"],
                "end_ms": block["snapshot"]["end_ms"],
                "first_user": block["snapshot"]["first_user"],
                "final_message": block["snapshot"]["final_message"],
            }
            for block in enriched_blocks
        ],
    }
    json_path.write_text(json.dumps(source_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    text_sections = [NOTE_TITLE, f"Date: {NOTE_DATE}", f"Primary domain: {PRIMARY_DOMAIN}", ""]
    for index, block in enumerate(enriched_blocks, start=1):
        snap = block["snapshot"]
        text_sections.extend([
            f"{index}. {block['topic']}",
            f"Repo: {block['repo']}",
            f"Domains: {', '.join(block['domains'])}",
            f"Request: {block['request']}",
            f"Summary: {block['summary']}",
            f"Outcome: {block['outcome']}",
            f"Files: {', '.join(block['files']) if block['files'] else 'None'}",
            f"Session file: {snap['path']}",
            f"CWD: {snap['cwd']}",
            f"First user: {snap['first_user']}",
            f"Final message: {snap['final_message']}",
            "",
        ])
    text_body = "\n".join(text_sections).strip() + "\n"
    txt_path.write_text(text_body, encoding="utf-8")
    write_minimal_text_pdf(pdf_path, NOTE_TITLE, text_body)

    rel_pdf = f"Documents/{str(pdf_path).split('/Documents/', 1)[1]}"
    rel_txt = f"Documents/{str(txt_path).split('/Documents/', 1)[1]}"
    rel_json = f"Documents/{str(json_path).split('/Documents/', 1)[1]}"

    note_id = new_uuid()
    note_created = earliest_start
    note_updated = latest_end

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    for title in DELETE_TITLES:
        existing_ids = cur.execute(
            "SELECT note_id FROM nj_note WHERE title = ? AND notebook = ? AND tab_domain = ? AND deleted = 0",
            (title, NOTEBOOK, TAB_DOMAIN),
        ).fetchall()
        cur.execute(
            "UPDATE nj_note SET deleted = 1, updated_at_ms = ? WHERE title = ? AND notebook = ? AND tab_domain = ? AND deleted = 0",
            (note_updated, title, NOTEBOOK, TAB_DOMAIN),
        )
        for row in existing_ids:
            insert_dirty(cur, "note", row[0], note_updated)

    existing_slots = cur.execute(
        """
        SELECT time_slot_id
        FROM nj_time_slot
        WHERE owner_scope = 'ME'
          AND deleted = 0
          AND title LIKE 'Codex:%'
          AND notes LIKE ?
        """,
        (f"%/Users/mac/.codex/sessions/2026/04/22/%",),
    ).fetchall()
    cur.execute(
        """
        UPDATE nj_time_slot
        SET deleted = 1, updated_at_ms = ?
        WHERE owner_scope = 'ME'
          AND deleted = 0
          AND title LIKE 'Codex:%'
          AND notes LIKE ?
        """,
        (note_updated, f"%/Users/mac/.codex/sessions/2026/04/22/%"),
    )
    for row in existing_slots:
        insert_dirty(cur, "time_slot", row[0], note_updated)

    cur.execute(
        """
        INSERT INTO nj_note(
            note_id, notebook, tab_domain, title, created_at_ms, updated_at_ms, pinned, deleted,
            dominance_mode, is_checklist, favorited, note_type, card_id, card_category, card_area,
            card_context, card_status, card_priority
        ) VALUES (?, ?, ?, ?, ?, ?, 0, 0, 'block', 0, 0, '', '', '', '', '', '', '')
        """,
        (note_id, NOTEBOOK, TAB_DOMAIN, NOTE_TITLE, note_created, note_updated),
    )
    insert_dirty(cur, "note", note_id, note_updated)

    for idx, block in enumerate(sorted(enriched_blocks, key=lambda item: item["snapshot"]["start_ms"]), start=1):
        snap = block["snapshot"]
        block_id = new_uuid()
        instance_id = str(uuid.uuid4()).upper()
        block_ms = snap["end_ms"] or snap["start_ms"]
        tag_json = json.dumps(block["domains"], ensure_ascii=False, separators=(",", ":"))
        payload_json = make_payload(block, snap, rel_pdf, rel_txt, rel_json)
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
        for tag in block["domains"]:
            cur.execute(
                "INSERT OR REPLACE INTO nj_block_tag(block_id, tag, dirty_bl, created_at_ms, updated_at_ms) VALUES (?, ?, 1, ?, ?)",
                (block_id, tag, block_ms, block_ms),
            )

        for range_idx, (slot_start, slot_end) in enumerate(snap["prompt_ranges"], start=1):
            time_slot_id = new_uuid()
            slot_title = block["timeslot_title"]
            if len(snap["prompt_ranges"]) > 1:
                slot_title = f"{slot_title} ({range_idx})"
            slot_notes = "\n".join([
                f"Topic: {block['topic']}",
                f"Repo: {block['repo']}",
                f"Domains: {', '.join(block['domains'])}",
                f"Request: {block['request']}",
                f"Summary: {block['summary']}",
                f"Outcome: {block['outcome']}",
                f"Session: {snap['path']}",
            ])
            cur.execute(
                """
                INSERT INTO nj_time_slot(
                    time_slot_id, owner_scope, title, category, start_at_ms, end_at_ms, notes,
                    created_at_ms, updated_at_ms, deleted
                ) VALUES (?, 'ME', ?, 'programming', ?, ?, ?, ?, ?, 0)
                """,
                (
                    time_slot_id,
                    slot_title,
                    slot_start,
                    slot_end,
                    slot_notes,
                    slot_start,
                    slot_end,
                ),
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
        "timeslot_count": sum(len(block["snapshot"]["prompt_ranges"]) for block in enriched_blocks),
        "source_pdf": str(pdf_path),
        "source_txt": str(txt_path),
        "source_json": str(json_path),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
