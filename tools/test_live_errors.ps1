param([string]$Runner,[string]$Root)
$ErrorActionPreference='Stop'
$env:SDL_VIDEODRIVER='dummy'
foreach($name in @('shutdown','paint')) {
    $file=Join-Path $Root "tests/live_error_$name.das"
    $output= & $Runner $file --watch --smoke-test --frames 5 2>&1 | Out-String
    $code=$LASTEXITCODE
    if($code -ne 3 -or !$output.Contains("EXPECTED $name error")) { Write-Output $output; throw "Expected diagnosed exit 3 for $name, got $code" }
}
Write-Output 'PASS: LiveHost shutdown and native paint failures report nonzero exits without crashing'
