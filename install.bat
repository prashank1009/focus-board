@echo off
rem Installs Focus Board from this folder. Keep the folder somewhere permanent (e.g. Documents) before running.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' | Unblock-File; & '%~dp0setup.ps1'"
