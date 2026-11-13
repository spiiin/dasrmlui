param(
    [string]$BuildDir='build/web',
    [string]$Emsdk=$env:EMSDK,
    [string]$SdlDir='',
    [string]$RmlDir='',
    [string]$FreeTypeSource='',
    [string[]]$CMakeArgs=@()
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$Emsdk){$Emsdk=Join-Path (Split-Path $root -Parent) 'emsdk'}
$build=if([IO.Path]::IsPathRooted($BuildDir)){$BuildDir}else{Join-Path $root $BuildDir}
$cache=Join-Path $build 'CMakeCache.txt'
function CachedPath([string]$name) {
    if(Test-Path $cache){
        $match=Select-String -LiteralPath $cache -Pattern "^${name}:[^=]+=(.+)$" | Select-Object -First 1
        if($match){return $match.Matches[0].Groups[1].Value}
    }
    return ''
}
if(!$SdlDir){$SdlDir=CachedPath 'DASSDL3_DIR'}
if(!$SdlDir){$SdlDir=Join-Path (Split-Path $root -Parent) 'dasSDL3'}
if(!$RmlDir){$RmlDir=CachedPath 'RMLUI_DIR'}
if(!$RmlDir){$RmlDir=Join-Path (Split-Path $root -Parent) 'RmlUi'}
$emcmake=Join-Path $Emsdk 'upstream/emscripten/emcmake.bat'
if(!(Test-Path $emcmake)){throw 'Emscripten SDK not found; pass -Emsdk or set EMSDK'}
$python=(Get-Command python -ErrorAction Stop).Source
& $python "$PSScriptRoot/prepare_web.py" --build $build --sdl $SdlDir --rml $RmlDir
if($LASTEXITCODE){exit $LASTEXITCODE}
$argsCmake=@('-S',"$root/web",'-B',$build,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',"-DDASSDL3_DIR=$SdlDir","-DRMLUI_DIR=$RmlDir")
if($FreeTypeSource){$argsCmake+="-DFREETYPE_SOURCE=$FreeTypeSource"}
& $emcmake cmake @argsCmake @CMakeArgs
if($LASTEXITCODE){exit $LASTEXITCODE}
& cmake --build $build --parallel 6
if($LASTEXITCODE){exit $LASTEXITCODE}
Write-Output "Ready: $build/site. Serve with python -m http.server 8766 --directory `"$build/site`""
