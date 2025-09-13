@echo off
echo 📱 Launching EmotionAI for Physical Android Device...
echo.

flutter run ^
  --dart-define=ENVIRONMENT=development ^
  --dart-define=BACKEND_TYPE=deployed ^
  --dart-define=DEVICE_TYPE=physical ^
  --dart-define=BASE_URL=https://emotionai.duckdns.org

echo.
echo ✅ Launch complete!
pause 