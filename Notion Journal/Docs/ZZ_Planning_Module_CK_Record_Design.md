# ZZ Planning Module (4 Modules) + CloudKit Record Plan

## Goal
Support fast future planning capture on iPhone/iPad without immediately generating execution blocks.

You can:
- tap a future date on iPhone,
- drop a quick planning memory,
- refine later on iPad/full view,
- only generate `#WEEKLY` or daily execution blocks when you explicitly submit.

## Week Convention
- `week_start_key` uses **Sunday start** in local timezone.
- Example: week of Sunday `2026-02-15` covers `2026-02-15` to `2026-02-21`.

## 4 Modules

### 1) Future Capture Module (iPhone-first)
Purpose: quick capture to memory, no time-block generation.

Behavior:
- User taps a date or week.
- Creates a planning memory item with minimal text.
- Item stays in CK as draft memory.

Inputs:
- `target_date_key` (or `week_start_key`)
- optional short note
- optional type (`weekly` or `daily`)

Output:
- `NJPlanningItem` record with `status = "captured"`.

### 2) Planning Inbox Module (CK-backed memory)
Purpose: persistent staging area across devices.

Behavior:
- Shows all future planning items not yet submitted.
- Group by week/date.
- Lets user edit, merge, mark ready, archive.

Output:
- Items move `captured -> ready` (still no execution block yet).

### 3) Weekly/Daily Composer Module (iPad/full interface)
Purpose: review context and convert memory to concrete plan.

Behavior:
- Load ZZ schedule, health plan, and prior planning notes.
- Build:
  - Weekly plan candidate (`#WEEKLY`)
  - Daily focus candidates (date-based)
- Keep edits in planning items until submit.

Output:
- `status = "ready"` planning items with richer content.

### 4) Block Commit Module (explicit submit)
Purpose: generate real execution blocks only when confirmed.

Behavior:
- On submit, create actual execution block(s):
  - weekly block with tag `#WEEKLY`
  - optional daily block(s)
- Write generated block id(s) back to planning items.
- Mark planning items as submitted.

Output:
- `status = "submitted"`
- `generated_block_id` populated.

## CloudKit Record (Single Record Type)

### Record Type
- `NJPlanningItem`

### Entity Name (local dirty queue)
- `planning_item`

### Primary Key
- `planning_item_id` (UUID string)

### Fields
- `planning_item_id: String` - stable id
- `owner_notebook: String` - usually `ZZ`
- `domain_key: String` - e.g. `zz.edu`
- `target_kind: String` - `weekly` or `daily`
- `target_date_key: String` - `YYYY-MM-DD` (for daily target)
- `week_start_key: String` - Sunday `YYYY-MM-DD` (for weekly grouping)
- `title: String` - short summary
- `notes: String` - freeform planning memory
- `tags_json: String` - json array of tags (e.g. `["#WEEKLY"]`)
- `status: String` - `captured | ready | submitted | archived`
- `priority: Int64` - lightweight ordering
- `source_device: String` - `iphone | ipad | mac`
- `context_json: String` - optional packed refs (ZZ schedule/health pointers)
- `generated_block_id: String` - filled after submit
- `submitted_at_ms: Int64` - 0 until submitted
- `created_at_ms: Int64`
- `updated_at_ms: Int64`
- `deleted: Int64` - soft delete flag

## Why One Record Type Works
- iPhone capture and iPad planning are just state transitions on same object.
- Avoids separate “draft vs submitted” tables.
- Keeps sync simple with existing `nj_dirty` pattern.

## Required Local DB Table

`nj_planning_item`
- Mirror all fields above.
- PK: `planning_item_id`.
- Indexes:
  - `idx_nj_planning_item_target ON (target_date_key ASC)`
  - `idx_nj_planning_item_week ON (week_start_key ASC)`
  - `idx_nj_planning_item_status_updated ON (status, updated_at_ms DESC)`

## Lifecycle Rules
- Capture on iPhone always creates `status = captured`.
- Editing details can happen on any device.
- Submission can only happen from composer/commit flow.
- Submission is idempotent: if `generated_block_id` already exists, do not create a duplicate block.
- If planning changes after submit, create a new planning item revision (or reset to `ready` and clear generated id by explicit action).

## Submit Contract to Block Layer
When commit runs:
1. Resolve all `ready` planning items for target week/day.
2. Build final payload with ZZ schedule + health context.
3. Create actual block(s).
4. Update each source planning item:
   - `status = submitted`
   - `generated_block_id = <new block id>`
   - `submitted_at_ms = now`

## Minimal Implementation Steps in Current Codebase
1. Add `nj_planning_item` to `/Users/mac/Developer/Notion Journal/Notion Journal/DB/DBSchemaInstaller.swift`.
2. Add model `NJPlanningItem` to `/Users/mac/Developer/Notion Journal/Notion Journal/Model.swift`.
3. Add table adapter `DBPlanningItemTable.swift` (CRUD + applyRemote + dirty enqueue).
4. Extend `/Users/mac/Developer/Notion Journal/Notion Journal/Sync/DBCloudBridge.swift` for `planning_item` load/apply.
5. Add mapper `NJPlanningItemCloudMapper.swift`.
6. Register in `/Users/mac/Developer/Notion Journal/Notion Journal/Sync/NJCloudSchema.swift` sync order.
7. Add `inferID` support in `/Users/mac/Developer/Notion Journal/Notion Journal/Sync/NJCloudSyncCoordinator.swift`.
8. Add `applyPulled` and `localCount` cases in `/Users/mac/Developer/Notion Journal/Notion Journal/DB/DBNoteRepository.swift`.

## Example Records

### Weekly memory item
```json
{
  "planning_item_id": "plan_01",
  "target_kind": "weekly",
  "week_start_key": "2026-02-15",
  "target_date_key": "2026-02-15",
  "title": "Week prep",
  "notes": "Push sentence expansion on Monday; keep sleep stable.",
  "tags_json": "[\"#WEEKLY\"]",
  "status": "captured",
  "generated_block_id": "",
  "created_at_ms": 1760000000000,
  "updated_at_ms": 1760000000000,
  "deleted": 0
}
```

### Daily memory item
```json
{
  "planning_item_id": "plan_02",
  "target_kind": "daily",
  "week_start_key": "2026-02-15",
  "target_date_key": "2026-02-18",
  "title": "Wednesday focus",
  "notes": "Grammar drill + jog 8km",
  "tags_json": "[]",
  "status": "captured",
  "generated_block_id": "",
  "created_at_ms": 1760000500000,
  "updated_at_ms": 1760000500000,
  "deleted": 0
}
```
