# EmotionAI App (Flutter)

Mobile client for EmotionAI. Uses Dio with token-refresh interceptors, Riverpod state management, secure storage, and WebSocket realtime updates.

## What’s inside (concise)
- **Dio + Auth**: Central token handling, access/refresh with automatic refresh on 401.
- **Profile & Records**: CRUD for profile and emotional records.
- **Breathing**: Sessions logging and patterns.
- **Therapy Chat**: Chat with backend agents.
- **Realtime Calendar**: WS connection with JWT.

Key docs per package (fill UI screenshots in these):
- `lib/config/` – API configuration, environments, base URLs. See `api_config.dart`.
- `lib/data/` – `ApiService`, `AuthApi`, DTOs/models; Dio interceptors and error handling.
- `lib/features/` – Screens and flows: auth, profile, records, breathing, chat.
- `lib/shared/services/` – Encryption and secure env services.

## Run locally
```bash
flutter pub get
flutter run --dart-define=BASE_URL=${BASE_URL} \
  --dart-define=ENVIRONMENT=production \
  --dart-define=BACKEND_TYPE=deployed \
  --dart-define=DEVICE_TYPE=physical \
  --dart-define=SHOW_CONFIG_LOGS=true
```

## Configuration
- Centralized at `lib/config/api_config.dart`.
- For Docker/local dev, adjust `BACKEND_TYPE`, `DOCKER_HOST`, `DEVICE_TYPE`.
- For deployed backend, set `BASE_URL` or rely on `production` mapping.

## Security
- Tokens stored with `flutter_secure_storage`.
- `EncryptionService` guards device-specific keys; handles corruption recovery.

## Tests
```bash
flutter test -r expanded
```
Includes unit tests for token refresh and ApiService endpoints plus basic integration flows.

## Backend
Backend repo: `emotionai-api`. See its root README and routers docs for endpoints and curl.

