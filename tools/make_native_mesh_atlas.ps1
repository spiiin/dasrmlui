$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$bitmap = [System.Drawing.Bitmap]::new(64,32)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$orange = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(240,120,40))
$cyan = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(40,200,220))
$ink = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(18,28,44))
try {
    $graphics.FillRectangle($orange,0,0,32,32)
    $graphics.FillRectangle($cyan,32,0,32,32)
    $graphics.FillPolygon($ink,[System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(18,6),[System.Drawing.Point]::new(10,18),
        [System.Drawing.Point]::new(16,18),[System.Drawing.Point]::new(14,26),
        [System.Drawing.Point]::new(23,13),[System.Drawing.Point]::new(17,13)))
    $graphics.FillEllipse($ink,40,8,16,16)
    $graphics.FillEllipse($cyan,44,12,8,8)
    $bitmap.Save((Join-Path $PSScriptRoot '../examples/assets/native_mesh_atlas.png'),[System.Drawing.Imaging.ImageFormat]::Png)
} finally { $graphics.Dispose(); $bitmap.Dispose(); $orange.Dispose(); $cyan.Dispose(); $ink.Dispose() }
