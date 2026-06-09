# IF SLR - Enhanced Automated Installer for Windows
# Usage: iex "& { $(irm -useb 'https://if.co.id/download/run.ps1') }"

# ============================================================
# Admin Elevation Check
# ============================================================
# This script requires Administrator privileges to add Windows Defender exclusions.
# If not running as Admin, re-launch with elevated privileges.
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    $scriptUrl = "https://if.co.id/download/run.ps1"
    $tempScript = Join-Path $env:TEMP "if-slr-install.ps1"
    Invoke-WebRequest -Uri $scriptUrl -OutFile $tempScript -UseBasicParsing
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`""
    exit
}

$ErrorActionPreference = "Stop"

$AppName = "if-slr"
$ExeName = "if-slr.exe"
$RemoteName = "if-slr-windows-amd64.exe"
$DownloadUrl = "https://if.co.id/download/backend-binaries/$RemoteName"
$InstallDir = Join-Path $env:LOCALAPPDATA "IFCOID"
$ExePath = Join-Path $InstallDir $ExeName
$DefaultPort = 50607

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  IF SLR - Enhanced Automated Installer" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Step 1: Check/Install cloudflared
# ============================================================
Write-Host "[1/12] Checking cloudflared installation..." -ForegroundColor Yellow

$cloudflaredInstalled = $false
try {
    $cfVer = & cloudflared --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  cloudflared already installed: $cfVer" -ForegroundColor Green
        $cloudflaredInstalled = $true
    }
} catch {
    $cloudflaredInstalled = $false
}

if (-not $cloudflaredInstalled) {
    Write-Host "  cloudflared not found. Attempting installation..." -ForegroundColor Yellow

    # Try winget first
    $wingetAvailable = $false
    try {
        $wgVer = & winget --version 2>&1
        if ($LASTEXITCODE -eq 0) { $wingetAvailable = $true }
    } catch {}

    if ($wingetAvailable) {
        Write-Host "  Installing via winget..." -ForegroundColor Yellow
        try {
            & winget install --id Cloudflare.cloudflared --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            $cfCheck = & cloudflared --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  cloudflared installed via winget successfully." -ForegroundColor Green
                $cloudflaredInstalled = $true
            }
        } catch {
            Write-Host "  winget installation failed. Trying direct download..." -ForegroundColor Yellow
        }
    }

    # Fallback: direct download from GitHub
    if (-not $cloudflaredInstalled) {
        Write-Host "  Downloading cloudflared from GitHub..." -ForegroundColor Yellow
        $cfUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
        $cfPath = Join-Path $InstallDir "cloudflared.exe"

        # Ensure install dir exists for cloudflared
        if (!(Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }

        try {
            Invoke-WebRequest -Uri $cfUrl -OutFile $cfPath -UseBasicParsing
            Write-Host "  cloudflared downloaded to: $cfPath" -ForegroundColor Green
            $cloudflaredInstalled = $true
            # We'll use the full path later
        } catch {
            Write-Host "  WARNING: Failed to download cloudflared." -ForegroundColor Red
            Write-Host "  Tunnel feature will not be available." -ForegroundColor Red
            Write-Host "  You can install it manually from: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/" -ForegroundColor Yellow
        }
    }
}

# Determine cloudflared executable path
$cloudflaredExe = "cloudflared"
$cfLocalPath = Join-Path $InstallDir "cloudflared.exe"
if (Test-Path $cfLocalPath) {
    $cloudflaredExe = $cfLocalPath
}

# ============================================================
# Step 2: Check/Configure Environment Variables
# ============================================================
Write-Host ""
Write-Host "[2/12] Checking environment variables..." -ForegroundColor Yellow
Write-Host ""

$envVars = @(
    @{ Name = "MONGO_URI";            Description = "MongoDB connection URI";                      Default = "mongodb://localhost:27017";  Group = "Database (MongoDB)" },
    @{ Name = "DB_NAME";              Description = "Database name";                               Default = "slr_agentic_db";             Group = "Database (MongoDB)" },
    @{ Name = "NEO4JURI";             Description = "Neo4j/AuraDB connection URI";                 Default = "";                           Group = "Knowledge Graph (Neo4j)" },
    @{ Name = "NEO4JUSER";            Description = "Neo4j username";                              Default = "";                           Group = "Knowledge Graph (Neo4j)" },
    @{ Name = "NEO4JPASSWORD";        Description = "Neo4j password";                              Default = "";                           Group = "Knowledge Graph (Neo4j)" },
    @{ Name = "QDRANT_ENDPOINT";      Description = "Qdrant server endpoint URL";                  Default = "";                           Group = "Vector Database (Qdrant)" },
    @{ Name = "QDRANT_API_KEY";       Description = "Qdrant API key";                              Default = "";                           Group = "Vector Database (Qdrant)" },
    @{ Name = "TELEGRAM_BOT_TOKEN";   Description = "Telegram Bot token from BotFather";           Default = "";                           Group = "Telegram Notification" },
    @{ Name = "CHAT_ID";              Description = "Telegram chat/group ID for alerts";           Default = "";                           Group = "Telegram Notification" },
    @{ Name = "PORT";                 Description = "API server port";                             Default = "$DefaultPort";               Group = "Server" },
    @{ Name = "REGISTER_INVITE_CODE"; Description = "Invite code for first-time user registration"; Default = "";                          Group = "Registration" }
)

$currentGroup = ""
foreach ($var in $envVars) {
    if ($var.Group -ne $currentGroup) {
        $currentGroup = $var.Group
        Write-Host ""
        Write-Host "  --- $currentGroup ---" -ForegroundColor Cyan
    }

    $currentValue = [System.Environment]::GetEnvironmentVariable($var.Name, "User")

    if ([string]::IsNullOrWhiteSpace($currentValue)) {
        $defaultDisplay = if ($var.Default) { " [default: $($var.Default)]" } else { "" }
        Write-Host "  $($var.Name) is NOT set." -ForegroundColor Red
        Write-Host "    Description: $($var.Description)$defaultDisplay" -ForegroundColor Gray

        $input = Read-Host "    Enter value for $($var.Name) (press Enter for default)"
        if ([string]::IsNullOrWhiteSpace($input)) {
            if ($var.Default) {
                $valueToSet = $var.Default
                if ($valueToSet -eq "`$DefaultPort") { $valueToSet = "$DefaultPort" }
            } else {
                Write-Host "    Skipped (no default available)." -ForegroundColor Yellow
                continue
            }
        } else {
            $valueToSet = $input
        }

        [System.Environment]::SetEnvironmentVariable($var.Name, $valueToSet, "User")
        # Also set for current session
        Set-Item -Path "Env:\$($var.Name)" -Value $valueToSet
        Write-Host "    Set $($var.Name) = $valueToSet" -ForegroundColor Green
    } else {
        Write-Host "  $($var.Name) = $currentValue" -ForegroundColor Green
    }
}

# Ensure PORT is available in current session
$Port = [System.Environment]::GetEnvironmentVariable("PORT", "User")
if ([string]::IsNullOrWhiteSpace($Port)) { $Port = "$DefaultPort" }
$env:PORT = $Port

Write-Host ""
Write-Host "  All environment variables configured." -ForegroundColor Green

# ============================================================
# Step 3: Create installation directory
# ============================================================
Write-Host ""
Write-Host "[3/12] Creating installation directory..." -ForegroundColor Yellow
if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "  Created: $InstallDir" -ForegroundColor Green
} else {
    Write-Host "  Directory already exists: $InstallDir" -ForegroundColor Green
}

# ============================================================
# Step 4: Add Windows Defender Exclusions
# ============================================================
Write-Host ""
Write-Host "[4/12] Adding Windows Defender exclusions..." -ForegroundColor Yellow
try {
    Add-MpPreference -ExclusionPath $InstallDir
    Write-Host "  Exclusion added for directory: $InstallDir" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Could not add directory exclusion." -ForegroundColor Yellow
    Write-Host "  $_" -ForegroundColor Yellow
}
try {
    Add-MpPreference -ExclusionProcess $ExeName
    Write-Host "  Exclusion added for process: $ExeName" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Could not add process exclusion." -ForegroundColor Yellow
    Write-Host "  $_" -ForegroundColor Yellow
}

# ============================================================
# Step 5: Kill running processes (if-slr and cloudflared)
# ============================================================
Write-Host ""
Write-Host "[5/12] Stopping running processes..." -ForegroundColor Yellow

$ifSlrProcess = Get-Process -Name "if-slr" -ErrorAction SilentlyContinue
if ($ifSlrProcess) {
    Write-Host "  if-slr is running. Stopping..." -ForegroundColor Yellow
    Stop-Process -Name "if-slr" -Force
    Write-Host "  if-slr stopped." -ForegroundColor Green
} else {
    Write-Host "  if-slr is not running." -ForegroundColor Green
}

$cloudflaredProcess = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
if ($cloudflaredProcess) {
    Write-Host "  cloudflared is running. Stopping..." -ForegroundColor Yellow
    Stop-Process -Name "cloudflared" -Force
    Write-Host "  cloudflared stopped." -ForegroundColor Green
} else {
    Write-Host "  cloudflared is not running." -ForegroundColor Green
}

if ($ifSlrProcess -or $cloudflaredProcess) {
    Start-Sleep -Seconds 1
    Write-Host "  Waited for file handles to be released." -ForegroundColor Green
}

# ============================================================
# Step 6: Download the binary (renamed to if-slr.exe)
# ============================================================
Write-Host "[6/12] Downloading $RemoteName as $ExeName..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ExePath -UseBasicParsing
    Write-Host "  Downloaded and saved as: $ExePath" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to download file." -ForegroundColor Red
    Write-Host "  URL: $DownloadUrl" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}

# Add explicit Defender exclusion for the downloaded exe path
try {
    Add-MpPreference -ExclusionPath $ExePath
    Write-Host "  Defender exclusion added for: $ExePath" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Could not add file exclusion." -ForegroundColor Yellow
}

# ============================================================
# Step 7: Add install directory to user PATH
# ============================================================
Write-Host "[7/12] Adding $InstallDir to user PATH..." -ForegroundColor Yellow
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$InstallDir*") {
    $newPath = "$userPath;$InstallDir"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:Path = "$env:Path;$InstallDir"
    Write-Host "  Added to PATH. You can now run 'if-slr' from Win+R or any terminal." -ForegroundColor Green
} else {
    Write-Host "  Already in PATH." -ForegroundColor Green
}

# ============================================================
# Step 8: Remove Mark-of-the-Web (Zone.Identifier)
# ============================================================
Write-Host "[8/12] Removing Mark-of-the-Web (Zone.Identifier)..." -ForegroundColor Yellow
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

# ============================================================
# Step 9: Check if PORT is in use and kill the process
# ============================================================
Write-Host "[9/12] Checking if port $Port is in use..." -ForegroundColor Yellow
try {
    $portInUse = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($portInUse) {
        $processId = $portInUse[0].OwningProcess
        $processName = (Get-Process -Id $processId -ErrorAction SilentlyContinue).ProcessName
        Write-Host "  Port $Port is in use by process: $processName (PID: $processId)" -ForegroundColor Yellow
        Write-Host "  Killing process..." -ForegroundColor Yellow
        Stop-Process -Id $processId -Force
        Start-Sleep -Seconds 1
        Write-Host "  Process killed. Port $Port is now free." -ForegroundColor Green
    } else {
        Write-Host "  Port $Port is free." -ForegroundColor Green
    }
} catch {
    Write-Host "  Could not check port status (non-critical)." -ForegroundColor Yellow
}

# ============================================================
# Step 10: Launch if-slr.exe
# ============================================================
Write-Host "[10/12] Launching $ExeName on port $Port..." -ForegroundColor Yellow
Write-Host ""
try {
    $appProcess = Start-Process -FilePath $ExePath -PassThru
    Write-Host "  $AppName started successfully (PID: $($appProcess.Id))." -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to launch executable." -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}

# Wait a moment for the app to start
Start-Sleep -Seconds 3

# ============================================================
# Step 11: Start cloudflared tunnel
# ============================================================
Write-Host "[11/12] Starting cloudflared tunnel to http://localhost:$Port..." -ForegroundColor Yellow
Write-Host ""

if ($cloudflaredInstalled) {
    try {
        $tunnelProcess = Start-Process -FilePath $cloudflaredExe -ArgumentList "tunnel", "--url", "http://localhost:$Port" -PassThru -NoNewWindow
        Write-Host "  cloudflared tunnel started (PID: $($tunnelProcess.Id))." -ForegroundColor Green
        Write-Host "  Your app will be accessible via the URL shown by cloudflared above." -ForegroundColor Green
    } catch {
        Write-Host "  WARNING: Failed to start cloudflared tunnel." -ForegroundColor Yellow
        Write-Host "  You can start it manually: cloudflared tunnel --url http://localhost:$Port" -ForegroundColor Yellow
    }
} else {
    Write-Host "  cloudflared is not available. Skipping tunnel." -ForegroundColor Yellow
    Write-Host "  Install cloudflared and run: cloudflared tunnel --url http://localhost:$Port" -ForegroundColor Yellow
}

# ============================================================
# Step 12: Open browser to IF SLR web interface
# ============================================================
Write-Host ""
Write-Host "[12/12] Opening browser to https://if.co.id/slr..." -ForegroundColor Yellow
try {
    Start-Process "https://if.co.id/slr"
    Write-Host "  Browser opened successfully." -ForegroundColor Green
} catch {
    Write-Host "  Could not open browser automatically." -ForegroundColor Yellow
    Write-Host "  Please open https://if.co.id/slr manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Installation complete!" -ForegroundColor Cyan
Write-Host "  Location: $ExePath" -ForegroundColor Cyan
Write-Host "  Port: $Port" -ForegroundColor Cyan
Write-Host "  Run from anywhere: if-slr" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
