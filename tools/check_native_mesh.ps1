param([string]$Runner, [string]$Script)
$ErrorActionPreference = 'Stop'
& $Runner $Script --smoke-test
if ($LASTEXITCODE -ne 0) { throw 'Native mesh fixture failed' }
Add-Type -AssemblyName System.Drawing
function Assert-Pixel($bitmap, $x, $y, $red, $green, $blue, $tolerance=4) {
    $pixel=$bitmap.GetPixel($x,$y)
    if ([Math]::Abs($pixel.R-$red) -gt $tolerance -or [Math]::Abs($pixel.G-$green) -gt $tolerance -or [Math]::Abs($pixel.B-$blue) -gt $tolerance) {
        throw "Wrong pixel at ($x,$y): $pixel; expected ($red,$green,$blue)"
    }
}
foreach ($backend in 'sdl','gl') {
    foreach ($phase in 'initial','cached','remount','cleared') {
        $bitmap=[System.Drawing.Bitmap]::new((Join-Path $PWD "logs/mesh_${backend}_$phase.png"))
        try {
            if ($phase -eq 'cleared') { Assert-Pixel $bitmap 30 30 60 80 100; continue }
            Assert-Pixel $bitmap 23 23 240 40 20
            Assert-Pixel $bitmap 95 23 20 220 80
            Assert-Pixel $bitmap 23 75 20 40 120
            Assert-Pixel $bitmap 95 75 240 220 40
            Assert-Pixel $bitmap 30 30 255 255 255
            Assert-Pixel $bitmap 35 35 20 220 80
            Assert-Pixel $bitmap 123 23 240 120 40
            Assert-Pixel $bitmap 123 93 40 100 220
            Assert-Pixel $bitmap 30 100 156 42 42 6
            Assert-Pixel $bitmap 210 50 180 40 200
            Assert-Pixel $bitmap 225 50 0 0 0
            Assert-Pixel $bitmap 210 145 0 0 0
        } finally { $bitmap.Dispose() }
    }
}
Write-Output 'PASS: mesh pixels on SDL/GL3: UV, atlas crops, tint, premultiplied alpha, vertex colors, clip, draw order and cache'
