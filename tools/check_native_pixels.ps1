param([string]$Runner, [string]$Script)
$ErrorActionPreference = 'Stop'
& $Runner $Script --smoke-test
if ($LASTEXITCODE -ne 0) { throw 'Native render fixture failed' }
Add-Type -AssemblyName System.Drawing
function Assert-Pixel($bitmap, $x, $y, $red, $green, $blue) {
    $pixel=$bitmap.GetPixel($x,$y)
    if ([Math]::Abs($pixel.R-$red) -gt 3 -or [Math]::Abs($pixel.G-$green) -gt 3 -or [Math]::Abs($pixel.B-$blue) -gt 3) {
        throw "Wrong pixel at ($x,$y): $pixel; expected ($red,$green,$blue)"
    }
}
foreach ($phase in 'initial','cached','changed','alpha','dpi','resized') {
    $bitmap=[System.Drawing.Bitmap]::new((Join-Path $PWD "logs/native_$phase.png"))
    try {
        $ink=if ($phase -in 'initial','cached') { @(40,200,100) } elseif ($phase -eq 'changed') { @(240,80,60) } else { @(120,40,30) }
        Assert-Pixel $bitmap 65 55 $ink[0] $ink[1] $ink[2]
        # Vertex opacity is premultiplied per primitive. The white triangle is
        # drawn over the red rectangle, so both half-transparent draws blend.
        if ($phase -in 'alpha','dpi','resized') { Assert-Pixel $bitmap 35 35 180 140 135 }
        else { Assert-Pixel $bitmap 35 35 240 240 240 }
        Assert-Pixel $bitmap 110 60 0 0 0
        Assert-Pixel $bitmap 60 90 0 0 0
        if ($phase -eq 'resized') { Assert-Pixel $bitmap 85 55 0 0 0 }
        else { Assert-Pixel $bitmap 85 55 $ink[0] $ink[1] $ink[2] }
    } finally { $bitmap.Dispose() }
}
Write-Output 'PASS: native geometry, triangle, clip, retained mesh, attribute, opacity, DPI and resize'
