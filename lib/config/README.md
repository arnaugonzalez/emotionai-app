# Config

`api_config.dart` centralizes base URL building and endpoint paths.

## dart-define parameters

| Parameter | Values | Default | Purpose |
|---|---|---|---|
| `BASE_URL` | any URL | _(empty)_ | Explicit full URL override — **trumps all other settings** |
| `BACKEND_TYPE` | `local`, `docker`, `deployed` | `local` | How to resolve the backend host |
| `DEVICE_TYPE` | `auto`, `emulator`, `physical`, `desktop`, `web` | `auto` | Which host to use for `local` backend |
| `DOCKER_HOST` | IP address | `192.168.77.140` | Host IP when `BACKEND_TYPE=docker` |
| `ENVIRONMENT` | `development`, `development_emulator`, `development_local`, `staging`, `production` | `development` | Controls feature flags and deployed URL mapping |
| `WS_BASE_URL` | any URL | _(empty)_ | Explicit WebSocket base URL override |
| `SHOW_CONFIG_LOGS` | `true`, `false` | `false` | Print config details on startup (debug builds only) |

## URL resolution logic

```
BASE_URL set?
  └─ yes → use BASE_URL verbatim
  └─ no  → check BACKEND_TYPE
              ├─ deployed → mapped URL or https://emotionai.duckdns.org
              ├─ docker   → http://{DOCKER_HOST}:8000
              └─ local    → http://{resolved host}:8000
                              ├─ emulator  → 10.0.2.2
                              ├─ desktop   → localhost
                              ├─ web       → localhost
                              └─ physical  → localhost (needs adb reverse)
```

> **Note:** `DEVICE_TYPE` only matters when `BACKEND_TYPE=local`. When using `docker` or `deployed`, device type is irrelevant — the host is determined entirely by `DOCKER_HOST` or the deployed URL map.

## Common scenarios

### Android emulator — local backend (default)

```bash
flutter run --dart-define=BACKEND_TYPE=local --dart-define=DEVICE_TYPE=emulator
# → http://10.0.2.2:8000
```

### Physical device — Docker backend

This is the main way to develop against a local backend on a physical phone. Set `DOCKER_HOST` to your dev machine's LAN IP.

```bash
flutter run --dart-define=BACKEND_TYPE=docker --dart-define=DOCKER_HOST=192.168.1.100
# → http://192.168.1.100:8000
```

The phone and dev machine must be on the same network. Find your IP with `ip addr` (Linux), `ipconfig` (Windows), or `ifconfig` (macOS).

### Physical device — local backend with adb reverse

Alternative to Docker mode when connected via USB:

```bash
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=BACKEND_TYPE=local --dart-define=DEVICE_TYPE=physical
# → http://localhost:8000 (forwarded to host via adb)
```

### Desktop (Linux / macOS / Windows)

```bash
flutter run -d linux --dart-define=BACKEND_TYPE=local
# → http://localhost:8000 (auto-detected as desktop)
```

### Web

```bash
flutter run -d chrome --dart-define=BACKEND_TYPE=local
# → http://localhost:8000 (auto-detected as web)
```

### Deployed — production

```bash
flutter run --dart-define=BACKEND_TYPE=deployed --dart-define=ENVIRONMENT=production
# → https://emotionai.duckdns.org

# Or with explicit URL:
flutter run --dart-define=BASE_URL=https://emotionai.duckdns.org --dart-define=BACKEND_TYPE=deployed --dart-define=ENVIRONMENT=production
```

### Deployed — staging

```bash
flutter run --dart-define=BACKEND_TYPE=deployed --dart-define=ENVIRONMENT=staging
# → https://staging-api.emotionai.app
```

### Explicit BASE_URL override (any scenario)

```bash
flutter run --dart-define=BASE_URL=http://192.168.1.50:9000
# → http://192.168.1.50:9000 (ignores BACKEND_TYPE, DEVICE_TYPE, DOCKER_HOST)
```

### WebSocket override

By default, the WS base URL is derived from `baseUrl` (`http → ws`, `https → wss`). To override:

```bash
flutter run --dart-define=WS_BASE_URL=wss://emotionai.duckdns.org --dart-define=BACKEND_TYPE=deployed --dart-define=ENVIRONMENT=production
```

### Verbose config logging

Add `SHOW_CONFIG_LOGS=true` to any command to print resolved URLs on startup (debug builds only):

```bash
flutter run --dart-define=BACKEND_TYPE=docker --dart-define=DOCKER_HOST=192.168.1.100 --dart-define=SHOW_CONFIG_LOGS=true
```

## Helper scripts

```bash
# Interactive launcher (prompts for backend type, device, etc.)
bash scripts/launch.sh

# Windows: Docker launch with IP prompt
scripts\launch_docker.bat

# Windows: detect and recommend your LAN IP
scripts\setup_ip.bat
```
