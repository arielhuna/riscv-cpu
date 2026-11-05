@echo off
rem run_all.bat - run every testbench in tb\ and write a summary.
rem Double-click it, or run .\run_all from PowerShell.
rem   Summary:   regression.txt (opens in Notepad when done)
rem   Full logs: build\logs\<name>.log
rem A test counts as PASS only if its log has "PASSED:", FAIL on "FAILED:"
rem or a compile/elaboration error, and NO RESULT if it prints neither.

setlocal enabledelayedexpansion
cd /d "%~dp0"
set "ROOT=%CD%"
set "OUT=%ROOT%\regression.txt"
set "LOGS=%ROOT%\build\logs"
if not exist "%LOGS%" mkdir "%LOGS%"

set /a NPASS=0
set /a NFAIL=0
set /a NNONE=0
set "FAILS="

> "%OUT%" echo Regression run: %DATE% %TIME%
>>"%OUT%" echo ============================================================
>>"%OUT%" echo.

for %%f in ("%ROOT%\tb\tb_*.sv") do call :run "%%~nf"

>>"%OUT%" echo.
>>"%OUT%" echo ============================================================
>>"%OUT%" echo PASS: %NPASS%    FAIL: %NFAIL%    NO RESULT: %NNONE%
if %NFAIL% gtr 0 (
    >>"%OUT%" echo FAILED TESTS:%FAILS%
) else (
    >>"%OUT%" echo ALL SELF-CHECKING TESTS PASSED
)

echo.
type "%OUT%"
start "" notepad "%OUT%"
endlocal
exit /b 0


rem ---------- run one testbench: %1 = tb_<name> ----------
:run
set "TB=%~1"
set "NAME=%TB:~3%"
set "LOG=%LOGS%\%NAME%.log"
set "COL=%NAME%                "
set "COL=%COL:~0,14%"
echo Running %NAME% ...

call "%ROOT%\sim.bat" %NAME% > "%LOG%" 2>&1

set "RES=none"
for /f "delims=" %%L in ('findstr /L /C:"PASSED:" /C:"FAILED:" "%LOG%"') do set "RES=%%L"

if "%RES:~0,7%"=="PASSED:" (
    set /a NPASS+=1
    >>"%OUT%" echo PASS   %COL% %RES%
    goto :eof
)

if "%RES:~0,7%"=="FAILED:" (
    set /a NFAIL+=1
    set "FAILS=!FAILS! %NAME%"
    >>"%OUT%" echo FAIL   %COL% %RES%
    findstr /L /C:"ERROR" "%LOG%" >> "%OUT%"
    goto :eof
)

findstr /L /C:"SIMULATION FAILED" "%LOG%" >nul
if not errorlevel 1 (
    set /a NFAIL+=1
    set "FAILS=!FAILS! %NAME%"
    >>"%OUT%" echo FAIL   %COL% compile/elaboration error, see build\logs\%NAME%.log
    findstr /L /C:"ERROR:" "%LOG%" >> "%OUT%"
    goto :eof
)

set /a NNONE+=1
>>"%OUT%" echo ----   %COL% no PASSED/FAILED line (not self-checking)
goto :eof
