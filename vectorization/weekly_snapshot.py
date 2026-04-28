#!/usr/bin/env python3

import argparse
import base64
import hashlib
import json
import re
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

try:
    from zoneinfo import ZoneInfo  # py>=3.9
except Exception:  # pragma: no cover
    ZoneInfo = None  # type: ignore[assignment]


DEFAULT_DB_PATH = Path(
    "/Users/mac/Library/Containers/FA955BEC-40DE-460A-84C5-691E7BAB14F9/Data/Documents/notion_journal.sqlite"
)


@dataclass(frozen=True)
class WeekWindow:
    tz_id: str
    week_start_local: datetime
    week_end_local: datetime

    @property
    def week_key(self) -> str:
        return self.week_start_local.strftime("%Y-%m-%d")

    def contains_ms_utc(self, ts_ms: int) -> bool:
        ts = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc).astimezone(self.week_start_local.tzinfo)
        return self.week_start_local <= ts < self.week_end_local


def _rtf_bytes_to_text(data: bytes) -> str:
    """
    Deterministic, dependency-free RTF -> plain text conversion.
    This is intentionally conservative (good enough for journal RTF produced by iOS/macOS).
    """
    try:
        s = data.decode("latin-1", errors="replace")
    except Exception:
        return ""

    out: list[str] = []
    i = 0
    n = len(s)
    pending_high_surrogate: Optional[int] = None

    def emit(ch: str) -> None:
        out.append(ch)

    while i < n:
        ch = s[i]
        if pending_high_surrogate is not None and ch != "\\":
            emit("\uFFFD")
            pending_high_surrogate = None
        if ch in "{}":
            i += 1
            continue
        if ch != "\\":
            emit(ch)
            i += 1
            continue

        # Control sequence
        i += 1
        if i >= n:
            break
        c = s[i]

        # Escaped literal characters
        if c in "\\{}":
            emit(c)
            i += 1
            continue

        # Hex escape \'hh
        if c == "'":
            if i + 2 < n:
                hx = s[i + 1 : i + 3]
                try:
                    emit(bytes([int(hx, 16)]).decode("latin-1", errors="replace"))
                except Exception:
                    pass
                i += 3
                continue
            i += 1
            continue

        # Single-character control symbols
        if c == "~":
            emit(" ")
            i += 1
            continue
        if c == "-":
            emit("-")
            i += 1
            continue
        if c == "_":
            emit("-")
            i += 1
            continue

        # Control word: letters + optional numeric parameter
        j = i
        while j < n and s[j].isalpha():
            j += 1
        word = s[i:j]

        # Optional numeric param
        k = j
        sign = 1
        if k < n and s[k] in "+-":
            if s[k] == "-":
                sign = -1
            k += 1
        num_start = k
        while k < n and s[k].isdigit():
            k += 1
        num_str = s[num_start:k]
        num_val: Optional[int] = None
        if num_str:
            try:
                num_val = sign * int(num_str)
            except Exception:
                num_val = None

        # Consume delimiter space if present
        if k < n and s[k] == " ":
            k += 1

        # Effects
        if word in {"par", "line"}:
            if pending_high_surrogate is not None:
                emit("\uFFFD")
                pending_high_surrogate = None
            emit("\n")
        elif word == "tab":
            if pending_high_surrogate is not None:
                emit("\uFFFD")
                pending_high_surrogate = None
            emit("\t")
        elif word == "emdash":
            if pending_high_surrogate is not None:
                emit("\uFFFD")
                pending_high_surrogate = None
            emit("—")
        elif word == "endash":
            if pending_high_surrogate is not None:
                emit("\uFFFD")
                pending_high_surrogate = None
            emit("–")
        elif word == "bullet":
            if pending_high_surrogate is not None:
                emit("\uFFFD")
                pending_high_surrogate = None
            emit("•")
        elif word == "u" and num_val is not None:
            # RTF uses signed 16-bit values for \uN
            v = num_val
            if v < 0:
                v = 65536 + v
            if 0xD800 <= v <= 0xDBFF:
                # High surrogate (likely part of an emoji). Wait for the next \u.
                if pending_high_surrogate is not None:
                    emit("\uFFFD")
                pending_high_surrogate = v
            elif 0xDC00 <= v <= 0xDFFF:
                # Low surrogate.
                if pending_high_surrogate is not None:
                    hi = pending_high_surrogate
                    lo = v
                    codepoint = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                    try:
                        emit(chr(codepoint))
                    except Exception:
                        emit("\uFFFD")
                    pending_high_surrogate = None
                else:
                    emit("\uFFFD")
            else:
                if pending_high_surrogate is not None:
                    emit("\uFFFD")
                    pending_high_surrogate = None
                try:
                    emit(chr(v))
                except Exception:
                    emit("\uFFFD")
            # Per spec, there may be a fallback character immediately after; skip it.
            if k < n:
                k += 1

        i = k

    if pending_high_surrogate is not None:
        emit("\uFFFD")
        pending_high_surrogate = None

    text = "".join(out)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _utf8_clean(s: str) -> str:
    # Prevent unpaired surrogate issues when writing JSON with ensure_ascii=False.
    return s.encode("utf-8", "replace").decode("utf-8")


def _plain_text_from_payload_json(payload_json: str) -> tuple[str, str]:
    """
    Returns (plain_text, rtf_base64).
    Mirrors the behavior of `Notion Journal/Export/NJBlockExporter.swift`:
    - Prefer `proton_json` -> nested `rtf_base64`
    - Fall back to a direct `rtf_base64` key
    """
    try:
        root = json.loads(payload_json)
    except Exception:
        return ("", "")

    def find_string(any_obj: Any, key: str) -> Optional[str]:
        if isinstance(any_obj, dict):
            v = any_obj.get(key)
            if isinstance(v, str) and v:
                return v
            for vv in any_obj.values():
                hit = find_string(vv, key)
                if hit:
                    return hit
        elif isinstance(any_obj, list):
            for vv in any_obj:
                hit = find_string(vv, key)
                if hit:
                    return hit
        return None

    def find_rtf(any_obj: Any) -> Optional[str]:
        if isinstance(any_obj, dict):
            v = any_obj.get("rtf_base64")
            if isinstance(v, str) and v:
                return v
            for vv in any_obj.values():
                hit = find_rtf(vv)
                if hit:
                    return hit
        elif isinstance(any_obj, list):
            for vv in any_obj:
                hit = find_rtf(vv)
                if hit:
                    return hit
        return None

    proton_json = find_string(root, "proton_json")
    if proton_json:
        try:
            pobj = json.loads(proton_json)
            rtf64 = find_rtf(pobj) or ""
        except Exception:
            rtf64 = ""
        if rtf64:
            try:
                raw = base64.b64decode(rtf64, validate=False)
                return (_rtf_bytes_to_text(raw), rtf64)
            except Exception:
                return ("", rtf64)

    rtf64 = find_string(root, "rtf_base64") or ""
    if not rtf64:
        return ("", "")
    try:
        raw = base64.b64decode(rtf64, validate=False)
        return (_rtf_bytes_to_text(raw), rtf64)
    except Exception:
        return ("", rtf64)


_HASHTAG_RE = re.compile(r"(?<!\w)#([a-zA-Z][\w\-]{1,63})")
_DATE_YMD_RE = re.compile(r"\b(20\d{2})[-/](0[1-9]|1[0-2])[-/](0[1-9]|[12]\d|3[01])\b")
_DATE_MDY_RE = re.compile(r"\b(0?[1-9]|1[0-2])/(0?[1-9]|[12]\d|3[01])/(20\d{2})\b")


def _extract_semantics(text: str, tags: list[str]) -> dict[str, Any]:
    normalized_tags = [t.strip() for t in tags if t and t.strip()]
    tag_set = {t.lower() for t in normalized_tags}

    hashtags = sorted({m.group(1).lower() for m in _HASHTAG_RE.finditer(text)})
    if hashtags:
        tag_set |= set(hashtags)

    kinds: list[str] = []
    if tag_set & {"plan", "planning", "todo", "task", "next"}:
        kinds.append("plan")
    if tag_set & {"fact", "log", "done", "journal"}:
        kinds.append("fact")
    if tag_set & {"backfill", "retro", "catchup"}:
        kinds.append("backfill")

    mentioned_dates: set[str] = set()
    for m in _DATE_YMD_RE.finditer(text):
        y, mo, d = m.group(1), m.group(2), m.group(3)
        mentioned_dates.add(f"{y}-{mo}-{d}")
    for m in _DATE_MDY_RE.finditer(text):
        mo, d, y = m.group(1), m.group(2), m.group(3)
        mentioned_dates.add(f"{y}-{int(mo):02d}-{int(d):02d}")

    return {
        "kinds": kinds,
        "hashtags": hashtags,
        "mentioned_dates": sorted(mentioned_dates),
    }


def _sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8", errors="replace")).hexdigest()


def _week_window_for_ts_ms(ts_ms: int, tz_id: str) -> WeekWindow:
    if ZoneInfo is None:
        tz = timezone.utc
        tz_id = "UTC"
    else:
        tz = ZoneInfo(tz_id)
    local_dt = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc).astimezone(tz)
    monday = local_dt.date() - timedelta(days=local_dt.weekday())
    start_local = datetime(monday.year, monday.month, monday.day, 0, 0, 0, tzinfo=tz)
    end_local = start_local + timedelta(days=7)
    return WeekWindow(tz_id=tz_id, week_start_local=start_local, week_end_local=end_local)


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def _read_manifest(out_dir: Path) -> dict[str, Any]:
    path = out_dir / "manifest.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _write_manifest(out_dir: Path, obj: dict[str, Any]) -> None:
    path = out_dir / "manifest.json"
    path.write_text(json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def _query_changed_week_keys(conn: sqlite3.Connection, since_ms: int, tz_id: str) -> set[str]:
    sql = """
    SELECT
      b.created_at_ms AS ts_ms
    FROM nj_note_block nb
    JOIN nj_block b ON b.block_id = nb.block_id
    JOIN nj_note n ON n.note_id = nb.note_id
    WHERE
      nb.updated_at_ms > ?
      OR b.updated_at_ms > ?
      OR n.updated_at_ms > ?;
    """
    week_keys: set[str] = set()
    for r in conn.execute(sql, (since_ms, since_ms, since_ms)):
        ts_ms = int(r["ts_ms"] or 0)
        if ts_ms <= 0:
            continue
        week_keys.add(_week_window_for_ts_ms(ts_ms, tz_id).week_key)
    return week_keys


def _week_bounds_ms_utc(week_key: str, tz_id: str) -> tuple[int, int]:
    # week_key is Monday local date "YYYY-MM-DD"
    y, m, d = (int(x) for x in week_key.split("-"))
    if ZoneInfo is None:
        tz = timezone.utc
    else:
        tz = ZoneInfo(tz_id)
    start_local = datetime(y, m, d, 0, 0, 0, tzinfo=tz)
    end_local = start_local + timedelta(days=7)
    start_utc = start_local.astimezone(timezone.utc)
    end_utc = end_local.astimezone(timezone.utc)
    return (int(start_utc.timestamp() * 1000), int(end_utc.timestamp() * 1000))


def _export_week(
    conn: sqlite3.Connection,
    out_dir: Path,
    week_key: str,
    tz_id: str,
    *,
    include_rtf: bool,
) -> dict[str, Any]:
    start_ms, end_ms = _week_bounds_ms_utc(week_key, tz_id)
    sql = """
    SELECT
      nb.instance_id,
      nb.note_id,
      nb.block_id,
      nb.order_key,
      nb.is_checked,
      nb.created_at_ms AS nb_created_at_ms,
      nb.updated_at_ms AS nb_updated_at_ms,
      nb.deleted AS nb_deleted,

      b.block_type,
      b.payload_json,
      b.domain_tag,
      b.tag_json,
      b.created_at_ms AS b_created_at_ms,
      b.updated_at_ms AS b_updated_at_ms,
      b.deleted AS b_deleted,

      n.notebook,
      n.tab_domain,
      n.title AS note_title,
      n.note_type,
      n.created_at_ms AS n_created_at_ms,
      n.updated_at_ms AS n_updated_at_ms,
      n.deleted AS n_deleted,

      (
        SELECT group_concat(tag, '\n')
        FROM nj_block_tag t
        WHERE t.block_id = b.block_id
      ) AS block_tags
    FROM nj_note_block nb
    JOIN nj_block b ON b.block_id = nb.block_id
    JOIN nj_note n ON n.note_id = nb.note_id
    WHERE
      b.created_at_ms >= ?
      AND b.created_at_ms < ?
      AND nb.deleted = 0
      AND b.deleted = 0
      AND n.deleted = 0
    ORDER BY b.created_at_ms ASC, nb.order_key ASC;
    """
    rows = list(conn.execute(sql, (start_ms, end_ms)))

    weeks_dir = out_dir / "weeks"
    weeks_dir.mkdir(parents=True, exist_ok=True)
    out_path = weeks_dir / f"week_{week_key}.jsonl"

    max_updated_at_ms = 0
    written = 0
    with out_path.open("w", encoding="utf-8") as f:
        for r in rows:
            payload_json = r["payload_json"] or "{}"
            text, rtf64 = _plain_text_from_payload_json(payload_json)
            text = _utf8_clean(text)
            tags = []
            if r["block_tags"]:
                tags = [t for t in str(r["block_tags"]).split("\n") if t.strip()]

            ts_ms = int(r["b_created_at_ms"] or 0)
            if ts_ms <= 0:
                continue

            ww = _week_window_for_ts_ms(ts_ms, tz_id)
            local_dt = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc).astimezone(ww.week_start_local.tzinfo)

            updated_at_ms = max(int(r["nb_updated_at_ms"] or 0), int(r["b_updated_at_ms"] or 0), int(r["n_updated_at_ms"] or 0))
            max_updated_at_ms = max(max_updated_at_ms, updated_at_ms)

            semantics = _extract_semantics(text, tags)
            tag_set = sorted({t.strip().lower() for t in tags if t.strip()} | set(semantics["hashtags"]))

            doc: dict[str, Any] = {
                "schema": "nj_weekly_doc_v1",
                "doc_id": str(r["instance_id"]),
                "week_start": ww.week_key,
                "ts_ms": ts_ms,
                "ts_local": local_dt.isoformat(),
                "updated_at_ms": updated_at_ms,
                "note": {
                    "note_id": str(r["note_id"]),
                    "notebook": _utf8_clean(str(r["notebook"] or "")),
                    "tab_domain": _utf8_clean(str(r["tab_domain"] or "")),
                    "title": _utf8_clean(str(r["note_title"] or "")),
                    "note_type": _utf8_clean(str(r["note_type"] or "")),
                },
                "block": {
                    "block_id": str(r["block_id"]),
                    "block_type": _utf8_clean(str(r["block_type"] or "")),
                    "domain_tag": _utf8_clean(str(r["domain_tag"] or "")),
                    "tag_json": _utf8_clean(str(r["tag_json"] or "")),
                },
                "tags": tag_set,
                "semantics": semantics,
                "text_hash": _sha256_text(text),
                "text": text,
            }
            if include_rtf:
                doc["rtf_base64"] = rtf64

            f.write(json.dumps(doc, sort_keys=True, ensure_ascii=False) + "\n")
            written += 1

    return {
        "week_key": week_key,
        "start_ms": start_ms,
        "end_ms": end_ms,
        "docs": written,
        "max_updated_at_ms": max_updated_at_ms,
        "out_path": str(out_path),
    }


def _iter_recent_week_keys(end_dt_local: datetime, weeks: int) -> list[str]:
    # Compute keys for the last N weeks (including the week containing end_dt_local).
    keys: list[str] = []
    ts_ms = int(end_dt_local.astimezone(timezone.utc).timestamp() * 1000)
    tz_id = end_dt_local.tzinfo.key if hasattr(end_dt_local.tzinfo, "key") else "UTC"
    w = _week_window_for_ts_ms(ts_ms, tz_id)
    cursor = w.week_start_local
    for _ in range(max(1, weeks)):
        keys.append(cursor.strftime("%Y-%m-%d"))
        cursor = cursor - timedelta(days=7)
    return sorted(set(keys))


def main() -> int:
    ap = argparse.ArgumentParser(description="Export weekly local-first semantic snapshots from Notion Journal sqlite.")
    ap.add_argument("--db-path", type=Path, default=DEFAULT_DB_PATH)
    ap.add_argument("--out-dir", type=Path, default=Path(".nj_semantic_memory"))
    ap.add_argument("--tz", type=str, default="Asia/Shanghai")
    ap.add_argument("--weeks", type=int, default=8, help="If first run, export the most recent N weeks.")
    ap.add_argument("--full", action="store_true", help="Re-export recent weeks even if manifest exists.")
    ap.add_argument("--include-rtf", action="store_true", help="Include `rtf_base64` in JSONL output (larger files).")
    ap.add_argument("--dry-run", action="store_true", help="Compute which weeks would export, without writing.")
    args = ap.parse_args()

    db_path: Path = args.db_path
    out_dir: Path = args.out_dir
    tz_id: str = args.tz

    if not db_path.exists():
        raise SystemExit(f"DB not found: {db_path}")

    manifest = _read_manifest(out_dir)
    since_ms = int(manifest.get("max_seen_updated_at_ms") or 0)

    if ZoneInfo is None:
        tz = timezone.utc
        tz_id = "UTC"
    else:
        tz = ZoneInfo(tz_id)

    now_local = datetime.now(tz=tz)
    out_dir.mkdir(parents=True, exist_ok=True)

    with _connect(db_path) as conn:
        if manifest and not args.full:
            week_keys = _query_changed_week_keys(conn, since_ms=since_ms, tz_id=tz_id)
            # If nothing changed, exit early.
            if not week_keys:
                if args.dry_run:
                    print("No changes detected; nothing to export.")
                return 0
        else:
            week_keys = set(_iter_recent_week_keys(now_local, weeks=int(args.weeks)))

        week_keys_list = sorted(week_keys)
        if args.dry_run:
            print(f"Would export {len(week_keys_list)} week(s): {', '.join(week_keys_list)}")
            return 0

        exported: list[dict[str, Any]] = []
        max_seen_updated = since_ms
        for wk in week_keys_list:
            meta = _export_week(conn, out_dir=out_dir, week_key=wk, tz_id=tz_id, include_rtf=bool(args.include_rtf))
            exported.append(meta)
            max_seen_updated = max(max_seen_updated, int(meta["max_updated_at_ms"] or 0))

        new_manifest = {
            "schema": "nj_weekly_snapshot_manifest_v1",
            "db_path": str(db_path),
            "tz": tz_id,
            "generated_at_local": now_local.isoformat(),
            "max_seen_updated_at_ms": max_seen_updated,
            "weeks_written": [m["week_key"] for m in exported],
        }
        _write_manifest(out_dir, new_manifest)

        total_docs = sum(int(m["docs"]) for m in exported)
        print(f"Exported weeks={len(exported)} docs={total_docs} out_dir={out_dir}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
