#!/usr/bin/env python3

import json
import base64
import sqlite3
import textwrap
import uuid
from datetime import datetime, timezone
from pathlib import Path


DB_PATH = Path("/Users/mac/Library/Containers/FA955BEC-40DE-460A-84C5-691E7BAB14F9/Data/Documents/notion_journal.sqlite")
SOURCE_ROOT = Path("/Users/mac/Library/Mobile Documents/iCloud~com~CYC~NotionJournal/Documents/2026/04/chatgpt")
NOTE_TITLE = "20260421 ChatGPT Summary"
NOTE_DATE = "2026-04-21"
NOTEBOOK = "Me"
TAB_DOMAIN = "Me.mind"
DELETE_TITLES = ["(20260421) ChatGPT Summary", "20260421 ChatGPT Summary"]


BLOCKS = [
    {
        "topic": "Private VPS versus commercial VPN reliability",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "Gemma4 on iPhone 17PM",
        "context": "The visible chat body was about why smaller private networking setups can work better in China than famous commercial VPN brands.",
        "summary": (
            "The conversation compared a small stable Shadowrocket-node style setup with bigger commercial VPN products like ExpressVPN. "
            "The logic was that low-profile private setups are often more stable, less detected, and less exposed to becoming obvious targets, even though they are less plug-and-play and more dependent on your own setup quality. "
            "What mattered was not just raw speed but survivability and consistency under China-specific conditions. "
            "That also connected back to your larger instinct that infrastructure should be quiet and dependable rather than flashy."
        ),
        "takeaway": "You were refining the idea that a smaller private path may be more trustworthy than branded consumer VPNs for real daily use.",
        "open_questions": ["What exact private setup gives you the best balance between low profile, maintenance burden, and reliability?"],
        "source_excerpt": "Smaller, quieter, lower-profile setups often work better in China than famous commercial VPN brands.",
    },
    {
        "topic": "Local model testing before committing hardware",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "Model Testing and Evaluation",
        "context": "You kept returning to the practical question of whether large local models are actually good enough for your real use cases.",
        "summary": (
            "This thread stayed grounded in testing discipline rather than model hype. "
            "Instead of deciding from online benchmarks or broad reputation, the point was to pressure-test models against a small but sharp eval set that reflects your actual needs. "
            "You were still trying to separate 'interesting on paper' from 'reliable enough to become part of your stack.' "
            "The deeper concern was not just quality in one reply, but whether the model can hold up across planning, review, and repeated use without wasting attention."
        ),
        "takeaway": "You wanted a local benchmark that reflects your real workflows before spending more money or attention on model upgrades.",
        "open_questions": ["What exact tasks should make up your private eval set so weak reasoning shows up quickly?"],
        "source_excerpt": "Use tight tests before you commit; the real question is whether the model is good enough for your work.",
    },
    {
        "topic": "Airflow mechanics and why AC comfort feels uneven",
        "domains": ["Me.mind"],
        "source_chat": "AC Airflow Mechanics",
        "context": "This looked like one of your practical home-friction conversations, where a small physical annoyance becomes worth understanding properly.",
        "summary": (
            "The discussion was about how airflow actually behaves rather than treating AC comfort as a mysterious good-or-bad feeling. "
            "You were likely trying to understand why certain positions in a room feel colder, stuffier, or less comfortable even when the overall system is working. "
            "This fits your pattern of reducing background irritation by turning fuzzy everyday discomfort into a model that can be explained and adjusted."
        ),
        "takeaway": "You were trying to convert home comfort from annoyance into understandable airflow logic.",
        "open_questions": ["Which adjustment matters most in your room: direction, fan speed, distance, or circulation path?"],
        "source_excerpt": "A practical thread about how AC airflow behaves and why comfort can differ even when cooling is on.",
    },
    {
        "topic": "China VPS as a stable control-and-API anchor",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "VPS Location and GFW",
        "context": "This was a continuation of your infrastructure design thinking around China connectivity, remote control, and AI access.",
        "summary": (
            "The China VPS idea kept returning as an anchor rather than a general-purpose tunnel box. "
            "The point was to preserve a stable path for control and API access without turning the whole system into a messy, overextended networking experiment. "
            "The stronger version of the idea was architectural: keep one reliable node that is always reachable, then layer only the minimum needed on top of it."
        ),
        "takeaway": "You were moving toward a cleaner infra design where one stable node does a few essential jobs well.",
        "open_questions": ["What services belong on the China VPS if you keep its role intentionally narrow?"],
        "source_excerpt": "Use the VPS as the stable anchor for control and access, not as a place where every workaround accumulates.",
    },
    {
        "topic": "Camera and gadget rumor triage",
        "domains": ["Me.mind"],
        "source_chat": "Insta360 Luna Rumors",
        "context": "This was one of several consumer-tech rumor threads where you were checking whether a rumored product was worth mentally tracking at all.",
        "summary": (
            "The conversation seems to have been less about gadget excitement and more about filtering signal from rumor noise. "
            "With products like Insta360 Luna, the real question is often whether the rumor implies a meaningful new capability or just another cycle of speculative headlines. "
            "You were likely trying to decide whether the product belongs in active consideration or can be mentally parked until there is something concrete."
        ),
        "takeaway": "You were using ChatGPT as a rumor filter so speculative product chatter does not waste too much attention.",
        "open_questions": ["What threshold of evidence makes a rumor worth active tracking for you?"],
        "source_excerpt": "A product-rumor thread focused on whether the speculation is meaningful enough to care about.",
    },
    {
        "topic": "Drone-spec rumor filtering",
        "domains": ["Me.mind"],
        "source_chat": "DJI Lito Drone Spec",
        "context": "Another consumer-tech check, but this time around drone specifications and whether the rumored product meaningfully changes the category.",
        "summary": (
            "This looked like a spec-triage conversation rather than a purchase decision. "
            "You were likely using the chat to sort out what in the rumor sounds genuinely new, what sounds like normal iterative improvement, and what should be ignored until official details exist. "
            "The deeper pattern is the same as with other rumor threads: avoid getting mentally dragged around by every leak unless it changes an actual decision."
        ),
        "takeaway": "You were filtering rumor-driven attention instead of letting every new spec leak become a real planning input.",
        "open_questions": ["Which rumored specs would actually change your behavior versus just sounding interesting?"],
        "source_excerpt": "Another rumor-filtering thread, focused on whether the drone specs matter enough to act on.",
    },
    {
        "topic": "MoE openness versus realistic local usability",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "MoE and Local Hosting",
        "context": "You were still exploring whether public model weights translate into real local usability on the kind of hardware and workflow you care about.",
        "summary": (
            "The conversation kept distinguishing theoretical openness from practical local deployment. "
            "A model being available does not automatically mean it is comfortable to run at home, affordable to serve, or compatible with the context lengths and tools you want. "
            "The useful part of the thread was that it kept pushing past the simple label of 'local' and into the actual conditions that make something desktop-local, server-local, or effectively not local for you."
        ),
        "takeaway": "You were learning to judge local-hosting claims by practical deployment reality rather than by slogans about openness.",
        "open_questions": ["Which open models are truly local for your machines, not just technically self-hostable?"],
        "source_excerpt": "Open weights are only the first gate; the real issue is whether the model is realistically usable on your setup.",
    },
    {
        "topic": "Emergency handling for the lost Home Return Permit",
        "domains": ["Me.mind", "me.rel.zz"],
        "source_chat": "回港證遺失處理",
        "context": "This was a live family-admin problem around lost travel documents and what the immediate next steps should be.",
        "summary": (
            "This thread was about converting a stressful paperwork problem into a concrete sequence of actions. "
            "The practical question was which office to contact, whether to go directly to a service point, and what supporting documents to prepare so the problem does not spiral into repeated delays. "
            "The tone was likely urgent and logistics-driven rather than theoretical, because the issue touches family movement and not just administrative neatness."
        ),
        "takeaway": "You were trying to turn a bureaucratic problem into a manageable action list before it consumed more family energy.",
        "open_questions": ["What is the fastest reliable path when a child needs an emergency replacement or return document?"],
        "source_excerpt": "A family-admin thread focused on the immediate steps after losing the Home Return Permit.",
    },
    {
        "topic": "Coordination overhead becoming the real AI cost",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "Model Size vs Coordination",
        "context": "You were worrying less about simple token pricing and more about how agent loops, retries, reviewers, and long workflows quietly multiply cost.",
        "summary": (
            "This conversation sharpened the idea that the future cost problem is not just intelligence quality but orchestration overhead. "
            "As systems add planners, memory refresh, retries, tool calls, and reviewer passes, the visible prompt becomes only a small part of the actual compute bill. "
            "That made your interest in local stateful systems feel economically grounded: they are not just about privacy or ownership, but about avoiding hidden re-invocation costs in long workflows."
        ),
        "takeaway": "You were identifying coordination overhead as the real long-term pressure point in agentic AI systems.",
        "open_questions": ["Which kinds of tasks in your own stack leak the most hidden coordination cost right now?"],
        "source_excerpt": "The future bottleneck is not only model intelligence, but how expensive it is to keep re-invoking intelligence over long workflows.",
    },
    {
        "topic": "Explaining body mechanics to Zhou Zhou simply",
        "domains": ["Me.mind", "zz.health"],
        "source_chat": "Children vs Adult Heart Rate",
        "context": "You wanted a child-sized explanation rather than an adult medical answer.",
        "summary": (
            "The conversation used a small-pump versus big-pump model to explain why a child’s heart beats faster than an adult’s. "
            "The point was not to be exhaustive, but to make the concept sticky and understandable for Zhou Zhou. "
            "This is part of a broader pattern in your chats: taking adult knowledge and translating it into language that actually lands for a child."
        ),
        "takeaway": "You were using ChatGPT as a translation layer from adult explanation into kid-understandable reasoning.",
        "open_questions": ["What other health or body ideas could be translated for Zhou Zhou in the same style?"],
        "source_excerpt": "A child explanation thread using the idea that a smaller heart needs to beat faster than a bigger one.",
    },
    {
        "topic": "On-device curiosity around Gemma-class models on a phone",
        "domains": ["Me.mind", "me.dev", "dev.llm"],
        "source_chat": "Gemma4 on iPhone 17PM",
        "context": "The title suggests you were exploring what it would mean to run stronger models directly on a phone-class device.",
        "summary": (
            "This thread fits your ongoing interest in shrinking AI capability closer to the device. "
            "The question was probably not just 'can it run?' but whether on-phone models would be useful enough, private enough, and fast enough to matter in daily life. "
            "What keeps showing up in these chats is your desire for systems that are personally owned, available even when connectivity is awkward, and structured around your actual usage rather than someone else's product assumptions."
        ),
        "takeaway": "You were testing how much meaningful AI capability might move from server dependence toward genuinely personal, on-device use.",
        "open_questions": ["What minimum level of on-device quality would make phone-local models genuinely useful for you?"],
        "source_excerpt": "A local-AI curiosity thread about what stronger models on a phone would really mean in practice.",
    },
    {
        "topic": "Nvidia results as a market-structure input, not just a headline",
        "domains": ["Me.mind", "me.finance"],
        "source_chat": "Nvidia Q1 FY2027 Results",
        "context": "This was likely part of your broader finance thinking around how major earnings releases interact with crowded positioning and narrative follow-through.",
        "summary": (
            "The Nvidia thread was probably less about simple earnings surprise and more about what the market was already positioned for. "
            "In your finance conversations, big reports are rarely treated as isolated facts; they are read through the lens of crowding, support, momentum continuation, and where expectations are already priced in. "
            "So the deeper question would have been whether results strengthen the trend, exhaust it, or set up a later 'sell the news' move."
        ),
        "takeaway": "You were reading a major earnings event through positioning and reaction quality, not just reported numbers.",
        "open_questions": ["What reaction pattern after Nvidia results would count as confirmation versus exhaustion?"],
        "source_excerpt": "A finance thread treating Nvidia earnings as part of positioning and trend logic rather than just headline numbers.",
    },
    {
        "topic": "Blood pressure, vessel stiffness, and what really helps",
        "domains": ["Me.mind", "me.health"],
        "source_chat": "Hypertension and Heart Rate",
        "context": "You were refining your understanding of the relationship between vessel stiffness, heart rate, medication, food, and exercise.",
        "summary": (
            "The key correction was that your intuition about vessel stiffness was directionally right, but incomplete. "
            "The conversation made clear that blood pressure control is not just about aging vessels, and not something food alone can solve. "
            "Food choices can help, especially via nitrates, potassium, omega-3s, and vascular-supportive foods, but the stronger long-term lever remains exercise plus overall control plus medication when needed. "
            "That kept the model practical and prevented it from drifting toward either fatalism or nutrition-as-magic."
        ),
        "takeaway": "You were building a more accurate personal model of vascular health where food supports the system but exercise and broader control do more of the heavy lifting.",
        "open_questions": ["How should you translate this into a real weekly vascular-improvement routine rather than just a concept?"],
        "source_excerpt": "Food helps, but exercise plus diet plus meds together equal real control.",
    },
    {
        "topic": "Buybacks as governance distortion rather than pure corruption",
        "domains": ["Me.mind", "me.finance"],
        "source_chat": "Stock Buybacks and Corruption",
        "context": "You were probing whether stock buybacks should be understood as outright corruption or as a more nuanced governance problem.",
        "summary": (
            "The answer resisted a simple moral label while still respecting your discomfort with the way buybacks can be used. "
            "Buybacks were framed as legitimate in some settings, neutral in others, and questionable when they become tools for metric management or short-term incentive satisfaction. "
            "The useful distinction was between actual capital return and financial engineering that overrides real business value. "
            "That gave you a better framework for evaluating companies without flattening the issue into a slogan."
        ),
        "takeaway": "You were refining a more precise finance lens instead of calling all buybacks either healthy or corrupt.",
        "open_questions": ["What signs most clearly separate healthy buybacks from management-image engineering?"],
        "source_excerpt": "The issue is more about incentive design and governance than a simple coordinated corruption scheme.",
    },
    {
        "topic": "Flight-buy timing as a structured decision",
        "domains": ["Me.mind"],
        "source_chat": "Best Time to Buy",
        "context": "You were thinking through when to buy Shenzhen-to-Kaohsiung flights without turning it into random guesswork.",
        "summary": (
            "This thread approached travel booking with the same structured timing mindset you often apply elsewhere. "
            "The point was to avoid both panic buying and aimless delay by using a practical window, roughly around forty days before departure, while tracking earlier. "
            "The conversation also looked at nearby airports, round-trip versus split-airline possibilities, and bundle effects. "
            "It turned a routine travel decision into a small rules-based system."
        ),
        "takeaway": "You were trying to reduce a travel purchase into a controlled timing play instead of a vague feeling call.",
        "open_questions": ["Would it help to keep a small route-tracking rule for future flights so the decision window becomes reusable?"],
        "source_excerpt": "Track early, buy at around 40 days, and do it as controlled timing rather than gambling.",
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
    txt_path = SOURCE_ROOT / "20260421-chatgpt-source.txt"
    json_path = SOURCE_ROOT / "20260421-chatgpt-source.json"
    pdf_path = SOURCE_ROOT / "20260421-chatgpt-source.pdf"

    source_doc = {
        "date": NOTE_DATE,
        "title": NOTE_TITLE,
        "source": "ChatGPT desktop app visible recents and visible body text sampled from the live UI on 2026-04-22",
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
