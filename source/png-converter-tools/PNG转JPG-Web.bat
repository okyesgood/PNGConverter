@echo off
setlocal EnableExtensions
chcp 65001 >nul
set "TOOL_DIR=%~dp0"
set "RUN_SCRIPT=%TOOL_DIR%run.ps1"
set "PS_SCRIPT=%TOOL_DIR%photoshop_convert.jsx"
set "DRAG_MODE=0"
if not "%~1"=="" set "DRAG_MODE=1"
if not exist "%RUN_SCRIPT%" goto missing_run
if not exist "%PS_SCRIPT%" goto missing_jsx
if "%~1"=="" goto manual_mode
set "ARG_FILE=%TEMP%\PngToJpgWeb_%RANDOM%_%RANDOM%.txt"
break > "%ARG_FILE%"
set "ARG_COUNT=0"
:collect_args
if "%~1"=="" goto args_collected
>> "%ARG_FILE%" echo(%~1
set /a ARG_COUNT+=1
shift
goto collect_args
:args_collected
echo [INFO] Received drag items: %ARG_COUNT%
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%RUN_SCRIPT%" -InputListFile "%ARG_FILE%"
set "EXIT_CODE=%ERRORLEVEL%"
del /q "%ARG_FILE%" >nul 2>&1
goto finish
:manual_mode
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%RUN_SCRIPT%"
set "EXIT_CODE=%ERRORLEVEL%"
goto finish
:missing_run
echo [ERROR] Missing run.ps1
set "EXIT_CODE=2"
goto finish
:missing_jsx
echo [ERROR] Missing photoshop_convert.jsx
set "EXIT_CODE=2"
:finish
if not "%EXIT_CODE%"=="0" echo [ERROR] Conversion finished with exit code %EXIT_CODE%.
exit /b %EXIT_CODE%
