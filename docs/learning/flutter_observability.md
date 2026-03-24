# Flutter Observability — Structured Log Shipping

## Overview

This document covers the structured log shipping system in EmotionAI app, which collects
structured diagnostic events in a local ring buffer and ships them to the backend for
storage in CloudWatch. This enables in-field debugging without crash reporters or native
log pipelines.

---

## Structured log shipping

### What MobileLogger is and where it lives

`MobileLogger` is a singleton structured logger that lives at
`lib/shared/logging/mobile_logger.dart`. It provides:

- `info(String event, Map<String,dynamic> fields)` — logs an informational event
- `error(String event, Map<String,dynamic> fields)` — logs an error event
- `dump()` — returns a snapshot of the current buffer contents as JSON strings
- `flush(ApiService)` — ships buffered entries to the backend and clears on success
- `userHash(String? email)` — returns a one-way hash of an email for privacy-safe tagging

Access the singleton via `MobileLogger.instance`.

### Ring-buffer design (2000 entries, FIFO eviction)

The logger uses a `ListQueue<String>` internally with a fixed capacity of 2000 entries.
Each logged event is JSON-encoded as a string and added to the tail. When the buffer is
full, the oldest entry is evicted from the head before the new one is appended. This
ensures the buffer always holds the most recent 2000 events and never grows unbounded.

```dart
if (_buffer.length == _capacity) _buffer.removeFirst();
_buffer.addLast(line);
```

All sensitive fields (`Authorization`, `access_token`, `refresh_token`) are redacted by
`_redact()` before the event is written to the buffer — they are never stored or shipped.

### How flush() works: snapshot → POST → conditional clear

`flush(ApiService apiService)` follows a safe, durable shipping protocol:

1. **Guard checks**: if `enabled` is false or the buffer is empty, return immediately
   without any network call.
2. **Snapshot**: create a non-growing copy of the buffer with `_buffer.toList()`. The
   original buffer entries remain in place during the network call.
3. **Decode**: each entry is a JSON-encoded string. Decode each back to
   `Map<String,dynamic>` before sending, since the backend expects a JSON array of
   objects.
4. **POST**: call `apiService.postMobileLogs(decoded)` — an authenticated POST to
   `POST /v1/api/mobile-logs` that expects 204 No Content.
5. **Conditional clear**: if the POST succeeds without throwing, call `_buffer.clear()`.
   If an exception is thrown, the buffer is NOT cleared — entries are retained for the
   next flush attempt.

```dart
Future<void> flush(ApiService apiService) async {
  if (!enabled) return;
  if (_buffer.isEmpty) return;

  final snapshot = _buffer.toList(growable: false);
  final decoded = snapshot
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();
  try {
    await apiService.postMobileLogs(decoded);
    _buffer.clear();
  } catch (e) {
    print('[MobileLogger] flush failed, retaining buffer: $e');
  }
}
```

### The two flush call sites

Flush is triggered automatically at two points in the app lifecycle:

**1. SyncManager.forceSync completion** (`lib/core/sync/sync_manager.dart`)

After a successful full sync cycle, logs accumulated during the sync (connectivity
events, API calls, conflict resolutions) are shipped immediately. The call is
fire-and-forget via `unawaited()` so it does not block the sync return value.

```dart
logger.i('✅ Force sync completed successfully');
unawaited(MobileLogger.instance.flush(_apiService));
return true;
```

`_apiService` is the `ApiService` instance already injected into `SyncManager` via its
constructor, so no new dependency is introduced.

**2. AppLifecycleState.resumed** (`lib/main.dart`)

When the app returns to the foreground, any logs accumulated while the app was in the
background (or during the paused → resumed transition) are shipped. The call uses
`.ignore()` because `didChangeAppLifecycleState` is not async and `unawaited()` from
`dart:async` requires an async context.

```dart
if (state == AppLifecycleState.resumed) {
  final apiService = ref.read(apiServiceProvider);
  MobileLogger.instance.flush(apiService).ignore();
}
```

### The backend endpoint

```
POST /v1/api/mobile-logs
Authorization: Bearer <JWT>
Content-Type: application/json

Body: List<MobileLogItem>
  Each item must have at minimum:
    - level: str  ("info" | "error")
    - event: str
  Optional fields: ts_iso, user_hash, device_id, online, sdk, app_ver, error, etc.

Response: 204 No Content
```

The URL is built by `ApiConfig.mobileLogsUrl()` which appends `/v1/api/mobile-logs` to
the resolved `baseUrl`. The `postMobileLogs` method in `ApiService` does NOT call
`_handleResponse` (which expects a JSON body) because the endpoint returns 204.

### Why the buffer is NOT cleared on failure (durability guarantee)

If the flush POST fails (network error, 401, 5xx, timeout), the buffer is intentionally
left intact. This means:

- No log entries are silently dropped during transient failures.
- The next flush trigger (next sync or next foreground resume) will retry all retained
  entries.
- In the worst case the buffer is bounded at 2000 entries — old entries will eventually
  be evicted by new ones if the device is permanently offline, but no hard crash occurs.

This is the same "write-local-first, sync-when-possible" principle that governs the rest
of the offline-first sync system.

### How to add a new log call

Call `MobileLogger.instance.info` or `MobileLogger.instance.error` from anywhere in the
app, passing a structured map of fields:

```dart
MobileLogger.instance.info('sync.upload_complete', {
  'record_count': 5,
  'entity_type': 'emotional_record',
  'duration_ms': 142,
});

MobileLogger.instance.error('api.request_failed', {
  'endpoint': '/v1/api/emotional_records/',
  'status': 503,
  'retry': true,
});
```

Do NOT pass `Authorization`, `access_token`, or `refresh_token` in the fields map —
they are redacted, but the convention is to never log them in the first place.

The `user_hash` field can be set by computing `MobileLogger.userHash(email)`, which
returns a 12-character SHA-256 prefix, safe for server-side log correlation without
exposing PII.

---

## ApiConfig integration

`ApiConfig.mobileLogsUrl()` returns the full URL for the mobile logs endpoint:

```dart
static const String _mobileLogs = '$_v1/mobile-logs';
static String mobileLogsUrl() => '$baseUrl$_mobileLogs';
```

This follows the same pattern as all other endpoint URL builders in `api_config.dart`
and respects the environment-based URL resolution (local, docker, deployed).

---

## WebSocket Reconnect Patterns

### Problem
`web_socket_channel` streams complete (call `onDone`) on any disconnect — network drop,
server restart, app backgrounding. There is no built-in reconnect. Without a handler the
stream dies silently and listeners stop receiving messages.

### Pattern: Exponential Backoff + Connectivity Trigger

```dart
// 1. Backoff table (cap at 30 s)
static const List<Duration> _backoffTable = [
  Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4),
  Duration(seconds: 8), Duration(seconds: 16), Duration(seconds: 30),
];

// 2. Both onError and onDone call _scheduleReconnect()
_ws!.stream.listen(
  (data) { ... },
  onError: (e) { _wsConnected = false; _scheduleReconnect(); },
  onDone: ()  { _wsConnected = false; _scheduleReconnect(); },
  cancelOnError: false,   // must be false — default true kills the sub on error
);

// 3. Schedule next attempt
void _scheduleReconnect() {
  if (_disposed) return;
  final delay = _backoffTable[_attemptCount.clamp(0, _backoffTable.length - 1)];
  _attemptCount++;
  _reconnectTimer = Timer(delay, _reconnect);
}

// 4. Immediate reconnect when network comes back
SyncManager().stateStream.listen((state) {
  if (state.isOnline && !_wsConnected && !_disposed) {
    _reconnectTimer?.cancel();
    _attemptCount = 0;
    _reconnect();
  }
});

// 5. Clean shutdown — MUST set _disposed = true before cancelling
void disposeRealtime() {
  _disposed = true;           // guard: prevents _scheduleReconnect from re-arming
  _reconnectTimer?.cancel();  // cancel any pending attempt
  _connectivitySub?.cancel();
  _ws?.sink.close(ws_status.normalClosure);
}
```

### Key Rules
- `cancelOnError: false` — without this, a single error kills the subscription permanently.
- `_disposed` guard — always check before scheduling. Without it, logout triggers a
  reconnect loop because `onDone` fires when you explicitly close the socket.
- Reset `_attemptCount = 0` on successful connect and on connectivity-restore trigger.
- SyncManager polls `/health` every 15 s and emits `ConnectivityStatus.online` transitions.
  Subscribing to `stateStream` gives sub-15 s recovery on network restore at zero cost.
- Token refresh: call `auth.getValidAccessToken()` inside `_doConnect()` (not once at
  startup) so a fresh token is always used after a long disconnect.

### Where This Is Used
`lib/features/calendar/events/calendar_events_provider.dart` — `CalendarEventsProvider`
