@echo off
rem Double-click to open PC Hand-off (no console window).
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0pc-handoff.ps1"
