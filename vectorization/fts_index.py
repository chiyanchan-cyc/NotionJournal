#!/usr/bin/env python3

import argparse
import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Optional


DEFAULT_OUT_DIR = Path(".nj_semantic_memory")


@dataclass(frozen=True)
class QueryFilters:
    week_start: Optional[str] = None
    tag: Optional[str] = None
    kind: Optional[str] = None
    mentioned_date: Optional[str] = None


def _connect(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.execute("PRAGMA temp_store=MEMORY;")
    return conn


def _init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS docs (
          doc_id TEXT NOT NULL UNIQUE,
          week_start TEXT NOT NULL,
          ts_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL,
          notebook TEXT,
          tab_domain TEXT,
          note_title TEXT,
          tags_text TEXT,
          tags_json TEXT,
          kinds_json TEXT,
          mentioned_dates_json TEXT,
          text_hash TEXT,
          text TEXT
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
          text,
          note_title,
          notebook,
          tags_text,
          content='docs',
          content_rowid='rowid',
          tokenize='unicode61'
        );

        CREATE TRIGGER IF NOT EXISTS docs_ai AFTER INSERT ON docs BEGIN
          INSERT INTO docs_fts(rowid, text, note_title, notebook, tags_text)
          VALUES (new.rowid, new.text, new.note_title, new.notebook, new.tags_text);
        END;
        CREATE TRIGGER IF NOT EXISTS docs_ad AFTER DELETE ON docs BEGIN
          INSERT INTO docs_fts(docs_fts, rowid, text, note_title, notebook, tags_text)
          VALUES('delete', old.rowid, old.text, old.note_title, old.notebook, old.tags_text);
        END;
        CREATE TRIGGER IF NOT EXISTS docs_au AFTER UPDATE ON docs BEGIN
          INSERT INTO docs_fts(docs_fts, rowid, text, note_title, notebook, tags_text)
          VALUES('delete', old.rowid, old.text, old.note_title, old.notebook, old.tags_text);
          INSERT INTO docs_fts(rowid, text, note_title, notebook, tags_text)
          VALUES (new.rowid, new.text, new.note_title, new.notebook, new.tags_text);
        END;

        CREATE TABLE IF NOT EXISTS meta (
          key TEXT PRIMARY KEY,
          value TEXT
        );
        """
    )


def _iter_week_jsonl_paths(out_dir: Path) -> list[Path]:
    weeks_dir = out_dir / "weeks"
    if not weeks_dir.exists():
        return []
    return sorted(p for p in weeks_dir.glob("week_*.jsonl") if p.is_file())


def _read_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if isinstance(obj, dict):
                yield obj


def _as_text(v: Any) -> str:
    if v is None:
        return ""
    if isinstance(v, str):
        return v
    return str(v)


def _index_docs(conn: sqlite3.Connection, out_dir: Path) -> dict[str, Any]:
    paths = _iter_week_jsonl_paths(out_dir)
    if not paths:
        return {"indexed": 0, "updated": 0, "paths": 0}

    cur = conn.cursor()
    updated = 0
    indexed = 0

    cur.execute("BEGIN;")
    for p in paths:
        for doc in _read_jsonl(p):
            if doc.get("schema") != "nj_weekly_doc_v1":
                continue

            doc_id = _as_text(doc.get("doc_id"))
            if not doc_id:
                continue

            week_start = _as_text(doc.get("week_start"))
            ts_ms = int(doc.get("ts_ms") or 0)
            updated_at_ms = int(doc.get("updated_at_ms") or 0)
            text_hash = _as_text(doc.get("text_hash"))
            text = _as_text(doc.get("text"))

            note = doc.get("note") if isinstance(doc.get("note"), dict) else {}
            notebook = _as_text(note.get("notebook"))
            tab_domain = _as_text(note.get("tab_domain"))
            note_title = _as_text(note.get("title"))

            tags = doc.get("tags") if isinstance(doc.get("tags"), list) else []
            tags_norm = [t.strip().lower() for t in tags if isinstance(t, str) and t.strip()]
            tags_text = " ".join(sorted(set(tags_norm)))

            semantics = doc.get("semantics") if isinstance(doc.get("semantics"), dict) else {}
            kinds = semantics.get("kinds") if isinstance(semantics.get("kinds"), list) else []
            kinds_norm = [k.strip().lower() for k in kinds if isinstance(k, str) and k.strip()]
            mentioned_dates = semantics.get("mentioned_dates") if isinstance(semantics.get("mentioned_dates"), list) else []
            mentioned_dates_norm = [d for d in mentioned_dates if isinstance(d, str) and d]

            existing = cur.execute(
                "SELECT updated_at_ms, text_hash FROM docs WHERE doc_id = ?;",
                (doc_id,),
            ).fetchone()
            if existing is not None:
                if int(existing["updated_at_ms"] or 0) == updated_at_ms and _as_text(existing["text_hash"]) == text_hash:
                    indexed += 1
                    continue

            cur.execute(
                """
                INSERT INTO docs(
                  doc_id, week_start, ts_ms, updated_at_ms,
                  notebook, tab_domain, note_title,
                  tags_text, tags_json, kinds_json, mentioned_dates_json,
                  text_hash, text
                )
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(doc_id) DO UPDATE SET
                  week_start=excluded.week_start,
                  ts_ms=excluded.ts_ms,
                  updated_at_ms=excluded.updated_at_ms,
                  notebook=excluded.notebook,
                  tab_domain=excluded.tab_domain,
                  note_title=excluded.note_title,
                  tags_text=excluded.tags_text,
                  tags_json=excluded.tags_json,
                  kinds_json=excluded.kinds_json,
                  mentioned_dates_json=excluded.mentioned_dates_json,
                  text_hash=excluded.text_hash,
                  text=excluded.text;
                """,
                (
                    doc_id,
                    week_start,
                    ts_ms,
                    updated_at_ms,
                    notebook,
                    tab_domain,
                    note_title,
                    tags_text,
                    json.dumps(sorted(set(tags_norm)), ensure_ascii=False),
                    json.dumps(sorted(set(kinds_norm)), ensure_ascii=False),
                    json.dumps(sorted(set(mentioned_dates_norm)), ensure_ascii=False),
                    text_hash,
                    text,
                ),
            )
            updated += 1
            indexed += 1

    cur.execute(
        """
        INSERT INTO meta(key, value)
        VALUES('schema', 'nj_fts_index_v1')
        ON CONFLICT(key) DO UPDATE SET value=excluded.value;
        """
    )
    cur.execute(
        """
        INSERT INTO meta(key, value)
        VALUES('last_built_at_unix_ms', CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER))
        ON CONFLICT(key) DO UPDATE SET value=excluded.value;
        """
    )

    cur.execute("COMMIT;")
    return {"indexed": indexed, "updated": updated, "paths": len(paths)}


def _build_where(filters: QueryFilters) -> tuple[str, list[Any]]:
    clauses: list[str] = []
    args: list[Any] = []
    if filters.week_start:
        clauses.append("d.week_start = ?")
        args.append(filters.week_start)
    if filters.tag:
        clauses.append("EXISTS (SELECT 1 FROM json_each(d.tags_json) WHERE value = ?)")
        args.append(filters.tag.strip().lower())
    if filters.kind:
        clauses.append("EXISTS (SELECT 1 FROM json_each(d.kinds_json) WHERE value = ?)")
        args.append(filters.kind.strip().lower())
    if filters.mentioned_date:
        clauses.append("EXISTS (SELECT 1 FROM json_each(d.mentioned_dates_json) WHERE value = ?)")
        args.append(filters.mentioned_date)
    if not clauses:
        return ("", [])
    return (" AND " + " AND ".join(clauses), args)


def _query(
    conn: sqlite3.Connection,
    q: str,
    *,
    limit: int,
    filters: QueryFilters,
) -> list[dict[str, Any]]:
    q = q.strip()
    if not q:
        return []
    where_extra, extra_args = _build_where(filters)

    sql = f"""
    SELECT
      d.doc_id,
      d.week_start,
      d.ts_ms,
      d.updated_at_ms,
      d.notebook,
      d.tab_domain,
      d.note_title,
      d.tags_json,
      d.kinds_json,
      d.mentioned_dates_json,
      bm25(docs_fts) AS score
    FROM docs_fts
    JOIN docs d ON d.rowid = docs_fts.rowid
    WHERE docs_fts MATCH ?{where_extra}
    ORDER BY score ASC
    LIMIT ?;
    """
    rows = conn.execute(sql, [q, *extra_args, int(limit)]).fetchall()
    out: list[dict[str, Any]] = []
    for r in rows:
        out.append({k: r[k] for k in r.keys()})
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Build/query a local SQLite FTS index over weekly Notion Journal snapshots.")
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    ap.add_argument("--db-path", type=Path, default=None)
    sub = ap.add_subparsers(dest="cmd", required=True)

    ap_build = sub.add_parser("build", help="Build or incrementally update index.sqlite from weeks/*.jsonl")
    ap_build.add_argument("--vacuum", action="store_true", help="VACUUM the DB after building (slower).")

    ap_query = sub.add_parser("query", help="Search (FTS5) with optional deterministic filters.")
    ap_query.add_argument("q", type=str, help="FTS query string, e.g. \"sleep AND #health\"")
    ap_query.add_argument("--limit", type=int, default=10)
    ap_query.add_argument("--week", type=str, default=None, help="Filter: week start (YYYY-MM-DD, local Monday).")
    ap_query.add_argument("--tag", type=str, default=None, help="Filter: tag (lowercased).")
    ap_query.add_argument("--kind", type=str, default=None, help="Filter: plan|fact|backfill (lowercased).")
    ap_query.add_argument("--mentioned-date", type=str, default=None, help="Filter: mentioned date (YYYY-MM-DD).")
    ap_query.add_argument("--json", action="store_true", help="Emit JSON (default is line-delimited).")

    args = ap.parse_args()

    out_dir: Path = args.out_dir
    db_path: Path = args.db_path or (out_dir / "index.sqlite")
    out_dir.mkdir(parents=True, exist_ok=True)

    with _connect(db_path) as conn:
        _init_schema(conn)
        if args.cmd == "build":
            meta = _index_docs(conn, out_dir=out_dir)
            if args.vacuum:
                conn.execute("VACUUM;")
            print(json.dumps({"ok": True, "db_path": str(db_path), **meta}, ensure_ascii=False))
            return 0

        if args.cmd == "query":
            filters = QueryFilters(
                week_start=args.week,
                tag=args.tag,
                kind=args.kind,
                mentioned_date=args.mentioned_date,
            )
            hits = _query(conn, args.q, limit=int(args.limit), filters=filters)
            if args.json:
                print(json.dumps({"q": args.q, "hits": hits}, ensure_ascii=False, indent=2))
            else:
                for h in hits:
                    tags = ",".join(json.loads(h["tags_json"] or "[]"))
                    kinds = ",".join(json.loads(h["kinds_json"] or "[]"))
                    title = _as_text(h.get("note_title"))
                    week = _as_text(h.get("week_start"))
                    print(f"{h['doc_id']}  week={week}  score={h['score']:.3f}  kinds={kinds}  tags={tags}  title={title}")
            return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())

