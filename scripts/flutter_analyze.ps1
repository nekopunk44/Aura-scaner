$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scannerRoot = Join-Path $repoRoot 'scanner_ap'
$tmpRoot = Join-Path $repoRoot '.tmp'
$appDataPath = Join-Path $tmpRoot 'appdata'
$localAppDataPath = Join-Path $tmpRoot 'localappdata'
$dartToolPath = Join-Path $appDataPath '.dart-tool'
$dartServerPath = Join-Path $localAppDataPath '.dartServer'
$dartExe = 'C:\Users\Admin\flutter\bin\cache\dart-sdk\bin\dart.exe'

New-Item -ItemType Directory -Force -Path $appDataPath, $localAppDataPath, $dartToolPath, $dartServerPath | Out-Null

$env:APPDATA = $appDataPath
$env:LOCALAPPDATA = $localAppDataPath

& $dartExe analyze (Join-Path $scannerRoot 'lib')
