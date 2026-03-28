# EmotionAI App — Tech Debt (Prioritised)

## P0 — Bugs / data loss risk

### ~~DELETE operations are not synced~~ ✅ FIXED
**Status**: Resolved — soft-delete + sync pipeline implemented.
- `deleted_at` column added to all SQLite tables (schema v11).
- `OfflineDataService._syncPendingDeletes()` pushes to backend `DELETE` endpoints.
- `SyncManager._handleDelete()` calls backend then hard-deletes locally.
- `SQLiteHelper.getPendingDelete*()` queries added for all 4 resource types.

---

### UPDATE falls back to re-create
**File**: `lib/core/sync/sync_manager.dart` line ~366
**Problem**: The `update` case in the sync upload path calls the same `create` endpoint as a new record. This can result in duplicate records in the backend if the original was already synced.
**Fix**: Add `PUT /v1/api/<resource>/<id>` endpoints on the backend (API side), then call them from the sync upload path when `operation == SyncOperation.update`.
**Blocked by**: API-side PUT endpoints not yet implemented.

---

## P1 — UX / reliability

### ~~No JWT token refresh~~ ✅ FIXED
**Status**: Resolved — `AuthApi` with `_AuthInterceptor` handles:
- Proactive refresh: checks JWT `exp` claim + 60s buffer before every request.
- Reactive retry: on 401, single refresh attempt then retry original request.
- Concurrent refresh debounce: `_refreshCompleter` prevents stampede.
- Secure storage persistence of `access_token`, `refresh_token`, `access_expiry`.

---

### `OfflineDataService` and `SyncManager` overlap — race condition risk
**Files**:
- `lib/shared/services/offline_data_service.dart`
- `lib/core/sync/sync_manager.dart`

**Problem**: Both classes independently write to SQLite and trigger API calls for the same data types. A user action that goes through `OfflineDataService` while `SyncManager`'s background timer fires simultaneously can cause double-writes or stale reads.
**Fix**: Make `OfflineDataService` the only class that does immediate writes (local + queued API call). `SyncManager` should only process the `sync_queue` — never do ad-hoc direct reads/writes to the data tables. Define clear ownership: `OfflineDataService` owns immediate paths, `SyncManager` owns background reconciliation.

---

## P2 — Code quality

### ~~Mixed state management (`ChangeNotifier` + Riverpod)~~ ✅ FIXED
**Status**: Resolved — `OfflineCalendarNotifier` already uses Riverpod `StateNotifier` + `StateNotifierProvider`. The `provider` package remains as transitive dependency only.

---

### ~~Duplicate widgets folder~~ ✅ FIXED
**Status**: Resolved — `lib/widgets/` deleted. All shared widgets live in `lib/shared/widgets/`.

---

### ~~Physical device IP hardcoded~~ ✅ FIXED
**Status**: Resolved — `ApiConfig` uses `--dart-define` flags (`BASE_URL`, `BACKEND_TYPE`, `DEVICE_TYPE`, `DOCKER_HOST`). No hardcoded IPs in runtime code (only in help text example).

---

### ~~Kotlin version outdated~~ ✅ FIXED
**Status**: Resolved — Kotlin upgraded from 1.8.22 → 2.1.0 in `android/settings.gradle.kts`. NDK updated to 27.1.12297006.

---

## P3 — Missing coverage

### No test coverage
**File**: `test/widget_test.dart` (single placeholder test)
**Problem**: Zero tests for the most critical paths in the app.

**Priority order for new tests:**
1. `SyncQueue` — queue/dequeue/retry/dead-letter logic (`test/core/sync/sync_queue_test.dart`)
2. `ConflictResolver` — auto-resolve rules per data type (`test/core/sync/conflict_resolver_test.dart`)
3. `ApiService` — response parsing, HTTP error classification (`test/data/api_service_test.dart`)
4. Auth redirect guards in `router.dart`
5. `TherapyChatNotifier` state transitions (loading, message added, crisis flag)

**Setup**: Use `ProviderContainer` (Riverpod) and `mocktail` or `mockito` to mock `ApiService` and `SqliteHelper`. No additional test packages needed for pure unit tests.

---

## Improvement opportunities (not debt)

- **No request/response logging interceptor** — API calls are invisible in production. Add a thin logging wrapper in `EnhancedApiService` that logs method, URL, status code, and duration (debug builds only).
- **`ConflictResolver` never auto-resolves `BreathingPattern` or `CustomEmotion`** — documented intentionally in the code, but worth revisiting since these are low-risk user-owned objects.
- **No pagination in `AllRecordsScreen`** — `records_repository.dart` fetches all records in one call. This will degrade as users accumulate data. Add cursor-based pagination.
- **`circuit_breaker.dart` thresholds are hardcoded** — the 3-failure/2-minute window is baked in. Moving to variables would make it configurable per environment.
