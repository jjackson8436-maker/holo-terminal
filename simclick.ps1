# Raises the Connect IQ simulator and clicks a point given relative to its window, then captures it.
param([int]$X, [int]$Y, [string]$Out = 'C:\Users\what\garmin\simclick.png')
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class SimC {
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
}
'@
[SimC]::SetProcessDPIAware() | Out-Null
$h = (Get-Process simulator | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1).MainWindowHandle
if ([SimC]::GetForegroundWindow() -ne $h) {
    [SimC]::ShowWindow($h, 6) | Out-Null   # minimize
    Start-Sleep -Milliseconds 300
    [SimC]::ShowWindow($h, 9) | Out-Null   # restore, which brings it to the front
    [SimC]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 600
}
if ([SimC]::GetForegroundWindow() -ne $h) { 'simulator is not in front; not clicking'; exit 1 }
$r = New-Object SimC+R; [SimC]::GetWindowRect($h, [ref]$r) | Out-Null
[SimC]::SetCursorPos($r.L + $X, $r.T + $Y) | Out-Null
Start-Sleep -Milliseconds 150
[SimC]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); [SimC]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 700
$b = New-Object System.Drawing.Bitmap 700, 600
[System.Drawing.Graphics]::FromImage($b).CopyFromScreen($r.L, $r.T, 0, 0, $b.Size)
$b.Save($Out)
"clicked at $($r.L + $X),$($r.T + $Y)"
