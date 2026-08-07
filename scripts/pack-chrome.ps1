# Build the Chrome Web Store package into dist/yasd2-<version>-chrome.zip
# Usage: pwsh -File scripts/pack-chrome.ps1
#
# Shared src/manifest.json already uses service_worker only. This script adds
# the Chromium-only `offscreen` permission required for thumbnail DOM parsing.

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

$srcManifest = Join-Path $repoRoot 'src\manifest.json'
if (-not (Test-Path $srcManifest)) {
    throw "Missing src/manifest.json at $repoRoot"
}

$version = (Get-Content $srcManifest -Raw | ConvertFrom-Json).version
if (-not $version) {
    throw 'Could not read version from src/manifest.json'
}

$distDir = Join-Path $repoRoot 'dist'
$stageDir = Join-Path $distDir 'chrome-src'
$zipPath = Join-Path $distDir "yasd2-$version-chrome.zip"

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
if (Test-Path $stageDir) {
    Remove-Item $stageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

Copy-Item -Path (Join-Path $repoRoot 'src\*') -Destination $stageDir -Recurse -Force

$manifestPath = Join-Path $stageDir 'manifest.json'
$manifest = Get-Content $manifestPath -Raw
if ($manifest -notmatch '"offscreen"') {
    $manifest = $manifest -replace '("contextMenus",\r?\n\s*)', "`$1`"offscreen`",`n    "
}
[System.IO.File]::WriteAllText($manifestPath, $manifest)

$parsed = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($parsed.background.scripts) {
    throw 'Chrome package must not include background.scripts'
}
if ($parsed.permissions -notcontains 'offscreen') {
    throw 'Chrome package missing offscreen permission'
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath

Write-Host "Chrome package: $zipPath"
Write-Host "Unpacked staging (for local load): $stageDir"
