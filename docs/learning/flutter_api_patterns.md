# Flutter API Patterns

Reference for recurring patterns in the EmotionAI app's API and authentication layer.

---

## JWT Token Lifecycle

### Storage Keys

`AuthApi` owns exactly three `FlutterSecureStorage` keys. No other code should read or write these keys directly.

| Key | Type | Description |
|---|---|---|
| `access_token` | `String` | JWT Bearer token attached to every authenticated request |
| `refresh_token` | `String` | Long-lived token used by `AuthApi.refresh()` to obtain new access tokens |
| `access_expiry` | `String` (ISO-8601) | Expiry timestamp set by `_persistAccess()`; fallback when `JwtDecoder` cannot parse the token |

> **NOTE:** The key `auth_token` does **not** exist in the current codebase. It was a legacy artefact that caused cold-start forced re-logins. It was removed in phase A1. Do not introduce it.

---

### Write Paths

Tokens are written in exactly one place:

```
AuthApi._storeTokensFromAuthResponse()
  ├── _persistAccess(token, expiresIn)   → writes 'access_token' + 'access_expiry'
  └── _persistRefresh(token)             → writes 'refresh_token'
```

Both `AuthApi.login()` and `AuthApi.register()` call `_storeTokensFromAuthResponse()`.

`_persistAccess()` also refreshes the in-memory cache fields `_inMemoryAccess` and `_accessExpiry`.

---

### Read Paths

| Reader | Key read | Why |
|---|---|---|
| `AuthApi.getValidAccessToken()` | `access_token` | Warms the in-memory cache on cold start |
| `_AuthInterceptor.onRequest` | `access_token` (fallback) | Attaches `Authorization: Bearer` header per request |
| `AuthNotifier._checkToken()` | `access_token` | Determines initial auth state at app startup |

---

### Clear Path

```dart
Future<void> clearTokens() async { ... }   // AuthApi
```

`clearTokens()` is the **single** place to wipe all token state. It:
1. Deletes `access_token`, `refresh_token`, and `access_expiry` from `FlutterSecureStorage`
2. Nulls the in-memory cache fields `_inMemoryAccess` and `_accessExpiry`

**Rule:** Always call `_authApi.clearTokens()` on logout. Never call `FlutterSecureStorage.delete` for token keys individually outside of `clearTokens()`.

---

### Server Logout

`ApiService.logout()` is the public logout entry point. It:

1. Awaits `_authApi.clearTokens()` — tokens are wiped before the server call
2. Fire-and-forgets `POST /v1/api/auth/logout` via `unawaited(...then<void>(...).catchError(...))`

The server call must remain fire-and-forget (unawaited + catchError) so that logout completes successfully even when the device is offline or the server is unreachable. Never await the server logout call.

---

### In-Memory Cache

`AuthApi` maintains `_inMemoryAccess` and `_accessExpiry` to avoid repeated secure storage reads per request (storage reads have non-trivial latency on device).

`clearTokens()` **must** null both fields. If they are not nulled, `_AuthInterceptor` will re-attach the old (now-invalid) token to the next request after logout.
