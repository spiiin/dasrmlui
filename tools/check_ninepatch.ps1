param([string]$Runner, [string]$Script)
$ErrorActionPreference = 'Stop'
& $Runner $Script --smoke-test
if ($LASTEXITCODE -ne 0) { throw 'Ninepatch render fixture failed' }
Add-Type -AssemblyName System.Drawing
function Assert-Pixel($bitmap, $x, $y, $red, $green, $blue) {
    $pixel = $bitmap.GetPixel($x,$y)
    if ([Math]::Abs($pixel.R-$red) -gt 2 -or [Math]::Abs($pixel.G-$green) -gt 2 -or [Math]::Abs($pixel.B-$blue) -gt 2) {
        throw "Wrong pixel at ($x,$y): $pixel; expected ($red,$green,$blue)"
    }
}
foreach ($scale in 1,2) {
    $bitmap = [System.Drawing.Bitmap]::new((Join-Path $PWD "logs/ninepatch_$scale.png"))
    try {
        $inset = if ($scale -eq 1) { 6 } else { 13 }
        foreach ($rect in @(@(20,20,120,80),@(200,20,240,160))) {
            $x,$y,$width,$height = $rect
            # Same corner inlays on differently sized panels, at both densities.
            Assert-Pixel $bitmap ($x+$inset) ($y+$inset) 250 227 167
            Assert-Pixel $bitmap ($x+$width-$inset-1) ($y+$inset) 250 227 167
            Assert-Pixel $bitmap ($x+$width-$inset-1) ($y+$height-$inset-1) 250 227 167
            Assert-Pixel $bitmap ($x+$inset) ($y+$height-$inset-1) 250 227 167
            Assert-Pixel $bitmap ($x+$width/2) ($y+$height/2) 25 52 68
        }
    } finally { $bitmap.Dispose() }
}
$bitmap = [System.Drawing.Bitmap]::new((Join-Path $PWD 'logs/ninepatch_paper.png'))
try { Assert-Pixel $bitmap 80 60 255 243 213; Assert-Pixel $bitmap 320 100 255 243 213 }
finally { $bitmap.Dispose() }
Write-Output 'PASS: ninepatch corners do not stretch, follow dp ratio, and change atlas region with theme'
