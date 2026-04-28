#!/usr/bin/env python3

import base64
import json
import sqlite3
from pathlib import Path


DB_PATH = Path("/Users/mac/Library/Containers/FA955BEC-40DE-460A-84C5-691E7BAB14F9/Data/Documents/notion_journal.sqlite")
TARGET_TITLES = ["20260420 ChatGPT Summary", "20260421 ChatGPT Summary"]


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


def render_visible_text(summary_data: dict) -> str:
    lines = []
    topic = (summary_data.get("topic") or "").strip()
    summary = (summary_data.get("summary") or "").strip()
    context = (summary_data.get("context") or "").strip()
    takeaway = (summary_data.get("takeaway") or "").strip()
    open_questions = [q.strip() for q in (summary_data.get("open_questions") or []) if str(q).strip()]

    if topic:
        lines.extend([topic, ""])
    if summary:
        lines.append(summary)
    if context:
        lines.extend(["", "Context", context])
    if takeaway:
        lines.extend(["", "Takeaway", takeaway])
    if open_questions:
        lines.extend(["", "Open Questions"])
        lines.extend(f"- {q}" for q in open_questions)
    return "\n".join(lines).strip()


def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    updated = 0

    qmarks = ",".join("?" for _ in TARGET_TITLES)
    rows = cur.execute(
        f"""
        SELECT b.block_id, b.payload_json
        FROM nj_block b
        JOIN nj_note_block nb ON nb.block_id = b.block_id
        JOIN nj_note n ON n.note_id = nb.note_id
        WHERE n.title IN ({qmarks})
          AND n.deleted = 0
          AND nb.deleted = 0
          AND b.deleted = 0
        """,
        TARGET_TITLES,
    ).fetchall()

    for block_id, payload_json in rows:
        try:
            payload = json.loads(payload_json)
            sections = payload.get("sections") or {}
            summary = ((sections.get("chatgpt_summary") or {}).get("data") or {})
            if not summary:
                continue
            visible_text = render_visible_text(summary)
            if not visible_text:
                continue
            sections["proton1"] = {
                "v": 1,
                "data": {
                    "proton_v": 1,
                    "proton_json": "",
                    "rtf_base64": make_rtf_base64(visible_text),
                },
            }
            payload["sections"] = sections
            cur.execute(
                "UPDATE nj_block SET payload_json = ?, dirty_bl = 1 WHERE block_id = ?",
                (json.dumps(payload, ensure_ascii=False, separators=(",", ":")), block_id),
            )
            updated += 1
        except Exception:
            continue

    conn.commit()
    conn.close()
    print(json.dumps({"updated_blocks": updated}))


if __name__ == "__main__":
    main()
