#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — rfqbot one-line installer bootstrap (Bash)
# =============================================================================
# Proaxiom Cyber — https://proaxiom.com.au
#
# This script bootstraps a fresh rfqbot installation on Linux or macOS.
# It downloads the private repo using your GitHub CLI credentials, sets up
# the authentication token for the installer, and hands off to
# scripts/install.sh.
#
# Prerequisites:
#   1. GitHub CLI (gh) installed and authenticated with repo access
#   2. Docker installed and running
#
# Usage:
#   curl -fsSL https://gist.githubusercontent.com/<GIST_URL>/bootstrap.sh | bash
#
# Or download and run manually:
#   bash bootstrap.sh
# =============================================================================

set -euo pipefail

REPO="Proaxiom-Cyber/rfqbot"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_step() {
  printf '\n\033[36m==> %s\033[0m\n' "$*"
}

_ok() {
  printf '    \033[32m[ok]\033[0m %s\n' "$*"
}

_fail() {
  printf '    \033[31m[error]\033[0m %s\n' "$*" >&2
}

_die() {
  _fail "$@"
  echo ""
  exit 1
}

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------

OS="$(uname -s)"
case "$OS" in
  Linux)  PLATFORM="linux" ;;
  Darwin) PLATFORM="macos" ;;
  *)      _die "Unsupported platform: $OS. This script supports Linux and macOS." ;;
esac

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

echo ""
echo "rfqbot installer bootstrap"
printf '\033[90mProaxiom Cyber\033[0m\n'
echo ""

# 1. GitHub CLI
_step "Checking GitHub CLI (gh)..."
if ! command -v gh >/dev/null 2>&1; then
  if [ "$PLATFORM" = "macos" ]; then
    _die "GitHub CLI (gh) is not installed.

Install it with:
    brew install gh

Then authenticate:
    gh auth login

And re-run this script."
  else
    _die "GitHub CLI (gh) is not installed.

Install it with one of:
    sudo apt install gh          # Debian / Ubuntu
    sudo dnf install gh          # Fedora / RHEL
    brew install gh              # Homebrew on Linux

Then authenticate:
    gh auth login

And re-run this script."
  fi
fi
_ok "gh found at $(command -v gh)"

# 2. gh authenticated
_step "Checking GitHub authentication..."
if ! gh auth status >/dev/null 2>&1; then
  _die "GitHub CLI is not authenticated.

Run the following, then re-run this script:
    gh auth login"
fi
_ok "gh is authenticated"

# 3. Docker
_step "Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
  if [ "$PLATFORM" = "macos" ]; then
    _die "Docker is not installed.

Install Docker Desktop from:
    https://www.docker.com/products/docker-desktop/

After installation, start Docker Desktop and re-run this script."
  else
    _die "Docker is not installed.

Install Docker Engine following the official guide:
    https://docs.docker.com/engine/install/

After installation, start the Docker service and re-run this script."
  fi
fi

if ! docker info >/dev/null 2>&1; then
  _die "Docker is installed but does not appear to be running.

Start the Docker service and re-run this script."
fi
_ok "Docker is running"

# 4. Repo access
_step "Checking access to $REPO..."
if ! gh repo view "$REPO" --json name >/dev/null 2>&1; then
  _die "Cannot access $REPO.

Make sure your GitHub account has been granted collaborator access to the
repository, and that your gh login has the 'repo' scope:
    gh auth refresh -s repo"
fi
_ok "Repository access confirmed"

# ---------------------------------------------------------------------------
# LXC mode hint
# ---------------------------------------------------------------------------

if command -v pct >/dev/null 2>&1; then
  echo ""
  printf '\033[33m    Note: pct detected — this host supports LXC mode.\033[0m\n'
  printf '    The bootstrap defaults to --docker. To use LXC mode instead,\n'
  printf '    download the repo manually and run:\n'
  printf '        bash scripts/install.sh --lxc --vmid <N>\n'
  echo ""
fi

# ---------------------------------------------------------------------------
# Download and extract
# ---------------------------------------------------------------------------

_step "Downloading $REPO (main branch)..."

TEMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/rfqbot-bootstrap-XXXXXX")"

# Ensure cleanup of the tarball and temp dir on exit (but not the extracted
# repo directory — install.sh needs it).
REPO_DIR=""
cleanup() {
  rm -f "$TEMP_BASE/rfqbot.tar.gz" 2>/dev/null || true
  # Only remove temp base if extraction failed (REPO_DIR not set).
  if [ -z "$REPO_DIR" ]; then
    rm -rf "$TEMP_BASE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

TARBALL="$TEMP_BASE/rfqbot.tar.gz"

if ! gh api "repos/$REPO/tarball/main" > "$TARBALL" 2>/dev/null; then
  _die "Failed to download repository tarball. Check your network connection and try again."
fi

if [ ! -s "$TARBALL" ]; then
  _die "Tarball was not created or is empty."
fi
_ok "Downloaded to $TARBALL"

_step "Extracting..."
EXTRACT_DIR="$TEMP_BASE/extract"
mkdir -p "$EXTRACT_DIR"

if ! tar -xzf "$TARBALL" -C "$EXTRACT_DIR"; then
  _die "Failed to extract tarball."
fi

# GitHub tarballs extract to a directory named <org>-<repo>-<shortsha>.
# Find it dynamically.
INNER_DIR="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d)"
DIR_COUNT="$(echo "$INNER_DIR" | wc -l | tr -d ' ')"

if [ "$DIR_COUNT" -ne 1 ] || [ -z "$INNER_DIR" ]; then
  _die "Expected exactly one directory inside the tarball, found $DIR_COUNT."
fi

REPO_DIR="$INNER_DIR"
_ok "Extracted to $REPO_DIR"

# Clean up the tarball — the extracted directory is still needed.
rm -f "$TARBALL"

# ---------------------------------------------------------------------------
# Set up token and hand off to install.sh
# ---------------------------------------------------------------------------

_step "Preparing installer environment..."

TOKEN="$(gh auth token 2>/dev/null)" || true
if [ -z "${TOKEN:-}" ]; then
  _die "Failed to retrieve GitHub token from 'gh auth token'."
fi
export RFQBOT_GITHUB_TOKEN="$TOKEN"
_ok "RFQBOT_GITHUB_TOKEN set from gh credentials"

INSTALLER="$REPO_DIR/scripts/install.sh"
if [ ! -f "$INSTALLER" ]; then
  _die "Installer not found at expected path: $INSTALLER"
fi

_step "Handing off to install.sh --docker..."
echo ""

cd "$REPO_DIR"
exec bash scripts/install.sh --docker
