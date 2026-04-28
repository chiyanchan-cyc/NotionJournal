#!/usr/bin/env python3

import base64
import json
import sqlite3
import textwrap
import uuid
from datetime import datetime, timezone
from pathlib import Path


DB_PATH = Path("/Users/mac/Library/Containers/FA955BEC-40DE-460A-84C5-691E7BAB14F9/Data/Documents/notion_journal.sqlite")
SOURCE_ROOT = Path("/Users/mac/Library/Mobile Documents/iCloud~com~CYC~NotionJournal/Documents/2026/04/chatgpt")
NOTE_TITLE = "20260427 ChatGPT Summary"
NOTE_DATE = "2026-04-27"
NOTEBOOK = "Me"
TAB_DOMAIN = "Me.mind"
DELETE_TITLES = ["(20260427) ChatGPT Summary", "20260427 ChatGPT Summary"]

SOURCE_CHAT = "Post-Earnings Pop Analysis"
SOURCE_PROJECT = "Finance Thought"

BLOCKS = [
    {
        "topic": "Turning rough trade ideas into executable MDs",
        "domains": ["Me.mind", "me.finance"],
        "context": (
            "The visible Finance Thought conversation was not just about new ideas; it was about upgrading rough notes into documents you could actually trade from. "
            "The framing line was that the MDs should stop being fragments and become complete executable documents."
        ),
        "summary": (
            "The discussion centered on converting earlier sketches into full trading MDs with a consistent decision structure. "
            "Instead of leaving the ideas as scattered narratives, the conversation reorganized them into a shared template: thesis, signals, timing, failure conditions, risks, and checklist. "
            "That made the output feel less like brainstorming and more like a real operating manual for how to enter, monitor, and exit a position. "
            "The meta-thread here was important: you were standardizing how you think, not just what you think."
        ),
        "takeaway": "The day was partly about building a repeatable trade-document format so future ideas become more executable.",
        "open_questions": [
            "Should every future Finance Thought thread be collapsed into this same MD template by default?",
            "Would a daily tracker layer on top of each MD make the framework easier to use in live markets?"
        ],
        "source_excerpt": (
            "The MDs should be complete, executable documents, not fragments. "
            "They were merged into full trading MDs with sections for thesis, signals, positioning, timing, risk, and checklist."
        ),
    },
    {
        "topic": "Xi-Trump thaw as a rumor-then-confirmation China trade",
        "domains": ["Me.mind", "me.finance"],
        "context": (
            "One of the completed MDs focused on a geopolitical thaw between Xi and Trump and treated it as a timing-sensitive China beta trade."
        ),
        "summary": (
            "This trade note framed a Xi-Trump rapprochement as a short-term risk-on setup for China rather than a long-term structural call. "
            "The logic was straightforward: tariff relief expectations, capital inflows, and a sentiment swing could all lift China-related risk assets during the rumor phase. "
            "But the note was careful about market structure. The move was described as event-driven and positioning-sensitive, with the edge concentrated before and into confirmation rather than after the official handshake. "
            "That is why the recommended expression leaned toward buying China beta early, adding on credible leaks, and scaling out aggressively into formal confirmation."
        ),
        "takeaway": "The important shift was from a vague geopolitical narrative to a disciplined 'buy rumor, sell handshake' event framework.",
        "open_questions": [
            "What real-time positioning signals are most trustworthy for deciding whether the rumor phase still has room?",
            "How do you distinguish a genuine thaw from a headline pop that never gets policy follow-through?"
        ],
        "source_excerpt": (
            "The thesis was that a geopolitical thaw drives short-term risk-on in China, but the exit belongs into confirmed meeting headlines or right after the handshake."
        ),
    },
    {
        "topic": "China AI as a scarcity and monetization trade",
        "domains": ["Me.mind", "me.finance"],
        "context": (
            "A second MD focused on China AI and treated the opportunity less as a frontier-model race and more as a constrained-supply economics trade."
        ),
        "summary": (
            "The China AI note argued that the local edge comes from scarcity rather than superiority. "
            "Because China AI operates under tighter supply constraints, token pricing, cloud quotas, and enterprise demand can produce better unit economics than the price-war dynamics showing up in parts of the US stack. "
            "The trade note mapped the whole chain instead of staying at the app layer: model providers, hyperscaler clouds, compute hardware, and packaging/backend names. "
            "The checklist mentality was clear here too. You were not just asking whether AI is important; you were defining concrete signals like price hikes, rationing, enterprise adoption, and visible monetization."
        ),
        "takeaway": "The thread sharpened China AI into an investable scarcity story with specific confirmation signals across the stack.",
        "open_questions": [
            "Which part of the China AI stack has the cleanest exposure to pricing power without overreliance on policy narrative?",
            "What would count as the earliest warning that the scarcity thesis is breaking?"
        ],
        "source_excerpt": (
            "China AI wins on scarcity, not superiority. "
            "The note emphasized rising pricing, quota restrictions, enterprise contracts, and the full domestic compute ecosystem."
        ),
    },
    {
        "topic": "Global AI infrastructure as the real picks-and-shovels trade",
        "domains": ["Me.mind", "me.finance"],
        "context": (
            "The third MD zoomed out from software and argued that the more durable AI trade may sit in power, copper, grid equipment, and data-center infrastructure."
        ),
        "summary": (
            "This part of the conversation repositioned AI as an infrastructure cycle rather than a pure software monetization story. "
            "The working thesis was that AI buildout ultimately means electricity demand, copper demand, transformer bottlenecks, grid investment, and cooling/data-center equipment orders. "
            "That changes both the investable universe and the patience required. Instead of chasing whichever model vendor looks hottest, the note emphasized utilities, copper producers, grid equipment, and data-center infrastructure names tied to physical buildout. "
            "It also came with an explicit warning structure: if AI capex slows, commodity prices weaken, or overcapacity appears, the thesis needs to be cut rather than defended."
        ),
        "takeaway": "You were converting AI enthusiasm into a more tangible infrastructure trade built around energy and industrial bottlenecks.",
        "open_questions": [
            "Which infrastructure names have the strongest direct linkage to AI demand rather than general macro optimism?",
            "At what point would the AI infrastructure thesis become late-cycle and crowded enough to fade?"
        ],
        "source_excerpt": (
            "The one-line summary was 'Sell AI hype, buy AI electricity,' with copper, power, grid, and data-center infrastructure as the key segments."
        ),
    },
]


def ms_for(date_str: str, hour: int, minute: int) -> int:
    dt = datetime.strptime(f"{date_str} {hour:02d}:{minute:02d}", "%Y-%m-%d %H:%M")
    dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)


def new_uuid() -> str:
    return str(uuid.uuid4())


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


def make_payload(block: dict, source_pdf_path: str, source_text_path: str, source_json_path: str) -> str:
    visible_text_parts = [
        block["topic"], "", block["summary"], "", "Context", block["context"], "", "Takeaway", block["takeaway"]
    ]
    if block["open_questions"]:
        visible_text_parts.extend(["", "Open Questions"])
        visible_text_parts.extend(f"- {item}" for item in block["open_questions"])
    visible_text = "\n".join(visible_text_parts)
    payload = {
        "v": 1,
        "sections": {
            "proton1": {
                "v": 1,
                "data": {"proton_v": 1, "proton_json": "", "rtf_base64": make_rtf_base64(visible_text)},
            },
            "chatgpt_summary": {
                "v": 1,
                "data": {
                    "date": NOTE_DATE,
                    "topic": block["topic"],
                    "domains": block["domains"],
                    "source_chat": SOURCE_CHAT,
                    "source_project": SOURCE_PROJECT,
                    "context": block["context"],
                    "summary": block["summary"],
                    "takeaway": block["takeaway"],
                    "open_questions": block["open_questions"],
                    "source_pdf_path": source_pdf_path,
                    "source_text_path": source_text_path,
                    "source_json_path": source_json_path,
                },
            },
        },
    }
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def main() -> None:
    SOURCE_ROOT.mkdir(parents=True, exist_ok=True)
    txt_path = SOURCE_ROOT / "20260427-chatgpt-source.txt"
    json_path = SOURCE_ROOT / "20260427-chatgpt-source.json"
    pdf_path = SOURCE_ROOT / "20260427-chatgpt-source.pdf"

    captured_sections = [
        "Good call — the MDs should be complete, executable documents, not fragments.",
        "MD 1 — XI–Trump Trade (FULL): geopolitical thaw drives short-term risk-on in China; buy rumor, sell handshake.",
        "MD 2 — China AI Trade (FULL): scarcity, pricing power, rationing, and enterprise adoption across the full domestic stack.",
        "MD 3 — Global AI Infrastructure Trade (FULL): copper, power, grid, and data-center infrastructure as the real picks-and-shovels AI trade.",
        "The closing idea was to turn these MDs into daily tracker dashboards or hedged long/short versions.",
    ]
    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "source": "Accessibility capture from the visible ChatGPT Finance Thought window on 2026-04-28.",
        "source_chat": SOURCE_CHAT,
        "source_project": SOURCE_PROJECT,
        "captured_sections": captured_sections,
        "blocks": BLOCKS,
    }
    json_path.write_text(json.dumps(source_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    text_sections = [
        NOTE_TITLE,
        f"Date: {NOTE_DATE}",
        f"Source chat: {SOURCE_CHAT}",
        f"Project: {SOURCE_PROJECT}",
        "Source type: Accessibility capture from visible ChatGPT window",
        "",
        "Captured visible source",
    ]
    text_sections.extend(f"- {line}" for line in captured_sections)
    text_sections.append("")
    for index, block in enumerate(BLOCKS, start=1):
        text_sections.extend([
            f"{index}. {block['topic']}",
            f"Domains: {', '.join(block['domains'])}",
            f"Context: {block['context']}",
            f"Summary: {block['summary']}",
            f"Takeaway: {block['takeaway']}",
            f"Open questions: {'; '.join(block['open_questions']) if block['open_questions'] else 'None'}",
            f"Excerpt: {block['source_excerpt']}",
            "",
        ])
    text_body = "\n".join(text_sections).strip() + "\n"
    txt_path.write_text(text_body, encoding="utf-8")
    write_minimal_text_pdf(pdf_path, NOTE_TITLE, text_body)

    rel_pdf = f"Documents/{str(pdf_path).split('/Documents/', 1)[1]}"
    rel_txt = f"Documents/{str(txt_path).split('/Documents/', 1)[1]}"
    rel_json = f"Documents/{str(json_path).split('/Documents/', 1)[1]}"
    note_id = new_uuid()
    note_created = ms_for(NOTE_DATE, 9, 0)
    note_updated = ms_for(NOTE_DATE, 23, 59)

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    for title in DELETE_TITLES:
        cur.execute(
            "UPDATE nj_note SET deleted = 1, updated_at_ms = ? WHERE title = ? AND notebook = ? AND tab_domain = ? AND deleted = 0",
            (note_updated, title, NOTEBOOK, TAB_DOMAIN),
        )
        for row in cur.execute("SELECT note_id FROM nj_note WHERE title = ? AND notebook = ? AND tab_domain = ?", (title, NOTEBOOK, TAB_DOMAIN)).fetchall():
            cur.execute(
                "INSERT OR REPLACE INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, last_error_at_ms, last_error_code, last_error_domain, next_retry_at_ms, ignore) VALUES ('note', ?, 'upsert', ?, 0, '', 0, 0, '', 0, 0)",
                (row[0], note_updated),
            )

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
    cur.execute(
        "INSERT OR REPLACE INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, last_error_at_ms, last_error_code, last_error_domain, next_retry_at_ms, ignore) VALUES ('note', ?, 'upsert', ?, 0, '', 0, 0, '', 0, 0)",
        (note_id, note_updated),
    )

    for idx, block in enumerate(BLOCKS, start=1):
        block_id = new_uuid()
        instance_id = str(uuid.uuid4()).upper()
        block_ms = ms_for(NOTE_DATE, 9 + min(idx, 10), (idx * 5) % 60)
        tag_json = json.dumps(block["domains"], ensure_ascii=False, separators=(",", ":"))
        payload_json = make_payload(block, rel_pdf, rel_txt, rel_json)
        cur.execute(
            "INSERT INTO nj_block(block_id, block_type, payload_json, domain_tag, tag_json, goal_id, lineage_id, parent_block_id, created_at_ms, updated_at_ms, deleted, dirty_bl) VALUES (?, 'text', ?, ?, ?, '', '', '', ?, ?, 0, 1)",
            (block_id, payload_json, TAB_DOMAIN, tag_json, block_ms, block_ms),
        )
        cur.execute(
            "INSERT INTO nj_note_block(instance_id, note_id, block_id, order_key, view_state_json, created_at_ms, updated_at_ms, deleted, is_checked, card_row_id, card_priority, card_category, card_area, card_context, card_title, card_status) VALUES (?, ?, ?, ?, '', ?, ?, 0, 0, '', '', '', '', '', '', '')",
            (instance_id, note_id, block_id, float(idx * 1000), block_ms, block_ms),
        )
        cur.execute(
            "INSERT OR REPLACE INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, last_error_at_ms, last_error_code, last_error_domain, next_retry_at_ms, ignore) VALUES ('block', ?, 'upsert', ?, 0, '', 0, 0, '', 0, 0)",
            (block_id, block_ms),
        )
        cur.execute(
            "INSERT OR REPLACE INTO nj_dirty(entity, entity_id, op, updated_at_ms, attempts, last_error, last_error_at_ms, last_error_code, last_error_domain, next_retry_at_ms, ignore) VALUES ('note_block', ?, 'upsert', ?, 0, '', 0, 0, '', 0, 0)",
            (instance_id, block_ms),
        )
        for tag in block["domains"]:
            cur.execute(
                "INSERT OR REPLACE INTO nj_block_tag(block_id, tag, dirty_bl, created_at_ms, updated_at_ms) VALUES (?, ?, 1, ?, ?)",
                (block_id, tag, block_ms, block_ms),
            )

    conn.commit()
    conn.close()
    print(json.dumps({
        "note_id": note_id,
        "title": NOTE_TITLE,
        "block_count": len(BLOCKS),
        "source_pdf": str(pdf_path),
        "source_txt": str(txt_path),
        "source_json": str(json_path),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
