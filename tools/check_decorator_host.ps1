param([string]$Runner, [string]$Script)
$output = & $Runner $Script --smoke-test 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or !$output.Contains('PASS: host destroys decorator data before script Context')) {
    Write-Output $output
    throw 'Decorator host cleanup did not complete with a live script Context'
}
Write-Output $output
$failure = & $Runner $Script 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -or !$failure.Contains('late decorator destroy fault')) {
    Write-Output $failure
    throw 'Host did not report the late decorator destructor callback failure'
}
Write-Output 'PASS: host reports late decorator destructor errors'
exit 0
