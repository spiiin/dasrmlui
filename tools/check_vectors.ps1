param([string]$Runner, [string]$Script)
$ErrorActionPreference = 'Stop'
& $Runner $Script --smoke-test
if ($LASTEXITCODE -ne 0) { throw 'Vector render fixture failed' }
Add-Type -AssemblyName System.Drawing
function Assert-Pixel($bitmap, $x, $y, $red, $green, $blue) {
    $pixel = $bitmap.GetPixel($x,$y)
    if ([Math]::Abs($pixel.R-$red) -gt 3 -or [Math]::Abs($pixel.G-$green) -gt 3 -or [Math]::Abs($pixel.B-$blue) -gt 3) {
        throw "Wrong pixel at ($x,$y): $pixel; expected ($red,$green,$blue)"
    }
}
foreach ($phase in '0','half','1','loop','dpi') {
    $bitmap = [System.Drawing.Bitmap]::new((Join-Path $PWD "logs/vector_$phase.png"))
    try {
        Assert-Pixel $bitmap 30 30 0 0 0
        Assert-Pixel $bitmap 70 70 232 80 91
        Assert-Pixel $bitmap 150 30 232 80 91
        Assert-Pixel $bitmap 390 30 232 80 91
        Assert-Pixel $bitmap 310 70 30 60 120
        # Known positions at quarter/half/full animation duration; a frozen,
        # blank or wrongly clocked player cannot pass these assertions.
        $center = switch ($phase) { 'half' {120} '1' {190} default {50} }
        Assert-Pixel $bitmap $center 210 245 92 110
        foreach ($other in 50,120,190) {
            if ($other -ne $center) { Assert-Pixel $bitmap $other 210 0 0 0 }
        }
    } finally { $bitmap.Dispose() }
}
$bitmap = [System.Drawing.Bitmap]::new((Join-Path $PWD 'logs/vector_changed.png'))
try {
    Assert-Pixel $bitmap 70 70 24 170 136
    Assert-Pixel $bitmap 280 70 30 60 120
    Assert-Pixel $bitmap 340 70 0 0 0
    Assert-Pixel $bitmap 120 210 24 170 136
    Assert-Pixel $bitmap 50 210 0 0 0
} finally { $bitmap.Dispose() }
$bitmap = [System.Drawing.Bitmap]::new((Join-Path $PWD 'logs/vector_resized.png'))
try {
    Assert-Pixel $bitmap 245 70 232 80 91
    Assert-Pixel $bitmap 170 235 24 170 136
    Assert-Pixel $bitmap 70 235 0 0 0
} finally { $bitmap.Dispose() }
Write-Output 'PASS: SVG crop, decorator, tint/opacity, inline replacement, DPI, Lottie motion, loop and source replacement'
