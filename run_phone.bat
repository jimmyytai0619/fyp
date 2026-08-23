@echo off
REM Runs the app on a connected phone, pointed at this PC's backend.
REM If AI matching stops working, check your PC's Wi-Fi IP (ipconfig)
REM and update the address below if it changed.
flutter run --dart-define=AI_BACKEND_URL=http://192.168.0.17:8000
