param([string]$Runner, [string]$Script)
$output = & $Runner $Script --smoke-test 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or !$output.Contains('PASS: host destroys native elements before script Context')) {
    Write-Output $output
    throw 'Native host cleanup did not complete with a live script Context'
}
Write-Output $output
$failure = & $Runner $Script 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -or !$failure.Contains('late native destroy fault')) {
    Write-Output $failure
    throw 'Host did not report the late native destructor callback failure'
}
Write-Output 'PASS: host reports late native destructor errors'
