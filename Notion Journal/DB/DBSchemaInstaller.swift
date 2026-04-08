import Foundation

enum DBSchemaInstaller {

    struct ColumnSpec {
        let name: String
        let declForAlter: String
    }

    struct TableSpec {
        let name: String
        let createSQL: String
        let columns: [ColumnSpec]
        let indexes: [String]
    }

    static func hardRecreateSchema(db: SQLiteDB) {
        let specs = allSpecs()
        for s in specs.reversed() {
            db.exec("DROP TABLE IF EXISTS \(s.name);")
        }
        for s in specs {
            db.exec(s.createSQL)
            for idx in s.indexes {
                db.exec(idx)
            }
        }
        print("NJ_DB_SCHEMA_RECREATED_OK")
    }

    static func ensureSchemaOrRecreate(db: SQLiteDB) {
        ensureSchema(db: db)
    }

    static func ensureSchema(db: SQLiteDB) {
        let specs = allSpecs()
        for s in specs {
            db.exec(s.createSQL)
            ensureColumns(db: db, table: s.name, columns: s.columns)
            for idx in s.indexes {
                db.exec(idx)
            }
        }
        print("NJ_DB_SCHEMA_OK")
    }

    private static func ensureColumns(db: SQLiteDB, table: String, columns: [ColumnSpec]) {
        let info = db.queryRows("PRAGMA table_info('\(table)');")
        var existing: Set<String> = []
        for r in info {
            if let n = r["name"] { existing.insert(n) }
        }
        for c in columns {
            if existing.contains(c.name) { continue }
            db.exec("ALTER TABLE \(table) ADD COLUMN \(c.name) \(c.declForAlter);")
        }
    }

    private static func hasColumns(db: SQLiteDB, table: String, required: [String]) -> Bool {
        let info = db.queryRows("PRAGMA table_info('\(table)');")
        var existing: Set<String> = []
        for r in info {
            if let n = r["name"] { existing.insert(n) }
        }
        for k in required {
            if !existing.contains(k) { return false }
        }
        return true
    }

    private static func needsHardReset(db: SQLiteDB) -> Bool {
        if !hasColumns(db: db, table: "nj_notebook", required: ["notebook_id"]) { return true }
        if !hasColumns(db: db, table: "nj_tab", required: ["tab_id", "notebook_id", "domain_key", "ord"]) { return true }
        if !hasColumns(db: db, table: "nj_dirty", required: ["attempts", "last_error"]) { return true }
        return false
    }

    private static func allSpecs() -> [TableSpec] {
        [
            TableSpec(
                name: "nj_notebook",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_notebook (
                    notebook_id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    color_hex TEXT NOT NULL,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    is_archived INTEGER NOT NULL DEFAULT 0,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "notebook_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "color_hex", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "is_archived", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_notebook_updated ON nj_notebook(updated_at_ms DESC);"
                ]
            ),

            TableSpec(
                name: "nj_tab",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_tab (
                    tab_id TEXT PRIMARY KEY,
                    notebook_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    domain_key TEXT NOT NULL,
                    color_hex TEXT NOT NULL,
                    ord INTEGER NOT NULL,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    is_hidden INTEGER NOT NULL DEFAULT 0,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "tab_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "notebook_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "domain_key", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "color_hex", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "ord", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "is_hidden", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_tab_nb_ord ON nj_tab(notebook_id, ord);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_tab_updated ON nj_tab(updated_at_ms DESC);"
                ]
            ),

            TableSpec(
                name: "nj_note",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_note (
                    note_id TEXT PRIMARY KEY,
                    notebook TEXT NOT NULL,
                    tab_domain TEXT NOT NULL,
                    title TEXT NOT NULL,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    pinned INTEGER NOT NULL DEFAULT 0,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "note_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "notebook", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "tab_domain", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "pinned", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_note_tab_updated ON nj_note(tab_domain, updated_at_ms DESC);"
                ]
            ),

            TableSpec(
                name: "nj_calendar_item",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_calendar_item (
                    date_key TEXT PRIMARY KEY,
                    title TEXT NOT NULL DEFAULT '',
                    photo_attachment_id TEXT NOT NULL DEFAULT '',
                    photo_local_id TEXT NOT NULL DEFAULT '',
                    photo_cloud_id TEXT NOT NULL DEFAULT '',
                    photo_thumb_path TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "date_key", declForAlter: "TEXT"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "photo_attachment_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "photo_local_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "photo_cloud_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "photo_thumb_path", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_calendar_item_updated ON nj_calendar_item(updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_calendar_item_date ON nj_calendar_item(date_key ASC);"
                ]
            ),
            TableSpec(
                name: "nj_planned_exercise",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_planned_exercise (
                    plan_id TEXT PRIMARY KEY,
                    date_key TEXT NOT NULL,
                    week_key TEXT NOT NULL DEFAULT '',
                    title TEXT NOT NULL DEFAULT '',
                    category TEXT NOT NULL DEFAULT '',
                    sport TEXT NOT NULL DEFAULT '',
                    session_type TEXT NOT NULL DEFAULT '',
                    target_distance_km REAL NOT NULL DEFAULT 0,
                    target_duration_min REAL NOT NULL DEFAULT 0,
                    notes TEXT NOT NULL DEFAULT '',
                    goal_json TEXT NOT NULL DEFAULT '',
                    cue_json TEXT NOT NULL DEFAULT '',
                    block_json TEXT NOT NULL DEFAULT '',
                    source_plan_id TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "plan_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "date_key", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "week_key", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "category", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "sport", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "session_type", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "target_distance_km", declForAlter: "REAL NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "target_duration_min", declForAlter: "REAL NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "notes", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "goal_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "cue_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "block_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "source_plan_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_planned_exercise_date ON nj_planned_exercise(date_key ASC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_planned_exercise_week ON nj_planned_exercise(week_key ASC, date_key ASC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_planned_exercise_updated ON nj_planned_exercise(updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_planning_note",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_planning_note (
                    planning_key TEXT PRIMARY KEY,
                    kind TEXT NOT NULL DEFAULT '',
                    target_key TEXT NOT NULL DEFAULT '',
                    note TEXT NOT NULL DEFAULT '',
                    proton_json TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "planning_key", declForAlter: "TEXT"),
                    ColumnSpec(name: "kind", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "target_key", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "note", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "proton_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_planning_note_kind_target ON nj_planning_note(kind, target_key ASC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_planning_note_updated ON nj_planning_note(updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_finance_macro_event",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_finance_macro_event (
                    event_id TEXT PRIMARY KEY,
                    date_key TEXT NOT NULL,
                    title TEXT NOT NULL DEFAULT '',
                    category TEXT NOT NULL DEFAULT '',
                    region TEXT NOT NULL DEFAULT '',
                    time_text TEXT NOT NULL DEFAULT '',
                    impact TEXT NOT NULL DEFAULT '',
                    source TEXT NOT NULL DEFAULT '',
                    notes TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "event_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "date_key", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "category", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "region", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "time_text", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "impact", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "source", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "notes", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_macro_event_date ON nj_finance_macro_event(date_key ASC, time_text ASC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_macro_event_updated ON nj_finance_macro_event(updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_finance_daily_brief",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_finance_daily_brief (
                    date_key TEXT PRIMARY KEY,
                    news_summary TEXT NOT NULL DEFAULT '',
                    expectation_summary TEXT NOT NULL DEFAULT '',
                    watch_items TEXT NOT NULL DEFAULT '',
                    bias TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "date_key", declForAlter: "TEXT"),
                    ColumnSpec(name: "news_summary", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "expectation_summary", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "watch_items", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "bias", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_daily_brief_updated ON nj_finance_daily_brief(updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_finance_research_session",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_finance_research_session (
                    session_id TEXT PRIMARY KEY,
                    title TEXT NOT NULL DEFAULT '',
                    theme_id TEXT NOT NULL DEFAULT '',
                    premise_id TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL DEFAULT '',
                    summary TEXT NOT NULL DEFAULT '',
                    last_message_at_ms INTEGER NOT NULL DEFAULT 0,
                    created_at_ms INTEGER NOT NULL DEFAULT 0,
                    updated_at_ms INTEGER NOT NULL DEFAULT 0,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "session_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "theme_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "premise_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "status", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "summary", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "last_message_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_research_session_premise ON nj_finance_research_session(premise_id ASC, updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_research_session_updated ON nj_finance_research_session(updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_finance_research_message",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_finance_research_message (
                    message_id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    role TEXT NOT NULL DEFAULT '',
                    body TEXT NOT NULL DEFAULT '',
                    source_refs_json TEXT NOT NULL DEFAULT '',
                    retrieval_context_json TEXT NOT NULL DEFAULT '',
                    task_request_json TEXT NOT NULL DEFAULT '',
                    sync_status TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL DEFAULT 0,
                    updated_at_ms INTEGER NOT NULL DEFAULT 0,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "message_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "session_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "role", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "body", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "source_refs_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "retrieval_context_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "task_request_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "sync_status", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_research_message_session_created ON nj_finance_research_message(session_id ASC, created_at_ms ASC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_research_message_sync_status ON nj_finance_research_message(sync_status ASC, updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_finance_research_task",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_finance_research_task (
                    task_id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL DEFAULT '',
                    message_id TEXT NOT NULL DEFAULT '',
                    task_kind TEXT NOT NULL DEFAULT '',
                    instruction TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL DEFAULT '',
                    priority INTEGER NOT NULL DEFAULT 0,
                    result_summary TEXT NOT NULL DEFAULT '',
                    result_refs_json TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL DEFAULT 0,
                    updated_at_ms INTEGER NOT NULL DEFAULT 0,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "task_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "session_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "message_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "task_kind", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "instruction", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "status", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "priority", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "result_summary", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "result_refs_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_research_task_session_status ON nj_finance_research_task(session_id ASC, status ASC, updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_finance_finding",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_finance_finding (
                    finding_id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL DEFAULT '',
                    premise_id TEXT NOT NULL DEFAULT '',
                    stance TEXT NOT NULL DEFAULT '',
                    summary TEXT NOT NULL DEFAULT '',
                    confidence REAL NOT NULL DEFAULT 0,
                    source_refs_json TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL DEFAULT 0,
                    updated_at_ms INTEGER NOT NULL DEFAULT 0,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "finding_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "session_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "premise_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "stance", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "summary", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "confidence", declForAlter: "REAL NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "source_refs_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_finding_session ON nj_finance_finding(session_id ASC, updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_finding_premise ON nj_finance_finding(premise_id ASC, updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_finance_journal_link",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_finance_journal_link (
                    link_id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL DEFAULT '',
                    message_id TEXT NOT NULL DEFAULT '',
                    finding_id TEXT NOT NULL DEFAULT '',
                    note_block_id TEXT NOT NULL DEFAULT '',
                    excerpt TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL DEFAULT 0,
                    updated_at_ms INTEGER NOT NULL DEFAULT 0,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "link_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "session_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "message_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "finding_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "note_block_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "excerpt", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_journal_link_session ON nj_finance_journal_link(session_id ASC, updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_finance_source_item",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_finance_source_item (
                    source_item_id TEXT PRIMARY KEY,
                    source_id TEXT NOT NULL DEFAULT '',
                    source_name TEXT NOT NULL DEFAULT '',
                    source_url TEXT NOT NULL DEFAULT '',
                    market_id TEXT NOT NULL DEFAULT '',
                    premise_ids_json TEXT NOT NULL DEFAULT '',
                    fetched_at_ms INTEGER NOT NULL DEFAULT 0,
                    published_at_ms INTEGER NOT NULL DEFAULT 0,
                    content_hash TEXT NOT NULL DEFAULT '',
                    raw_excerpt TEXT NOT NULL DEFAULT '',
                    raw_text_ck_asset_path TEXT NOT NULL DEFAULT '',
                    raw_json TEXT NOT NULL DEFAULT '',
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "source_item_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "source_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "source_name", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "source_url", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "market_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "premise_ids_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "fetched_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "published_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "content_hash", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "raw_excerpt", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "raw_text_ck_asset_path", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "raw_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_source_item_market ON nj_finance_source_item(market_id ASC, fetched_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_finance_source_item_source ON nj_finance_source_item(source_id ASC, fetched_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_time_slot",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_time_slot (
                    time_slot_id TEXT PRIMARY KEY,
                    owner_scope TEXT NOT NULL DEFAULT 'ME',
                    title TEXT NOT NULL DEFAULT '',
                    category TEXT NOT NULL DEFAULT 'personal',
                    start_at_ms INTEGER NOT NULL,
                    end_at_ms INTEGER NOT NULL,
                    notes TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "time_slot_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "owner_scope", declForAlter: "TEXT NOT NULL DEFAULT 'ME'"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "category", declForAlter: "TEXT NOT NULL DEFAULT 'personal'"),
                    ColumnSpec(name: "start_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "end_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "notes", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_time_slot_owner_start ON nj_time_slot(owner_scope, start_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_time_slot_owner_updated ON nj_time_slot(owner_scope, updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_time_slot_owner_category_start ON nj_time_slot(owner_scope, category, start_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_personal_goal",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_personal_goal (
                    goal_id TEXT PRIMARY KEY,
                    owner_scope TEXT NOT NULL DEFAULT 'ME',
                    title TEXT NOT NULL DEFAULT '',
                    focus TEXT NOT NULL DEFAULT 'keyword',
                    keyword TEXT NOT NULL DEFAULT '',
                    weekly_target INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL DEFAULT 'active',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "goal_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "owner_scope", declForAlter: "TEXT NOT NULL DEFAULT 'ME'"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "focus", declForAlter: "TEXT NOT NULL DEFAULT 'keyword'"),
                    ColumnSpec(name: "keyword", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "weekly_target", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "status", declForAlter: "TEXT NOT NULL DEFAULT 'active'"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_personal_goal_owner_status_updated ON nj_personal_goal(owner_scope, status, updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_personal_goal_owner_focus_updated ON nj_personal_goal(owner_scope, focus, updated_at_ms DESC);"
                ]
            ),

            TableSpec(
                name: "nj_block",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_block (
                    block_id TEXT PRIMARY KEY,
                    block_type TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    domain_tag TEXT,
                    tag_json TEXT,
                    goal_id TEXT,
                    lineage_id TEXT,
                    parent_block_id TEXT,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0,
                    dirty_bl INTEGER NOT NULL DEFAULT 1
                );
                """,
                columns: [
                    ColumnSpec(name: "block_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "block_type", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "payload_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "domain_tag", declForAlter: "TEXT"),
                    ColumnSpec(name: "tag_json", declForAlter: "TEXT"),
                    ColumnSpec(name: "goal_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "lineage_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "parent_block_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "dirty_bl", declForAlter: "INTEGER NOT NULL DEFAULT 1")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_block_updated ON nj_block(updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_block_goal ON nj_block(goal_id);"
                ]
            ),

            TableSpec(
                name: "nj_note_block",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_note_block (
                    instance_id TEXT PRIMARY KEY,
                    note_id TEXT NOT NULL,
                    block_id TEXT NOT NULL,
                    order_key REAL NOT NULL,
                    view_state_json TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "instance_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "note_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "block_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "order_key", declForAlter: "REAL NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "view_state_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_note_block_note_order ON nj_note_block(note_id, deleted, order_key);"
                ]
            ),

            TableSpec(
                name: "nj_dirty",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_dirty (
                        entity TEXT NOT NULL,
                        entity_id TEXT NOT NULL,
                        op TEXT NOT NULL,
                        updated_at_ms INTEGER NOT NULL,
                        attempts INTEGER NOT NULL DEFAULT 0,
                        last_error TEXT NOT NULL DEFAULT '',
                        last_error_at_ms INTEGER NOT NULL DEFAULT 0,
                        last_error_code INTEGER NOT NULL DEFAULT 0,
                        last_error_domain TEXT NOT NULL DEFAULT '',
                        next_retry_at_ms INTEGER NOT NULL DEFAULT 0,
                        ignore INTEGER NOT NULL DEFAULT 0,
                        PRIMARY KEY(entity, entity_id)
                );
                """,
                columns: [
                    ColumnSpec(name: "entity", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "entity_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "op", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "attempts", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "last_error", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "last_error_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "last_error_code", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "last_error_domain", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "next_retry_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "ignore", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_dirty_ignore_updated ON nj_dirty(ignore, updated_at_ms DESC);"
                ]
            ),

            TableSpec(
                name: "nj_attachment",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_attachment (
                    attachment_id TEXT PRIMARY KEY,
                    block_id TEXT NOT NULL,
                    note_id TEXT,
                    kind TEXT NOT NULL,
                    thumb_path TEXT,
                    full_photo_ref TEXT,
                    display_w INTEGER NOT NULL DEFAULT 400,
                    display_h INTEGER NOT NULL DEFAULT 400,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0,
                    dirty_bl INTEGER NOT NULL DEFAULT 1
                );
                """,
                columns: [
                    ColumnSpec(name: "attachment_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "block_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "note_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "kind", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "thumb_path", declForAlter: "TEXT"),
                    ColumnSpec(name: "full_photo_ref", declForAlter: "TEXT"),
                    ColumnSpec(name: "display_w", declForAlter: "INTEGER NOT NULL DEFAULT 400"),
                    ColumnSpec(name: "display_h", declForAlter: "INTEGER NOT NULL DEFAULT 400"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "dirty_bl", declForAlter: "INTEGER NOT NULL DEFAULT 1")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_attachment_block_updated ON nj_attachment(block_id, deleted, updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_attachment_note_updated ON nj_attachment(note_id, deleted, updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_attachment_updated ON nj_attachment(updated_at_ms DESC);"
                ]
            ),
            
            
            TableSpec(
                name: "nj_block_tag",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_block_tag (
                    block_id TEXT NOT NULL,
                    tag TEXT NOT NULL,
                    dirty_bl INTEGER NOT NULL DEFAULT 1,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    PRIMARY KEY(block_id, tag)
                );
                """,
                columns: [
                    ColumnSpec(name: "block_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "tag", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "dirty_bl", declForAlter: "INTEGER NOT NULL DEFAULT 1"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_block_tag_block ON nj_block_tag(block_id);"
                ]
            ),

            TableSpec(
                name: "nj_presence",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_presence (
                    target_type TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    note_id TEXT,
                    device_id TEXT NOT NULL,
                    actor TEXT NOT NULL,
                    last_seen_ms INTEGER NOT NULL,
                    PRIMARY KEY(target_type, target_id, device_id)
                );
                """,
                columns: [
                    ColumnSpec(name: "target_type", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "target_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "note_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "device_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "actor", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "last_seen_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_presence_seen ON nj_presence(last_seen_ms DESC);"
                ]
            ),

            TableSpec(
                name: "nj_kv",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_kv (
                    k TEXT PRIMARY KEY,
                    v TEXT NOT NULL
                );
                """,
                columns: [
                    ColumnSpec(name: "k", declForAlter: "TEXT"),
                    ColumnSpec(name: "v", declForAlter: "TEXT NOT NULL DEFAULT ''")
                ],
                indexes: []
            ),

            TableSpec(
                name: "nj_goal",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_goal (
                    goal_id TEXT PRIMARY KEY,
                    origin_block_id TEXT,
                    domain_tags_json TEXT NOT NULL,
                    goal_tag TEXT,
                    status TEXT NOT NULL,
                    reflect_cadence TEXT,
                    payload_json TEXT NOT NULL,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "goal_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "origin_block_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "domain_tags_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "goal_tag", declForAlter: "TEXT"),
                    ColumnSpec(name: "status", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "reflect_cadence", declForAlter: "TEXT"),
                    ColumnSpec(name: "payload_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_goal_updated ON nj_goal(updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_goal_origin ON nj_goal(origin_block_id);"
                ]
            ),
            TableSpec(
                name: "nj_outline",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_outline (
                    outline_id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    category TEXT NOT NULL DEFAULT '',
                    status TEXT NOT NULL DEFAULT '',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "outline_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "category", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "status", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_outline_updated ON nj_outline(updated_at_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_outline_category ON nj_outline(category, updated_at_ms DESC);"
                ]
            ),
            TableSpec(
                name: "nj_outline_node",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_outline_node (
                    node_id TEXT PRIMARY KEY,
                    outline_id TEXT NOT NULL,
                    parent_node_id TEXT,
                    ord INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    comment TEXT NOT NULL DEFAULT '',
                    domain_tag TEXT NOT NULL DEFAULT '',
                    is_checklist INTEGER NOT NULL DEFAULT 0,
                    is_checked INTEGER NOT NULL DEFAULT 0,
                    is_collapsed INTEGER NOT NULL DEFAULT 0,
                    filter_json TEXT NOT NULL DEFAULT '{}',
                    goal_refs_json TEXT NOT NULL DEFAULT '[]',
                    block_refs_json TEXT NOT NULL DEFAULT '[]',
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0
                );
                """,
                columns: [
                    ColumnSpec(name: "node_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "outline_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "parent_node_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "ord", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "title", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "comment", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "domain_tag", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "is_checklist", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "is_checked", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "is_collapsed", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "filter_json", declForAlter: "TEXT NOT NULL DEFAULT '{}'"),
                    ColumnSpec(name: "goal_refs_json", declForAlter: "TEXT NOT NULL DEFAULT '[]'"),
                    ColumnSpec(name: "block_refs_json", declForAlter: "TEXT NOT NULL DEFAULT '[]'"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_outline_node_outline_parent_ord ON nj_outline_node(outline_id, parent_node_id, ord);",
                    "CREATE INDEX IF NOT EXISTS idx_nj_outline_node_outline_updated ON nj_outline_node(outline_id, updated_at_ms DESC);"
                ]
            )
            ,
            TableSpec(
                name: "health_samples",
                createSQL: """
                CREATE TABLE IF NOT EXISTS health_samples (
                    sample_id TEXT PRIMARY KEY,
                    type TEXT NOT NULL,
                    start_ms INTEGER NOT NULL,
                    end_ms INTEGER NOT NULL,
                    value_num REAL NOT NULL DEFAULT 0,
                    value_str TEXT NOT NULL DEFAULT '',
                    unit TEXT NOT NULL DEFAULT '',
                    source TEXT NOT NULL DEFAULT '',
                    metadata_json TEXT NOT NULL DEFAULT '',
                    device_id TEXT NOT NULL DEFAULT '',
                    inserted_at_ms INTEGER NOT NULL
                );
                """,
                columns: [
                    ColumnSpec(name: "sample_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "type", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "start_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "end_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "value_num", declForAlter: "REAL NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "value_str", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "unit", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "source", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "metadata_json", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "device_id", declForAlter: "TEXT NOT NULL DEFAULT ''"),
                    ColumnSpec(name: "inserted_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_health_samples_type_start ON health_samples(type, start_ms DESC);",
                    "CREATE INDEX IF NOT EXISTS idx_health_samples_start ON health_samples(start_ms DESC);"
                ]
            )

        ]
    }
}
