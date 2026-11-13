# The configuration must be able to link the dasSDL3 build CMake is pointed at:
# Release, RelWithDebInfo and MinSizeRel go with a non-debug one, Debug only with
# a Debug one. CMake reports a mismatch at configure time. Use a separate
# -BuildDir for each configuration to keep them side by side.
#
# Visual Studio is chosen in this order: -VisualStudio, the installation that
# configured -BuildDir earlier, the DASRMLUI_VS environment variable, the latest
# installation with the C++ tools. It must be the toolchain dasSDL3 was built with.
#
# -CMakeArgs passes extra arguments to the configure step, for example
#   ./tools/build.ps1 -CMakeArgs '-DDASSDL3_DIR=D:/work/dasSDL3','-DRMLUI_DIR=D:/work/RmlUi'
param(
    [ValidateSet('Release', 'RelWithDebInfo', 'MinSizeRel', 'Debug')][string]$Configuration = 'Release',
    [string]$BuildDir = 'build',
    [string]$VisualStudio = '',
    [string[]]$CMakeArgs = @()
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = if ([System.IO.Path]::IsPathRooted($BuildDir)) { $BuildDir } else { Join-Path $root $BuildDir }
New-Item -ItemType Directory -Force (Join-Path $root 'logs') | Out-Null
$vs = $VisualStudio
$cache = Join-Path $build 'CMakeCache.txt'
if (!$vs -and (Test-Path $cache)) {
    $compiler = Select-String -Path $cache -Pattern '^CMAKE_CXX_COMPILER:[A-Z]+=(.+)/VC/Tools/MSVC/' | Select-Object -First 1
    if ($compiler) { $vs = $compiler.Matches[0].Groups[1].Value }
}
if (!$vs) { $vs = $env:DASRMLUI_VS }
if (!$vs) {
    $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
    if (Test-Path $vswhere) {
        $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    }
}
if (!$vs -or !(Test-Path "$vs/VC/Auxiliary/Build/vcvars64.bat")) { throw "Visual Studio C++ tools not found (looked in '$vs')" }
$vcvars = Join-Path $vs 'VC/Auxiliary/Build/vcvars64.bat'
$ninja = Join-Path $vs 'Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe'
$extra = ($CMakeArgs | ForEach-Object { "`"$_`"" }) -join ' '
& cmd /c "`"$vcvars`" >nul && cmake -S `"$root`" -B `"$build`" -G Ninja -DCMAKE_BUILD_TYPE=$Configuration -DCMAKE_MAKE_PROGRAM=`"$ninja`" $extra && cmake --build `"$build`" --parallel 6"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
