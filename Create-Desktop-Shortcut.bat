@echo off
echo.
echo   PC Health Monitor - Creating Desktop Shortcut
echo   ===============================================
echo.

if not exist "%~dp0PC-Health-Monitor.ps1" (
    echo   ERROR: PC-Health-Monitor.ps1 not found in this folder.
    echo   Make sure both files are in the same folder and try again.
    echo.
    pause
    exit /b 1
)

powershell.exe -ExecutionPolicy Bypass -File "%~dp0Create-Desktop-Shortcut.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   Something went wrong during shortcut creation.
    echo   Try right-clicking this file and selecting "Run as Administrator".
    echo.
)

pause
