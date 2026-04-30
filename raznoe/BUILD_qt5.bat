@echo off
setlocal

cd /d "%~dp0"

set "QT_ROOT_WIN=C:\qt\5.15.2\android"
set "ANDROID_SDK_WIN=D:\Android\Sdk"
set "ANDROID_NDK_WIN=D:\Android\Sdk\ndk\21.3.6528147"
set "JAVA_HOME_WIN=C:\Program Files\Java\jdk-11.0.6"
set "FLOWENGINE_DIR_WIN=D:\work\Android\flowengine\src\flowengine\flowengine\_install\android\arm64-v8a\Debug\lib\cmake\flowengine"
set "ABI=arm64-v8a"
set "CFG=Debug"
set "ANDROID_API=23"

set "PROJECT_ROOT_WIN=%CD%"
set "BUILD_DIR_WIN=%PROJECT_ROOT_WIN%\build-android-%ABI%"

set "QT_ROOT=%QT_ROOT_WIN:\=/%"
set "ANDROID_SDK=%ANDROID_SDK_WIN:\=/%"
set "ANDROID_NDK=%ANDROID_NDK_WIN:\=/%"
set "FLOWENGINE_DIR=%FLOWENGINE_DIR_WIN:\=/%"

set "PATH=%QT_ROOT_WIN%\bin;%JAVA_HOME_WIN%\bin;%PATH%"
set "JAVA_HOME=%JAVA_HOME_WIN%"

if not exist "%QT_ROOT_WIN%\lib\cmake\Qt5\Qt5Config.cmake" (
  echo Qt5Config.cmake not found under %QT_ROOT_WIN%
  exit /b 1
)

if not exist "%FLOWENGINE_DIR_WIN%\flowengineConfig.cmake" (
  echo flowengineConfig.cmake not found under %FLOWENGINE_DIR_WIN%
  exit /b 1
)

set "ABI_FLAG_V7=OFF"
set "ABI_FLAG_A64=OFF"
set "ABI_FLAG_X86=OFF"
set "ABI_FLAG_X64=OFF"
if /I "%ABI%"=="armeabi-v7a" set "ABI_FLAG_V7=ON"
if /I "%ABI%"=="arm64-v8a"   set "ABI_FLAG_A64=ON"
if /I "%ABI%"=="x86"         set "ABI_FLAG_X86=ON"
if /I "%ABI%"=="x86_64"      set "ABI_FLAG_X64=ON"

echo ==== tool versions ====
cmake --version
ninja --version
echo.

echo ==== cleaning build dir ====
rmdir /s /q "%BUILD_DIR_WIN%" 2>nul
mkdir "%BUILD_DIR_WIN%"
cd /d "%BUILD_DIR_WIN%"

cmake -G Ninja ^
  -DCMAKE_BUILD_TYPE=%CFG% ^
  -DCMAKE_PREFIX_PATH="%QT_ROOT%" ^
  -DQt5_DIR="%QT_ROOT%/lib/cmake/Qt5" ^
  -DCMAKE_TOOLCHAIN_FILE="%ANDROID_NDK%/build/cmake/android.toolchain.cmake" ^
  -DCMAKE_FIND_ROOT_PATH="%QT_ROOT%" ^
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH ^
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH ^
  -Dflowengine_DIR="%FLOWENGINE_DIR%" ^
  -DANDROID_SDK="%ANDROID_SDK%" ^
  -DANDROID_NDK="%ANDROID_NDK%" ^
  -DCMAKE_ANDROID_NDK="%ANDROID_NDK%" ^
  -DANDROID_ABI=%ABI% ^
  -DANDROID_BUILD_ABI_armeabi-v7a=%ABI_FLAG_V7% ^
  -DANDROID_BUILD_ABI_arm64-v8a=%ABI_FLAG_A64% ^
  -DANDROID_BUILD_ABI_x86=%ABI_FLAG_X86% ^
  -DANDROID_BUILD_ABI_x86_64=%ABI_FLAG_X64% ^
  -DANDROID_PLATFORM=%ANDROID_API% ^
  -DANDROID_STL=c++_shared ^
  "%PROJECT_ROOT_WIN%"
if errorlevel 1 goto :fail

echo.
echo ==== deployment settings (key lines) ====
findstr /i "\"application-binary\" \"architectures\" \"android-package-source-directory\"" android_deployment_settings.json
echo.

echo ==== native build ====
cmake --build .
if errorlevel 1 goto :fail

echo.
echo ==== package APK ====
cmake --build . --target apk
if errorlevel 1 goto :fail

echo.
echo ==== APK files ====
dir /s /b *.apk

goto :eof

:fail
echo.
echo FAILED
exit /b 1
