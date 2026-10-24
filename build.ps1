# Builds the watch face. Property defaults can be overridden for one build without touching
# the committed properties.xml: -Theme, -Labels, and -Personal (reads personal.json, which is
# gitignored and holds your own usage URL).
#   build.ps1                       debug .prg for the simulator
#   build.ps1 -Release -Personal    release .prg for your own watch
param(
    [string]$Device = 'venusq2',
    [int]$Theme = -1,
    [string]$Labels = '',
    [switch]$Personal,
    [switch]$Release,
    [string]$Out = ''
)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Join-Path $root 'holoface'
$propsFile = Join-Path $proj 'resources\properties\properties.xml'
$orig = [IO.File]::ReadAllText($propsFile)
$props = $orig
if ($Personal) {
    $pj = Get-Content (Join-Path $root 'personal.json') -Raw | ConvertFrom-Json
    if ($pj.usageUrl) { $props = $props -replace '(<property id="usageUrl" type="string">)[^<]*(</property>)', "`${1}$($pj.usageUrl)`${2}" }
    if ($null -ne $pj.theme -and $Theme -lt 0) { $Theme = [int]$pj.theme }
    if ($null -ne $pj.labels -and $Labels -eq '') { $Labels = "$($pj.labels)".ToLower() }
}
if ($Theme -ge 0) { $props = $props -replace '(<property id="theme" type="number">)\d+(</property>)', "`${1}$Theme`${2}" }
if ($Labels -ne '') { $props = $props -replace '(<property id="labels" type="boolean">)\w+(</property>)', "`${1}$Labels`${2}" }

$jdk = (Get-ChildItem 'C:\Program Files\Microsoft' -Directory -Filter 'jdk-21*' | Select-Object -First 1).FullName
$env:PATH = "$jdk\bin;$env:PATH"
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
if ($Out -eq '') { $Out = Join-Path $proj 'bin\HoloFace.prg' }
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$mc = @('-f', (Join-Path $proj 'monkey.jungle'), '-d', $Device, '-o', $Out, '-y', (Join-Path $root 'developer_key.der'), '-w', '-l', '2')
if ($Release) { $mc += '-r' }
try {
    [IO.File]::WriteAllText($propsFile, $props)
    & "$sdk\bin\monkeyc.bat" @mc 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match 'BUILD|ERROR' }
    "exit $LASTEXITCODE"
} finally {
    [IO.File]::WriteAllText($propsFile, $orig)
}
