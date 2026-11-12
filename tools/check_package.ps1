# Installs the runtime component into a scratch folder under <Build> and proves it
# stands on its own: every runtime folder must be found beside the executable, and
# an example must run with the package as the working directory. The folder is
# named after this process, so two test runs at once do not share it.
param([string]$Build, [string]$Config = '')
$ErrorActionPreference = 'Stop'
$package = Join-Path $Build "package-check-$PID"
try {
    $install = @('--install', $Build, '--component', 'runtime', '--prefix', $package)
    if ($Config) { $install += @('--config', $Config) }
    $log = & cmake @install 2>&1 | Out-String
    if ($LASTEXITCODE) { Write-Output $log; throw "cmake --install failed with exit code $LASTEXITCODE" }

    $exe = Get-ChildItem (Join-Path $package 'bin') -Filter 'dasrmlui*' | Select-Object -First 1
    if (!$exe) { throw 'The package has no dasrmlui binary in bin/' }
    Remove-Item Env:DASRMLUI_HOME -ErrorAction SilentlyContinue
    $roots = (& $exe.FullName --roots | Out-String).Trim() -split "`r?`n"
    if ($LASTEXITCODE) { Write-Output $roots; throw "--roots reported a missing runtime folder (exit $LASTEXITCODE)" }
    if ($roots.Count -ne 5) { Write-Output $roots; throw "Expected five runtime locations, got $($roots.Count)" }
    foreach ($line in $roots) {
        if (!$line.EndsWith('(beside the executable)')) {
            Write-Output $roots
            throw "Not taken from the package: $line"
        }
    }

    New-Item -ItemType Directory -Force (Join-Path $package 'logs') | Out-Null
    Push-Location $package
    try {
        $env:SDL_VIDEODRIVER = 'dummy'
        $output = & $exe.FullName 'examples/dashboard.das' --smoke-test 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    if ($code) { Write-Output $output; throw "The packaged example exited with code $code" }
    Write-Output "PASS: the package runs on its own"
    Write-Output $roots
} finally {
    if (Test-Path $package) { Remove-Item -Recurse -Force $package -ErrorAction SilentlyContinue }
}
