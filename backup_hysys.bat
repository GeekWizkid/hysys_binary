@echo off
setlocal EnableExtensions

set "TARGET_LABEL=HYSYS_BACKUP"
set "SRC_APP=D:\HYSYS 1.1"
set "SRC_RE=D:\VSProjects\re"

for /f "delims=" %%I in ('powershell -NoProfile -Command Get-Date -Format dd.MM.yyyy') do set "TODAY=%%I"
if not defined TODAY (
    echo [ERROR] Cannot determine current date.
    exit /b 1
)

call :find_backup_drive
if errorlevel 1 exit /b 1

echo Backup drive: %BACKUP_DRIVE%
echo Backup date: %TODAY%

set "BASE_DIR=%BACKUP_DRIVE%\Hysys"
set "BACKUP_DIR=%BASE_DIR%\%TODAY%"
set "APP_DIR=%BACKUP_DIR%\HYSYS_1.1"
set "GIT_DIR=%BACKUP_DIR%\git"
set "RE_ZIP=%APP_DIR%\re.zip"

where git >nul 2>&1
if errorlevel 1 (
    echo [ERROR] git not found in PATH.
    exit /b 1
)

echo [1/5] Create folders...
if not exist "%APP_DIR%" mkdir "%APP_DIR%"
if not exist "%GIT_DIR%" mkdir "%GIT_DIR%"
if errorlevel 1 (
    echo [ERROR] Cannot create backup folders.
    exit /b 1
)

echo [2/5] Copy application files...
call :copy_required "%SRC_APP%\hysys.exe.i64" "%APP_DIR%"
if errorlevel 1 exit /b 1

call :copy_required "%SRC_APP%\Iface.dll.i64" "%APP_DIR%"
if errorlevel 1 exit /b 1

call :copy_required "%SRC_APP%\hysys.CT" "%APP_DIR%"
if errorlevel 1 exit /b 1

echo [3/5] Archive %SRC_RE% ...
if not exist "%SRC_RE%" (
    echo [ERROR] Folder not found: "%SRC_RE%"
    exit /b 1
)

powershell -NoProfile -Command "& { $ErrorActionPreference = 'Stop'; Compress-Archive -Path '%SRC_RE%' -DestinationPath '%RE_ZIP%' -Force }"
if errorlevel 1 (
    echo [ERROR] Archive creation failed.
    exit /b 1
)

echo [4/5] Git mirror backup...
call :mirror_repo "https://flowengine.t-soft.ru/tsoft/flowengine" "flowengine.git"
if errorlevel 1 exit /b 1

call :mirror_repo "https://flowengine.t-soft.ru/tsoft/flowengine.wiki" "flowengine.wiki.git"
if errorlevel 1 exit /b 1

call :mirror_repo "https://flowengine.t-soft.ru/tsoft/flowengineui" "flowengineui.git"
if errorlevel 1 exit /b 1

call :mirror_repo "https://flowengine.t-soft.ru/tsoft/flowengineui.wiki" "flowengineui.wiki.git"
if errorlevel 1 exit /b 1

echo [5/5] Done.
echo Backup completed:
echo %BACKUP_DIR%
exit /b 0

:find_backup_drive
set "BACKUP_DRIVE="

for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    vol %%D: 2>nul | find /I "%TARGET_LABEL%" >nul
    if not errorlevel 1 (
        set "BACKUP_DRIVE=%%D:"
        goto :drive_found
    )
)

echo [ERROR] Backup drive with label "%TARGET_LABEL%" not found.
exit /b 1

:drive_found
exit /b 0

:copy_required
if not exist "%~1" (
    echo [ERROR] File not found: "%~1"
    exit /b 1
)
copy /Y "%~1" "%~2\" >nul
if errorlevel 1 (
    echo [ERROR] Copy failed: "%~1"
    exit /b 1
)
exit /b 0

:mirror_repo
set "REPO_URL=%~1"
set "REPO_NAME=%~2"

if exist "%GIT_DIR%\%REPO_NAME%\HEAD" (
    echo Updating %REPO_NAME% ...
    git -C "%GIT_DIR%\%REPO_NAME%" remote update --prune
) else (
    echo Cloning %REPO_NAME% ...
    git clone --mirror "%REPO_URL%" "%GIT_DIR%\%REPO_NAME%"
)

if errorlevel 1 (
    echo [ERROR] Git backup failed for %REPO_NAME%.
    exit /b 1
)
exit /b 0
