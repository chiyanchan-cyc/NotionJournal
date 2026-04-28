#!/usr/bin/env python3

import json
import base64
import os
import sqlite3
import textwrap
import uuid
from datetime import datetime, timezone
from pathlib import Path


DB_PATH = Path("/Users/mac/Library/Containers/FA955BEC-40DE-460A-84C5-691E7BAB14F9/Data/Documents/notion_journal.sqlite")
SOURCE_ROOT = Path("/Users/mac/Library/Mobile Documents/iCloud~com~CYC~NotionJournal/Documents/2026/04/chatgpt")
NOTE_TITLE = "20260420 ChatGPT Summary"
NOTE_DATE = "2026-04-20"
NOTEBOOK = "Me"
TAB_DOMAIN = "Me.mind"
DELETE_TITLES = ["(20260420) ChatGPT Summary", "20260420 ChatGPT Summary"]


BLOCKS = [
    {
        "topic": "Oil move versus real positioning",
        "domains": ["Me.mind", "me.finance"],
        "source_chat": "Repo Market Manipulation?",
        "context": "You were trying to decide whether a sharp move in repo and related risk assets should be read as exhaustion, manipulation, or genuine pressure from people still not positioned.",
        "summary": (
            "The conversation pushed back on the instinct that a 12 percent move in roughly ten days automatically means 'everyone is max long.' "
            "The more useful lens was to separate a stretched chart from a failed market. A move can still keep rising if underweight managers are chasing, "
            "systematic flows are still adding, shorts are still covering, or a fresh narrative shift is forcing re-pricing. "
            "The important trading takeaway was that feeling uncomfortable is not the same as having a short setup. "
            "What matters is when that stretched condition turns into lost follow-through, broken support, or an inability to absorb selling."
        ),
        "takeaway": "You were refining a rule: do not short because a move feels too far already; wait for the structure to actually fail.",
        "open_questions": ["What market structure signals best separate crowded long pain from true failed support?"],
        "source_excerpt": (
            "A 12% move in ~10 days feels like 'everyone is max long,' but that conclusion is usually too fast. "
            "Catch-up flows, systematic flows, short covering, and a narrative shift can all keep the move alive."
        ),
    },
    {
        "topic": "UVXY timing instead of emotional dip-buying",
        "domains": ["Me.mind", "me.finance"],
        "source_chat": "ChatGPT History Automation",
        "context": "Even though the chat title was unrelated, the visible body was about volatility timing and whether UVXY had become cheap enough to buy.",
        "summary": (
            "This thread was really about resisting the urge to call something cheap just because it is off the highs. "
            "The specific point was that UVXY around the high-thirties is lower than the panic spike, but not yet 'cheap cheap' in the way you would want for a patient volatility entry. "
            "The conversation framed the trade more like zone-mapping than prediction: wait for the market to calm down, then define where UVXY becomes attractive rather than buying simply because it has dropped."
        ),
        "takeaway": "You were shifting from reactive VIX chasing toward a calmer zone-based framework for volatility entries.",
        "open_questions": ["What UVXY versus VIX zones would count as high-conviction accumulation areas?"],
        "source_excerpt": (
            "Right now UVXY is roughly 38 to 39. That is off the highs, but not really 'cheap cheap.' "
            "Better to wait for a calmer market, then decide entry."
        ),
    },
    {
        "topic": "Stable API identity versus connectivity hacks",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "IP Changes and OpenAI API",
        "context": "You were thinking about API access reliability and whether prior infrastructure choices needed to be reversed.",
        "summary": (
            "The conversation clarified that cancelling one infrastructure service and keeping API access are separate decisions. "
            "The real issue was not account identity alone, but maintaining a stable path from where you are to the API endpoint. "
            "The recommended shape was a steady VPS relay in a place like Japan or Singapore, with VPN only as backup rather than as the main architecture. "
            "That made the problem feel less like 'did I break the account setup?' and more like 'what is the lowest-friction connectivity layer that stays reliable?'"
        ),
        "takeaway": "You were reducing the problem from a vague access fear into a clean relay-design question.",
        "open_questions": ["Which relay location gives the best balance of API stability, latency, and operational simplicity?"],
        "source_excerpt": (
            "You do not need to reverse that decision. Cancelling Greenmiles and relying on API are separate layers. "
            "API access needs a stable VPS relay, with VPN only as fallback."
        ),
    },
    {
        "topic": "Paying for uncertainty reduction, not raw parameters",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "Local vs Cloud Models",
        "context": "You were trying to understand what frontier API usage is really buying you compared with local models.",
        "summary": (
            "This thread reframed API cost away from naive parameter-count thinking. "
            "The useful idea was that you are not paying for 'more parameters' in some abstract sense. "
            "You are paying for better information, stronger search through uncertain problem space, and better judgment when the task is still ambiguous. "
            "That led to a more disciplined mental model: send only the parts of the problem where uncertainty is real, keep routine and well-bounded loops local, and treat the API like a search-space expander rather than a default solver."
        ),
        "takeaway": "You were defining a division of labor between local systems and frontier inference based on uncertainty, not prestige.",
        "open_questions": ["How small can the 'delta of uncertainty' be before a task should stay fully local?"],
        "source_excerpt": (
            "You are not literally paying for extra parameters. You are paying for extra information and better exploration. "
            "Use the API for the delta of uncertainty, not for everything."
        ),
    },
    {
        "topic": "Testing local models before committing to them",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "Model Testing and Evaluation",
        "context": "You were deciding whether a 70B-class local model would actually be good enough for the kind of work you want to do.",
        "summary": (
            "The tone here was practical and anti-romantic. Instead of deciding from benchmarks, marketing, or enthusiasm, the conversation leaned toward 'rent first, decide later.' "
            "The real target was to create tight evaluation tasks that expose weak reasoning, brittle planning, or failure to hold context before you spend money or redesign your setup around a model. "
            "In that sense, 70B was treated less like a badge and more like a truth test: can it survive your actual tasks with enough reliability to earn a permanent place?"
        ),
        "takeaway": "You wanted evidence from your own workload before committing hardware, workflows, or money to a local model path.",
        "open_questions": ["What short eval set would most quickly expose whether 70B is truly sufficient for your use cases?"],
        "source_excerpt": (
            "Rent first, decide later. Is 70B actually good enough? Use tight tests and expose weak reasoning before buying."
        ),
    },
    {
        "topic": "China VPS as control plane, not VPN habit",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "VPS Location and GFW",
        "context": "You were thinking through whether a China-based VPS would make your remote setup more stable.",
        "summary": (
            "This discussion treated the China VPS as an always-reachable anchor for two jobs only: remote control and API continuity. "
            "The key discipline was not to let it sprawl into a general-purpose VPN hub or a messy all-in-one solution. "
            "By keeping the role narrow, you preserve reliability and avoid building a fragile tower of networking workarounds. "
            "The conversation ended in a design principle more than a one-off answer: use the VPS as infrastructure backbone, not as a place where every workaround accumulates."
        ),
        "takeaway": "You were testing a cleaner infrastructure architecture where the China VPS is a stable anchor instead of a catch-all tunnel box.",
        "open_questions": ["What exact services belong on the China VPS if it stays narrowly scoped to control and API access?"],
        "source_excerpt": (
            "China VPS = always-reachable anchor for Jump Desktop plus your API. Keep it for control and API only, not as a VPN hub."
        ),
    },
    {
        "topic": "MoE availability versus practical local reality",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "MoE and Local Hosting",
        "context": "You were asking whether MoE models and GLM-5.1 being public really means they are locally usable in the way you care about.",
        "summary": (
            "The answer separated theoretical self-hostability from practical local usefulness. "
            "Yes, the weights being public means the model is self-hostable in principle. But that by itself does not mean it is realistic on normal local hardware, easy to run in the framework you want, or comfortable at the context length you need. "
            "So the real question became less 'is it open?' and more 'what class of machine and software stack does this actually require?' "
            "That moved the conversation away from slogans and toward deployment reality."
        ),
        "takeaway": "You were learning to treat 'open weights' as only the first gate, not the whole answer to local viability.",
        "open_questions": ["Which models are truly desktop-local for you rather than merely server-local?"],
        "source_excerpt": (
            "MoE is not the reason by itself. GLM-5.1 may be self-hostable, but it is closer to server-local than ordinary home-hardware local."
        ),
    },
    {
        "topic": "Token pricing is being hidden by agent loops",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "Model Size vs Coordination",
        "context": "You were thinking past simple per-token pricing and worrying about how much hidden compute future agentic systems will burn.",
        "summary": (
            "This thread sharpened a structural concern you already had: once systems start chaining planners, retrieval, reviewers, summarizers, tool calls, and retries, the sticker price per million tokens stops telling the real story. "
            "A task that looks tiny at the surface may secretly explode into many internal passes. "
            "That is why the conversation landed on local stateful systems as strategically important. "
            "The bottleneck is not only model intelligence; it is the cost of repeatedly re-invoking intelligence across long workflows. "
            "That made your interest in local LLMs feel less ideological and more economically inevitable."
        ),
        "takeaway": "You were recognizing that future AI costs will be driven by orchestration overhead, not just visible prompt length.",
        "open_questions": ["Which parts of your workflows leak the most tokens today because of repeated planner-reviewer loops?"],
        "source_excerpt": (
            "The more the industry pushes agent loops, long context, tool calls, retries, reviewers, planners, and memory refresh, the less meaningful token price per million becomes."
        ),
    },
    {
        "topic": "Losing a child’s return permit and what to do next",
        "domains": ["Me.mind", "me.rel.zz"],
        "source_chat": "回港證遺失處理",
        "context": "This was a practical family-admin thread about emergency travel paperwork after a child lost a Home Return Permit.",
        "summary": (
            "The conversation moved quickly into action mode. "
            "Rather than abstract policy explanation, the focus was on what office to contact, whether it was better to call first or go directly to a Guangdong service point, and what supporting documents should be prepared for an emergency return arrangement. "
            "The emotional subtext was clear too: this was not an academic immigration question, but a live family logistics problem where delay and confusion would cost energy."
        ),
        "takeaway": "You were trying to turn a stressful bureaucratic problem into a manageable checklist with the right first stop.",
        "open_questions": ["Which office is the fastest reliable first contact when a child needs an emergency return document?"],
        "source_excerpt": (
            "Better to contact Hong Kong immigration and also be ready to go directly to the relevant Guangdong service point with the supporting documents."
        ),
    },
    {
        "topic": "Explaining heart rate to Zhou Zhou in child language",
        "domains": ["Me.mind", "zz.health"],
        "source_chat": "Children vs Adult Heart Rate",
        "context": "You wanted an explanation that would make sense for Zhou Zhou rather than a dry medical definition.",
        "summary": (
            "This was a teaching-and-translation thread. "
            "The explanation used the water-pump analogy: a child’s heart is smaller, so it needs to beat faster to move the same blood around a smaller body, while an adult heart is larger and can push more blood per beat. "
            "The important part was not medical completeness; it was finding a simple picture Zhou Zhou could actually hold in his head."
        ),
        "takeaway": "You were converting physiology into a child-sized explanation instead of leaving it as adult knowledge.",
        "open_questions": ["What other body explanations could use the same 'small pump versus big pump' teaching style for Zhou Zhou?"],
        "source_excerpt": (
            "Heart like a water pump. A child has a smaller heart, so it beats faster. An adult has a bigger heart, so it can beat slower."
        ),
    },
    {
        "topic": "Vessel stiffness, food, and what actually changes blood pressure",
        "domains": ["Me.mind", "me.health"],
        "source_chat": "Hypertension and Heart Rate",
        "context": "You were trying to refine your model of hypertension, vessel stiffness, medication, food, and exercise.",
        "summary": (
            "This conversation validated your core intuition while correcting it. "
            "Yes, vessel stiffness matters and can push the system toward higher compensation. But hypertension is not simply 'aging plus stiff vessels' in a fixed sense. "
            "The discussion then separated helpful supports from primary levers. Foods such as nitrates, potassium-rich items, omega-3s, and polyphenols can help the vessel environment, but the more important long-term driver is exercise, especially sustained Zone 2 work, together with medication and general lifestyle control. "
            "That kept the model from becoming either fatalistic or food-magical."
        ),
        "takeaway": "You were refining a more accurate and actionable model: food helps, but exercise plus meds plus sustained habits are what really move the system.",
        "open_questions": ["What would a personal 'vascular improvement stack' look like if built around your actual running zones and meal habits?"],
        "source_excerpt": (
            "You are thinking in the right direction. Vessel stiffness matters, but food helps only as part of the larger picture. "
            "Exercise plus diet plus meds together equals real control."
        ),
    },
    {
        "topic": "When buybacks are capital return versus metric engineering",
        "domains": ["Me.mind", "me.finance"],
        "source_chat": "Stock Buybacks and Corruption",
        "context": "You were testing whether stock buybacks should be understood as outright corruption or as something subtler.",
        "summary": (
            "The answer resisted a simplistic moral label while still taking your discomfort seriously. "
            "Buybacks were described as a legitimate capital-return tool in some cases, a neutral mechanism in others, and a questionable one when used to inflate metrics or satisfy short-term activist pressure. "
            "So the issue was framed less as a coordinated corruption scheme and more as a governance and incentive-design problem. "
            "That helped distinguish between healthy use of excess cash and financial engineering that overrides real business value."
        ),
        "takeaway": "You were trying to build a more precise lens for judging buybacks instead of collapsing everything into 'good' or 'corrupt.'",
        "open_questions": ["What signals best distinguish healthy buybacks from short-term metric management when you are evaluating a company?"],
        "source_excerpt": (
            "Buybacks themselves are not one of the most used corruption tools, but there is a gray area where incentives and corporate behavior make them feel manipulative."
        ),
    },
    {
        "topic": "Buying Shenzhen to Kaohsiung flights like a timing problem",
        "domains": ["Me.mind"],
        "source_chat": "Best Time to Buy",
        "context": "This was a practical travel-planning thread approached with the same timing mindset you often use elsewhere.",
        "summary": (
            "The conversation treated flight buying as a controlled timing problem rather than a random guess. "
            "For the Shenzhen to Kaohsiung route, the suggested sweet spot was around forty days before departure, with earlier months used for tracking rather than immediate purchase. "
            "The thread also added leverage points like checking nearby airports, comparing round-trip versus one-way mixes, and considering bundles. "
            "What made it feel like one of your conversations was the mindset: build timing rules, avoid panic buying, and use structured optionality."
        ),
        "takeaway": "You were turning even travel purchasing into a rules-based timing exercise instead of relying on vague instinct.",
        "open_questions": ["Would a route-tracking note be worth keeping for this trip so the buy window becomes explicit instead of ad hoc?"],
        "source_excerpt": (
            "Best time to buy is around 40 days before departure. Start tracking earlier, then buy with controlled timing instead of gambling on a last-minute deal."
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
    out.extend(
        f"trailer << /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref_start}\n%%EOF\n".encode("latin-1")
    )
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
    txt_path = SOURCE_ROOT / "20260420-chatgpt-fullrun-source.txt"
    json_path = SOURCE_ROOT / "20260420-chatgpt-fullrun-source.json"
    pdf_path = SOURCE_ROOT / "20260420-chatgpt-fullrun-source.pdf"

    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "source": "ChatGPT desktop app visible conversation bodies captured from the live UI",
        "blocks": BLOCKS,
    }
    json_path.write_text(json.dumps(source_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    text_sections = [f"{NOTE_TITLE}", f"Date: {NOTE_DATE}", ""]
    for index, block in enumerate(BLOCKS, start=1):
        text_sections.extend(
            [
                f"{index}. {block['topic']}",
                f"Source chat: {block['source_chat']}",
                f"Domains: {', '.join(block['domains'])}",
                f"Context: {block['context']}",
                f"Summary: {block['summary']}",
                f"Takeaway: {block['takeaway']}",
                f"Open questions: {'; '.join(block['open_questions']) if block['open_questions'] else 'None'}",
                f"Excerpt: {block['source_excerpt']}",
                "",
            ]
        )
    text_body = "\n".join(text_sections).strip() + "\n"
    txt_path.write_text(text_body, encoding="utf-8")
    write_minimal_text_pdf(pdf_path, NOTE_TITLE, text_body)

    rel_pdf = str(pdf_path).split("/Documents/", 1)[1]
    rel_txt = str(txt_path).split("/Documents/", 1)[1]
    rel_json = str(json_path).split("/Documents/", 1)[1]
    rel_pdf = f"Documents/{rel_pdf}"
    rel_txt = f"Documents/{rel_txt}"
    rel_json = f"Documents/{rel_json}"

    note_id = new_uuid()
    note_created = ms_for(NOTE_DATE, 9, 0)
    note_updated = ms_for(NOTE_DATE, 23, 59)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = OFF")
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
