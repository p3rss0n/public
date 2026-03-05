#!/usr/bin/env bash

set -euo pipefail

############################################
# macos-desiredstate.sh
# macOS Desired State - curl compatible
############################################

REPO_RAW_BASE="https://raw.githubusercontent.com/p3rss0n/public/main"
TMP_DIR="/tmp/macos-desiredstate"
BREWFILE="$TMP_DIR/Brewfile"

log() {
    printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$1"
}

############################################
# Prevent running as root
############################################
if [ "$EUID" -eq 0 ]; then
    echo "Do not run this script with sudo."
    exit 1
fi

############################################
# Ensure temp directory
############################################
mkdir -p "$TMP_DIR"

############################################
# Ensure Command Line Tools (Homebrew method)
############################################
ensure_clt() {

    if xcode-select -p >/dev/null 2>&1; then
        log "Command Line Tools already installed."
        return
    fi

    log "Installing Command Line Tools (Homebrew method)..."

    sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    CLT_LABEL=$(softwareupdate -l 2>/dev/null \
        | grep "Command Line Tools" \
        | sed -e 's/^ *\* *//' \
        | head -n 1)

    if [ -n "$CLT_LABEL" ]; then
        sudo softwareupdate -i "$CLT_LABEL" --verbose
        sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        log "Command Line Tools installed."
    else
        sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        log "Command Line Tools not available via softwareupdate."
        log "Falling back to interactive installer."
        xcode-select --install
        exit 1
    fi
}

############################################
# Ensure Homebrew
############################################
ensure_homebrew() {

    if command -v brew >/dev/null 2>&1; then
        log "Homebrew already installed."
        return
    fi

    log "Installing Homebrew..."

    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Apple Silicon path
    if [ -d "/opt/homebrew/bin" ]; then
        if ! grep -q 'brew shellenv' "$HOME/.zshrc" 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zshrc"
        fi
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    log "Homebrew installed."
}

############################################
# Ensure Rosetta (Apple Silicon only)
############################################
ensure_rosetta() {

    ARCH=$(uname -m)

    if [ "$ARCH" != "arm64" ]; then
        return
    fi

    if /usr/bin/pgrep oahd >/dev/null 2>&1; then
        log "Rosetta already installed."
        return
    fi

    log "Installing Rosetta..."
    sudo softwareupdate --install-rosetta --agree-to-license || true
}

############################################
# Fetch Brewfile from GitHub
############################################
fetch_brewfile() {

    log "Fetching Brewfile from GitHub..."
    curl -fsSL "$REPO_RAW_BASE/Brewfile" -o "$BREWFILE"
}

############################################
# Sync Brewfile
############################################
ensure_brew_bundle() {

    if [ ! -f "$BREWFILE" ]; then
        log "Brewfile not found."
        return
    fi

    log "Updating Homebrew..."
    brew update
    brew upgrade

    log "Reconciling Brewfile..."
    brew bundle --file="$BREWFILE"

    log "Brewfile sync complete."
}

############################################
# Ensure MAS login
############################################
ensure_mas_login() {

    if ! command -v mas >/dev/null 2>&1; then
        return
    fi

    if mas account >/dev/null 2>&1; then
        log "App Store account detected."
    else
        log "Not logged into App Store."
        log "Please open App Store and login manually."
    fi
}

############################################
# Cleanup
############################################
cleanup() {

    log "Cleaning up Homebrew..."
    brew autoremove || true
    brew cleanup || true
}

############################################
# Main
############################################
main() {

    log "Starting macOS desired state reconciliation"

    ensure_clt
    ensure_homebrew
    ensure_rosetta
    fetch_brewfile
    ensure_brew_bundle
    ensure_mas_login
    cleanup

    log "macOS desired state complete."
}

main "$@"