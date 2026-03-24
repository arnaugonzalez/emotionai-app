---
phase: 05-mobile-logs-flush
plan: 01
subsystem: observability
tags: [flutter, structured-logging, ring-buffer, mobile-logs, api, dio]

# Dependency graph
requires:
  - phase: 04-crisis-detection
    provides: ApiService and apiServiceProvider wired in app_providers.dart; ConsumerStatefulWidget pattern in main.dart
provides:
  - MobileLogger ring buffer wired to ship entries to backend via POST /v1/api/mobile-logs
  - ApiConfig.mobileLogsUrl() endpoint constant
  - ApiService.postMobileLogs() authenticated POST method
  - MobileLogger.instance singleton + flush(ApiService) with durability guarantee
  - Flush triggered after forceSync success and on AppLifecycleState.resumed
affects: [06-websocket-reconnect, observability, diagnostics]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Ring-buffer log flush: snapshot buffer → POST → conditional clear on success"
    - "Lifecycle hook flush: .ignore() pattern for fire-and-forget in non-async lifecycle callbacks"
    - "Fire-and-forget with unawaited(): used in sync_manager.dart post-success path"

key-files:
  created:
    - emotionai-app/docs/learning/flutter_observability.md
  modified:
    - emotionai-app/lib/config/api_config.dart
    - emotionai-app/lib/data/api_service.dart
    - emotionai-app/lib/shared/logging/mobile_logger.dart
    - emotionai-app/lib/core/sync/sync_manager.dart
    - emotionai-app/lib/main.dart

key-decisions:
  - "flush() uses .ignore() in didChangeAppLifecycleState because lifecycle callbacks are not async contexts — unawaited() from dart:async requires an async context"
  - "Buffer is NOT cleared on flush failure — durability over delivery-once semantics matches offline-first pattern used across the app"
  - "MobileLogger.instance singleton initialized with enabled=true so the shared instance is active by default"
  - "postMobileLogs early-returns on empty list to avoid pointless authenticated POSTs"

patterns-established:
  - "Flutter lifecycle flush: use .ignore() not unawaited() in didChangeAppLifecycleState"
  - "Snapshot-before-POST: take buffer snapshot before network call; only clear after confirmed success"

requirements-completed: [A5-LOG-01, A5-LOG-02, A5-LOG-03]

# Metrics
duration: 5min
completed: 2026-03-24
---

# Phase 05 Plan 01: Mobile Logs Flush Summary

**MobileLogger ring buffer wired to POST /v1/api/mobile-logs after sync completion and on app foreground resume, with snapshot-then-clear durability guarantee**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-24T04:07:23Z
- **Completed:** 2026-03-24T04:12:41Z
- **Tasks:** 3
- **Files modified:** 5 + 1 created

## Accomplishments

- Added `ApiConfig.mobileLogsUrl()` constant and `ApiService.postMobileLogs()` authenticated POST method for the `/v1/api/mobile-logs` endpoint
- Added `MobileLogger.instance` singleton and `flush(ApiService)` method — buffer is snapshotted before POST, cleared only after confirmed delivery, retained on any exception
- Wired flush at two call sites: `SyncManager.forceSync` success path (unawaited) and `main.dart` `AppLifecycleState.resumed` (.ignore() pattern)
- Created `docs/learning/flutter_observability.md` documenting the ring-buffer design, flush protocol, call sites, and usage guide

## Task Commits

Each task was committed atomically:

1. **Task 1: Add mobileLogsUrl to ApiConfig and postMobileLogs to ApiService** - `871598b` (feat)
2. **Task 2: Add MobileLogger.instance singleton and flush() method** - `1c6550d` (feat)
3. **Task 3: Wire flush at sync completion and on app foreground resume** - `63cad85` (feat)

All commits are in the `emotionai-app` sub-repository.

## Files Created/Modified

- `lib/config/api_config.dart` — added `_mobileLogs` constant and `mobileLogsUrl()` URL builder
- `lib/data/api_service.dart` — added `postMobileLogs(List<Map<String,dynamic>>)` method with empty-list guard
- `lib/shared/logging/mobile_logger.dart` — added singleton `instance` getter and `flush(ApiService)` method
- `lib/core/sync/sync_manager.dart` — added import and `unawaited(MobileLogger.instance.flush(_apiService))` after forceSync success
- `lib/main.dart` — added import and `MobileLogger.instance.flush(apiService).ignore()` in `AppLifecycleState.resumed`
- `docs/learning/flutter_observability.md` — new file: structured log shipping reference

## Decisions Made

- `flush()` uses `.ignore()` in `didChangeAppLifecycleState` because lifecycle callbacks are not async contexts — `unawaited()` from `dart:async` requires an async context.
- Buffer is NOT cleared on flush failure — durability over delivery-once semantics, consistent with the offline-first pattern used across the app.
- `MobileLogger.instance` is initialized with `enabled: true` so the shared singleton is active by default.
- `postMobileLogs` early-returns on empty list to avoid a pointless authenticated POST.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing unused imports blocking analyzer exit 0**
- **Found during:** Task 2 (MobileLogger flush implementation)
- **Issue:** `mobile_logger.dart` had unused imports of `flutter/foundation.dart` and `flutter/services.dart` that caused `flutter analyze` to exit 1, blocking the plan's success criteria
- **Fix:** Removed both unused imports
- **Files modified:** `lib/shared/logging/mobile_logger.dart`
- **Verification:** `flutter analyze` exits 0 after removal
- **Committed in:** `1c6550d` (Task 2 commit)

**2. [Rule 1 - Bug] Fixed pre-existing connectivity_plus v6 API mismatch**
- **Found during:** Task 2 (MobileLogger flush implementation)
- **Issue:** `onConnectivityChanged` emits `List<ConnectivityResult>` in connectivity_plus v6+, but the code compared against a single `ConnectivityResult.none`, causing an `unrelated_type_equality_checks` warning and incorrect offline detection
- **Fix:** Updated listener from `result != ConnectivityResult.none` to `!results.every((r) => r == ConnectivityResult.none)`
- **Files modified:** `lib/shared/logging/mobile_logger.dart`
- **Verification:** `flutter analyze` exits 0 with no issues
- **Committed in:** `1c6550d` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 - pre-existing bugs)
**Impact on plan:** Both fixes required to satisfy success criteria (flutter analyze exit 0). The connectivity fix also corrects a functional bug in offline detection. No scope creep.

## Issues Encountered

None — plan executed smoothly once pre-existing lint issues were resolved as part of Task 2.

## User Setup Required

None - no external service configuration required. The backend endpoint `POST /v1/api/mobile-logs` must exist; it was already implemented in `emotionai-api` (Phase A5 of API roadmap).

## Next Phase Readiness

- MobileLogger flush fully wired; structured diagnostics will now reach CloudWatch after each sync and foreground resume
- Phase 06 (WebSocket Reconnect) can proceed independently — no dependencies on this phase
- Pre-existing issue noted: `apiServiceProvider` undefined identifier in `therapy_chat_provider.dart` (pre-dates this phase, out of scope, tracked in STATE.md)

---
*Phase: 05-mobile-logs-flush*
*Completed: 2026-03-24*
