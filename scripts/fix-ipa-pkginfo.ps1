param(
    [string]$Ipa = "$PSScriptRoot\..\dist\GoodbyeDPI-unsigned.ipa"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Ipa)) { throw "IPA not found: $Ipa" }

$work = Join-Path $env:TEMP ("gdpi-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item $Ipa (Join-Path $work "in.zip")
Expand-Archive -LiteralPath (Join-Path $work "in.zip") -DestinationPath (Join-Path $work "unpacked") -Force
$app = Get-ChildItem -Path (Join-Path $work "unpacked\Payload") -Filter "*.app" -Directory | Select-Object -First 1
if (-not $app) { throw "No .app in Payload" }

[System.IO.File]::WriteAllBytes((Join-Path $app.FullName "PkgInfo"), [Text.Encoding]::ASCII.GetBytes("APPL????"))
$appex = Get-ChildItem -Path $app.FullName -Filter "*.appex" -Directory -Recurse | Select-Object -First 1
if ($appex) {
    [System.IO.File]::WriteAllBytes((Join-Path $appex.FullName "PkgInfo"), [Text.Encoding]::ASCII.GetBytes("XPC!!!!!"))
}

$outZip = Join-Path $work "out.zip"
if (Test-Path $outZip) { Remove-Item $outZip }
Push-Location (Join-Path $work "unpacked")
Compress-Archive -Path "Payload" -DestinationPath $outZip -Force
Pop-Location
$outIpa = [IO.Path]::ChangeExtension($Ipa, $null) + "-fixed.ipa"
Copy-Item $outZip $outIpa -Force
Write-Host "Fixed IPA: $outIpa"
Write-Host "Sideloadly: Apple ID sideload this file. Do not use Normal Install unless you have a paid P12."
