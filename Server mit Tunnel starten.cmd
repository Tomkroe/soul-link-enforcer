@echo off
rem Startet Server und kostenlosen Cloudflare-Tunnel; zeigt die Adresse fuer config.lua.
cd /d "%~dp0"
if not exist node_modules call npm install
call npm run tunnel
pause
