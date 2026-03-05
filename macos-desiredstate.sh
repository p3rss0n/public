#!/usr/bin/env bash

set -euo pipefail

############################################
# macos-desiredstate.sh
# Curl-native desired state for macOS
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
if [[ "$EUID" -eq 0 ]]; then
    echo "Do not run this script with sudo."
    exit 1
fi

############################################
# Ensure temporary working directory
############################################
mkdir -p "$TMP_DIR"

############################################
# Ensure Command Line Tools
############################################
ensure_clt() {

    if xcode-select -p >/dev/null 2>&1; then
        log "Command Line Tools already installed."
        return
    fi

    log "Command Line Tools not found."
    log "Starting installation..."

    xcode-select --install || true

    log "Waiting for Command Line Tools to finish installing..."

    until xcode-select -p >/dev/null 2>&1; do
        sleep 15
    done

    log "Command Line Tools installed."
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

    if [[ -d "/opt/homebrew/bin" ]]; then
        if ! grep -q 'brew shellenv' "$HOME/.zshrc" 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zshrc"
        fi
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    log "Homebrew installed."
}

############################################
# Ensure Rosetta (Apple Silicon)
############################################
ensure_rosetta() {

    if [[ "$(uname -m)" != "arm64" ]]; then
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

    if [[ ! -f "$BREWFILE" ]]; then
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