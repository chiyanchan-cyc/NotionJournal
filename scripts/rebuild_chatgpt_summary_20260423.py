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
NOTE_TITLE = "20260423 ChatGPT Summary"
NOTE_DATE = "2026-04-23"
NOTEBOOK = "Me"
TAB_DOMAIN = "Me.mind"
DELETE_TITLES = ["(20260423) ChatGPT Summary", "20260423 ChatGPT Summary"]


BLOCKS = [
    {
        "topic": "Sudoku difficulty should become deeper, not bigger, for Zhou Zhou",
        "domains": ["Me.mind", "zz.edu", "zz.adhd"],
        "source_chat": "Sudoku Mental Bandwidth",
        "context": "You were refining how to use Sudoku for Zhou Zhou without accidentally turning it into a working-memory overload exercise that teaches the wrong thing.",
        "summary": (
            "The conversation made a precise distinction between making Sudoku bigger and making it cognitively deeper. "
            "For Zhou Zhou, the issue is not basic reasoning ability; it is multi-step tracking, sequencing, sustained attention, and impulse control. "
            "So a harder 4x4 is better than a larger 6x6 if the difficulty comes from justification, structured stopping rules, and deliberate rescanning rather than from just increasing the amount he has to juggle. "
            "That reframed the exercise from puzzle difficulty into executive-function training."
        ),
        "takeaway": "You were designing learning tasks around the actual bottleneck instead of defaulting to a more advanced-looking format.",
        "open_questions": ["What other school-style exercises can be made deeper rather than bigger so they train sequencing without overwhelming him?"],
        "source_excerpt": "Don’t make 4×4 harder in the normal sense. Make it deeper, not bigger.",
    },
    {
        "topic": "Codex from iPhone should be a button to press, not a rebuilt system",
        "domains": ["Me.mind", "me.dev"],
        "source_chat": "iPhone Codex Access",
        "context": "You were exploring whether you could trigger a full iOS build-and-run loop from the bedroom iPhone through Codex and your Mac mini.",
        "summary": (
            "The answer was yes in a practical sense, but only if the real build loop remains on the Mac and is already stable. "
            "The iPhone is best understood as the control surface, not the place where the build logic lives. "
            "That means Codex or a remote-control layer simply presses a reliable script like `make ios-device`, while Xcode, signing, trust, and the actual iPhone install loop remain grounded in the Mac mini setup. "
            "The important principle was not to rebuild Codex, but to give it a dependable button to press."
        ),
        "takeaway": "You were reducing a remote-build fantasy into a very concrete control-surface architecture.",
        "open_questions": ["What is the minimum reliable device-build command you want Codex to trigger repeatedly without supervision?"],
        "source_excerpt": "This is exactly the workflow you want: not rebuild Codex, just give Codex a reliable button to press.",
    },
    {
        "topic": "SaaS surprise setups depend on revenue model, not just sector label",
        "domains": ["Me.mind", "me.finance"],
        "source_chat": "VIX update and strategy",
        "context": "You refined a finance idea by separating seat-based, usage-based, and hybrid SaaS businesses instead of treating the whole group as one macro bucket.",
        "summary": (
            "This thread sharpened the trade by moving away from the vague idea that the market is selling all SaaS equally. "
            "The useful split was by revenue model. Seat-based names are more exposed to the headcount-compression logic you were worried about, while usage-based names are more cyclical and can rebound with demand, and hybrid names may be the most interesting because they combine some seat stability with usage upside. "
            "That made the setup far more precise and turned a broad narrative into a ranked opportunity set."
        ),
        "takeaway": "You were learning to map market punishment through business-model mechanics instead of through sector shorthand.",
        "open_questions": ["Which names best combine low expectations with the strongest asymmetry if the cycle turns back up?"],
        "source_excerpt": "The market is not selling all SaaS. It is repricing different revenue models differently.",
    },
    {
        "topic": "AI hardware hype is creating the wrong urge to buy too early",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "AI Insights and Limits",
        "context": "You were pressure-testing whether now is actually the right time to buy a more powerful AI-oriented machine, or whether hype is distorting the decision.",
        "summary": (
            "The conversation argued that current AI-PC and high-RAM machine pricing is inflated by hype around local AI, HBM, and future-looking capability you may not need yet. "
            "Because your present loop with ChatGPT, Codex, summaries, and widgets is already working well, the real risk is overpaying, overbuilding, and solving the wrong problem too early. "
            "The smarter move, according to the thread, is to let your current system mature until the right machine spec becomes obvious instead of letting hype dictate an expensive purchase."
        ),
        "takeaway": "You were protecting yourself from buying a machine for imagined future pressure instead of today’s actual bottleneck.",
        "open_questions": ["What minimum future signal would justify moving from patient waiting to a deliberate machine purchase?"],
        "source_excerpt": "You’re avoiding overpaying, overbuilding, and solving the wrong problem.",
    },
    {
        "topic": "An LLM notebook is the whiteboard for building a thinking system",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "OpenClaw Open Source Details",
        "context": "You kept exploring where an LLM notebook fits inside your larger home-LLM and memory architecture.",
        "summary": (
            "The conversation clarified that the notebook itself is not the chatbot, the agent, or the final intelligence layer. "
            "Instead, it is the workspace where prompts, context, experiments, and memory fragments get organized into something more structured. "
            "That made the notebook feel like the design surface for the brain rather than the brain itself, which is an important distinction for the way you think about systems."
        ),
        "takeaway": "You were clarifying the roles of notebook, memory, and agent so the architecture stays modular.",
        "open_questions": ["How much of your future memory system should live in the notebook versus in background structured storage?"],
        "source_excerpt": "You’re building a thinking system with memory. The notebook is the whiteboard where you design the brain.",
    },
    {
        "topic": "LLM help in video editing should stay assistive, not magical",
        "domains": ["Me.mind", "me.dev"],
        "source_chat": "LLM-assisted Video Editing",
        "context": "You were considering how language models can fit into video editing workflows without turning into fake full-automation promises.",
        "summary": (
            "This thread fit your pattern of wanting AI to reduce friction in a targeted way rather than claiming it can replace everything. "
            "The likely sweet spot is planning, summarizing clips, structuring edits, or generating a draft edit logic, while the real creative and technical editing still belongs in proper tools. "
            "That keeps the model useful without turning the workflow into brittle automation theater."
        ),
        "takeaway": "You were looking for assistive leverage rather than a fake one-click editing fantasy.",
        "open_questions": ["Which video-editing subtasks are verbal enough that an LLM can genuinely save time without getting in the way?"],
        "source_excerpt": "Use the model as an assistive layer in the workflow, not as a claim that the whole editing process can be automated cleanly.",
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
        block["topic"],
        "",
        block["summary"],
        "",
        "Context",
        block["context"],
        "",
        "Takeaway",
        block["takeaway"],
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
                "data": {
                    "proton_v": 1,
                    "proton_json": "",
                    "rtf_base64": make_rtf_base64(visible_text),
                },
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
    txt_path = SOURCE_ROOT / "20260423-chatgpt-source.txt"
    json_path = SOURCE_ROOT / "20260423-chatgpt-source.json"
    pdf_path = SOURCE_ROOT / "20260423-chatgpt-source.pdf"
    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "source": "ChatGPT desktop app visible project chat and visible recents/body text sampled from the live UI on 2026-04-24",
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
        for row in cur.execute(
            "SELECT note_id FROM nj_note WHERE title = ? AND notebook = ? AND tab_domain = ?",
            (title, NOTEBOOK, TAB_DOMAIN),
        ).fetchall():
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
