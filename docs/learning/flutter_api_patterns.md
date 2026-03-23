# Flutter API Patterns — EmotionAI

Developer reference for how the app connects to its backend across different
environments. This file is part of the project's learning docs.

---

## Environment Configuration and Build Flavors

EmotionAI does not use Flutter build flavors (no `--flavor` flag, no
`android/app/src/flavor/` trees). Instead, environment is expressed entirely
through `--dart-define` constants resolved at compile time.

### Available dart-define Constants

| Constant | Values | Default | Purpose |
|---|---|---|---|
| `ENVIRONMENT` | `development`, `staging`, `production` | `development` | Controls feature flags, log verbosity |
| `BACKEND_TYPE` | `local`, `docker`, `deployed` | `local` | Selects URL resolution branch |
| `DEVICE_TYPE` | `emulator`, `physical`, `desktop`, `web`, `auto` | `auto` | Used with `local` backend to pick host |
| `DOCKER_HOST` | IPv4 address | `''` (empty) | **Required** when `BACKEND_TYPE=docker` |
| `BASE_URL` | Full URL | `''` (empty) | Overrides all resolution — highest priority |
| `WS_BASE_URL` | Full WS URL | `''` (empty) | Overrides WebSocket URL |
| `SHOW_CONFIG_LOGS` | `true` / `false` | `false` | Prints URL resolution to debug console |

All constants live in `lib/config/api_config.dart`. That file is the
**single source of truth** for every URL and feature flag.

### URL Resolution Priority

```
1. BASE_URL non-empty          → use it verbatim (highest priority)
2. BACKEND_TYPE=deployed       → https://emotionai.duckdns.org (or BASE_URL)
3. BACKEND_TYPE=docker         → http://<DOCKER_HOST>:8000
                                  (DOCKER_HOST empty → AssertionError at startup)
4. BACKEND_TYPE=local + emulator → http://10.0.2.2:8000
5. BACKEND_TYPE=local + physical → http://localhost:8000
                                    (requires adb reverse or WiFi port-forward)
6. BACKEND_TYPE=local + desktop  → http://localhost:8000
```

### Why 10.0.2.2 for Emulators?

Android emulator's virtual network maps `10.0.2.2` to the host machine's
loopback address. `localhost` inside the emulator refers to the emulator
itself, not the host. iOS Simulator uses `localhost` normally.

### Quick-Start Commands (using run_dev.sh)

```bash
# Android emulator, local backend
./scripts_emotionai/run_dev.sh emulator

# Physical device, local backend (port-forward active)
adb reverse tcp:8000 tcp:8000
./scripts_emotionai/run_dev.sh physical

# Physical device, Docker backend at 192.168.1.100
./scripts_emotionai/run_dev.sh docker 192.168.1.100

# Production backend
./scripts_emotionai/run_dev.sh prod

# Flutter web
./scripts_emotionai/run_dev.sh web
```

### Manual flutter run (without run_dev.sh)

```bash
# Emulator
flutter run \
  --dart-define=DEVICE_TYPE=emulator \
  --dart-define=BACKEND_TYPE=local \
  --dart-define=SHOW_CONFIG_LOGS=true

# Physical device against Docker
flutter run \
  --dart-define=DEVICE_TYPE=physical \
  --dart-define=BACKEND_TYPE=docker \
  --dart-define=DOCKER_HOST=192.168.1.100

# Production
flutter run \
  --dart-define=BACKEND_TYPE=deployed \
  --dart-define=ENVIRONMENT=production
```

### VS Code launch.json Example

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "EmotionAI — Emulator",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=DEVICE_TYPE=emulator",
        "--dart-define=BACKEND_TYPE=local",
        "--dart-define=SHOW_CONFIG_LOGS=true"
      ]
    },
    {
      "name": "EmotionAI — Docker (update DOCKER_HOST)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=DEVICE_TYPE=physical",
        "--dart-define=BACKEND_TYPE=docker",
        "--dart-define=DOCKER_HOST=192.168.1.100"
      ]
    },
    {
      "name": "EmotionAI — Production",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=BACKEND_TYPE=deployed",
        "--dart-define=ENVIRONMENT=production"
      ]
    }
  ]
}
```

### What Must Never Be Done

- **Never hardcode an IP address** in api_config.dart or anywhere else.
  LAN IPs are developer-local and machine-specific. They break every other
  developer and compile into the binary.
- **Never commit a `--dart-define=DOCKER_HOST=...`** value to a shared
  launch.json or CI config. It is a local-machine concern.
- **Never call `Uri.parse(baseUrl)` outside api_config.dart.** All callers
  use `ApiConfig.someUrl()` methods.

---

## Adding a New Endpoint

1. Add a private path constant (`static const String _myEndpoint = ...`)
2. Add a public URL builder (`static String myEndpointUrl() => '$baseUrl$_myEndpoint'`)
3. Add the endpoint method to `lib/data/api_service.dart`
4. Add a Riverpod provider/notifier in `lib/features/<feature>/providers/`

Never call `ApiConfig.baseUrl` directly from a widget.

---

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

---

*File maintained by the EmotionAI project. Last updated: phase A3-env-config.*
