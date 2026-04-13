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
# The script walks you through installing any missing prerequisites (gh,
# Docker Desktop) and authenticating to GitHub. It never crashes with an
# unhandled exception — every failure produces a clear message and guidance.
#
# Usage (run in a PowerShell terminal):
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

function Write-Warn {
    param([string]$Message)
    Write-Host "    [warn] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    [error] $Message" -ForegroundColor Red
}

function Exit-WithError {
    param([string]$Message)
    Write-Fail $Message
    Write-Host ""
    Write-Host "    If you need help, contact Proaxiom support." -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "    Press Enter to close"
    exit 1
}

function Wait-ForUser {
    param([string]$Message)
    Write-Host ""
    Read-Host "    $Message — press Enter to continue"
}

function Confirm-YesNo {
    param([string]$Prompt, [bool]$DefaultYes = $true)
    $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    $answer = Read-Host "    $Prompt $suffix"
    if ($DefaultYes) {
        return -not ($answer -match '^[Nn]')
    } else {
        return ($answer -match '^[Yy]')
    }
}

# ---------------------------------------------------------------------------
# Top-level error handler — no stack traces ever reach the user
# ---------------------------------------------------------------------------
try {

Write-Host ""
Write-Host "rfqbot installer bootstrap" -ForegroundColor White
Write-Host "Proaxiom Cyber" -ForegroundColor DarkGray
Write-Host ""

# =========================================================================
# 1. GitHub CLI
# =========================================================================
Write-Step "Checking GitHub CLI (gh)..."

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Warn "GitHub CLI (gh) is not installed."

    # Check if winget is available
    $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

    if ($hasWinget -and (Confirm-YesNo "Install it now via winget?")) {
        Write-Host "    Installing GitHub CLI..." -ForegroundColor Cyan
        try {
            & winget install GitHub.cli --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        } catch {
            Write-Warn "winget install encountered an error: $($_.Exception.Message)"
        }
        # Refresh PATH so the current session picks up the new install
        $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')

        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            Write-Warn "gh was installed but is not on PATH yet."
            Wait-ForUser "Close and reopen your terminal, then re-run this script"
            exit 1
        }
        Write-Ok "gh installed successfully"
    } else {
        Write-Host ""
        Write-Host "    Install gh manually:" -ForegroundColor White
        if ($hasWinget) {
            Write-Host "        winget install GitHub.cli" -ForegroundColor White
        }
        Write-Host "        https://cli.github.com/" -ForegroundColor White
        Write-Host ""
        Wait-ForUser "Install gh, then come back here"

        # Re-check after user says they've installed it
        $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            Exit-WithError "gh is still not on PATH. You may need to close and reopen your terminal."
        }
        Write-Ok "gh found"
    }
} else {
    Write-Ok "gh found at $(Get-Command gh | Select-Object -ExpandProperty Source)"
}

# =========================================================================
# 2. GitHub authentication
# =========================================================================
Write-Step "Checking GitHub authentication..."

$ghAuthed = $false
try {
    $null = & gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) { $ghAuthed = $true }
} catch {}

if (-not $ghAuthed) {
    Write-Warn "GitHub CLI is not authenticated."
    Write-Host "    Starting gh auth login — follow the prompts below." -ForegroundColor Cyan
    Write-Host ""
    try {
        & gh auth login
        if ($LASTEXITCODE -ne 0) { throw "login failed" }
    } catch {
        Write-Warn "gh auth login did not complete successfully."
        Wait-ForUser "Run 'gh auth login' manually in another terminal, then come back"

        # Re-check
        try {
            $null = & gh auth status 2>&1
            if ($LASTEXITCODE -ne 0) { throw "still not authed" }
        } catch {
            Exit-WithError "gh is still not authenticated. Run 'gh auth login' and try again."
        }
    }
}
Write-Ok "gh is authenticated"

# =========================================================================
# 3. Docker
# =========================================================================
Write-Step "Checking Docker..."

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Warn "Docker Desktop is not installed."

    $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

    if ($hasWinget -and (Confirm-YesNo "Install Docker Desktop now via winget?")) {
        Write-Host "    Installing Docker Desktop (this may take a few minutes)..." -ForegroundColor Cyan
        try {
            & winget install Docker.DockerDesktop --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        } catch {
            Write-Warn "winget install encountered an error: $($_.Exception.Message)"
        }
        $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')

        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Write-Warn "Docker was installed but is not on PATH yet."
            Write-Host "    You may need to restart your computer for Docker Desktop to finish setup." -ForegroundColor Yellow
            Wait-ForUser "Restart if needed, start Docker Desktop, then re-run this script"
            exit 1
        }
        Write-Ok "Docker Desktop installed"
    } else {
        Write-Host ""
        Write-Host "    Install Docker Desktop from:" -ForegroundColor White
        Write-Host "        https://www.docker.com/products/docker-desktop/" -ForegroundColor White
        if ($hasWinget) {
            Write-Host "    Or: winget install Docker.DockerDesktop" -ForegroundColor White
        }
        Write-Host ""
        Wait-ForUser "Install Docker Desktop and start it, then come back here"

        $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Exit-WithError "docker is still not on PATH. You may need to restart your computer."
        }
    }
}

# Check if Docker daemon is running
$dockerRunning = $false
try {
    $null = & docker info 2>&1
    if ($LASTEXITCODE -eq 0) { $dockerRunning = $true }
} catch {}

if (-not $dockerRunning) {
    Write-Warn "Docker is installed but the daemon is not running."

    # Try to find and launch Docker Desktop
    $dockerDesktopExe = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
        "$env:LOCALAPPDATA\Docker\Docker Desktop.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($dockerDesktopExe) {
        Write-Host "    Starting Docker Desktop..." -ForegroundColor Cyan
        try { Start-Process $dockerDesktopExe } catch {
            Write-Warn "Could not start Docker Desktop automatically."
        }
    } else {
        Write-Host "    Could not find Docker Desktop executable." -ForegroundColor Yellow
    }

    Write-Host "    Waiting for Docker daemon to become ready..." -ForegroundColor Cyan
    Write-Host "    (If Docker Desktop isn't running, please start it now.)" -ForegroundColor Yellow

    $retries = 45  # 90 seconds
    $dots = 0
    while ($retries -gt 0) {
        Start-Sleep -Seconds 2
        try {
            $null = & docker info 2>&1
            if ($LASTEXITCODE -eq 0) { $dockerRunning = $true; break }
        } catch {}
        $retries--
        $dots++
        if ($dots % 5 -eq 0) {
            Write-Host "    ... still waiting ($([math]::Round($retries * 2))s remaining)" -ForegroundColor DarkGray
        }
    }

    if (-not $dockerRunning) {
        Write-Warn "Docker did not become ready within 90 seconds."
        Wait-ForUser "Start Docker Desktop manually, wait for it to finish loading, then press Enter"

        try {
            $null = & docker info 2>&1
            if ($LASTEXITCODE -eq 0) { $dockerRunning = $true }
        } catch {}

        if (-not $dockerRunning) {
            Exit-WithError "Docker daemon is still not running. Start Docker Desktop and re-run this script."
        }
    }
    Write-Ok "Docker is now running"
} else {
    Write-Ok "Docker is running"
}

# =========================================================================
# 4. Repository access
# =========================================================================
Write-Step "Checking access to $REPO..."

$repoAccess = $false
try {
    $null = & gh repo view $REPO --json name 2>&1
    if ($LASTEXITCODE -eq 0) { $repoAccess = $true }
} catch {}

if (-not $repoAccess) {
    Write-Warn "Cannot access $REPO."
    Write-Host "    This usually means one of:" -ForegroundColor Yellow
    Write-Host "      - Your GitHub account hasn't been granted collaborator access" -ForegroundColor Yellow
    Write-Host "      - Your gh session is missing the 'repo' scope" -ForegroundColor Yellow

    if (Confirm-YesNo "Try refreshing gh with the 'repo' scope?") {
        try {
            & gh auth refresh -s repo
        } catch {
            Write-Warn "Scope refresh did not complete: $($_.Exception.Message)"
        }

        try {
            $null = & gh repo view $REPO --json name 2>&1
            if ($LASTEXITCODE -eq 0) { $repoAccess = $true }
        } catch {}
    }

    if (-not $repoAccess) {
        Exit-WithError "Cannot access $REPO. Contact Proaxiom to confirm your GitHub account has been granted collaborator access."
    }
}
Write-Ok "Repository access confirmed"

# =========================================================================
# 5. Download and extract
# =========================================================================
Write-Step "Downloading $REPO (main branch)..."

$TempBase = Join-Path $env:TEMP "rfqbot-bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
try {
    New-Item -ItemType Directory -Path $TempBase -Force | Out-Null
} catch {
    Exit-WithError "Could not create temp directory at $TempBase — check disk space and permissions."
}

$TarballPath = Join-Path $TempBase 'rfqbot.tar.gz'

$downloadOk = $false
$lastError = ""
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $output = & gh api "repos/$REPO/tarball/main" -o $TarballPath 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path $TarballPath) -and (Get-Item $TarballPath).Length -gt 0) {
            $downloadOk = $true
            break
        }
        $lastError = ($output | Out-String).Trim()
    } catch {
        $lastError = $_.Exception.Message
    }

    if ($attempt -lt 3) {
        Write-Warn "Download attempt $attempt failed. Retrying in 3 seconds..."
        Start-Sleep -Seconds 3
    }
}

if (-not $downloadOk) {
    Write-Fail "Failed to download repository after 3 attempts."
    if ($lastError) {
        Write-Host "    Last error: $lastError" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "    This is often caused by missing 'repo' scope on your gh token." -ForegroundColor Yellow
    Write-Host "    Try: gh auth refresh -s repo" -ForegroundColor White
    Write-Host "    Then re-run this script." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "    Press Enter to close"
    exit 1
}
Write-Ok "Downloaded to $TarballPath"

Write-Step "Extracting..."
$ExtractDir = Join-Path $TempBase 'extract'
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null

try {
    & tar -xzf $TarballPath -C $ExtractDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "tar failed" }
} catch {
    Exit-WithError "Failed to extract tarball. Ensure 'tar' is available (built into Windows 10 build 17063+)."
}

# GitHub tarballs extract to a directory named <org>-<repo>-<shortsha>.
$InnerDirs = Get-ChildItem -Path $ExtractDir -Directory
if ($InnerDirs.Count -ne 1) {
    Exit-WithError "Expected exactly one directory inside the tarball, found $($InnerDirs.Count)."
}
$RepoDir = $InnerDirs[0].FullName
Write-Ok "Extracted to $RepoDir"

# Clean up the tarball — the extracted directory is still needed.
Remove-Item -Path $TarballPath -Force -ErrorAction SilentlyContinue

# =========================================================================
# 6. Set up token and hand off to install.ps1
# =========================================================================
Write-Step "Preparing installer environment..."

$Token = $null
try {
    $Token = (& gh auth token 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) { $Token = $null }
} catch {}

if ([string]::IsNullOrWhiteSpace($Token)) {
    Exit-WithError "Failed to retrieve GitHub token from 'gh auth token'. Try running 'gh auth login' again."
}
$env:RFQBOT_GITHUB_TOKEN = $Token
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
} catch {
    Write-Fail "install.ps1 encountered an error: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "    The extracted repo is still at: $RepoDir" -ForegroundColor DarkGray
    Write-Host "    You can retry manually with:" -ForegroundColor DarkGray
    Write-Host "        cd `"$RepoDir`"" -ForegroundColor White
    Write-Host "        `$env:RFQBOT_GITHUB_TOKEN = (gh auth token)" -ForegroundColor White
    Write-Host "        .\scripts\install.ps1 -Docker" -ForegroundColor White
    Write-Host ""
    Read-Host "    Press Enter to close"
    exit 1
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# End of top-level try block
# ---------------------------------------------------------------------------
} catch {
    Write-Host ""
    Write-Fail "An unexpected error occurred: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "    If this keeps happening, please contact Proaxiom support" -ForegroundColor DarkGray
    Write-Host "    with the error message above." -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "    Press Enter to close"
    exit 1
}
