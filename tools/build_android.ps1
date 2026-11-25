[CmdletBinding()]
param(
    [string]$DasSDL3 = "$PSScriptRoot/../../dasSDL3",
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$JavaHome = $env:JAVA_HOME,
    [string[]]$CMakeArgs = @(),
    [switch]$Run,
    [string]$Serial,
    [ValidatePattern('^[a-z][a-z0-9_]*$')] [string]$Example = 'dashboard'
)
$ErrorActionPreference = 'Stop'
if (!$AndroidSdk) { $AndroidSdk = "$env:LOCALAPPDATA/Android/Sdk" }
if (!$JavaHome) { $JavaHome = "$env:ProgramFiles/Android/Android Studio/jbr" }
$env:ANDROID_HOME = (Resolve-Path $AndroidSdk).Path
$env:JAVA_HOME = (Resolve-Path $JavaHome).Path
$root = (Resolve-Path "$PSScriptRoot/..").Path
$binding = (Resolve-Path $DasSDL3).Path
$native = "$root/build/android"
$stage = "$root/build/android-stage"
$bin = "$env:ANDROID_HOME/cmake/3.31.6/bin"
$ndk = "$env:ANDROID_HOME/ndk/28.2.13676358"
function Invoke-Checked([string]$program, [string[]]$arguments) {
    & $program @arguments
    if ($LASTEXITCODE -ne 0) { throw "$program exited with code $LASTEXITCODE" }
}
Invoke-Checked "$bin/cmake.exe" (@('-S', "$root/android", '-B', $native, '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$bin/ninja.exe", "-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake",
    '-DANDROID_ABI=arm64-v8a', '-DANDROID_PLATFORM=android-28', '-DANDROID_STL=c++_shared',
    '-DCMAKE_BUILD_TYPE=Release', "-DDASSDL3_DIR=$binding") + $CMakeArgs)
Invoke-Checked "$bin/cmake.exe" @('--build', $native, '--target', 'main', '--parallel', '6')
Invoke-Checked "$bin/cmake.exe" @('--install', $native, '--strip', '--component', 'apk', '--prefix', $stage)
$wrapper = (Get-Content "$native/sdl-gradle-wrapper.txt" -Raw).Trim()
Invoke-Checked $wrapper @('-p', "$root/android", 'assembleDebug')
$apk = (Get-Item "$root/build/android-apk/outputs/apk/debug/dasrmlui-debug.apk").FullName
Write-Host "APK: $apk"
if ($Run) {
    $adb = "$env:ANDROID_HOME/platform-tools/adb.exe"
    $device = if ($Serial) { @('-s', $Serial) } else { @() }
    Invoke-Checked $adb ($device + @('install', '-r', $apk))
    Invoke-Checked $adb ($device + @('shell', 'am', 'force-stop', 'org.dasrmlui.demo'))
    Invoke-Checked $adb ($device + @('shell', 'am', 'start', '-W', '-n', 'org.dasrmlui.demo/.DemoActivity', '--es', 'example', $Example))
}
