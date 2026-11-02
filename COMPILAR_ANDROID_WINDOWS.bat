@echo off
setlocal
cd /d "%~dp0"
echo ======================================================
echo     OITOSETE FLOWTEXT - COMPILACAO ANDROID
echo ======================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\compilar_android_windows.ps1" %*
if errorlevel 1 (
  echo.
  echo [ERRO] A compilacao nao foi concluida. Leia o erro acima.
  pause
  exit /b 1
)
echo.
echo [OK] Veja o APK na pasta dist.
pause
endlocal
