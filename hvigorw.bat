@echo off
setlocal

set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"

if not defined ComSpec set "ComSpec=%SystemRoot%\System32\cmd.exe"
if not exist "%ComSpec%" set "ComSpec=%SystemRoot%\System32\cmd.exe"

set "SYSTEM32_DIR=%SystemRoot%\System32"
set "POWERSHELL_DIR=%SystemRoot%\System32\WindowsPowerShell\v1.0"

echo %PATH% | "%SYSTEM32_DIR%\findstr.exe" /I /C:"%SYSTEM32_DIR%" >nul
if errorlevel 1 set "PATH=%SYSTEM32_DIR%;%PATH%"

echo %PATH% | "%SYSTEM32_DIR%\findstr.exe" /I /C:"%POWERSHELL_DIR%" >nul
if errorlevel 1 set "PATH=%POWERSHELL_DIR%;%PATH%"

if defined HARMONY_HVIGORW_BIN if exist "%HARMONY_HVIGORW_BIN%" goto run_hvigor
if defined HARMONY_COMMANDLINE_TOOLS_HOME if exist "%HARMONY_COMMANDLINE_TOOLS_HOME%\bin\hvigorw.bat" set "HARMONY_HVIGORW_BIN=%HARMONY_COMMANDLINE_TOOLS_HOME%\bin\hvigorw.bat"
if not defined HARMONY_HVIGORW_BIN if exist "D:\command-line-tools\bin\hvigorw.bat" set "HARMONY_HVIGORW_BIN=D:\command-line-tools\bin\hvigorw.bat"
if not defined HARMONY_HVIGORW_BIN if exist "D:\hongmeng\command-line-tools\bin\hvigorw.bat" set "HARMONY_HVIGORW_BIN=D:\hongmeng\command-line-tools\bin\hvigorw.bat"

:run_hvigor
if not defined HARMONY_HVIGORW_BIN (
  echo [FAIL] Unable to locate Harmony hvigorw.bat. 1>&2
  echo [FAIL] Set HARMONY_HVIGORW_BIN or HARMONY_COMMANDLINE_TOOLS_HOME first. 1>&2
  exit /b 1
)

call "%HARMONY_HVIGORW_BIN%" %*
exit /b %ERRORLEVEL%
