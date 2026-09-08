@echo off
REM Builds an APK for the PHYSICAL PHONE (use that one as the FINDER) and
REM installs it over USB.
REM
REM The LAN address is baked in at build time, so the phone keeps working
REM after you unplug it — as long as the phone is on the same Wi-Fi as this
REM PC and the backend is running.
REM
REM If AI features stop working later, this PC's IP has probably changed:
REM run "ipconfig", read the IPv4 address, and update the line below.

set BACKEND=http://192.168.0.6:8000

echo Building APK against %BACKEND% ...
call flutter build apk --debug --dart-define=AI_BACKEND_URL=%BACKEND%
if errorlevel 1 goto :eof

echo Installing on the connected phone...
"%LOCALAPPDATA%\Android\sdk\platform-tools\adb.exe" install -r build\app\outputs\flutter-apk\app-debug.apk

echo.
echo Done. The phone app now talks to %BACKEND% and can be unplugged.
