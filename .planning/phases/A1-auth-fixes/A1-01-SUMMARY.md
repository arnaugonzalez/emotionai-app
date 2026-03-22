---
phase: A1-auth-fixes
plan: "01"
subsystem: auth
tags: [jwt, flutter-secure-storage, riverpod, dio, token-lifecycle, logout]

# Dependency graph
requires: []
provides:
  - "FlutterSecureStorage read key 'access_token' in AuthNotifier._checkToken (cold-start auth fix)"
  - "AuthApi.clearTokens() as single canonical token wipe method"
  - "ApiService.logout() calls clearTokens + fire-and-forgets POST /v1/api/auth/logout"
  - "ApiConfig.logoutUrl() static URL builder for /v1/api/auth/logout"
  - "JWT token lifecycle documentation at docs/learning/flutter_api_patterns.md"
affects: [auth, logout, cold-start, offline-sync, any feature that calls ApiService.logout]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "clearTokens() as single token wipe method — never call FlutterSecureStorage.delete for token keys outside this method"
    - "fire-and-forget server logout — unawaited(.then<void>((_){}).catchError((_){})) so logout works offline"
    - "TDD for auth layer — test file per feature, mocktail + DioAdapter"

key-files:
  created:
    - test/auth_token_key_test.dart
    - test/auth_logout_test.dart
    - docs/learning/flutter_api_patterns.md
  modified:
    - lib/features/auth/auth_provider.dart
    - lib/config/api_config.dart
    - lib/data/auth_api.dart
    - lib/data/api_service.dart

key-decisions:
  - "Use unawaited(.then<void>((_){}).catchError((_){})) instead of bare catchError to satisfy Dart type system for fire-and-forget on Future<Response<dynamic>>"
  - "Remove _clearToken() and _storage field from ApiService entirely — ApiService never needed direct storage access; AuthApi owns all token storage"
  - "clearTokens() placed after getValidAccessToken() in AuthApi — public API grouped together"

patterns-established:
  - "Single-owner rule: AuthApi owns all three token storage keys; no other class reads/writes them directly"
  - "Logout pattern: clear local tokens first (await), then notify server (fire-and-forget)"

requirements-completed: [AUTH-01, AUTH-02, AUTH-03]

# Metrics
duration: 6min
completed: 2026-03-22
---

# Phase A1 Plan 01: Auth Token Lifecycle Fixes Summary

**Fixed three P0 auth bugs: cold-start forced re-login (wrong storage key), stale tokens on logout (wrong delete key, wrong method), and silent server-side session leak (no logout endpoint call)**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-22T12:04:50Z
- **Completed:** 2026-03-22T12:10:30Z
- **Tasks:** 3
- **Files modified:** 7 (4 source, 3 test/docs)

## Accomplishments

- Fixed cold-start forced re-login: `_checkToken` now reads `'access_token'` (the key `AuthApi._persistAccess` writes) instead of the non-existent `'auth_token'`
- Fixed logout token leak: `AuthApi.clearTokens()` deletes all three storage keys (`access_token`, `refresh_token`, `access_expiry`) and nulls the in-memory cache; `ApiService.logout()` now calls this instead of the dead `_clearToken()` method that deleted the wrong key
- Fixed server session leak: `ApiService.logout()` now fire-and-forgets `POST /v1/api/auth/logout` so the server can invalidate the session, while remaining offline-safe
- Added `ApiConfig.logoutUrl()` so the endpoint path is centralized, not hardcoded
- Created JWT token lifecycle reference doc at `docs/learning/flutter_api_patterns.md`

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix _checkToken key + add logoutUrl to ApiConfig** - `7dd6993` (fix + test, TDD)
2. **Task 2: Add AuthApi.clearTokens() and wire logout in ApiService** - `901e163` (fix + test, TDD)
3. **Task 3: Document JWT token lifecycle in flutter_api_patterns.md** - `78d42d4` (docs)

**Plan metadata:** (see final commit)

## Files Created/Modified

- `lib/features/auth/auth_provider.dart` — line 30: `'auth_token'` → `'access_token'` (1 line change, high-impact)
- `lib/config/api_config.dart` — added `_authLogout` constant and `logoutUrl()` static method
- `lib/data/auth_api.dart` — added `clearTokens()` public method (12 lines) after `getValidAccessToken()`
- `lib/data/api_service.dart` — replaced `logout()` body with clearTokens + fire-and-forget; removed dead `_clearToken()` method, unused `_storage` field, and unused `FlutterSecureStorage` import; added `dart:async` import
- `test/auth_token_key_test.dart` — 5 unit tests for _checkToken key behavior and `logoutUrl()`
- `test/auth_logout_test.dart` — 7 unit tests for `clearTokens()` (3 key deletes + in-memory null) and `ApiService.logout()` (calls clearTokens, offline-safe)
- `docs/learning/flutter_api_patterns.md` — JWT token lifecycle reference: storage keys, write paths, read paths, clear path, server logout, in-memory cache

## Decisions Made

- Used `unawaited(.then<void>((_) {}).catchError((_) {}))` for the fire-and-forget server logout call. The bare `catchError((_) {})` pattern produces a Dart analyzer warning because `catchError` on `Future<Response<dynamic>>` must return a `Response<dynamic>`, not `void`. The `.then<void>(...)` coerces the future to `Future<void>` before `catchError`, satisfying the type checker with zero runtime overhead.
- Removed `ApiService._storage` field (was `const FlutterSecureStorage()`) entirely. It was only used by the now-deleted `_clearToken()` method. `ApiService` should not own token storage — `AuthApi` is the sole owner.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed analyzer warning in fire-and-forget logout POST**
- **Found during:** Task 2 (wiring `logout()` in `ApiService`)
- **Issue:** `catchError((_) {})` on `Future<Response<dynamic>>` produced `body_might_complete_normally_catch_error` warning — the callback must return `Response<dynamic>`, not void
- **Fix:** Changed to `.then<void>((_) {}).catchError((_) {})` to coerce to `Future<void>` before the catchError
- **Files modified:** `lib/data/api_service.dart`
- **Verification:** `flutter analyze lib/data/api_service.dart` — 0 issues
- **Committed in:** `901e163` (part of Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Fix was necessary for correctness; analyzer warning would surface in CI. No scope creep.

## Issues Encountered

- Two pre-existing `unused_local_variable` warnings in `lib/data/auth_api.dart` (`isLogin`, `isRegister` in `_AuthInterceptor.onError`) confirmed as pre-existing before this plan's changes. Out of scope per deviation boundary rules. Documented for deferred fix.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- All three auth lifecycle P0 bugs are resolved
- `AuthApi.clearTokens()` is now the canonical token wipe — future logout-adjacent features (e.g., account deletion, forced logout on server push) should call this
- Cold-start auth is correct; emulator/device smoke test would confirm end-to-end but was not available in this environment
- Pre-existing analyzer warnings in `_AuthInterceptor.onError` (`isLogin`, `isRegister` unused) should be fixed in a follow-up

---
*Phase: A1-auth-fixes*
*Completed: 2026-03-22*

## Self-Check: PASSED

- All 7 files found on disk
- All 3 task commits verified in git history (7dd6993, 901e163, 78d42d4)
- 12/12 tests passing
- 0 new analyzer errors introduced
