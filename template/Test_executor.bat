@echo off
setlocal EnableDelayedExpansion

rem =====================================================================
rem JMeter Template launcher.
rem Responsibilities (operational only):
rem   - parse CLI args
rem   - create per-run output directory
rem   - invoke jmeter.bat in non-GUI mode
rem   - propagate exit code
rem   - zip runDir on success via bundled tar.exe
rem See jmeter-template-plan.md sections 4.4 and 4.5.
rem =====================================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "PROFILE="
set "ENVNAME="
set "PROJECT="
set "MODE="
set "PROXY_HOST="
set "PROXY_PORT="
set "RESULTS_ROOT=%SCRIPT_DIR%\results"

:parse
if "%~1"=="" goto after_parse
if /I "%~1"=="--help"         goto usage
if /I "%~1"=="-h"             goto usage
if /I "%~1"=="/?"             goto usage
if /I "%~1"=="--profile"      (set "PROFILE=%~2"     & shift & shift & goto parse)
if /I "%~1"=="--env"          (set "ENVNAME=%~2"     & shift & shift & goto parse)
if /I "%~1"=="--project"      (set "PROJECT=%~2"     & shift & shift & goto parse)
if /I "%~1"=="--mode"         (set "MODE=%~2"        & shift & shift & goto parse)
if /I "%~1"=="--proxy-host"   (set "PROXY_HOST=%~2"  & shift & shift & goto parse)
if /I "%~1"=="--proxy-port"   (set "PROXY_PORT=%~2"  & shift & shift & goto parse)
if /I "%~1"=="--results-root" (set "RESULTS_ROOT=%~2" & shift & shift & goto parse)
echo [FATAL] Unknown argument: %~1
goto usage_err

:after_parse
if "%PROFILE%"==""  (echo [FATAL] Missing required --profile)  & goto usage_err
if "%ENVNAME%"==""  (echo [FATAL] Missing required --env)      & goto usage_err
if "%PROJECT%"==""  (echo [FATAL] Missing required --project)  & goto usage_err
if not "%MODE%"=="" (
  if /I not "%MODE%"=="weighted" if /I not "%MODE%"=="sequential" (
    echo [FATAL] Invalid --mode: %MODE% ^(expected weighted^|sequential^)
    goto usage_err
  )
)

rem --- Resolve profile file path (used for an early existence check) ---
set "PROFILE_FILE=%SCRIPT_DIR%\profiles\%PROFILE%.json"
if not exist "%PROFILE_FILE%" (
  echo [FATAL] Profile file not found: %PROFILE_FILE%
  exit /b 2
)
if not exist "%SCRIPT_DIR%\environmentVariables.json" (
  echo [FATAL] Missing environmentVariables.json in %SCRIPT_DIR%
  exit /b 2
)
if not exist "%SCRIPT_DIR%\jmeter.jmx" (
  echo [FATAL] Missing jmeter.jmx in %SCRIPT_DIR%
  exit /b 2
)

rem --- Timestamp yyyyMMdd_HHmmss. Prefer Java 17; fall back without PowerShell. ---
call :make_timestamp
if "%TS%"=="" (
  echo [FATAL] Could not determine timestamp.
  exit /b 3
)
set "RUN_NAME=%PROJECT%_%TS%"
set "RUN_DIR=%RESULTS_ROOT%\%RUN_NAME%"
set "ZIP_FILE=%RESULTS_ROOT%\%RUN_NAME%.zip"

rem --- Create run directory tree ---
if not exist "%RESULTS_ROOT%" mkdir "%RESULTS_ROOT%"
if exist "%RUN_DIR%" (
  echo [FATAL] Run directory already exists: %RUN_DIR%
  exit /b 4
)
mkdir "%RUN_DIR%"
mkdir "%RUN_DIR%\custom"
mkdir "%RUN_DIR%\report"

rem --- Optional -J flags. Mandatory -J flags are quoted directly at invocation. ---
set "MODE_FLAG="
set "PROXY_HOST_FLAG="
set "PROXY_PORT_FLAG="
if not "%MODE%"==""       set "MODE_FLAG=-Jmode=%MODE%"
if not "%PROXY_HOST%"=="" set "PROXY_HOST_FLAG=-Jproxy.host=%PROXY_HOST%"
if not "%PROXY_PORT%"=="" set "PROXY_PORT_FLAG=-Jproxy.port=%PROXY_PORT%"

rem --- JMeter output paths ---
set "JTL=%RUN_DIR%\raw.jtl"
set "JLOG=%RUN_DIR%\jmeter.log"
set "HTML=%RUN_DIR%\report"

echo.
echo [INFO] Run directory: %RUN_DIR%
echo [INFO] Launching JMeter...
echo.

rem JMeter CLI generates the HTML dashboard inline with -e -o.
rem The -o directory must not exist OR must be empty; we just created it empty.
rem Per §4.7, listeners are disabled in the .jmx — CLI relies on -l for JTL output.
call jmeter.bat -n -t "%SCRIPT_DIR%\jmeter.jmx" -l "%JTL%" -j "%JLOG%" -e -o "%HTML%" "-Jprofile=%PROFILE%" "-Jenv=%ENVNAME%" "-JprojectName=%PROJECT%" "-JresultsRootDir=%RESULTS_ROOT%" "-JrunDir=%RUN_DIR%" %MODE_FLAG% %PROXY_HOST_FLAG% %PROXY_PORT_FLAG%
set "JMX_EXIT=%ERRORLEVEL%"

if not "%JMX_EXIT%"=="0" (
  echo.
  echo [ERROR] JMeter exited with code %JMX_EXIT% — skipping zip step.
  exit /b %JMX_EXIT%
)

rem --- Zip runDir using bundled tar.exe (Windows 10+). -a selects format by extension.
echo.
echo [INFO] Packaging results: %ZIP_FILE%
pushd "%RESULTS_ROOT%" >NUL
tar.exe -a -cf "%ZIP_FILE%" "%RUN_NAME%"
set "ZIP_EXIT=%ERRORLEVEL%"
popd >NUL

if not "%ZIP_EXIT%"=="0" (
  echo [WARN] tar.exe failed with code %ZIP_EXIT% — runDir preserved at %RUN_DIR%
  exit /b %ZIP_EXIT%
)

echo [INFO] Done.
exit /b 0

:make_timestamp
set "TS="
if "%TEMP%"=="" goto timestamp_java_done
set "TS_HELPER=%TEMP%\jmeter_template_timestamp_%RANDOM%%RANDOM%.java"
> "%TS_HELPER%" echo import java.time.LocalDateTime;
>> "%TS_HELPER%" echo import java.time.format.DateTimeFormatter;
>> "%TS_HELPER%" echo class JMeterTemplateTimestamp {
>> "%TS_HELPER%" echo   public static void main(String[] args) {
>> "%TS_HELPER%" echo     System.out.print(LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss")));
>> "%TS_HELPER%" echo   }
>> "%TS_HELPER%" echo }
for /f "usebackq delims=" %%I in (`java "%TS_HELPER%" 2^>NUL`) do set "TS=%%I"
if exist "%TS_HELPER%" del /q "%TS_HELPER%" >NUL 2>NUL
:timestamp_java_done
if not "%TS%"=="" exit /b 0

rem Fallback for older hosts. wmic is deprecated, so this is intentionally secondary.
set "LDT="
for /f "usebackq tokens=2 delims==" %%I in (`wmic os get LocalDateTime /value 2^>NUL ^| findstr "="`) do set "LDT=%%I"
if not "%LDT%"=="" (
  set "TS=%LDT:~0,8%_%LDT:~8,6%"
  exit /b 0
)

rem Last-resort locale-tolerant parse of common Windows DATE/TIME formats.
call :timestamp_from_env
exit /b 0

:timestamp_from_env
set "DATE_TEXT=%DATE%"
set "TIME_TEXT=%TIME: =0%"
set "P1="
set "P2="
set "P3="
set "P4="
set "Y="
set "M="
set "D="
for /f "tokens=1-4 delims=/-. " %%A in ("%DATE_TEXT%") do (
  set "P1=%%A"
  set "P2=%%B"
  set "P3=%%C"
  set "P4=%%D"
)
if not "!P1:~3,1!"=="" if "!P1:~4,1!"=="" (
  set "Y=!P1!"
  set "M=!P2!"
  set "D=!P3!"
  goto timestamp_from_env_build
)
if not "!P4!"=="" if not "!P4:~3,1!"=="" if "!P4:~4,1!"=="" (
  set "Y=!P4!"
  set "M=!P2!"
  set "D=!P3!"
  goto timestamp_from_env_build
)
if not "!P3:~3,1!"=="" if "!P3:~4,1!"=="" (
  set "Y=!P3!"
  set "M=!P1!"
  set "D=!P2!"
)
:timestamp_from_env_build
if "!M:~1,1!"=="" set "M=0!M!"
if "!D:~1,1!"=="" set "D=0!D!"
if not "!Y!"=="" if not "!M!"=="" if not "!D!"=="" (
  set "TS=!Y!!M!!D!_!TIME_TEXT:~0,2!!TIME_TEXT:~3,2!!TIME_TEXT:~6,2!"
)
exit /b 0

:usage
echo.
echo Usage:
echo   Test_executor.bat --profile ^<name^> --env ^<name^> --project ^<name^>
echo                     [--mode weighted^|sequential]
echo                     [--proxy-host ^<host^> --proxy-port ^<port^>]
echo                     [--results-root ^<path^>]
echo                     [--help]
echo.
echo Required:
echo   --profile       Profile name; resolves to profiles\^<name^>.json
echo   --env           Environment key in environmentVariables.json (e.g. dev, staging, prod)
echo   --project       Project name; used in results folder name
echo.
echo Optional:
echo   --mode          Override profile's mode (weighted^|sequential)
echo   --proxy-host    HTTP proxy host
echo   --proxy-port    HTTP proxy port
echo   --results-root  Override default .\results
echo   --help, -h      Show this help
echo.
echo Output:
echo   results\^<project^>_yyyyMMdd_HHmmss\   runDir (raw.jtl, jmeter.log, effective-config.json, report\, custom\)
echo   results\^<project^>_yyyyMMdd_HHmmss.zip  archive of runDir (on success)
echo.
exit /b 0

:usage_err
echo.
echo Run "Test_executor.bat --help" for usage.
exit /b 1
