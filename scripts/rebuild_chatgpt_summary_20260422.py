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
NOTE_TITLE = "20260422 ChatGPT Summary"
NOTE_DATE = "2026-04-22"
NOTEBOOK = "Me"
TAB_DOMAIN = "Me.mind"
DELETE_TITLES = ["(20260422) ChatGPT Summary", "20260422 ChatGPT Summary"]


BLOCKS = [
    {
        "topic": "OpenClaw and the idea of an LLM notebook with memory",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "OpenClaw Open Source Details",
        "context": "You were trying to understand what an LLM notebook really is and how it fits into a broader memory-based AI system.",
        "summary": (
            "The chat reframed an LLM notebook as the AI-era equivalent of a coding notebook: not just a place to chat, but a workspace for building up thinking blocks, prompts, and results in a persistent context. "
            "The key idea was that the notebook itself is not the brain, the chatbot, or the agent. It is the whiteboard where the brain gets designed. "
            "That pushed the conversation toward a larger architecture in which ChatGPT, a notebook layer, and an eventual home LLM or agent system all play different roles instead of collapsing into one tool."
        ),
        "takeaway": "You were clarifying the difference between a memory workspace and the intelligence system that will eventually use it.",
        "open_questions": ["How should the notebook, memory, and agent layers be separated in your own architecture so each one stays simple?"],
        "source_excerpt": "You’re building a thinking system with memory. The LLM notebook is the whiteboard where you design the brain.",
    },
    {
        "topic": "Video editing with LLM assistance rather than full automation fantasy",
        "domains": ["Me.mind", "me.dev"],
        "source_chat": "LLM-assisted Video Editing",
        "context": "This thread was about using language models to help video work without pretending the whole editing process becomes magically automatic.",
        "summary": (
            "The conversation treated LLM help in video editing as an assistive layer rather than a full replacement for actual editing tools. "
            "The valuable role for the model would be in structuring ideas, describing cuts, organizing notes, or drafting edit plans, while the real editing workflow still lives in dedicated tooling. "
            "That fits your broader pattern of wanting AI to reduce friction without forcing you into fake all-in-one automation claims."
        ),
        "takeaway": "You were looking for a practical way to use LLMs to support creative workflow, not a glossy but unrealistic 'AI edits everything' story.",
        "open_questions": ["Which editing steps are actually language-shaped enough that an LLM can save time without becoming annoying?"],
        "source_excerpt": "An assistive use of the model inside the editing workflow, rather than pretending the whole video process can be automated cleanly.",
    },
    {
        "topic": "Remote access to Codex from an iPhone",
        "domains": ["Me.mind", "me.dev"],
        "source_chat": "Safari Lag vs App",
        "context": "You were checking whether the ChatGPT or Codex ecosystem officially supports using the phone as a live remote-control surface for your desktop coding setup.",
        "summary": (
            "The answer split the problem cleanly. Officially, Codex can reach remote devboxes over SSH and can continue work across app, web, CLI, and IDE surfaces, but that is different from using the mobile ChatGPT app as a full remote-control client for the desktop experience. "
            "So the practical setup remained: run Codex on the real machine, use Codex surfaces for continuity, and if you truly need phone-based control, rely on a separate remote desktop layer rather than expecting the mobile app to be that layer. "
            "This was another example of you trying to reduce setup annoyance by understanding what is actually supported versus what only sounds plausible."
        ),
        "takeaway": "You were mapping the least-annoying architecture for reaching your coding machine from the phone without expecting unsupported magic.",
        "open_questions": ["What is the cleanest phone-to-Mac path for your setup: Codex continuity only, or continuity plus a narrow remote desktop fallback?"],
        "source_excerpt": "Remote machine control by Codex exists via SSH to remote devboxes, but using the mobile ChatGPT app as a live remote-control client is not officially supported.",
    },
    {
        "topic": "Automatic coding journal logging needs a small bridge, not ChatGPT alone",
        "domains": ["Me.mind", "dev.nj", "me.dev"],
        "source_chat": "Lazy pinky technique fix",
        "context": "Despite the mismatched title, the visible chat body was about automatically logging programming work into your journal.",
        "summary": (
            "This conversation clarified that what you want is not impossible, but it is also not something the ChatGPT Mac app does by itself. "
            "The real system would need a small bridge: detect coding activity, collect signals like recent git commits or terminal commands, summarize them with an LLM, and then write the result into Notion Journal. "
            "The recommended approach was intentionally conservative: start with a simple script, a manual or scheduled trigger, an API call, and a journal write. Get the loop working first, then make it more automatic later."
        ),
        "takeaway": "You were translating an appealing automation idea into a realistic bridge architecture instead of waiting for the app alone to do it.",
        "open_questions": ["What is the minimum viable signal set for auto-logging your coding work without turning it into noise?"],
        "source_excerpt": "ChatGPT on Mac can help refine summaries, but for automation you need a small local bridge that detects activity, summarizes it, and writes it to the journal.",
    },
    {
        "topic": "Market stretch versus real failure still matters",
        "domains": ["Me.mind", "me.finance"],
        "source_chat": "Repo Market Manipulation?",
        "context": "This topic kept staying alive in your mind: how to distinguish an uncomfortable extended move from a market that is actually breaking.",
        "summary": (
            "This thread continued the finance pattern of refusing to short something simply because it feels too stretched. "
            "The useful distinction remained between a move that is uncomfortable and a move that has actually lost support, failed to follow through, or stopped absorbing selling. "
            "That keeps your trading framework grounded in structure rather than emotional disbelief."
        ),
        "takeaway": "You were still reinforcing the idea that stretched is not the same as broken.",
        "open_questions": ["What concrete structure break would finally justify acting against a persistent crowded move?"],
        "source_excerpt": "The market may feel extended, but that alone does not create a real short setup unless support and follow-through actually fail.",
    },
    {
        "topic": "History capture and journal automation are becoming one system",
        "domains": ["Me.mind", "dev.nj", "me.dev"],
        "source_chat": "ChatGPT History Automation",
        "context": "You keep circling the idea that chat history, coding history, and personal memory should feed into one durable capture system.",
        "summary": (
            "This conversation sat at the overlap of journaling, memory, and automation. "
            "The real goal is no longer just to save transcripts, but to create a durable memory system that can preserve what you were working on, what changed, and how your attention moved. "
            "That is why delta capture, source storage, and structured summaries keep coming back as design requirements instead of optional polish."
        ),
        "takeaway": "You were treating history capture as memory architecture, not as passive archiving.",
        "open_questions": ["How should coding history and ChatGPT history merge so the journal captures one coherent thinking trail?"],
        "source_excerpt": "The point is not just to save history, but to build a system that remembers how your work and thoughts moved over time.",
    },
    {
        "topic": "Controller and iPadOS compatibility as friction removal",
        "domains": ["Me.mind"],
        "source_chat": "8BitDo SN30 Pro iPadOS",
        "context": "A practical compatibility check around whether one device setup actually behaves the way you need it to.",
        "summary": (
            "This was a small but real background-friction conversation. "
            "The point was not collecting hardware trivia, but deciding whether a controller setup on iPadOS can be trusted enough to stop occupying attention. "
            "That fits your pattern of using ChatGPT to clear persistent uncertainty around practical setup questions."
        ),
        "takeaway": "You were using the chat to remove one more low-grade technical uncertainty from daily life.",
        "open_questions": ["Is there a simple rule you can keep for which accessories are worth testing versus avoiding?"],
        "source_excerpt": "A practical device-compatibility thread aimed at clearing one nagging setup question rather than exploring the whole ecosystem.",
    },
    {
        "topic": "API identity and stable connectivity remain separate problems",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "IP Changes and OpenAI API",
        "context": "You were still separating account/API concerns from the networking path used to actually reach the service reliably.",
        "summary": (
            "The core idea remained that stable API access is not the same thing as any one consumer networking product or previous subscription choice. "
            "The architecture question is how to maintain a reliable path to the API, likely with a steady relay or VPS, while keeping identity and connectivity as separate layers. "
            "That mental separation helps keep the system understandable rather than emotionally tangled."
        ),
        "takeaway": "You were continuing to reduce a messy access problem into cleaner infrastructure layers.",
        "open_questions": ["What is the simplest stable relay design that lets you stop thinking about API reachability day to day?"],
        "source_excerpt": "Account identity and connectivity are separate layers; the real issue is building a stable path to the API.",
    },
    {
        "topic": "Mechanical piano issues as a fixable system, not a mystery",
        "domains": ["Me.mind"],
        "source_chat": "Piano Action and Damper Issues",
        "context": "Another practical problem-solving thread where you were trying to understand why a physical instrument behaves strangely.",
        "summary": (
            "The piano thread fits your broader style: when something physical behaves oddly, you want a model of the mechanism instead of just a vague sense that it is wrong. "
            "By treating piano action and damper issues as understandable mechanical relationships, the problem becomes diagnosable and less mentally sticky."
        ),
        "takeaway": "You were reducing instrument frustration by converting it into a mechanical explanation problem.",
        "open_questions": ["What simple symptom-to-cause map would help you decide when to self-diagnose versus call a technician?"],
        "source_excerpt": "A practical thread about turning piano behavior from annoyance into understandable mechanics.",
    },
    {
        "topic": "Local versus cloud models still comes down to role separation",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "Local vs Cloud Models",
        "context": "You continue to refine which tasks should stay local and which deserve a stronger cloud model.",
        "summary": (
            "The question is no longer local versus cloud as a tribal choice. It is role separation. "
            "Routine loops, bounded work, and stateful repeated tasks lean local, while genuine uncertainty and frontier-level judgment lean cloud. "
            "That division keeps showing up because it matches both cost control and your desire for systems that feel personally owned."
        ),
        "takeaway": "You were continuing to design a two-layer AI workflow based on task type rather than ideology.",
        "open_questions": ["What is the cleanest rule set for deciding when a task crosses the boundary from local to cloud?"],
        "source_excerpt": "The useful split is by task role and uncertainty, not by treating local and cloud as competing belief systems.",
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
    txt_path = SOURCE_ROOT / "20260422-chatgpt-source.txt"
    json_path = SOURCE_ROOT / "20260422-chatgpt-source.json"
    pdf_path = SOURCE_ROOT / "20260422-chatgpt-source.pdf"
    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "source": "ChatGPT desktop app visible recents and visible body text sampled from the live UI on 2026-04-23",
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
