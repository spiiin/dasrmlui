param([string]$Runner,[string]$Root)
$ErrorActionPreference='Stop'
$env:SDL_VIDEODRIVER='dummy'
foreach($name in @('shutdown','paint')) {
    $file=Join-Path $Root "tests/live_error_$name.das"
    # Windows PowerShell 5.1 turns a native command's stderr into error records;
    # under 'Stop' the first expected diagnostic line would end the script.
    $ErrorActionPreference='Continue'
    $output= & $Runner $file --watch --smoke-test --frames 5 2>&1 | Out-String
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if($code -ne 3 -or !$output.Contains("EXPECTED $name error")) { Write-Output $output; throw "Expected diagnosed exit 3 for $name, got $code" }
}
Write-Output 'PASS: LiveHost shutdown and native paint failures report nonzero exits without crashing'
