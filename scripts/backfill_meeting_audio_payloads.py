#!/usr/bin/env python3

import base64
import json
import sqlite3
from pathlib import Path


DB_PATH = Path("/Users/mac/Library/Containers/FA955BEC-40DE-460A-84C5-691E7BAB14F9/Data/Documents/notion_journal.sqlite")
ICLOUD_ROOT = Path("/Users/mac/Library/Mobile Documents/iCloud~com~CYC~NotionJournal")

SUMMARY_OVERRIDES = {
    "899585fc-4a97-400d-a97d-e2f3d0908d99": (
        "本次职业治疗会议回顾了周周在注意力、听觉处理和任务持续性方面的表现。周周前半段能维持约30至35分钟专注，完成看影片、记录重点和复述任务时整体稳定；进入新游戏后因为规则较复杂，专注度下降。治疗师建议继续在家用由短到长的句子复述、听觉指令和绘本复述来练习听觉记忆与漏词监测。"
    ),
    "6f02b8b3-5f26-45c0-90af-6ded2bb873d4": (
        "本次ABA会议回顾了周周在课堂任务、活动转换和情绪社交训练上的表现。周周完成桌面任务速度不错，但在后段遇到较难题目时会卡住，也会因外界干扰被打断注意力；整体仍能持续坐在座位上完成任务，并获得额外奖励。会议也讨论了表情辨识、社交情境理解，以及后续让爸爸在家和学校主导练习、治疗师提供方法支持的方向。"
    ),
    "b389f8d2-62e8-40d7-a457-c2f52ccfe25d": (
        "本次ABA会议回顾了周周在课堂任务、活动转换和情绪社交训练上的表现。周周完成桌面任务速度不错，但在后段遇到较难题目时会卡住，也会因外界干扰被打断注意力；整体仍能持续坐在座位上完成任务，并获得额外奖励。会议也讨论了表情辨识、社交情境理解，以及后续让爸爸在家和学校主导练习、治疗师提供方法支持的方向。"
    ),
    "21acae58-fde4-42f4-8cf0-1b79d97b3f47": (
        "本次职业治疗会议主要回顾了周周在听觉注意、记录重点和任务速度上的进展。周周能够连续完成由简单到较复杂的听觉任务，中途虽然想聊天，但在提示后能重新回到任务并抓住重点，整体注意力与处理速度都有提升。治疗师也提到周周会用“讨价还价”式互动作为策略，只要不突破底线可接受，建议继续维持目前练习节奏。"
    ),
    "b9fe3c4d-8514-4164-9af5-4386b3cd1b40": (
        "本次ABA会议反馈周周当天整体状态良好，能一次性完成原本三选二的全部任务，专注度、活动转换和座位维持都表现稳定，并额外获得奖励。治疗师特别提到周周愿意分享饼干给老师，展现出同理心与关怀；在后续社交训练中，他对表情与情绪的辨识仍偶尔需要提示。双方也讨论了下一步由爸爸在家和学校更主动带练，治疗师提供方法支持的安排。"
    ),
}


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


def make_rtf_base64(text: str) -> str:
    rtf = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 " + rtf_escape(text) + "}"
    return base64.b64encode(rtf.encode("utf-8")).decode("ascii")


def fmt_ts(sec: float) -> str:
    ms = int(round(sec * 1000))
    h = ms // 3600000
    ms -= h * 3600000
    m = ms // 60000
    ms -= m * 60000
    s = ms // 1000
    ms -= s * 1000
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"


def transcript_from_json(json_path: Path) -> str:
    if not json_path.exists():
        return ""
    try:
        root = json.loads(json_path.read_text())
    except Exception:
        return ""
    lines = []
    for seg in root.get("segments", []):
        if not isinstance(seg, dict):
            continue
        text = str(seg.get("text", "")).strip()
        if not text:
            continue
        speaker = str(seg.get("speaker", "")).strip() or "SPEAKER"
        start = float(seg.get("start", 0.0))
        end = float(seg.get("end", 0.0))
        lines.append(f"[{fmt_ts(start)} -> {fmt_ts(end)}] {speaker}: {text}")
    return "\n".join(lines).strip()


def sidecar_for_audio(audio_path: str) -> Path | None:
    rel = audio_path.lstrip("/")
    if not rel:
        return None
    path = ICLOUD_ROOT / rel
    return path.with_suffix(".meeting.json")


def load_sidecar(audio_path: str) -> dict:
    sidecar = sidecar_for_audio(audio_path)
    if sidecar is None or not sidecar.exists():
        return {}
    try:
        return json.loads(sidecar.read_text())
    except Exception:
        return {}


def decode_people(raw: str) -> list[str]:
    try:
        people = json.loads(raw or "[]")
    except Exception:
        return []
    out: list[str] = []
    for item in people:
        if not isinstance(item, dict):
            continue
        name = str(item.get("displayName", "")).strip()
        role = str(item.get("role", "")).strip()
        if not name:
            continue
        out.append(f"{name} ({role})" if role else name)
    return out


def render_body(title: str, topic: str, location: str, participants: list[str], summary: str, transcript: str) -> str:
    lines = [title or "Audio Recording"]
    if topic:
        lines.append(f"Topic: {topic}")
    if location:
        lines.append(f"Location: {location}")
    if participants:
        lines.append(f"Participants: {', '.join(participants)}")
    lines.append("")
    lines.append("Summary")
    lines.append(summary or "Summary pending.")
    _ = transcript
    return "\n".join(lines)


def main() -> None:
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        """
        select block_id, payload_json
        from nj_block
        where block_type='audio' and deleted=0
        order by updated_at_ms asc
        """
    ).fetchall()

    repaired = 0
    imported_transcripts = 0
    backfilled_summaries = 0

    for block_id, payload_json in rows:
        root = json.loads(payload_json)
        sections = root.setdefault("sections", {})
        audio = sections.setdefault("audio", {"v": 1, "data": {}})
        audio_data = audio.setdefault("data", {})
        proton1 = sections.setdefault("proton1", {"v": 1, "data": {}})
        proton_data = proton1.setdefault("data", {})

        title = str(audio_data.get("title", "")).strip() or "Audio Recording"
        audio_path = str(audio_data.get("audio_path", "")).strip()
        json_path = str(audio_data.get("json_path", "")).strip()
        transcript = str(audio_data.get("transcript_txt", "")).strip()
        if not transcript and json_path:
            transcript = transcript_from_json(ICLOUD_ROOT / json_path.lstrip("/"))
            if transcript:
                audio_data["transcript_txt"] = transcript
                imported_transcripts += 1
        if not transcript:
            continue

        summary = str(audio_data.get("summary_txt", "")).strip()
        if block_id in SUMMARY_OVERRIDES and (not summary or summary.lower() == "summary pending."):
            summary = SUMMARY_OVERRIDES[block_id]
            audio_data["summary_txt"] = summary
            if not str(audio_data.get("summary_title", "")).strip():
                audio_data["summary_title"] = title
            backfilled_summaries += 1

        sidecar = load_sidecar(audio_path)
        topic = str(audio_data.get("meeting_topic_txt", "")).strip() or str(sidecar.get("topicText", "")).strip()
        location = str(audio_data.get("meeting_location_txt", "")).strip() or str(sidecar.get("locationText", "")).strip()
        participants = decode_people(str(audio_data.get("meeting_persons_json", "")).strip())
        if not participants:
            participants = [
                f"{str(item.get('displayName', '')).strip()} ({str(item.get('role', '')).strip()})".rstrip(" ()")
                if str(item.get("role", "")).strip()
                else str(item.get("displayName", "")).strip()
                for item in sidecar.get("participants", [])
                if str(item.get("displayName", "")).strip()
            ]
            if sidecar.get("participants"):
                audio_data["meeting_persons_json"] = json.dumps(sidecar["participants"], ensure_ascii=False)

        if topic:
            audio_data["meeting_topic_txt"] = topic
        if location:
            audio_data["meeting_location_txt"] = location
        if topic or location or participants:
            audio_data["meeting_context_complete"] = 1

        audio_data["transcript_state"] = "done"
        audio_data["transcript_error_txt"] = ""
        proton_data["proton_v"] = 1
        proton_data.setdefault("proton_json", "")
        proton_data["rtf_base64"] = make_rtf_base64(
            render_body(title, topic, location, participants, summary, transcript)
        )

        updated_payload = json.dumps(root, ensure_ascii=False, separators=(",", ":"))
        conn.execute(
            "update nj_block set payload_json=?, updated_at_ms=strftime('%s','now')*1000 where block_id=?",
            (updated_payload, block_id),
        )
        repaired += 1

    conn.commit()
    print(
        json.dumps(
            {
                "db": str(DB_PATH),
                "audio_blocks_seen": len(rows),
                "repaired_blocks": repaired,
                "imported_transcripts": imported_transcripts,
                "backfilled_summaries": backfilled_summaries,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
