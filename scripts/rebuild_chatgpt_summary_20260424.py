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
NOTE_TITLE = "20260424 ChatGPT Summary"
NOTE_DATE = "2026-04-24"
NOTEBOOK = "Me"
TAB_DOMAIN = "Me.mind"
DELETE_TITLES = ["(20260424) ChatGPT Summary", "20260424 ChatGPT Summary"]

BLOCKS = [
    {
        "topic": "Remote iPhone access to Codex and build workflows",
        "domains": ["Me.mind", "me.dev"],
        "source_chat": "iPhone Codex Access",
        "context": "You were still refining the idea of reaching your coding and build environment from the phone without rebuilding the whole stack around the phone itself.",
        "summary": (
            "The thread appears to have stayed centered on using the iPhone as a control surface rather than as the place where the real coding or build system lives. "
            "That means the useful architecture remains: keep the dependable build and tooling loop on the Mac, then expose a small reliable trigger or remote-control surface from the phone. "
            "This fits your larger instinct to prefer minimal, dependable control paths over clever but fragile reinventions."
        ),
        "takeaway": "You were continuing to reduce remote access into a narrow trigger-and-control problem instead of a device-role confusion problem.",
        "open_questions": ["What is the smallest reliable phone-triggerable command surface you actually need day to day?"],
        "source_excerpt": "A continuing thread about using the iPhone as the control surface for a Mac-based Codex and build loop.",
    },
    {
        "topic": "Volatility and market-setup refinement",
        "domains": ["Me.mind", "me.finance"],
        "source_chat": "VIX update and strategy",
        "context": "You were revisiting market structure and volatility through a more tactical setup lens rather than just reacting to fear readings.",
        "summary": (
            "This looks like a continuation of your broader finance work around when volatility is actionable and when it is just emotionally loud. "
            "The important pattern in your recent finance chats has been to move away from headline reactions and toward specific structure: what changed, what failed, what is overpricing fear, and what is merely noisy. "
            "So this thread likely advanced the way you think about volatility as a tactical input rather than a story in itself."
        ),
        "takeaway": "You were still trying to turn VIX-type fear data into an actual decision framework instead of a mood signal.",
        "open_questions": ["What volatility condition would count as a true setup versus just another dramatic reading?"],
        "source_excerpt": "A finance thread focused on updating the volatility view and translating it into a sharper strategy.",
    },
    {
        "topic": "AI insight versus AI purchase pressure",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "AI Insights and Limits",
        "context": "You were thinking about AI capability, but also about the limits of current hardware and the danger of hype-driven purchases.",
        "summary": (
            "This thread seems to have continued your recent pattern of resisting pressure to buy into AI hardware or capability narratives before the real bottleneck is clear. "
            "What matters to you is not maximum advertised capability, but whether a system meaningfully improves the loops you actually run today. "
            "So the likely focus was on insight through restraint: understand the limit, avoid overbuilding, and wait for the next step to become obviously justified."
        ),
        "takeaway": "You were using AI discussion to sharpen judgment, not to accelerate an unnecessary purchase.",
        "open_questions": ["Which specific capability gap would finally make a bigger local-AI hardware move feel justified?"],
        "source_excerpt": "A thread about AI’s real limits and the danger of letting hype force the wrong next step.",
    },
    {
        "topic": "Brix meter usefulness versus gadget curiosity",
        "domains": ["Me.mind"],
        "source_chat": "Brix Meter Functionality",
        "context": "This looks like another practical question where you were trying to understand whether a tool does something genuinely useful or just sounds interesting.",
        "summary": (
            "The likely heart of this conversation was not the object itself, but whether the measurement it offers would actually improve a decision you care about. "
            "That is consistent with the way you often use ChatGPT: to filter out low-value gadget curiosity and ask whether a tool changes behavior, confidence, or outcome enough to matter."
        ),
        "takeaway": "You were testing a tool by practical consequence rather than by novelty.",
        "open_questions": ["Does a Brix meter improve any real workflow you care about, or is it just mildly interesting information?"],
        "source_excerpt": "A practical tool-value thread about whether a Brix meter meaningfully changes anything you would actually do.",
    },
    {
        "topic": "Where LLM use in China may be heading in 2026",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "LLMs in China 2026",
        "context": "You were likely thinking not just about models themselves, but about access patterns, infrastructure, and what the next stage of LLM use could look like in China.",
        "summary": (
            "This thread likely sat at the intersection of model capability, policy reality, connectivity, and the shape of practical adoption. "
            "Given your other recent conversations, the real concern is usually not abstract geopolitics but what architectures, local stacks, and access patterns become most viable under real China conditions. "
            "That makes the topic less about prediction theater and more about planning around plausible infrastructure futures."
        ),
        "takeaway": "You were trying to understand the next environment for practical LLM use in China, not just the headline narrative around it.",
        "open_questions": ["Which 2026 China-LLM scenario would matter most for how you build your own local and remote setup?"],
        "source_excerpt": "A forward-looking thread about what practical LLM usage in China may look like in 2026.",
    },
    {
        "topic": "OpenClaw and structured notebook-style AI systems",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "OpenClaw Open Source Details",
        "context": "You kept returning to how notebook-like AI systems, memory, and your home-LLM ideas should fit together.",
        "summary": (
            "This appears to have continued your effort to understand what kind of structured workspace is needed between raw chat and a more durable agent or memory system. "
            "The real value of these discussions is that they keep separating roles cleanly: notebook, memory, and agent are related, but they are not the same thing. "
            "That is the kind of architectural clarity you keep pushing toward."
        ),
        "takeaway": "You were continuing to shape a layered thinking system instead of collapsing everything into one chat interface.",
        "open_questions": ["What exact boundary should separate your notebook layer from long-term memory and agent execution?"],
        "source_excerpt": "A continuing architecture thread about notebook-like AI systems, memory, and what belongs in each layer.",
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
                    "source_chat": block["source_chat"],
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
    txt_path = SOURCE_ROOT / "20260424-chatgpt-source.txt"
    json_path = SOURCE_ROOT / "20260424-chatgpt-source.json"
    pdf_path = SOURCE_ROOT / "20260424-chatgpt-source.pdf"
    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "source": "Best-effort reconstruction from verified ChatGPT recent titles and limited local source visibility on 2026-04-25; not a full transcript export",
        "blocks": BLOCKS,
    }
    json_path.write_text(json.dumps(source_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    text_sections = [NOTE_TITLE, f"Date: {NOTE_DATE}", ""]
    for index, block in enumerate(BLOCKS, start=1):
        text_sections.extend([
            f"{index}. {block['topic']}",
            f"Source chat: {block['source_chat']}",
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
            cur.execute("INSERT OR REPLACE INTO nj_block_tag(block_id, tag, dirty_bl, created_at_ms, updated_at_ms) VALUES (?, ?, 1, ?, ?)", (block_id, tag, block_ms, block_ms))
    conn.commit()
    conn.close()
    print(json.dumps({
        "note_id": note_id, "title": NOTE_TITLE, "block_count": len(BLOCKS),
        "source_pdf": str(pdf_path), "source_txt": str(txt_path), "source_json": str(json_path)
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
