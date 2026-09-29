param(
    [string]$Repo = "",
    [string]$OutDir = "$PSScriptRoot\..\dist"
)

$ErrorActionPreference = "Stop"

$gh = $null
foreach ($p in @(
    "$env:ProgramFiles\GitHub CLI\gh.exe",
    "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe",
    "$env:LOCALAPPDATA\GitHub CLI\gh.exe"
)) {
    if (Test-Path $p) { $gh = $p; break }
}
if (-not $gh) { $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source }
if (-not $gh) {
    Write-Host "Install GitHub CLI: winget install GitHub.cli"
    Write-Host "Then: gh auth login"
    exit 1
}

if (-not $Repo) {
    $Repo = & $gh repo view --json nameWithOwner -q .nameWithOwner
    if (-not $Repo) { $Repo = "whowould/GoodbyeDPI-iOS" }
}

Write-Host "Triggering IPA build on GitHub (macOS runner) for $Repo"
& $gh workflow run ios.yml --repo $Repo --ref master
Start-Sleep -Seconds 6
$id = & $gh run list --repo $Repo --workflow ios.yml --limit 1 --json databaseId --jq ".[0].databaseId"
if (-not $id) {
    Write-Host "No workflow run found. Enable Actions on the repo once, then re-run."
    exit 1
}
Write-Host "Waiting for run $id ..."
& $gh run watch $id --repo $Repo --exit-status
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
& $gh run download $id --repo $Repo --name GoodbyeDPI-unsigned --dir $OutDir
Write-Host "IPA: $OutDir"
Write-Host "Install on iPhone: Sideloadly or AltStore (Windows). Resign with your Apple ID."
