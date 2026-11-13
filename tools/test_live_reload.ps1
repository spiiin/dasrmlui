param([Parameter(Mandatory=$true)][string]$Runner,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$dir=Join-Path $Root ("build/live-watch-"+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir | Out-Null
$app=Join-Path $dir 'app.das'; $styles=Join-Path $dir 'styles.das'
$out=Join-Path $dir 'stdout.log'; $err=Join-Path $dir 'stderr.log'
$template=Get-Content -LiteralPath (Join-Path $Root 'tests/live_watch_app.das.in') -Raw
$styleTemplate=Get-Content -LiteralPath (Join-Path $Root 'tests/live_watch_styles.das.in') -Raw
function Write-App([int]$version,[bool]$reject=$false) {
    $field=if($version -eq 1){'number'}else{'total'}
    $local=if($version -eq 1){'note'}else{'text'}
    $extra=if($version -eq 1){''}else{'state("inserted",0) $(var unused:int&) {}'}
    $text=$template.Replace('#FIELD#',$field).Replace('#LOCAL_FIELD#',$local).Replace('#VERSION#',"$version").Replace('#SCHEMA#',"$version").Replace('#EXTRA_STATE#',$extra).Replace('#REJECT#',"$reject".ToLowerInvariant())
    [IO.File]::WriteAllText($app,$text)
}
function Read-Log([string]$path) {
    if(!(Test-Path -LiteralPath $path)){return ''}
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=[IO.StreamReader]::new($stream)
    try {return $reader.ReadToEnd()} finally {$reader.Dispose();$stream.Dispose()}
}
function Await([string]$marker,[string]$path=$out,[int]$offset=0) {
    $deadline=[DateTime]::UtcNow.AddSeconds(35)
    while([DateTime]::UtcNow -lt $deadline) {
        $text=Read-Log $path
        if($text.Length -ge $offset -and $text.Substring($offset).Contains($marker)){ return }
        if($process.HasExited){ throw "Runner exited $($process.ExitCode) while waiting for $marker" }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out waiting for $marker"
}
Write-App 1
[IO.File]::WriteAllText($styles,$styleTemplate.Replace('#WIDTH#','100'))
$env:SDL_VIDEODRIVER='dummy'
$process=Start-Process -FilePath $Runner -ArgumentList @('"'+$app+'"','--watch','--styles','"'+$styles+'"','--smoke-test','--frames','1800') -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
try {
    Await 'CHECK version=1 mounts=1'
    [IO.File]::WriteAllText($styles,$styleTemplate.Replace('#WIDTH#','200'))
    Await 'STYLE CHECK version=1 mounts=1'
    # An RCSS warning rejects the candidate without changing the current DOM/sheet.
    [IO.File]::WriteAllText($styles,$styleTemplate.Replace('width(px(#WIDTH#))','property("width","broken-length")'))
    Await 'invalid stylesheet; current styles kept' $err
    $health=(Read-Log $out).Length
    Await 'HEALTHY 1' $out $health
    [IO.File]::WriteAllText($styles,$styleTemplate.Replace('#WIDTH#','200'))
    Await 'styles reloaded' $out $health
    # A compiler error must not call unmount or change the generation.
    [IO.File]::WriteAllText($app,'this is intentionally invalid daScript')
    Await 'compile failed; current UI kept' $err
    $health=(Read-Log $out).Length
    Await 'HEALTHY 1' $out $health
    # Reject a LOCAL migration during the candidate first mount, after root migration.
    Write-App 2 $true
    Await 'Live state migration rejected' $err
    Await 'restored last good program' $err
    Await 'CHECK version=1 mounts=2' $out $health
    # Rename fields, insert a new local state before the old one, then migrate.
    Write-App 2
    Await 'CHECK version=2 mounts=3'
    Await 'STYLE CHECK version=2 mounts=3'
    $text=Read-Log $out
    if(([regex]::Matches($text,'window=(\d+)') | ForEach-Object {$_.Groups[1].Value} | Select-Object -Unique).Count -ne 1){ throw 'SDL window changed' }
    Write-Output 'PASS: real file watch, isolated styles, DOM/focus, compile failure, local migration rollback, root/local migration and stable named slots'
} catch {
    Write-Output (Read-Log $out)
    Write-Output (Read-Log $err)
    throw
} finally {
    if(!$process.HasExited){ Stop-Process -Id $process.Id; $process.WaitForExit() }
    $process.Dispose()
}
