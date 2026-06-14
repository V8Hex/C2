@echo off
echo ============================================
echo  PhotoVault - Push to GitHub ^& Build IPA
echo ============================================
echo.

REM Initialize git repo
cd /d "%~dp0"
git init
git add -A
git commit -m "PhotoVault initial commit"

echo.
echo ============================================
echo  NEXT STEPS:
echo ============================================
echo.
echo  1. Create a PRIVATE repo on GitHub:
echo     https://github.com/new
echo     Name it: photovault (set to PRIVATE!)
echo.
echo  2. Run these commands:
echo     git remote add origin https://github.com/YOUR_USERNAME/photovault.git
echo     git branch -M main
echo     git push -u origin main
echo.
echo  3. Go to your repo ^> Actions tab
echo     The build will start automatically
echo     Wait ~5 minutes for it to finish
echo.
echo  4. Download the IPA:
echo     Actions ^> Latest run ^> Artifacts ^> PhotoVault-unsigned
echo.
echo  5. Sideload the IPA:
echo     - AltStore (needs AltServer on PC)
echo     - TrollStore (if device supports it)
echo     - Sideloadly
echo.
echo ============================================
pause
