@echo off
echo 🚀 Launching EmotionAI for Android Virtual Device (AVD)...
echo.

flutter run ^
  --dart-define=ENVIRONMENT=development_emulator ^
  --dart-define=BACKEND_TYPE=deployed ^
  --dart-define=DEVICE_TYPE=emulator ^
  --dart-define=BASE_URL=https://emotionai.duckdns.org

echo.
echo ✅ Launch complete!
pause 