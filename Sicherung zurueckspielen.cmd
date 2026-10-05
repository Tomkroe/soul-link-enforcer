@echo off
rem Listet die Sicherungen bzw. spielt eine zurueck (DeSmuME vorher schliessen).
cd /d "%~dp0"
call npm run restore
echo.
set /p NR=Nummer der Sicherung zum Zurueckspielen (leer = abbrechen): 
if not "%NR%"=="" call npm run restore -- %NR%
pause
