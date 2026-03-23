---
phase: A2-sync-delete
plan: "01"
subsystem: sync
tags: [offline-sync, delete, sqlite, api, flutter, fastapi]
dependency_graph:
  requires: []
  provides: [offline-delete-sync]
  affects: [sync_manager, sqlite_helper, api_service, api_routers]
tech_stack:
  added: []
  patterns: [soft-delete-then-hard-delete, ownership-check-404]
key_files:
  created:
    - emotionai-app/docs/learning/flutter_api_patterns.md
  modified:
    - emotionai-app/lib/shared/services/sqlite_helper.dart
    - emotionai-app/lib/config/api_config.dart
    - emotionai-app/lib/data/api_service.dart
    - emotionai-app/lib/core/sync/sync_manager.dart
    - emotionai-api/src/presentation/api/routers/records.py
    - emotionai-api/src/presentation/api/routers/breathing.py
    - emotionai-api/src/presentation/api/routers/data.py
decisions:
  - "Hard-delete on API (server drives source of truth); soft-delete in SQLite until API confirms 204"
  - "All four get*/getAll* queries filter WHERE deleted_at IS NULL to prevent resurrection during download merge"
  - "Renamed existing SQLiteHelper.deleteCustomEmotion kept intact; added hardDeleteCustomEmotion and softDeleteCustomEmotion alongside it"
  - "Null check on SyncItem.id removed (field is non-nullable String) to satisfy flutter analyze"
metrics:
  duration: "~25 minutes"
  completed: "2026-03-23"
  tasks_completed: 3
  files_changed: 7
---

# Phase A2 Plan 01: Sync Delete Summary

**One-liner**: Full offline-delete sync path using soft-delete (deleted_at) in SQLite v11, four API DELETE endpoints with ownership checks, and a functioning _handleDelete dispatcher in SyncManager.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | API: four DELETE endpoints | c80f827 | records.py, breathing.py, data.py |
| 2 | App: schema v11, URL builders, ApiService delete methods | 9b69282 | sqlite_helper.dart, api_config.dart, api_service.dart |
| 3 | App: fix _handleDelete, annotate _handleUpdate, learning doc | f02fbb5 | sync_manager.dart, docs/learning/flutter_api_patterns.md |

## What Was Built

### API — Four DELETE endpoints (records.py, breathing.py, data.py)

- `DELETE /v1/api/emotional_records/{record_id}` — ownership check (user_id), 404 if not found, 204 on success
- `DELETE /v1/api/breathing_sessions/{session_id}` — same ownership pattern
- `DELETE /v1/api/breathing_patterns/{pattern_id}` — ownership check plus `is_preset == False` guard (presets cannot be deleted)
- `DELETE /v1/api/custom_emotions/{emotion_id}` — same ownership pattern

All endpoints validate UUID format (400 on bad UUID), enforce user ownership (404 for cross-user or missing), and return 204 No Content.

### App — SQLite schema v11 (sqlite_helper.dart)

- Version bumped from 10 to 11
- `deleted_at TEXT` column added to all four CREATE TABLE statements
- Migration block for `oldVersion < 11` that runs ALTER TABLE on all four tables (safe: catches existing-column errors)
- Eight `get*`/`getAll*` methods updated with `WHERE deleted_at IS NULL`
- Three `getUnsynced*` methods updated with `AND deleted_at IS NULL` to prevent re-upload of pending-delete rows
- New methods: `softDeleteEmotionalRecord`, `hardDeleteEmotionalRecord`, `softDeleteBreathingSession`, `hardDeleteBreathingSession`, `softDeleteBreathingPattern`, `hardDeleteBreathingPattern`, `softDeleteCustomEmotion`, `hardDeleteCustomEmotion`

### App — ApiConfig URL builders (api_config.dart)

Four static methods added: `emotionalRecordUrl(id)`, `breathingSessionUrl(id)`, `breathingPatternUrl(id)`, `customEmotionUrl(id)`.

### App — ApiService delete methods (api_service.dart)

Four `Future<void>` methods using `_dio.delete`: `deleteEmotionalRecord`, `deleteBreathingSession`, `deleteBreathingPattern`, `deleteCustomEmotion`. No response body parsing (204 No Content).

### App — SyncManager._handleDelete fixed (sync_manager.dart)

Replaced the old no-op switch with a working dispatcher that calls `_apiService.delete*(id)` then `_sqliteHelper.hardDelete*(id)`. Added TODO comment on `_handleUpdate` explaining the POST-instead-of-PUT bug (XC-001 UPDATE half, not yet fixed).

### Learning doc (docs/learning/flutter_api_patterns.md)

"Offline DELETE Sync" section explaining the soft-delete→sync→hard-delete pattern, why immediate hard-delete would cause resurrection, and key files involved.

## Verification

- `flutter analyze` on all modified Dart files: **No issues found**
- Python AST parse on all three modified API routers: **syntax OK**
- Schema version confirmed: `version: 11`
- `deleted_at IS NULL` guards: 11 occurrences in sqlite_helper.dart
- `Future<void> delete*` methods: 4 in api_service.dart
- Old skip warning (`backend DELETE endpoint not yet available`): **0 occurrences** (removed)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unnecessary null check on non-nullable SyncItem.id**
- **Found during:** Task 3 — flutter analyze reported unnecessary_null_comparison warning
- **Issue:** The plan's `_handleDelete` template included `if (item.id == null)` guard but `SyncItem.id` is declared as non-nullable `String` in sync_queue.dart
- **Fix:** Removed null guard and `!` non-null assertion; simplified to `final id = item.id;`
- **Files modified:** lib/core/sync/sync_manager.dart
- **Commit:** f02fbb5

## Known Stubs

None — all four entity DELETE endpoints are wired end-to-end. The `softDelete*` methods are written and available for UI layer to call, though calling sites (feature screens) are not wired in this plan (that is the next UI integration step).

## Self-Check: PASSED

- `/home/eager-eagle/code/emotionai/emotionai-app/.claude/worktrees/agent-adeb3aac/docs/learning/flutter_api_patterns.md` — FOUND
- `/home/eager-eagle/code/emotionai/emotionai-app/.claude/worktrees/agent-adeb3aac/lib/shared/services/sqlite_helper.dart` — FOUND (version 11)
- `/home/eager-eagle/code/emotionai/emotionai-app/.claude/worktrees/agent-adeb3aac/lib/config/api_config.dart` — FOUND (URL builders)
- `/home/eager-eagle/code/emotionai/emotionai-app/.claude/worktrees/agent-adeb3aac/lib/data/api_service.dart` — FOUND (4 delete methods)
- `/home/eager-eagle/code/emotionai/emotionai-app/.claude/worktrees/agent-adeb3aac/lib/core/sync/sync_manager.dart` — FOUND (_handleDelete dispatching)
- API commits: c80f827 (emotionai-api repo), App commits: 9b69282, f02fbb5 (worktree branch)
