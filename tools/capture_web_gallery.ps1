param([string]$Runner="",[string]$Root=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
if(!$Runner){$Runner=Join-Path $Root 'build/bin/dasrmlui.exe'}
$destination=Join-Path $Root 'web/assets/screenshots'
New-Item -ItemType Directory -Force $destination | Out-Null
$oldVideoDriver=$env:SDL_VIDEODRIVER
$env:SDL_VIDEODRIVER='windows'
$manifest=Get-Content (Join-Path $Root 'web/examples.json') -Raw | ConvertFrom-Json
Push-Location $Root
try {
    foreach($demo in $manifest) {
        if($demo.id -eq 'live_lab'){continue}
        & $Runner "examples/$($demo.id).das" --smoke-test *> "logs/gallery-$($demo.id).log"
        if($LASTEXITCODE){throw "Failed to capture $($demo.id); see logs/gallery-$($demo.id).log"}
        Copy-Item -LiteralPath "logs/$($demo.id).png" -Destination (Join-Path $destination "$($demo.id).png")
        Write-Output "Captured $($demo.id)"
    }
    $source=Get-Content 'examples/live_lab.das' -Raw
    $source=$source.Replace('def update() { ui_frame(app) $(var model:Desk) { studio(model) } }',
        'def update() { ui_frame(app) $(var model:Desk) { studio(model) }; rui_render(); verify(rui_screenshot("logs/gallery-live_lab.png")) }')
    $fixture=Join-Path $Root 'build/web/gallery-live_lab.das'
    New-Item -ItemType Directory -Force (Split-Path $fixture -Parent) | Out-Null
    [IO.File]::WriteAllText($fixture,$source)
    & $Runner $fixture --watch --styles examples/live_lab_styles.das --frames 3 *> logs/gallery-live_lab.log
    if($LASTEXITCODE){throw 'Failed to capture Live workbench'}
    Copy-Item -LiteralPath 'logs/gallery-live_lab.png' -Destination (Join-Path $destination 'live_lab.png')
} finally {Pop-Location; $env:SDL_VIDEODRIVER=$oldVideoDriver}
