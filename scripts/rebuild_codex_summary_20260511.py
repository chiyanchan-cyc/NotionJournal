#!/usr/bin/env python3

import json
import sqlite3
import textwrap
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path


DB_PATH = Path("/Users/mac/Library/Containers/FA955BEC-40DE-460A-84C5-691E7BAB14F9/Data/Documents/notion_journal.sqlite")
SOURCE_ROOT = Path("/Users/mac/Library/Mobile Documents/iCloud~com~CYC~NotionJournal/Documents/2026/05/codex")
NOTE_TITLE = "20260511 Codex Summary"
NOTE_DATE = "2026-05-11"
NOTEBOOK = "Me"
TAB_DOMAIN = "Dev"
PRIMARY_DOMAIN = "me.dev"
DELETE_TITLES = ["(20260511) Codex Summary", "20260511 Codex Summary"]

SESSION_ROOT = Path("/Users/mac/.codex/sessions/2026/05/11")
LOCAL_TZ = timezone(timedelta(hours=8))
DAY_START_LOCAL = datetime(2026, 5, 11, 0, 0, 0, tzinfo=LOCAL_TZ)
DAY_END_LOCAL = datetime(2026, 5, 12, 0, 0, 0, tzinfo=LOCAL_TZ)
DAY_START_MS = int(DAY_START_LOCAL.timestamp() * 1000)
DAY_END_MS = int(DAY_END_LOCAL.timestamp() * 1000)


def new_uuid() -> str:
    return str(uuid.uuid4())


def pdf_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


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

    txt_path = SOURCE_ROOT / "20260511-codex-source.txt"
    json_path = SOURCE_ROOT / "20260511-codex-source.json"
    pdf_path = SOURCE_ROOT / "20260511-codex-source.pdf"

    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "tab_domain": TAB_DOMAIN,
        "primary_domain": PRIMARY_DOMAIN,
        "source": "No local Codex session files were captured for 2026-05-11",
        "session_root": str(SESSION_ROOT),
        "blocks": [],
        "timeslots": [],
    }
    json_path.write_text(json.dumps(source_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    text_body = (
        f"{NOTE_TITLE}\n"
        f"Date: {NOTE_DATE}\n"
        f"Primary domain: {PRIMARY_DOMAIN}\n\n"
        "No local Codex session files were captured for this date, so no programming blocks or prompt-based timeslots were created.\n"
    )
    txt_path.write_text(text_body, encoding="utf-8")
    write_minimal_text_pdf(pdf_path, NOTE_TITLE, text_body)

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
            (DAY_START_MS, title, NOTEBOOK, TAB_DOMAIN),
        )
        for row in existing_ids:
            insert_dirty(cur, "note", row[0], DAY_START_MS)

    existing_slots = cur.execute(
        """
        SELECT time_slot_id FROM nj_time_slot
        WHERE owner_scope = 'ME' AND deleted = 0 AND title LIKE 'Codex:%' AND notes LIKE ?
        """,
        ("%/Users/mac/.codex/sessions/2026/05/11/%",),
    ).fetchall()
    cur.execute(
        """
        UPDATE nj_time_slot SET deleted = 1, updated_at_ms = ?
        WHERE owner_scope = 'ME' AND deleted = 0 AND title LIKE 'Codex:%' AND notes LIKE ?
        """,
        (DAY_START_MS, "%/Users/mac/.codex/sessions/2026/05/11/%"),
    )
    for row in existing_slots:
        insert_dirty(cur, "time_slot", row[0], DAY_START_MS)

    cur.execute(
        """
        INSERT INTO nj_note(
            note_id, notebook, tab_domain, title, created_at_ms, updated_at_ms, pinned, deleted,
            dominance_mode, is_checklist, favorited, note_type, card_id, card_category, card_area,
            card_context, card_status, card_priority
        ) VALUES (?, ?, ?, ?, ?, ?, 0, 0, 'block', 0, 0, '', '', '', '', '', '', '')
        """,
        (note_id, NOTEBOOK, TAB_DOMAIN, NOTE_TITLE, DAY_START_MS, DAY_START_MS),
    )
    insert_dirty(cur, "note", note_id, DAY_START_MS)

    conn.commit()
    conn.close()
    print(json.dumps({
        "note_id": note_id,
        "title": NOTE_TITLE,
        "tab_domain": TAB_DOMAIN,
        "primary_domain": PRIMARY_DOMAIN,
        "block_count": 0,
        "timeslot_count": 0,
        "source_pdf": str(pdf_path),
        "source_txt": str(txt_path),
        "source_json": str(json_path),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
