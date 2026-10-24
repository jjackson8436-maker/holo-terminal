# Builds a debug face with the given theme and label setting (and your usage URL from personal.json),
# clears the simulator's saved settings, loads the face, and captures the simulator window.
param([int]$Theme = 2, [string]$Labels = 'false', [string]$Out = 'C:\Users\what\garmin\sim.png')
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$b = & (Join-Path $root 'build.ps1') -Personal -Theme $Theme -Labels $Labels
$b
if (-not ($b -match 'BUILD SUCCESSFUL')) { exit 1 }
Remove-Item "$env:TEMP\com.garmin.connectiq\GARMIN\APPS\SETTINGS\HOLOFACE.SET" -ErrorAction SilentlyContinue
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
$jdk = (Get-ChildItem 'C:\Program Files\Microsoft' -Directory -Filter 'jdk-21*' | Select-Object -First 1).FullName
$env:PATH = "$jdk\bin;$env:PATH"
if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) { Start-Process "$sdk\bin\simulator.exe"; Start-Sleep 6 }
Start-Process -FilePath "$sdk\bin\monkeydo.bat" -ArgumentList (Join-Path $root 'holoface\bin\HoloFace.prg'), 'venusq2' -WindowStyle Hidden
Start-Sleep 14
& (Join-Path $root 'simshot.ps1') -Out $Out
