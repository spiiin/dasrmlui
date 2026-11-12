param([string]$Runner, [string]$Script, [string]$Expected)
$output = & $Runner $Script --smoke-test 2>&1 | Out-String
$code = $LASTEXITCODE
if ($code -eq 0 -or !$output.Contains($Expected)) {
    Write-Output $output
    throw "Expected nonzero exit and diagnostic: $Expected; got exit $code"
}
Write-Output "PASS: expected diagnostic '$Expected'"
