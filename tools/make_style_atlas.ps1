# Deterministic geometric source art for the ninepatch demo. No external assets.
param([string]$Output = "$PSScriptRoot/../examples/assets/style_atlas.png")
Add-Type -AssemblyName System.Drawing
$bitmap = [System.Drawing.Bitmap]::new(192,96)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
function Fill-Rectangle($color, $x, $y, $width, $height) {
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($color))
    try { $graphics.FillRectangle($brush,$x,$y,$width,$height) } finally { $brush.Dispose() }
}
try {
    foreach ($variant in 0,1) {
        $offset = $variant * 96
        $outer = if ($variant -eq 0) { '#516f80' } else { '#a98950' }
        $edge = if ($variant -eq 0) { '#94b8c4' } else { '#e6ca8b' }
        $inner = if ($variant -eq 0) { '#193444' } else { '#fff3d5' }
        Fill-Rectangle $outer $offset 0 96 96
        Fill-Rectangle $edge ($offset+2) 2 92 92
        Fill-Rectangle $outer ($offset+5) 5 86 86
        Fill-Rectangle $inner ($offset+8) 8 80 80
        # Corner inlays lie outside the 24px inner rectangle, so do not stretch.
        foreach ($x in 10,78) { foreach ($y in 10,78) {
            Fill-Rectangle '#dcb566' ($offset+$x) $y 8 8
            Fill-Rectangle '#fae3a7' ($offset+$x+2) ($y+2) 4 4
        } }
    }
    $bitmap.Save([System.IO.Path]::GetFullPath($Output),[System.Drawing.Imaging.ImageFormat]::Png)
} finally { $graphics.Dispose(); $bitmap.Dispose() }
