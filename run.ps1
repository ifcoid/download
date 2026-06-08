# IF SLR - Automated Installer for Windows
# Usage: iex "& { $(irm -useb 'https://if.co.id/download/run.ps1') }"

$ErrorActionPreference = "Stop"

$AppName = "if-slr"
$ExeName = "if-slr-windows-amd64.exe"
$DownloadUrl = "https://if.co.id/download/backend-binaries/$ExeName"
$InstallDir = Join-Path $env:LOCALAPPDATA "IFCOID"
$ExePath = Join-Path $InstallDir $ExeName

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  IF SLR - Automated Installer" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Create installation directory
Write-Host "[1/4] Creating installation directory..." -ForegroundColor Yellow
if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "  Created: $InstallDir" -ForegroundColor Green
} else {
    Write-Host "  Directory already exists: $InstallDir" -ForegroundColor Green
}

# Step 2: Download the binary
Write-Host "[2/4] Downloading $ExeName..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ExePath -UseBasicParsing
    Write-Host "  Downloaded to: $ExePath" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to download file." -ForegroundColor Red
    Write-Host "  URL: $DownloadUrl" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}

# Step 3: Remove Mark-of-the-Web (Zone.Identifier)
Write-Host "[3/4] Removing Mark-of-the-Web (Zone.Identifier)..." -ForegroundColor Yellow
try {
    if (Test-Path "$ExePath:Zone.Identifier") {
        Remove-Item "$ExePath:Zone.Identifier" -Force
        Write-Host "  Zone.Identifier removed successfully." -ForegroundColor Green
    } else {
        Write-Host "  No Zone.Identifier found (already clean)." -ForegroundColor Green
    }
    Unblock-File -Path $ExePath
    Write-Host "  File unblocked via Unblock-File." -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Could not remove Zone.Identifier." -ForegroundColor Yellow
    Write-Host "  $_" -ForegroundColor Yellow
}

# Step 4: Run the executable
Write-Host "[4/4] Launching $ExeName..." -ForegroundColor Yellow
Write-Host ""
try {
    Start-Process -FilePath $ExePath -Wait
    Write-Host ""
    Write-Host "  Done! $AppName has been launched successfully." -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to launch executable." -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Installation complete!" -ForegroundColor Cyan
Write-Host "  Location: $ExePath" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
