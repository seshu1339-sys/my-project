# Run AFTER the normal `flutter build web` (never a second Flutter compile).
# Produces build/admin_web: a byte-identical copy of build/web (same
# compiled Dart/JS app, same hidden-route OTP gate) with only the static
# index.html/manifest.json/icon files from web_admin_overlay/ laid on top,
# so the `admin` Firebase Hosting target can serve a distinct PWA identity
# ("Locamarket Control") without touching the customer app's build/web at
# all. See web_admin_overlay/README.md for what's still a placeholder.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$source = Join-Path $repoRoot 'build/web'
$overlay = Join-Path $repoRoot 'web_admin_overlay'
$dest = Join-Path $repoRoot 'build/admin_web'

if (-not (Test-Path $source)) { throw "build/web not found. Run 'flutter build web' first." }
if (-not (Test-Path $overlay)) { throw "web_admin_overlay directory not found." }

if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Copy-Item $source $dest -Recurse

Get-ChildItem $overlay -Recurse -File | Where-Object { $_.Name -ne 'README.md' } | ForEach-Object {
  $relative = $_.FullName.Substring($overlay.Length + 1)
  $target = Join-Path $dest $relative
  $targetDir = Split-Path $target -Parent
  if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
  Copy-Item $_.FullName $target -Force
}

Write-Host "Built build/admin_web (admin PWA overlay applied on top of build/web)."
