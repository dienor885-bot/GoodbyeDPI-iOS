param(
    [string]$Repo = "",
    [string]$OutDir = "$PSScriptRoot\..\dist"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Install GitHub CLI: winget install GitHub.cli"
    Write-Host "Then: gh auth login"
    exit 1
}

if (-not $Repo) {
    $Repo = (gh repo view --json nameWithOwner -q .nameWithOwner)
}

Write-Host "Triggering IPA build on GitHub (macOS runner) for $Repo"
gh workflow run ios.yml --repo $Repo
Start-Sleep -Seconds 4
$id = gh run list --repo $Repo --workflow ios.yml --limit 1 --json databaseId -q ".[0].databaseId"
Write-Host "Waiting for run $id ..."
gh run watch $id --repo $Repo --exit-status
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
gh run download $id --repo $Repo --name GoodbyeDPI-unsigned --dir $OutDir
Write-Host "IPA: $OutDir"
Write-Host "Install on iPhone: Sideloadly or AltStore (Windows). Resign with your Apple ID."
