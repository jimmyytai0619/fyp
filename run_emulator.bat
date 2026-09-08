@echo off
REM Runs the app on the desktop Android emulator, for testing two accounts at
REM once (e.g. loser on the emulator, finder on the phone APK).
REM
REM The emulator reaches this PC at 10.0.2.2, its built-in alias for the host
REM machine -- NOT the LAN IP the phone uses. That address is already the
REM default in lib/services/api_service.dart, so no --dart-define is needed.
REM
REM Set AVD below to the emulator you want. It must use an x86_64 system
REM image: Flutter no longer supports 32-bit x86 emulators and reports them as
REM "unsupported" even though they boot fine.

REM TZ: the emulator ignores the host timezone and boots on UTC, so its clock
REM reads 8 hours behind a UTC+8 machine. Launching it with an explicit zone
REM keeps the two in step. Change this if you are not in Malaysia.
set AVD=Pixel_5_API_31
set TZ=Asia/Kuala_Lumpur
set ADB="%LOCALAPPDATA%\Android\sdk\platform-tools\adb.exe"
set EMULATOR="%LOCALAPPDATA%\Android\sdk\emulator\emulator.exe"

REM Check for the EMULATOR specifically: a plugged-in phone must not be
REM mistaken for it, or the emulator would never start.
echo Launching %AVD% (skipped if already running)...
REM -no-snapshot-load forces a cold boot. Resuming from a snapshot also
REM restores that snapshot's CLOCK, leaving the emulator seconds-to-hours
REM behind real time — and Supabase then rejects every login with "JWT issued
REM at future", because the token's timestamp is ahead of what the device
REM believes the time to be. A cold boot re-syncs the clock to this PC.
%ADB% -s emulator-5554 get-state >nul 2>&1
if errorlevel 1 (
    start "" %EMULATOR% -avd %AVD% -timezone %TZ% -no-snapshot-load
) else (
    echo Emulator already running - skipping launch.
)

echo Waiting for the emulator to finish booting...
%ADB% -s emulator-5554 wait-for-device
:waitboot
for /f "tokens=*" %%i in ('%ADB% -s emulator-5554 shell getprop sys.boot_completed 2^>nul') do set BOOTED=%%i
if not "%BOOTED%"=="1" (
    timeout /t 3 /nobreak >nul
    goto waitboot
)

REM -d targets the emulator explicitly: with the phone also plugged in, plain
REM "flutter run" would stop and ask which device to use.
echo Emulator ready. Starting the app...
flutter run -d emulator-5554
