@echo off
setlocal
cd /d "%~dp0.."

set PY=python
if exist ".venv\Scripts\python.exe" set PY=.venv\Scripts\python.exe

echo Stopping old servers on port 8123...
powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 8123 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }"

if not exist "C:\Program Files\BlueStacks_nxt\HD-Player.exe" (
  echo First run - starting automatic BlueStacks + game setup...
  start "Arcade Setup" /MIN "%PY%" src\arcade_setup.py > setup.log 2>&1
)

echo Starting arcade server...
start "Arcade Server" /MIN "%PY%" src\server.py --port 8123

timeout /t 10 /nobreak >nul
start http://127.0.0.1:8123
echo Open http://127.0.0.1:8123 if the browser did not launch.
