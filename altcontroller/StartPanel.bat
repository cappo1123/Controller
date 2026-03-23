@echo off
title Secret Service Panel Launcher
color 0b

echo [Info] Stopping existing server instances...
taskkill /f /im WebSocketServer.exe >nul 2>&1
taskkill /f /im "Secret Service.exe" >nul 2>&1
taskkill /f /im AltPanel.exe >nul 2>&1

set "COMPILER=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

timeout /t 1 /nobreak >nul
echo [Info] Compiling SecretService.cs...
"%COMPILER%" /nologo /optimize+ /target:winexe /out:"Secret Service.exe" ^
  /r:System.dll ^
  /r:System.Windows.Forms.dll ^
  /r:System.Drawing.dll ^
  /r:System.Net.dll ^
  /r:System.Net.Http.dll ^
  SecretService.cs
if errorlevel 1 (
    echo [Error] Compilation failed!
    pause
    exit /b 1
)

echo [Info] Launching Secret Service...
start "" "Secret Service.exe"
exit
