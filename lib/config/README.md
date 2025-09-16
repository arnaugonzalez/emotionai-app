# Config

`api_config.dart` centralizes base URL building and endpoint paths.

Highlights
- Supports `local`, `docker`, and `deployed` backends
- Honors `BASE_URL` override
- WS base derived automatically (`ws`/`wss`)
- Optional verbose logs with `--dart-define=SHOW_CONFIG_LOGS=true` (debug builds)

Common runs
```bash
# Deployed backend (DNS)
flutter run --dart-define=BASE_URL=${BASE_URL} \
  --dart-define=BACKEND_TYPE=deployed --dart-define=ENVIRONMENT=production

# Local dev (Android emulator)
flutter run --dart-define=BACKEND_TYPE=local --dart-define=DEVICE_TYPE=emulator
```


