param([string]$Runner, [string]$Script)
$ErrorActionPreference = 'Stop'
& $Runner $Script --smoke-test
if ($LASTEXITCODE -ne 0) { throw 'Decorator fixture failed' }
Add-Type -AssemblyName System.Drawing
function Assert-Pixel($bitmap, $x, $y, $red, $green, $blue) {
    $pixel=$bitmap.GetPixel($x,$y)
    if ([Math]::Abs($pixel.R-$red) -gt 3 -or [Math]::Abs($pixel.G-$green) -gt 3 -or [Math]::Abs($pixel.B-$blue) -gt 3) {
        throw "Wrong pixel at ($x,$y): $pixel; expected ($red,$green,$blue)"
    }
}
foreach ($backend in 'sdl','gl') {
    foreach ($phase in 'initial','cached','invalidate','changed','alpha','dpi','resized','removed','remount') {
        $bitmap=[System.Drawing.Bitmap]::new((Join-Path $PWD "logs/decorator_${backend}_$phase.png"))
        try {
            # Second element paints only its content box, using schema defaults.
            Assert-Pixel $bitmap 144 24 0 0 0
            Assert-Pixel $bitmap 190 50 40 200 100
            Assert-Pixel $bitmap 150 50 180 40 200
            Assert-Pixel $bitmap 170 84 40 100 240
            if ($phase -eq 'removed') { Assert-Pixel $bitmap 50 55 0 0 0; continue }
            $color=if ($phase -in 'initial','cached','invalidate') { @(40,200,100) } elseif ($phase -eq 'alpha') { @(120,40,30) } else { @(240,80,60) }
            Assert-Pixel $bitmap 50 55 $color[0] $color[1] $color[2]
            # Padding-box starts after the border. Parent clips the larger box.
            # Opacity is applied per draw; the half-transparent bar overlays the fill.
            if ($phase -eq 'alpha') { Assert-Pixel $bitmap 23 50 150 40 115 }
            else { Assert-Pixel $bitmap 23 50 180 40 200 }
            Assert-Pixel $bitmap 115 50 0 0 0
            Assert-Pixel $bitmap 50 95 0 0 0
            if ($phase -in 'dpi','resized','remount') { Assert-Pixel $bitmap 28 50 180 40 200 }
            if ($phase -in 'resized','remount') { Assert-Pixel $bitmap 100 50 0 0 0 }
            if ($phase -eq 'changed') { Assert-Pixel $bitmap 90 88 40 100 240 }
            if ($phase -in 'initial','cached','invalidate') { Assert-Pixel $bitmap 90 88 40 200 100 }
            # PNG used by the decorator, away from its icon and atlas boundary.
            if ($phase -eq 'alpha') { Assert-Pixel $bitmap 35 35 180 80 35 }
            else { Assert-Pixel $bitmap 35 35 240 120 40 }
        } finally { $bitmap.Dispose() }
    }
    $hover=[System.Drawing.Bitmap]::new((Join-Path $PWD "logs/decorator_${backend}_hover.png"))
    try { Assert-Pixel $hover 190 50 80 120 240; Assert-Pixel $hover 154 50 180 40 200 }
    finally { $hover.Dispose() }
}
Write-Output 'PASS: decorator pixels on SDL/GL3: defaults, parameters, texture, area, clip, opacity, DPI, resize and cache'
