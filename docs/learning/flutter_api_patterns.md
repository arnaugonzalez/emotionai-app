# Flutter API Patterns — EmotionAI Learning Notes

## Offline DELETE Sync

**Problem**: Deleting a record while offline requires two things to happen in the correct order:
1. The delete must reach the API when connectivity is restored.
2. The download merge step must not resurrect the row before the delete is dispatched.

**Solution used in EmotionAI**:

When a user deletes a record, the UI layer calls `softDelete*(id)` on `SQLiteHelper`, which sets `deleted_at = now()` on the row (schema v11+). The row is NOT hard-deleted yet.

At sync time, `SyncManager._handleDelete` is called with a `SyncItem` of `operation = 'delete'`. It:
1. Calls the corresponding `ApiService.delete*(id)` → HTTP DELETE → expects 204.
2. On success, calls `SQLiteHelper.hardDelete*(id)` to remove the local row.
3. On failure (network error, 404), the `SyncQueue` retry mechanism keeps the item for the next attempt.

The download merge methods (`getEmotionalRecords`, `getAllEmotionalRecords`, etc.) all include `WHERE deleted_at IS NULL` so soft-deleted rows are invisible to the merge step and cannot be re-inserted from a remote GET response.

**Why not hard-delete immediately?**

Hard-deleting before the API call would leave the record on the server. On the next sync cycle, `_downloadRemoteChanges` would fetch it back from the API and re-insert it — exactly the bug this fixes.

**Key files**:
- `lib/shared/services/sqlite_helper.dart` — `softDelete*`, `hardDelete*`, schema v11 migration
- `lib/data/api_service.dart` — `deleteEmotionalRecord`, `deleteBreathingSession`, `deleteBreathingPattern`, `deleteCustomEmotion`
- `lib/config/api_config.dart` — `emotionalRecordUrl(id)`, `breathingSessionUrl(id)`, etc.
- `lib/core/sync/sync_manager.dart` — `_handleDelete`
- API routers: `records.py`, `breathing.py`, `data.py` — `DELETE /{id}` endpoints

**API contract**: DELETE endpoints return 204 No Content on success, 404 if the record does not exist or belongs to another user. The app treats 404 as a success-like condition (record already gone on server) — add that handling if retry storms appear in production.
