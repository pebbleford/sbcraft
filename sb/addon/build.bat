@echo off
rem Builds SBCraft.addon64 (the ReShade add-on) with MSVC into build\. Run scripts\fetch_deps.sh first (headers).
rem Uses the newest Visual Studio with the C++ x64 tools; set VCVARS to another vcvars64.bat to pick one.
setlocal
set HERE=%~dp0
set RESHADE_INC=%HERE%..\..\third_party\reshade\include
if not exist "%RESHADE_INC%\reshade.hpp" echo third_party is missing: run scripts\fetch_deps.sh first& exit /b 1
if defined VCVARS goto havevc
rem No parentheses block here: the ")" in "Program Files (x86)" would end it. Git Bash also drops variables with
rem parentheses in their names, so ProgramFiles(x86) can be missing.
set "PF86=%ProgramFiles(x86)%"
if "%PF86%"=="" set "PF86=C:\Program Files (x86)"
pushd "%PF86%\Microsoft Visual Studio\Installer"
for /f "usebackq delims=" %%i in (`.\vswhere.exe -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VCVARS=%%i\VC\Auxiliary\Build\vcvars64.bat"
popd
:havevc
if not exist "%VCVARS%" echo No Visual Studio with the C++ x64 tools was found: install "Desktop development with C++" or set VCVARS& exit /b 1
call "%VCVARS%" >nul || exit /b 1
if not exist "%HERE%build" mkdir "%HERE%build"
cl /nologo /LD /O2 /EHsc /std:c++20 /MT /W3 /DWIN32_LEAN_AND_MEAN /DNOMINMAX /D_CRT_SECURE_NO_WARNINGS ^
  /I "%RESHADE_INC%" ^
  "%HERE%src\main.cpp" "%HERE%src\host.cpp" "%HERE%src\compositor.cpp" "%HERE%src\ws.cpp" ^
  /Fo"%HERE%build\\" /Fe"%HERE%build\SBCraft.addon64" ^
  /link ws2_32.lib user32.lib || exit /b 1
echo built %HERE%build\SBCraft.addon64
