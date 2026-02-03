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
                name: "nj_block",
                createSQL: """
                CREATE TABLE IF NOT EXISTS nj_block (
                    block_id TEXT PRIMARY KEY,
                    block_type TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    domain_tag TEXT,
                    tag_json TEXT,
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
                    ColumnSpec(name: "lineage_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "parent_block_id", declForAlter: "TEXT"),
                    ColumnSpec(name: "created_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "updated_at_ms", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "deleted", declForAlter: "INTEGER NOT NULL DEFAULT 0"),
                    ColumnSpec(name: "dirty_bl", declForAlter: "INTEGER NOT NULL DEFAULT 1")
                ],
                indexes: [
                    "CREATE INDEX IF NOT EXISTS idx_nj_block_updated ON nj_block(updated_at_ms DESC);"
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
