# EmotionAI App — Claude Code Context

## What This Project Is

Flutter mobile app (single codebase → Android, iOS, Web) for the EmotionAI platform. Users log emotions via a color wheel, track them on a calendar, run guided breathing sessions, and chat with an AI therapist. The app is fully offline-first — all writes are queued locally and synced to the FastAPI backend when connectivity is restored.

**Backend**: `../emotionai-api` (FastAPI on AWS EC2)
**Dart SDK**: ^3.7.2 | **Flutter**: 3.x
**State**: Riverpod 2.4 | **Nav**: GoRouter 15 | **DB**: SQLite (sqflite)

---

## Project Structure

```
lib/
├── main.dart                          # Entry point — ProviderScope, orientation lock, SecureEnvService init
├── app/router.dart                    # GoRouter: all routes, auth/PIN redirect guards
├── config/api_config.dart             # SINGLE source of truth for all API URLs and feature flags
├── core/
│   ├── sync/
│   │   ├── sync_manager.dart          # Orchestrates all sync — background timer, connectivity, upload/download
│   │   ├── sync_queue.dart            # SQLite-backed queue with retry (max 3) and dead-letter table
│   │   └── conflict_resolver.dart     # Detects and resolves local vs remote data divergence
│   └── theme/
│       ├── app_theme.dart             # MaterialTheme
│       └── tokens.dart                # Design tokens
├── data/
│   ├── api_service.dart               # Base HTTP client (auth headers, error classification, endpoint methods)
│   ├── exceptions/api_exceptions.dart # Custom exception hierarchy (maps HTTP codes to typed errors)
│   └── models/                        # All data models — each has fromJson/toJson (API) + fromMap/toMap (SQLite)
├── features/                          # One folder per product feature
│   ├── auth/                          # Login, Register, PIN screens + AuthNotifier (StateNotifier)
│   ├── breathing_menu/                # Breathing patterns list + breathing session screen
│   ├── calendar/                      # Emotion calendar + offline calendar provider
│   ├── color_wheel/                   # Emotion color picker
│   ├── custom_emotion/                # Create custom emotion dialog
│   ├── home/                          # Main dashboard
│   ├── profile/                       # Profile display/edit, therapy context
│   ├── records/                       # All emotion records history
│   ├── terms/                         # Terms dialog
│   ├── therapy_chat/                  # AI therapist chat, agent switcher, crisis detection
│   └── usage/                         # Token usage display
├── shared/
│   ├── providers/app_providers.dart   # Central DI — all global providers defined here
│   ├── services/
│   │   ├── circuit_breaker.dart       # Prevents cascade failures (3 failures → open 2min)
│   │   ├── enhanced_api_service.dart  # ApiService wrapped with circuit breaker + fallback
│   │   ├── offline_data_service.dart  # Hybrid: try API, fall back to SQLite
│   │   ├── sqlite_helper.dart         # Singleton SQLite connection, all table schemas
│   │   ├── encryption_service.dart    # AES-256 for at-rest sensitive data
│   │   └── secure_env_service.dart    # Encrypts .env vars into FlutterSecureStorage at startup
│   └── widgets/                       # Shared UI components (MainScaffold, OfflineBanner, SyncStatusWidget, etc.)
├── utils/
│   ├── color_utils.dart
│   └── data_validator.dart
└── widgets/                           # Root-level generic widgets (ValidationErrorWidget, etc.)
```

---

## Key Files to Know

| File | Purpose |
|---|---|
| `lib/shared/providers/app_providers.dart` | Central DI — add every new provider here |
| `lib/config/api_config.dart` | All API URLs + feature flags + environment detection |
| `lib/data/api_service.dart` | HTTP client — add new endpoint methods here |
| `lib/app/router.dart` | All routes and redirect guards |
| `lib/core/sync/sync_manager.dart` | Sync orchestrator — start here for offline-related bugs |
| `lib/shared/services/sqlite_helper.dart` | DB schema, all table definitions, v9 schema |
| `lib/features/therapy_chat/providers/therapy_chat_provider.dart` | Most complex provider — crisis detection, agent switching |
| `lib/data/exceptions/api_exceptions.dart` | Exception types — extend here for new error categories |

---

## State Management

**Primary pattern**: Riverpod `StateNotifierProvider` + `StateNotifier`. Use this for every new feature.

**Secondary (legacy, do not add more)**: `provider` package with `ChangeNotifier`. Only `OfflineCalendarProvider` still uses this. Target for refactoring.

**Provider naming convention**:
- `xyzProvider` → exposes a service/repository singleton
- `xyzNotifierProvider` → StateNotifierProvider (mutable state)
- `xyzStateProvider` → StreamProvider for reactive data

**Global providers** (defined in `app_providers.dart`):
```
sqliteHelperProvider, apiServiceProvider, enhancedApiServiceProvider,
circuitBreakerManagerProvider, offlineDataServiceProvider,
syncQueueProvider, conflictResolverProvider, syncManagerProvider,
syncStateProvider, connectivityProvider, appInitializationProvider
```

---

## Navigation

Routes are defined in `lib/app/router.dart`. The `routerProvider` watches `authProvider`.

**Redirect logic** (runs on every navigation):
1. Not logged in → `/login`
2. Logged in + on `/login` → `/` (home)
3. Logged in + PIN set + PIN not verified → `/pin`

**Protected routes** are wrapped in `ShellRoute` → `MainScaffold` (bottom nav).

**To add a new route**:
1. Add the `GoRoute` entry in `router.dart`
2. Add a case in `MainScaffold`'s bottom nav if it needs a nav bar item
3. Pass complex objects via `state.extra` (see breathing session pattern)

---

## Offline-First Sync System

This is the most complex part of the app. Before touching it, understand the flow:

```
User action (create record)
  → OfflineDataService tries API
    → Success: saves to SQLite with synced=1
    → Failure: saves to SQLite with synced=0 + enqueues in SyncQueue
      → SyncManager background timer (every 5min) picks up queue
        → Uploads to API
          → Success: marks synced=1 in SQLite
          → Failure (3x): moves to dead-letter table
```

**ConflictResolver** runs during full sync: compares local vs remote by ID, detects divergence, auto-resolves if safe (breathing session with only a comment added), otherwise raises a `SyncConflict` → `ConflictResolutionDialog` shown to user.

**Known gaps in sync**:
- `DELETE` operations are not synced — only create/update
- `UPDATE` falls back to re-create (line 366 in `sync_manager.dart`)
- These must be addressed before production data deletion is enabled

---

## API Configuration

**Never hardcode URLs.** All API config lives in `lib/config/api_config.dart`.

Environment is resolved at build time from `--dart-define` flags:
```bash
# Run on physical device against local backend
flutter run --dart-define=DEVICE_TYPE=physical

# Run against Docker backend with custom host
flutter run --dart-define=DEVICE_TYPE=physical --dart-define=DOCKER_HOST=192.168.1.100
```

URL resolution priority:
1. `production` env → `https://emotionai.duckdns.org`
2. `deployed` backend type → HTTPS URL
3. `docker` backend type → `{DOCKER_HOST}:8000`
4. `local` + emulator → `http://10.0.2.2:8000`
5. `local` + physical → `http://localhost:8000` (requires `adb reverse tcp:8000 tcp:8000` or WiFi port-forward)

**Feature flags** (in `api_config.dart`) default per environment — check before adding conditional logic elsewhere.

---

## Local Storage (SQLite)

Single database: `emotion_ai.db` at schema version 9. Managed by `SqliteHelper` singleton.

**Tables**:
- `emotional_records` — core emotion logs, `synced` flag (0/1)
- `breathing_sessions` — session results, `synced` flag
- `breathing_patterns` — custom patterns, `synced` flag
- `custom_emotions` — user-defined emotions, `synced` flag
- `sync_queue` — pending sync operations (managed by `SyncQueue`)
- `sync_dead_letter` — failed sync ops after 3 retries (auto-cleaned after 30 days)
- `sync_conflicts` — detected conflicts awaiting user resolution

**Schema changes**: bump `_databaseVersion`, add a migration block in `_onUpgrade`. Never recreate tables on upgrade.

**Model convention**: every model must implement both `fromJson/toJson` (for the API) and `fromMap/toMap` (for SQLite). Use `copyWith()` for immutable updates.

---

## Known Issues / Tech Debt

→ See `.claude/skills/tech_debt_review/SKILL.md` for all 50 App items (TD-001–TD-050), severity classifications, sprint plans, and file→debt lookup.
→ See `.claude/skills/security_audit/SKILL.md` for 6 P0 security vulnerabilities (SEC-009–SEC-014) with remediation playbooks.

Key items to be aware of when editing:
- Hardcoded admin PIN in `pin_code_screen.dart` — decompilable from APK
- Weak encryption key derivation in `encryption_service.dart`
- Delete/Update not synced — `sync_manager.dart` lines 365–372
- No token refresh — expired JWTs cause silent 401s
- Duplicate `apiServiceProvider` in `app_providers.dart` vs `auth_provider.dart`
- `OfflineCalendarProvider` is the only legacy `ChangeNotifier` — migrate to Riverpod
- `DOCKER_HOST` must be passed via --dart-define when BACKEND_TYPE=docker (guard in api_config.dart throws if missing)

---

## Common Tasks

### Run the app
```bash
# Emulator (uses 10.0.2.2 for localhost)
flutter run

# Physical device against local backend
flutter run --dart-define=DEVICE_TYPE=physical

# Against deployed backend (production)
flutter run --dart-define=ENVIRONMENT=production
```

### Build
```bash
flutter build apk --release
flutter build ios --release
flutter build web
```

### Code generation (after editing models with @JsonSerializable)
```bash
dart run build_runner build --delete-conflicting-outputs
# or watch mode during development
dart run build_runner watch
```

### Analyze & format
```bash
flutter analyze
dart format lib/
```

### Add a new feature
1. Create `lib/features/<feature_name>/` folder
2. Add screen(s), provider(s), and model(s) inside it
3. Register provider in `lib/shared/providers/app_providers.dart`
4. Add endpoint methods to `lib/data/api_service.dart`
5. Add route in `lib/app/router.dart`
6. Add nav item to `MainScaffold` if needed

### Add a new data type to sync
1. Add table to `sqlite_helper.dart` (bump schema version)
2. Add model with `fromMap/toMap` + `fromJson/toJson`
3. Add upload/download methods in `sync_manager.dart` mirroring the pattern in `_uploadPendingData`/`_downloadRemoteData`
4. Add conflict detection in `conflict_resolver.dart`

---

## Testing

**Current state**: 1 placeholder test in `test/widget_test.dart` — effectively no coverage.

**Framework**: `flutter_test` (built-in) — no additional test packages installed yet.

**Priority test targets** (in order):
1. `SyncQueue` — queue/dequeue/retry/dead-letter logic
2. `ConflictResolver` — auto-resolve rules per data type
3. `ApiService` — response parsing, error classification
4. Auth redirect guards in `router.dart`
5. Provider state transitions in `TherapyChatNotifier`

**To add tests**: create files under `test/` mirroring the `lib/` structure. Use `ProviderContainer` to test Riverpod providers in isolation.

---

## Security

- **JWT tokens**: stored in `FlutterSecureStorage`, never in SharedPreferences
- **Env variables** (OPENAI_API_KEY, ADMIN_PIN): loaded from `assets/.env` at startup, immediately encrypted by `SecureEnvService` and re-read from secure storage for all subsequent access
- **At-rest data**: `EncryptionService` provides AES-256 for sensitive SQLite fields
- **PIN lock**: session flag `pin_verified` cleared on `AppLifecycleState.paused` (in `main.dart` — `didChangeAppLifecycleState`)
- **Certificate pinning** (optional): see `scripts_emotionai/deploy/README.nginx.md` — stub in `lib/network/pinned_http_client.dart` if the path exists

---

## Style & Conventions

- **Riverpod only** for new state — no new `ChangeNotifier` or `provider` package usage
- **Feature-first folder structure** — screens, providers, and widgets for a feature live together under `lib/features/<feature>/`
- **No API calls from widgets** — always go through a provider/notifier
- **No hardcoded URLs or IPs** — use `ApiConfig` constants
- **Model immutability** — use `copyWith()`, never mutate fields directly
- **Error propagation** — throw typed `ApiException` subclasses from `api_service.dart`, handle in the notifier, expose error state to the widget
- **Offline writes always queue** — when creating/updating data, always write to SQLite first, then sync; never assume the API call succeeds
