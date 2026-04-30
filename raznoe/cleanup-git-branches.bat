@echo off
setlocal EnableDelayedExpansion

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo Это не git-репозиторий.
    pause
    exit /b 1
)

git fetch --prune

for /f "delims=" %%i in ('git branch --show-current') do set "CURRENT_BRANCH=%%i"

echo Текущая ветка: %CURRENT_BRANCH%
echo.
echo Локальные ветки, которых больше нет на сервере:
echo -----------------------------------------------

set COUNT=0

for /f "tokens=1,* delims=:" %%a in ('git for-each-ref --format="%%(refname:short):%%(upstream:track)" refs/heads') do (
    set "BRANCH=%%a"
    set "TRACK=%%b"

    if "!TRACK!"=="[gone]" (
        if /I not "!BRANCH!"=="%CURRENT_BRANCH%" (
            echo !BRANCH!
            set /a COUNT+=1
        )
    )
)

echo -----------------------------------------------

if %COUNT%==0 (
    echo Нечего удалять.
    pause
    exit /b 0
)

echo Найдено веток: %COUNT%
echo.
set /p "CONFIRM=Введите Y чтобы удалить эти ветки: "

if /I not "%CONFIRM%"=="Y" (
    echo Отмена.
    pause
    exit /b 0
)

echo.
echo Удаление...

for /f "tokens=1,* delims=:" %%a in ('git for-each-ref --format="%%(refname:short):%%(upstream:track)" refs/heads') do (
    set "BRANCH=%%a"
    set "TRACK=%%b"

    if "!TRACK!"=="[gone]" (
        if /I not "!BRANCH!"=="%CURRENT_BRANCH%" (
            echo Удаляю !BRANCH!
            git branch -D "!BRANCH!"
        )
    )
)

echo.
echo Готово.
pause