# ME Time Module: CloudKit Record Design

## Goal
Sync personal time slots and personal goals across iPhone/iPad/Mac/Watch.

## Record Types

### 1) `NJTimeSlot`
Primary key field:
- `time_slot_id: String` (UUID, stable)

Fields:
- `time_slot_id: String`
- `owner_scope: String` (`"ME"`)
- `title: String`
- `category: String` (`piano | exercise | personal`)
- `start_at_ms: Int64`
- `end_at_ms: Int64`
- `notes: String`
- `created_at_ms: Int64`
- `updated_at_ms: Int64`
- `deleted: Int64` (`0 | 1`)

CloudKit indexes to add:
- Query index: `owner_scope ASC, start_at_ms DESC`
- Query index: `owner_scope ASC, updated_at_ms DESC`
- Query index: `owner_scope ASC, category ASC, start_at_ms DESC`
- Query index: `time_slot_id ASC` (for direct fetch checks)

### 2) `NJPersonalGoal`
Primary key field:
- `goal_id: String` (UUID, stable)

Fields:
- `goal_id: String`
- `owner_scope: String` (`"ME"`)
- `title: String`
- `focus: String` (`piano | exercise | keyword`)
- `keyword: String`
- `weekly_target: Int64`
- `status: String` (`active | archived`)
- `created_at_ms: Int64`
- `updated_at_ms: Int64`
- `deleted: Int64` (`0 | 1`)

CloudKit indexes to add:
- Query index: `owner_scope ASC, status ASC, updated_at_ms DESC`
- Query index: `owner_scope ASC, focus ASC, updated_at_ms DESC`
- Query index: `goal_id ASC`

## Entity mapping (local sync queue)
- `time_slot` -> `NJTimeSlot`
- `personal_goal` -> `NJPersonalGoal`

## Notes
- Keep one owner scope (`ME`) for this module to avoid mixing with ZZ items.
- Keep soft-delete (`deleted`) so sync stays idempotent with existing dirty queue behavior.
