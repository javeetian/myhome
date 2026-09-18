@echo off
REM C SDK 一致性测试构建 (Windows / MSVC)
REM 用法: build_test.bat  (需已安装 Visual Studio 2022+)
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if errorlevel 1 call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
cd /d "%~dp0"
cl /nologo /W3 /O2 /utf-8 /Fetest_sdk.exe ^
   test\test_c_sdk.c ^
   core\protocol\crc16.c ^
   core\protocol\ble_frame.c ^
   core\codec\device_json.c ^
   core\runtime\ble_stream_decoder.c ^
   core\runtime\fragment.c ^
   core\runtime\device_runtime.c ^
   /I test\generated
if errorlevel 1 exit /b 1
".\test_sdk.exe"
