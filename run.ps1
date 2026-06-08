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

# Step 1: Check and install cloudflared
Write-Host "[1/6] Checking cloudflared installation..." -ForegroundColor Yellow
$cloudflaredInstalled = $false
try {
    $cfCmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cfCmd) {
        $cloudflaredInstalled = $true
        Write-Host "  cloudflared is already installed: $($cfCmd.Source)" -ForegroundColor Green
    }
} catch {
    $cloudflaredInstalled = $false
}

if (-not $cloudflaredInstalled) {
    Write-Host "  cloudflared is not installed. Attempting installation..." -ForegroundColor Yellow

    # Try winget first
    $wingetAvailable = $false
    try {
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetCmd) { $wingetAvailable = $true }
    } catch {}

    if ($wingetAvailable) {
        Write-Host "  Installing via winget..." -ForegroundColor Yellow
        try {
            winget install Cloudflare.cloudflared --accept-source-agreements --accept-package-agreements
            Write-Host "  cloudflared installed successfully via winget." -ForegroundColor Green
        } catch {
            Write-Host "  winget installation failed. Falling back to direct download..." -ForegroundColor Yellow
            $wingetAvailable = $false
        }
    }

    if (-not $wingetAvailable) {
        Write-Host "  Downloading cloudflared directly..." -ForegroundColor Yellow
        $cfUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
        $cfDir = Join-Path $env:LOCALAPPDATA "cloudflared"
        $cfPath = Join-Path $cfDir "cloudflared.exe"

        if (!(Test-Path $cfDir)) {
            New-Item -ItemType Directory -Path $cfDir -Force | Out-Null
        }

        try {
            Invoke-WebRequest -Uri $cfUrl -OutFile $cfPath -UseBasicParsing
            Write-Host "  Downloaded cloudflared to: $cfPath" -ForegroundColor Green

            # Add to user PATH if not already there
            $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
            if ($currentPath -notlike "*$cfDir*") {
                [System.Environment]::SetEnvironmentVariable("Path", "$currentPath;$cfDir", "User")
                $env:Path = "$env:Path;$cfDir"
                Write-Host "  Added $cfDir to user PATH." -ForegroundColor Green
            }
            Write-Host "  cloudflared installed successfully." -ForegroundColor Green
        } catch {
            Write-Host "  WARNING: Failed to download cloudflared." -ForegroundColor Red
            Write-Host "  $_" -ForegroundColor Red
            Write-Host "  You can install it manually from: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" -ForegroundColor Yellow
        }
    }
}

# Step 2: Check and configure environment variables
Write-Host "[2/6] Checking environment variables..." -ForegroundColor Yellow
Write-Host ""

$envVars = @(
    @{ Name = "MONGO_URI";           Description = "MongoDB connection URI";             Default = "mongodb://localhost:27017"; Required = $true },
    @{ Name = "DB_NAME";             Description = "Database name";                      Default = "slr_agentic_db";            Required = $false },
    @{ Name = "NEO4JURI";            Description = "Neo4j/AuraDB connection URI";        Default = "";                          Required = $false },
    @{ Name = "NEO4JUSER";           Description = "Neo4j username";                     Default = "";                          Required = $false },
    @{ Name = "NEO4JPASSWORD";       Description = "Neo4j password";                     Default = "";                          Required = $false },
    @{ Name = "QDRANT_ENDPOINT";     Description = "Qdrant server endpoint URL";         Default = "";                          Required = $false },
    @{ Name = "QDRANT_API_KEY";      Description = "Qdrant API key";                     Default = "";                          Required = $false },
    @{ Name = "EMBED_ENDPOINT";      Description = "Embedding server endpoint URL";      Default = "";                          Required = $false },
    @{ Name = "EMBED_API_KEY";       Description = "Embedding server API key";           Default = "";                          Required = $false },
    @{ Name = "EMBED_MODEL";         Description = "Embedding model name";               Default = "BAAI/bge-m3";              Required = $false },
    @{ Name = "TELEGRAM_BOT_TOKEN";  Description = "Telegram Bot token from BotFather";  Default = "";                          Required = $false },
    @{ Name = "CHAT_ID";             Description = "Telegram Chat ID for notifications"; Default = "";                          Required = $false }
)

$missingVars = @()
foreach ($var in $envVars) {
    $currentValue = [System.Environment]::GetEnvironmentVariable($var.Name, "User")
    if ([string]::IsNullOrEmpty($currentValue)) {
        $missingVars += $var
    } else {
        Write-Host "  [OK] $($var.Name) is set." -ForegroundColor Green
    }
}

if ($missingVars.Count -gt 0) {
    Write-Host ""
    Write-Host "  The following environment variables are not set:" -ForegroundColor Yellow
    foreach ($var in $missingVars) {
        $reqLabel = if ($var.Required) { " [REQUIRED]" } else { "" }
        Write-Host "    - $($var.Name): $($var.Description)$reqLabel" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Please provide values for each variable." -ForegroundColor Cyan
    Write-Host "  Press Enter to use the default value (shown in brackets), or type 'skip' to skip optional variables." -ForegroundColor Cyan
    Write-Host ""

    foreach ($var in $missingVars) {
        $defaultDisplay = if ($var.Default) { $var.Default } else { "none" }
        $reqLabel = if ($var.Required) { " [REQUIRED]" } else { " [optional]" }

        $prompt = "  $($var.Name)$reqLabel (default: $defaultDisplay): "
        Write-Host $prompt -ForegroundColor White -NoNewline
        $userInput = Read-Host

        if ($userInput -eq "skip" -and -not $var.Required) {
            Write-Host "    Skipped." -ForegroundColor DarkGray
            continue
        }

        if ([string]::IsNullOrEmpty($userInput)) {
            if ($var.Default) {
                $userInput = $var.Default
            } elseif ($var.Required) {
                Write-Host "    ERROR: This variable is required. Using default or please re-run the script." -ForegroundColor Red
                continue
            } else {
                Write-Host "    Skipped (no default)." -ForegroundColor DarkGray
                continue
            }
        }

        # Set as persistent User environment variable
        [System.Environment]::SetEnvironmentVariable($var.Name, $userInput, "User")
        # Also set in current session
        Set-Item -Path "Env:\$($var.Name)" -Value $userInput
        Write-Host "    Set $($var.Name) = $userInput" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  Environment variables configured successfully." -ForegroundColor Green
} else {
    Write-Host "  All environment variables are already configured." -ForegroundColor Green
}

Write-Host ""

# Step 3: Create installation directory
Write-Host "[3/6] Creating installation directory..." -ForegroundColor Yellow
if (!(Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "  Created: $InstallDir" -ForegroundColor Green
} else {
    Write-Host "  Directory already exists: $InstallDir" -ForegroundColor Green
}

# Step 4: Download the binary
Write-Host "[4/6] Downloading $ExeName..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ExePath -UseBasicParsing
    Write-Host "  Downloaded to: $ExePath" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to download file." -ForegroundColor Red
    Write-Host "  URL: $DownloadUrl" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}

# Step 5: Remove Mark-of-the-Web (Zone.Identifier)
Write-Host "[5/6] Removing Mark-of-the-Web (Zone.Identifier)..." -ForegroundColor Yellow
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

# Step 6: Run the executable
Write-Host "[6/6] Launching $ExeName..." -ForegroundColor Yellow
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
