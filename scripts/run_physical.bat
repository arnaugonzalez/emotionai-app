@echo off
REM Script to run Flutter app on physical device with current machine IP
REM Update the IP address below to match your machine's current IP

echo Getting current machine IP...
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /i "IPv4.*192.168"') do (
    for /f "tokens=1" %%j in ("%%i") do set CURRENT_IP=%%j
)

if defined CURRENT_IP (
    echo Found IP: %CURRENT_IP%
    echo Starting Flutter app with IP: %CURRENT_IP%
    flutter run --dart-define=ENVIRONMENT=development --dart-define=BACKEND_TYPE=deployed --dart-define=DEVICE_TYPE=physical --dart-define=BASE_URL=https://emotionai.duckdns.org
) else (
    echo Could not detect IP automatically. Using default IP...
    echo Update this script with your machine's IP address
    flutter run --dart-define=ENVIRONMENT=development --dart-define=BACKEND_TYPE=deployed --dart-define=DEVICE_TYPE=physical --dart-define=BASE_URL=https://emotionai.duckdns.org
)

pause