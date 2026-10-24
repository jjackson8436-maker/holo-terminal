# Saves a capture of the Connect IQ simulator window, even if other windows cover it (PrintWindow).
param([string]$Out = 'C:\Users\what\garmin\sim.png')
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class SimP {
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
}
'@
[SimP]::SetProcessDPIAware() | Out-Null
$p = Get-Process simulator | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
$r = New-Object SimP+R; [SimP]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$b = New-Object System.Drawing.Bitmap ($r.Rt - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($b)
$hdc = $g.GetHdc()
$ok = [SimP]::PrintWindow($p.MainWindowHandle, $hdc, 2)
$g.ReleaseHdc($hdc)
$b.Save($Out)
"printwindow=$ok $($b.Width)x$($b.Height) -> $Out"
