# =============================================================================
# bootstrap.ps1 — rfqbot one-line installer bootstrap (PowerShell)
# =============================================================================
# Proaxiom Cyber — https://proaxiom.com.au
#
# This script bootstraps a fresh rfqbot installation on Windows or macOS.
# It downloads the private repo using your GitHub CLI credentials, sets up
# the authentication token for the Docker-based installer, and hands off to
# scripts/install.ps1.
#
# Prerequisites:
#   1. GitHub CLI (gh) installed and authenticated with repo access
#   2. Docker Desktop installed and running
#
# Usage (run in an elevated PowerShell terminal):
#   irm https://raw.githubusercontent.com/Proaxiom-Cyber/rfqbot-install/main/bootstrap.ps1 | iex
#
# Or download and run manually:
#   .\bootstrap.ps1
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$REPO = 'Proaxiom-Cyber/rfqbot'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    [ok] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    [error] $Message" -ForegroundColor Red
}

function Exit-WithError {
    param([string]$Message)
    Write-Fail $Message
    Write-Host ""
    exit 1
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "rfqbot installer bootstrap" -ForegroundColor White
Write-Host "Proaxiom Cyber" -ForegroundColor DarkGray
Write-Host ""

# 1. GitHub CLI
Write-Step "Checking GitHub CLI (gh)..."
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "    GitHub CLI (gh) is not installed." -ForegroundColor Yellow
    $answer = Read-Host "    Install it now via winget? [Y/n]"
    if ($answer -match '^[Nn]') {
        Exit-WithError "gh is required. Install it manually with: winget install GitHub.cli"
    }
    Write-Host "    Installing GitHub CLI..." -ForegroundColor Cyan
    & winget install GitHub.cli --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    # winget installs to a path not in the current session — refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Exit-WithError "gh was installed but is not on PATH. Close and reopen your terminal, then re-run this script."
    }
    Write-Ok "gh installed successfully"
} else {
    Write-Ok "gh found at $(Get-Command gh | Select-Object -ExpandProperty Source)"
}

# 2. gh authenticated
Write-Step "Checking GitHub authentication..."
$ghAuthed = $false
try {
    $null = & gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) { $ghAuthed = $true }
} catch {}

if (-not $ghAuthed) {
    Write-Host "    GitHub CLI is not authenticated. Starting login..." -ForegroundColor Yellow
    & gh auth login
    if ($LASTEXITCODE -ne 0) {
        Exit-WithError "GitHub authentication failed. Run 'gh auth login' manually and try again."
    }
}
Write-Ok "gh is authenticated"

# 3. Docker
Write-Step "Checking Docker..."
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "    Docker Desktop is not installed." -ForegroundColor Yellow
    $answer = Read-Host "    Install it now via winget? [Y/n]"
    if ($answer -match '^[Nn]') {
        Exit-WithError @"
Docker Desktop is required. Install it from:
    https://www.docker.com/products/docker-desktop/
Or: winget install Docker.DockerDesktop
"@
    }
    Write-Host "    Installing Docker Desktop (this may take a few minutes)..." -ForegroundColor Cyan
    & winget install Docker.DockerDesktop --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Exit-WithError "Docker was installed but is not on PATH. You may need to restart your computer, then re-run this script."
    }
    Write-Ok "Docker Desktop installed"
}

$dockerRunning = $false
try {
    $null = & docker info 2>&1
    if ($LASTEXITCODE -eq 0) { $dockerRunning = $true }
} catch {}

if (-not $dockerRunning) {
    Write-Host "    Docker is installed but not running. Attempting to start Docker Desktop..." -ForegroundColor Yellow
    Start-Process "Docker Desktop" -ErrorAction SilentlyContinue
    Write-Host "    Waiting for Docker to start (this can take 30-60 seconds)..." -ForegroundColor Cyan
    $retries = 30
    while ($retries -gt 0) {
        Start-Sleep -Seconds 2
        try {
            $null = & docker info 2>&1
            if ($LASTEXITCODE -eq 0) { $dockerRunning = $true; break }
        } catch {}
        $retries--
    }
    if (-not $dockerRunning) {
        Exit-WithError "Docker Desktop did not start in time. Start it manually, then re-run this script."
    }
    Write-Ok "Docker Desktop is now running"
} else {
    Write-Ok "Docker is running"
}

# 4. Repo access
Write-Step "Checking access to $REPO..."
try {
    $null = & gh repo view $REPO --json name 2>&1
    if ($LASTEXITCODE -ne 0) { throw "no access" }
} catch {
    Write-Host "    Cannot access $REPO." -ForegroundColor Yellow
    Write-Host "    This usually means your GitHub account needs collaborator access." -ForegroundColor Yellow
    Write-Host "    If you have access but gh lacks the 'repo' scope, run:" -ForegroundColor Yellow
    Write-Host "        gh auth refresh -s repo" -ForegroundColor White
    $answer = Read-Host "    Try refreshing gh scopes now? [Y/n]"
    if ($answer -notmatch '^[Nn]') {
        & gh auth refresh -s repo
        try {
            $null = & gh repo view $REPO --json name 2>&1
            if ($LASTEXITCODE -ne 0) { throw "still no access" }
        } catch {
            Exit-WithError "Still cannot access $REPO. Contact Proaxiom to confirm your GitHub account has been granted access."
        }
    } else {
        Exit-WithError "Cannot proceed without access to $REPO. Contact Proaxiom to confirm your GitHub account has been granted access."
    }
}
Write-Ok "Repository access confirmed"

# ---------------------------------------------------------------------------
# Download and extract
# ---------------------------------------------------------------------------

Write-Step "Downloading $REPO (main branch)..."

$TempBase = Join-Path $env:TEMP "rfqbot-bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $TempBase -Force | Out-Null

$TarballPath = Join-Path $TempBase 'rfqbot.tar.gz'

try {
    & gh api "repos/$REPO/tarball/main" -o $TarballPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "download failed" }
} catch {
    Exit-WithError "Failed to download repository tarball. Check your network connection and try again."
}

if (-not (Test-Path $TarballPath)) {
    Exit-WithError "Tarball was not created at $TarballPath"
}
Write-Ok "Downloaded to $TarballPath"

Write-Step "Extracting..."
$ExtractDir = Join-Path $TempBase 'extract'
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null

try {
    & tar -xzf $TarballPath -C $ExtractDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "extraction failed" }
} catch {
    Exit-WithError "Failed to extract tarball. Ensure 'tar' is available (built into Windows 10+)."
}

# GitHub tarballs extract to a directory named <org>-<repo>-<shortsha>.
# Find it dynamically.
$InnerDirs = Get-ChildItem -Path $ExtractDir -Directory
if ($InnerDirs.Count -ne 1) {
    Exit-WithError "Expected exactly one directory inside the tarball, found $($InnerDirs.Count)."
}
$RepoDir = $InnerDirs[0].FullName
Write-Ok "Extracted to $RepoDir"

# Clean up the tarball — the extracted directory is still needed.
Remove-Item -Path $TarballPath -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Set up token and hand off to install.ps1
# ---------------------------------------------------------------------------

Write-Step "Preparing installer environment..."

$Token = & gh auth token 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($Token)) {
    Exit-WithError "Failed to retrieve GitHub token from 'gh auth token'."
}
$env:RFQBOT_GITHUB_TOKEN = $Token.Trim()
Write-Ok "RFQBOT_GITHUB_TOKEN set from gh credentials"

$InstallerPath = Join-Path $RepoDir 'scripts' 'install.ps1'
if (-not (Test-Path $InstallerPath)) {
    Exit-WithError "Installer not found at expected path: $InstallerPath"
}

Write-Step "Handing off to install.ps1 -Docker..."
Write-Host ""

try {
    Push-Location $RepoDir
    & pwsh -File $InstallerPath -Docker
} finally {
    Pop-Location
}
