@echo off
setlocal
set "VER=1.1.0"
title EMYDPI v%VER% - Discord + Roblox
cd /d "%~dp0"

:: --- Yonetici yetkisi (hosts ve zamanlanmis gorev icin gerekli) ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Yonetici izni isteniyor...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "PS=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0emydpi.ps1""

:menu
cls
echo ==================================================
echo          EMYDPI v%VER% - Discord + Roblox
echo   Sadece secilen servislerin trafigini DPI'dan
echo   gecirir. Diger site ve DNS ayarlarina dokunmaz.
echo   github.com/yigitislamoglu/EMYDPI
echo ==================================================
echo.
%PS% -Action status
echo.
echo   [1] Kur / Onar      (ilk kurulumda Discord + Roblox)
echo   [2] Tamamen kaldir
echo   [3] Proxy'yi baslat (Discord'u da yeniden baslatir)
echo   [4] Proxy'yi durdur
echo   [5] Log goster
echo   [6] Yedek mod ile kur (1 calismazsa dene)
echo   [7] Servis sec      (Discord / Roblox / ikisi)
echo   [0] Cikis
echo.
set "secim="
set /p "secim=Seciminiz: "

if "%secim%"=="1" ( %PS% -Action install   & pause & goto menu )
if "%secim%"=="2" ( %PS% -Action uninstall & pause & goto menu )
if "%secim%"=="3" ( %PS% -Action start     & pause & goto menu )
if "%secim%"=="4" ( %PS% -Action stop      & pause & goto menu )
if "%secim%"=="5" ( %PS% -Action log       & pause & goto menu )
if "%secim%"=="6" ( %PS% -Action install -Mode frag & pause & goto menu )
if "%secim%"=="7" goto servis
if "%secim%"=="0" exit /b
goto menu

:servis
echo.
echo   Hangi servisler icin kurulsun?
echo   [1] Discord + Roblox
echo   [2] Sadece Discord
echo   [3] Sadece Roblox
echo   [0] Geri
echo.
set "sv="
set /p "sv=Seciminiz: "
if "%sv%"=="1" ( %PS% -Action install -Services "Discord,Roblox" & pause & goto menu )
if "%sv%"=="2" ( %PS% -Action install -Services "Discord"        & pause & goto menu )
if "%sv%"=="3" ( %PS% -Action install -Services "Roblox"         & pause & goto menu )
goto menu
