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
#   irm https://gist.githubusercontent.com/<GIST_URL>/bootstrap.ps1 | iex
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
    Exit-WithError @"
GitHub CLI (gh) is not installed.

Install it with:
    winget install GitHub.cli

Then authenticate:
    gh auth login

And re-run this script.
"@
}
Write-Ok "gh found at $(Get-Command gh | Select-Object -ExpandProperty Source)"

# 2. gh authenticated
Write-Step "Checking GitHub authentication..."
try {
    $null = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) { throw "not authenticated" }
} catch {
    Exit-WithError @"
GitHub CLI is not authenticated.

Run the following, then re-run this script:
    gh auth login
"@
}
Write-Ok "gh is authenticated"

# 3. Docker
Write-Step "Checking Docker..."
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Exit-WithError @"
Docker is not installed.

Install Docker Desktop from:
    https://www.docker.com/products/docker-desktop/

After installation, start Docker Desktop and re-run this script.
"@
}

try {
    $null = & docker info 2>&1
    if ($LASTEXITCODE -ne 0) { throw "docker not running" }
} catch {
    Exit-WithError @"
Docker is installed but does not appear to be running.

Start Docker Desktop and re-run this script.
"@
}
Write-Ok "Docker is running"

# 4. Repo access
Write-Step "Checking access to $REPO..."
try {
    $null = & gh repo view $REPO --json name 2>&1
    if ($LASTEXITCODE -ne 0) { throw "no access" }
} catch {
    Exit-WithError @"
Cannot access $REPO.

Make sure your GitHub account has been granted collaborator access to the
repository, and that your gh login has the 'repo' scope:
    gh auth refresh -s repo
"@
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
