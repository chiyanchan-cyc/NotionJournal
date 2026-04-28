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
NOTE_TITLE = "20260424 Codex Summary"
NOTE_DATE = "2026-04-24"
NOTEBOOK = "Me"
TAB_DOMAIN = "Dev"
PRIMARY_DOMAIN = "me.dev"
DELETE_TITLES = ["(20260424) Codex Summary", "20260424 Codex Summary"]

SESSION_ROOT = Path("/Users/mac/.codex/sessions/2026/04/24")
LOCAL_TZ = timezone(timedelta(hours=8))
DAY_START_LOCAL = datetime(2026, 4, 24, 0, 0, 0, tzinfo=LOCAL_TZ)
DAY_END_LOCAL = datetime(2026, 4, 25, 0, 0, 0, tzinfo=LOCAL_TZ)
DAY_START_MS = int(DAY_START_LOCAL.timestamp() * 1000)
DAY_END_MS = int(DAY_END_LOCAL.timestamp() * 1000)

BLOCKS = [
    {
        "topic": "GPT Researcher: made the repo usable for remodex-style testing instead of leaving setup half-configured",
        "timeslot_title": "Codex: GPT Researcher setup",
        "domains": ["me.dev"],
        "repo": "GPT_Researcher",
        "session_file": "rollout-2026-04-24T07-24-15-019dbca8-8c25-7801-85c3-34fe2ed0c41a.jsonl",
        "request": "Help get GPT_Researcher into a state where remodex-style testing can actually happen instead of stalling on setup gaps.",
        "summary": (
            "We treated this as an environment-readiness task rather than pretending the project was already runnable. "
            "The work focused on making the setup behave the way the repo documentation implies, so testing the real research flow would not silently fail or get blocked by missing environment configuration."
        ),
        "outcome": (
            "The repo ended the session in a testable state, which turns a vague 'can we try remodex?' request into an actual runnable starting point."
        ),
        "files": [],
    },
    {
        "topic": "GPT Researcher: evaluated research plugins, pricing, and the path toward IBKR integration",
        "timeslot_title": "Codex: Research plugin evaluation",
        "domains": ["me.dev", "me.finance"],
        "repo": "GPT_Researcher",
        "session_file": "rollout-2026-04-24T07-27-47-019dbcab-c7eb-7351-a30d-9bbc8d107f40.jsonl",
        "request": "Explain what the visible research plugins do, compare likely pricing/value for trade research, and check why IBKR is not listed plus what an integration path would look like.",
        "summary": (
            "This was less code-edit heavy than the other sessions, but it was still real Codex work around tool selection and integration strategy. "
            "We translated a long plugin list into practical categories, checked which ones were likely worth paying for in a fast trade-research workflow, and then verified that IBKR was not an existing ready-made Codex connector so the realistic path would be through IBKR's official APIs instead."
        ),
        "outcome": (
            "That gave you a much clearer shortlist of research tools and a grounded answer on IBKR: no native marketplace connector yet, but an integration is still possible through the official API surface."
        ),
        "files": [],
    },
    {
        "topic": "Notion Journal: explained why cards sync to iPad as notes by tracing the shared sync model",
        "timeslot_title": "Codex: Card-note sync model check",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-24T07-43-33-019dbcba-3687-7f02-be19-caff83912327.jsonl",
        "request": "Check why a card is syncing to iPad as a note and verify whether that is a bug or the intended model.",
        "summary": (
            "We followed the data model instead of guessing from the UI and confirmed that cards and notes are not separate CloudKit entity families in this app. "
            "They both travel through the same underlying note sync path, so the iPad behavior is a consequence of the storage model rather than a one-off serialization mistake."
        ),
        "outcome": (
            "This turned a suspicious cross-device behavior into an explained architectural behavior, which is useful because it points to where a future separation would need to happen if you want different semantics."
        ),
        "files": [
            "Notion Journal/Model.swift",
        ],
    },
    {
        "topic": "Notion Journal: repaired the meeting transcription pipeline so queued meetings can actually progress",
        "timeslot_title": "Codex: Meeting transcription fix",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-24T07-44-08-019dbcba-bd82-72b2-ad89-5c10dad45208.jsonl",
        "request": "Check why meeting transcription is stuck on summary pending and verify whether the pipeline is really running.",
        "summary": (
            "We found a real pipeline break rather than a mere UI lag. The transcription runner in AppStore was effectively a stub, which meant meetings could stay queued forever without any worker advancing them into a finished body. "
            "The fix reconnected the actual processing path so queued meetings are not stranded in a permanent pending state."
        ),
        "outcome": (
            "That converted meeting transcription from a dead queue into a real pipeline again, which should let summaries and block bodies move forward instead of freezing at the placeholder stage."
        ),
        "files": [
            "Notion Journal/AppStore.swift",
        ],
    },
    {
        "topic": "LLMJournal: cut ZZCoin ledger load cost and made the widget balance refresh path more realistic",
        "timeslot_title": "Codex: ZZCoin widget and ledger",
        "domains": ["me.dev", "dev.llm"],
        "repo": "LLMJournal",
        "session_file": "rollout-2026-04-24T07-45-45-019dbcbc-3898-7202-8111-6fa4cfcede84.jsonl",
        "request": "Fix the stale ZZCoin widget balance and the very slow ledger open behavior.",
        "summary": (
            "We treated the slow ledger and stale widget as the same broad problem: too much expensive data handling for a screen that should feel instant. "
            "The change narrowed the ledger fetch window to a manageable recent slice instead of dragging in an oversized transaction history on open, which also gives the widget-side balance path a saner data surface to work from."
        ),
        "outcome": (
            "The ledger should feel materially lighter on open, and the widget balance path is now grounded in a tighter, more maintainable retrieval pattern."
        ),
        "files": [
            "journal/LLMJournal/ZZCoinView.swift",
        ],
    },
    {
        "topic": "Notion Journal: built a weekly block review pass to separate planning-tagged blocks from the real weekly record",
        "timeslot_title": "Codex: Weekly block review",
        "domains": ["me.dev", "dev.nj"],
        "repo": "Notion Journal",
        "session_file": "rollout-2026-04-24T20-39-57-019dbf81-07f8-79f0-858a-75495e2c81b3.jsonl",
        "request": "Look at last week's NJ blocks, use note date for note-dominant notes, exclude planning-tagged blocks, and surface the real weekly record.",
        "summary": (
            "This session was more data archaeology than feature UI, but it was still a concrete Codex work thread. We applied your dating rule carefully, separated planning blocks tagged like #WEEKLY from the rest, and reduced the weekly block set to something readable rather than mixing planning scaffolding with lived work. "
            "The value here was in making the journal query logic match your actual mental model of what counts as the week."
        ),
        "outcome": (
            "You ended up with a cleaner weekly block set and a more trustworthy interpretation rule for future review-style passes."
        ),
        "files": [],
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

    txt_path = SOURCE_ROOT / "20260424-codex-source.txt"
    json_path = SOURCE_ROOT / "20260424-codex-source.json"
    pdf_path = SOURCE_ROOT / "20260424-codex-source.pdf"

    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "tab_domain": TAB_DOMAIN,
        "primary_domain": PRIMARY_DOMAIN,
        "source": "Codex session history from local desktop session JSONL files for 2026-04-24",
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
                "prompt_ranges": block["snapshot"]["prompt_ranges"],
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
        SELECT time_slot_id
        FROM nj_time_slot
        WHERE owner_scope = 'ME'
          AND deleted = 0
          AND title LIKE 'Codex:%'
          AND notes LIKE ?
        """,
        (f"%/Users/mac/.codex/sessions/2026/04/24/%",),
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
        (latest_end, f"%/Users/mac/.codex/sessions/2026/04/24/%"),
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
        "timeslot_count": sum(len(block["snapshot"]["prompt_ranges"]) for block in enriched_blocks),
        "source_pdf": str(pdf_path),
        "source_txt": str(txt_path),
        "source_json": str(json_path),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
