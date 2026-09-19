@echo off
rem ============================================================================
rem  myhome sdk/device  ->  Jieli SDK  one-key deploy (framework + build lists)
rem
rem  usage:
rem    deploy_to_sdk.bat C:\work\jl\jl380n_demo\SDK
rem    deploy_to_sdk.bat C:\work\jl\<other-jieli-ic>_demo\SDK
rem
rem  re-run this after every change to this project's framework/ code,
rem  otherwise the SDK still builds the old copy.
rem ============================================================================
setlocal

if "%~1"=="" (
    echo [ERROR] missing SDK root. usage: deploy_to_sdk.bat C:\work\jl\jl380n_demo\SDK
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_to_sdk.ps1" -SdkRoot "%~1"
if errorlevel 1 (
    echo [ERROR] deploy failed.
    pause
    exit /b 1
)
endlocal
