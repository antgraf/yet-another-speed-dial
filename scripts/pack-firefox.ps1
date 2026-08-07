# Build the Firefox (AMO) package into dist/yasd2-<version>-firefox.zip
# Usage: pwsh -File scripts/pack-firefox.ps1
#
# Shared src/manifest.json is Chrome-first (service_worker only). This script:
# - replaces background.service_worker with background.scripts for Firefox
# - omits Chrome-only js/chromeOffscreen.js

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
$stageDir = Join-Path $distDir 'firefox-src'
$zipPath = Join-Path $distDir "yasd2-$version-firefox.zip"

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
if (Test-Path $stageDir) {
    Remove-Item $stageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

Copy-Item -Path (Join-Path $repoRoot 'src\*') -Destination $stageDir -Recurse -Force

$chromeOffscreen = Join-Path $stageDir 'js\chromeOffscreen.js'
if (Test-Path $chromeOffscreen) {
    Remove-Item $chromeOffscreen -Force
}

$manifestPath = Join-Path $stageDir 'manifest.json'
$manifest = Get-Content $manifestPath -Raw
$firefoxBackground = @'
  "background": {
    "scripts": [
      "js/hostPermissions.js",
      "background.js",
      "offscreen.js"
    ]
  },
'@
$manifest = $manifest -replace '(?ms)\s*"background":\s*\{[^}]*\},', "`n$firefoxBackground"
[System.IO.File]::WriteAllText($manifestPath, $manifest)

# Validate JSON and expected background.scripts
$parsed = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($parsed.background.service_worker) {
    throw 'Firefox package still has background.service_worker'
}
if (-not $parsed.background.scripts) {
    throw 'Firefox package missing background.scripts'
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath

Write-Host "Firefox package: $zipPath"
