param([string]$Runner, [string]$Script)
$ErrorActionPreference = 'Stop'
& $Runner $Script --smoke-test
if ($LASTEXITCODE -ne 0) { throw 'GPU effects fixture failed' }
Add-Type -AssemblyName System.Drawing
function Assert-Pixel($bitmap, $x, $y, $red, $green, $blue) {
    $pixel=$bitmap.GetPixel($x,$y)
    if ([Math]::Abs($pixel.R-$red) -gt 3 -or [Math]::Abs($pixel.G-$green) -gt 3 -or [Math]::Abs($pixel.B-$blue) -gt 3) {
        throw "Wrong pixel at ($x,$y): $pixel; expected ($red,$green,$blue)"
    }
}
foreach ($fixture in 'gpu_raw','gpu') {
$clockStart=0
foreach ($phase in 'initial','time','alpha','dpi','removed','remount') {
    $bitmap=[System.Drawing.Bitmap]::new((Join-Path $PWD "logs/${fixture}_$phase.png"))
    try {
        Assert-Pixel $bitmap 550 50 40 200 100 # Ordinary geometry after custom GL programs.
        if ($phase -eq 'removed') {
            foreach ($x in 50,150,250,350,450) { Assert-Pixel $bitmap $x 50 0 0 0 }
            Assert-Pixel $bitmap 250 140 0 0 0
            continue
        }
        $changed=$phase -in 'alpha','dpi','remount'
        if ($changed) { Assert-Pixel $bitmap 50 50 10 50 25 } # Straight alpha -> premultiplied, with element opacity.
        else { Assert-Pixel $bitmap 50 50 40 200 100 }
        Assert-Pixel $bitmap 20 20 0 0 0 # Rounded shader mesh.
        Assert-Pixel $bitmap 150 50 100 200 40
        Assert-Pixel $bitmap 250 50 $(if ($changed) {25} else {50}) 200 40
        Assert-Pixel $bitmap 350 50 100 200 20 # Reverse filter order gives a different color.
        Assert-Pixel $bitmap 450 50 100 200 40 # Backdrop only inside its element.
        Assert-Pixel $bitmap 425 50 40 200 100
        Assert-Pixel $bitmap 350 140 50 100 20 # Built-in filter after a custom pass.
        Assert-Pixel $bitmap 550 140 50 100 20 # Unpremultiply source / premultiply output, with alpha uniform.
        Assert-Pixel $bitmap 423 140 0 0 0
        Assert-Pixel $bitmap 430 140 40 200 100
        Assert-Pixel $bitmap 502 140 40 200 100 # Offset sampling writes into extended ink overflow.
        Assert-Pixel $bitmap 505 140 0 0 0
        Assert-Pixel $bitmap 135 140 255 0 0 # 25% length stays 20 px across DPI changes.
        Assert-Pixel $bitmap 145 140 0 255 0
        if ($phase -in 'dpi','remount') { Assert-Pixel $bitmap 25 140 255 0 0 }
        else { Assert-Pixel $bitmap 25 140 0 255 0 }
        Assert-Pixel $bitmap 25 240 0 0 0
        Assert-Pixel $bitmap 40 240 40 200 100 # Transform respects parent clipping.
        Assert-Pixel $bitmap 75 240 0 0 0
        $clock=$bitmap.GetPixel(250,140).R
        if ($phase -eq 'initial') { $clockStart=$clock }
        elseif ([Math]::Abs($clock-$clockStart) -lt 50) { throw 'u_time did not animate independently of component updates' }
    } finally { $bitmap.Dispose() }
}
}
Write-Output 'PASS: shader/filter pixels, ordered chains, backdrop, alpha, native pass, overflow, transform, clipping, DPI, time and remount'
$template=[System.Drawing.Bitmap]::new((Join-Path $PWD 'logs/gpu_template.png'))
try { Assert-Pixel $template 650 45 40 200 100 } finally { $template.Dispose() }
