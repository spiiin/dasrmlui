param([ValidateSet('Release')][string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Force (Join-Path $root 'logs') | Out-Null
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = 'C:/msvs17.8/2022/Professional'
if (!(Test-Path "$vs/VC/Auxiliary/Build/vcvars64.bat")) {
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}
if (!$vs) { throw 'Visual Studio C++ tools not found' }
$vcvars = Join-Path $vs 'VC/Auxiliary/Build/vcvars64.bat'
$ninja = Join-Path $vs 'Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe'
& cmd /c "`"$vcvars`" >nul && cmake -S `"$root`" -B `"$root/build`" -G Ninja -DCMAKE_BUILD_TYPE=$Configuration -DCMAKE_MAKE_PROGRAM=`"$ninja`" && cmake --build `"$root/build`" --parallel 6"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
