# Crops the watch screen (320x360) out of a simulator capture and enlarges it 2x.
param([string[]]$Names)
Add-Type -AssemblyName System.Drawing
foreach ($n in $Names) {
    $s = [System.Drawing.Bitmap]::FromFile("C:\Users\what\garmin\$n.png")
    $c = $s.Clone((New-Object System.Drawing.Rectangle 133, 310, 320, 360), $s.PixelFormat)
    $b = New-Object System.Drawing.Bitmap 640, 720
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.InterpolationMode = 'NearestNeighbor'
    $g.DrawImage($c, 0, 0, 640, 720)
    $b.Save("C:\Users\what\garmin\$n-zoom.png")
    $s.Dispose()
}
