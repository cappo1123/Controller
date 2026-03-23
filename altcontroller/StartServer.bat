@echo off
title Secret Service WebSocket Launcher
color 0b

echo [Info] Stopping existing server instances...
taskkill /f /im WebSocketServer.exe >nul 2>&1

set "COMPILER=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

timeout /t 1 /nobreak >nul
echo [Info] Compiling WebSocketServer.cs with optimizations...
"%COMPILER%" /nologo /optimize+ /out:WebSocketServer.exe /target:exe ^
  /r:System.dll ^
  /r:System.Net.dll ^
  /r:System.Net.Http.dll ^
  WebSocketServer.cs
if errorlevel 1 (
    echo [Error] Compilation failed!
    pause
    exit /b 1
)

echo [Info] Launching Server in High Priority Mode...
start "Secret Service WebSocket (FAST)" /high WebSocketServer.exe
exit
