@echo off
REM Script to run Flutter app on Android emulator
echo Starting Flutter app on Android emulator...
echo Backend will be accessible at: http://10.0.2.2:8000
flutter run --dart-define=ENVIRONMENT=development_emulator --dart-define=BACKEND_TYPE=deployed --dart-define=DEVICE_TYPE=emulator --dart-define=BASE_URL=https://emotionai.duckdns.org
pause