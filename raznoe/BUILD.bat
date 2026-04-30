@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  BUILD_ANDROID.bat for FlowEngine (CMake project)
rem  - Builds FlowEngine for Android (one ABI per build dir)
rem  - Works with CMake 3.11+ (no -S/-B, no --parallel)
rem
rem  Put this .bat in the SAME folder as FlowEngine's CMakeLists.txt
rem  (the one that defines option(FLOWENGINE_SHARED ...)).
rem
rem  Usage:
rem    BUILD_ANDROID.bat                 (defaults: arm64-v8a Debug STATIC)
rem    BUILD_ANDROID.bat arm64-v8a Debug OFF
rem    BUILD_ANDROID.bat armeabi-v7a Release OFF
rem    BUILD_ANDROID.bat all Debug OFF   (builds arm64-v8a + armeabi-v7a)
rem
rem  Args:
rem    %1 = ABI      (arm64-v8a | armeabi-v7a | x86 | x86_64 | all)
rem    %2 = CONFIG   (Debug | Release)
rem    %3 = SHARED   (ON | OFF)  -> ON produces libflowengine.so, OFF produces libflowengine.a
rem ============================================================

rem ----------- EDIT THESE PATHS -----------
set "ANDROID_NDK_WIN=D:\Android\Sdk\ndk\21.3.6528147"
set "ANDROID_SDK_WIN=D:\Android\Sdk"
rem API level: 21+ is typical; keep in sync with your app (23 in your logs)
set "ANDROID_API=23"
rem Where to install (optional). Will create:
rem   <this_dir>\_install\android\<abi>\<config>\lib\cmake\flowengine\flowengineConfig.cmake
set "INSTALL_ROOT_WIN=%CD%\_install"
rem ----------------------------------------

rem Defaults (can be overridden by args)
set "ABI=%~1"
if "%ABI%"=="" set "ABI=arm64-v8a"
set "CFG=%~2"
if "%CFG%"=="" set "CFG=Debug"
set "FLOWENGINE_SHARED=%~3"
if "%FLOWENGINE_SHARED%"=="" set "FLOWENGINE_SHARED=OFF"

rem Normalize SHARED arg
if /I "%FLOWENGINE_SHARED%"=="1" set "FLOWENGINE_SHARED=ON"
if /I "%FLOWENGINE_SHARED%"=="0" set "FLOWENGINE_SHARED=OFF"
if /I "%FLOWENGINE_SHARED%"=="TRUE" set "FLOWENGINE_SHARED=ON"
if /I "%FLOWENGINE_SHARED%"=="FALSE" set "FLOWENGINE_SHARED=OFF"

rem Script dir (source dir)
set "SRC_WIN=%~dp0"
if "%SRC_WIN:~-1%"=="\" set "SRC_WIN=%SRC_WIN:~0,-1%"

if not exist "%SRC_WIN%\CMakeLists.txt" (
  echo ERROR: CMakeLists.txt not found next to this .bat:
  echo   %SRC_WIN%\CMakeLists.txt
  echo Put BUILD_ANDROID.bat into the FlowEngine source folder that contains CMakeLists.txt.
  exit /b 1
)

rem Quick tool checks
echo ==== tool versions ====
where cmake >nul 2>nul && cmake --version
where ninja >nul 2>nul && ninja --version
echo.

rem Allow "all" ABIs
if /I "%ABI%"=="all" (
  for %%A in (arm64-v8a armeabi-v7a) do (
    call :build_one "%%A" "%CFG%" "%FLOWENGINE_SHARED%"
    if errorlevel 1 exit /b 1
  )
  echo.
  echo DONE: built all requested ABIs.
  exit /b 0
)

call :build_one "%ABI%" "%CFG%" "%FLOWENGINE_SHARED%"
exit /b %errorlevel%

:build_one
setlocal EnableExtensions EnableDelayedExpansion

set "ABI=%~1"
set "CFG=%~2"
set "FLOWENGINE_SHARED=%~3"

echo ============================================================
echo Building FlowEngine for ABI=!ABI!  CONFIG=!CFG!  SHARED=!FLOWENGINE_SHARED!
echo Source: %SRC_WIN%
echo ============================================================

set "BUILD_WIN=%SRC_WIN%\build-android-!ABI!-!CFG!"
set "PREFIX_WIN=%INSTALL_ROOT_WIN%\android\!ABI!\!CFG!"

rem Clean build dir to avoid ABI mixing
if exist "!BUILD_WIN!" rmdir /s /q "!BUILD_WIN!" 2>nul
mkdir "!BUILD_WIN!" 2>nul

cd /d "!BUILD_WIN!" || exit /b 1

rem Convert to forward slashes for the Android toolchain (safe on Windows)
set "SRC=!SRC_WIN:\=/!"
set "NDK=!ANDROID_NDK_WIN:\=/!"
set "SDK=!ANDROID_SDK_WIN:\=/!"
set "PREFIX=!PREFIX_WIN:\=/!"

rem Configure
cmake -G "Ninja" ^
  -DCMAKE_BUILD_TYPE=!CFG! ^
  -DCMAKE_TOOLCHAIN_FILE="!NDK!/build/cmake/android.toolchain.cmake" ^
  -DANDROID_NDK="!NDK!" ^
  -DANDROID_ABI=!ABI! ^
  -DANDROID_PLATFORM=!ANDROID_API! ^
  -DANDROID_STL=c++_shared ^
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON ^
  -DFLOWENGINE_SHARED=!FLOWENGINE_SHARED! ^
  -DCMAKE_INSTALL_PREFIX="!PREFIX!" ^
  "!SRC!"
if errorlevel 1 (
  echo.
  echo CONFIGURE FAILED for ABI=!ABI!
  exit /b 1
)

rem Build
cmake --build .
if errorlevel 1 (
  echo.
  echo BUILD FAILED for ABI=!ABI!
  exit /b 1
)

rem Install (gives you a stable prefix to use from other projects)
cmake --build . --target install
if errorlevel 1 (
  echo.
  echo INSTALL FAILED for ABI=!ABI!
  exit /b 1
)

rem Create a minimal flowengineConfig.cmake so find_package(flowengine CONFIG REQUIRED) works
set "PKG_DIR_WIN=!PREFIX_WIN!\lib\cmake\flowengine"
if not exist "!PKG_DIR_WIN!" mkdir "!PKG_DIR_WIN!" 2>nul

set "CFG_FILE=!PKG_DIR_WIN!\flowengineConfig.cmake"
(
  echo include^("${CMAKE_CURRENT_LIST_DIR}/flowengineTargets.cmake"^)
) > "!CFG_FILE!"

echo.
echo ---- Outputs ----
if /I "!FLOWENGINE_SHARED!"=="ON" (
  if exist "!BUILD_WIN!\libflowengine.so" echo Built:  !BUILD_WIN!\libflowengine.so
  if exist "!PREFIX_WIN!\lib\libflowengine.so" echo Install: !PREFIX_WIN!\lib\libflowengine.so
) else (
  if exist "!BUILD_WIN!\libflowengine.a" echo Built:  !BUILD_WIN!\libflowengine.a
  if exist "!PREFIX_WIN!\lib\libflowengine.a" echo Install: !PREFIX_WIN!\lib\libflowengine.a
)

echo Package dir for find_package:
echo   !PKG_DIR_WIN!
echo   ^(use: -Dflowengine_DIR="!PKG_DIR_WIN!" in your app^)
echo.

endlocal
exit /b 0
