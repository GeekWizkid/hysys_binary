@echo off
setlocal

rem ============================================================
rem Build flowengineui for Android arm64-v8a using the SAME
rem parameters as CMakePresets.json (no cmake --preset).
rem Usage:
rem   BUILD_android_arm64_from_presets.bat
rem   BUILD_android_arm64_from_presets.bat Debug
rem   BUILD_android_arm64_from_presets.bat Release
rem ============================================================

cd /d "%~dp0"
set "SRC=%CD%"

set "CONFIG=%~1"
if not defined CONFIG set "CONFIG=Debug"

if /I "%CONFIG%"=="Debug" (
  set "BUILD=%SRC%\build\android-arm64-debug"
) else if /I "%CONFIG%"=="Release" (
  set "BUILD=%SRC%\build\android-arm64-release"
) else (
  echo Unknown config: %CONFIG%
  echo Use Debug or Release
  exit /b 1
)

rem ---- values copied from CMakePresets.json ----
set "QT_ANDROID_ROOT=D:\Qt6Official\6.10.2\android_arm64_v8a"
set "QT_HOST_PATH=D:\Qt6Official\6.10.2\mingw_64"
set "ANDROID_SDK_ROOT=D:\Android\sdk"
set "ANDROID_NDK=D:\Android\sdk\ndk\27.2.12479018"
set "FLOWENGINE_DIR=D:\flowengine-android-arm64\lib\cmake\flowengine"
set "TOOLCHAIN_FILE=%ANDROID_NDK%\build\cmake\android.toolchain.cmake"
set "QT_QMAKE_EXECUTABLE=%QT_ANDROID_ROOT%\bin\qmake.bat"
rem ----------------------------------------------

set "ANDROID_NDK_ROOT=%ANDROID_NDK%"
set "PATH=%QT_HOST_PATH%\bin;%PATH%"

if not exist "%TOOLCHAIN_FILE%" (
  echo TOOLCHAIN_FILE not found: %TOOLCHAIN_FILE%
  exit /b 1
)
if not exist "%QT_ANDROID_ROOT%\lib\cmake\Qt6\Qt6Config.cmake" (
  echo Qt6Config.cmake not found under %QT_ANDROID_ROOT%
  exit /b 1
)
if not exist "%FLOWENGINE_DIR%\flowengineConfig.cmake" (
  echo flowengineConfig.cmake not found under %FLOWENGINE_DIR%
  exit /b 1
)

where cmake >nul 2>nul || (echo cmake not found in PATH & exit /b 1)
where ninja >nul 2>nul || (echo ninja not found in PATH & exit /b 1)

echo ==== tool versions ====
cmake --version
ninja --version

echo ==== configure parameters ====
echo SRC=%SRC%
echo BUILD=%BUILD%
echo CONFIG=%CONFIG%
echo QT_ANDROID_ROOT=%QT_ANDROID_ROOT%
echo QT_HOST_PATH=%QT_HOST_PATH%
echo ANDROID_SDK_ROOT=%ANDROID_SDK_ROOT%
echo ANDROID_NDK=%ANDROID_NDK%
echo FLOWENGINE_DIR=%FLOWENGINE_DIR%

echo ==== cleaning build dir ====
rmdir /s /q "%BUILD%" 2>nul

echo ==== configure ====
cmake -S "%SRC%" -B "%BUILD%" -G Ninja ^
  -DCMAKE_BUILD_TYPE=%CONFIG% ^
  -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN_FILE%" ^
  -DUSE_QT6=ON ^
  -DANDROID_ABI=arm64-v8a ^
  -DANDROID_PLATFORM=android-28 ^
  -DANDROID_STL=c++_shared ^
  -DANDROID_USE_LEGACY_TOOLCHAIN_FILE=OFF ^
  -DANDROID_SDK_ROOT="%ANDROID_SDK_ROOT%" ^
  -DANDROID_NDK="%ANDROID_NDK%" ^
  -DCMAKE_PREFIX_PATH="%QT_ANDROID_ROOT%" ^
  -DCMAKE_FIND_ROOT_PATH="%QT_ANDROID_ROOT%" ^
  -DQT_HOST_PATH="%QT_HOST_PATH%" ^
  -DQT_QMAKE_EXECUTABLE="%QT_QMAKE_EXECUTABLE%" ^
  -Dflowengine_DIR="%FLOWENGINE_DIR%" ^
  -DQT_NO_GLOBAL_APK_TARGET_PART_OF_ALL=OFF ^
  -DQT_USE_TARGET_ANDROID_BUILD_DIR=ON
if errorlevel 1 goto :fail

echo ==== native+apk build ====
cmake --build "%BUILD%"
if errorlevel 1 goto :fail

echo ==== APK files ====
dir /s /b "%BUILD%\*.apk"
goto :eof

:fail
echo.
echo FAILED
exit /b 1
