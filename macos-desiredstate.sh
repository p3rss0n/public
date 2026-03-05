#!/usr/bin/env bash

set -euo pipefail

############################################
# macos-desiredstate.gsh
# Ensures macOS matches desired state
############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="${SCRIPT_DIR}/Brewfile"

log() {
    printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$1"
}

############################################
# Ensure Homebrew
############################################
ensure_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        log "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Apple Silicon
        if [[ -d "/opt/homebrew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    else
        log "Homebrew already installed."
    fi
}

############################################
# Ensure Rosetta (Apple Silicon)
############################################
ensure_rosetta() {
    if [[ "$(uname -m)" == "arm64" ]]; then
        if ! pgrep oahd >/dev/null 2>&1; then
            log "Installing Rosetta..."
            softwareupdate --install-rosetta --agree-to-license
        else
            log "Rosetta already installed."
        fi
    fi
}

############################################
# Ensure Brew bundle
############################################
ensure_brew_bundle() {
    if [[ -f "$BREWFILE" ]]; then
        log "Syncing Brewfile..."
        brew update
        brew upgrade
        brew bundle --file="$BREWFILE"
    else
        log "No Brewfile found at $BREWFILE"
    fi
}

############################################
# Ensure Mac App Store login
############################################
ensure_mas_login() {
    if command -v mas >/dev/null 2>&1; then
        if ! mas account >/dev/null 2>&1; then
            log "Not logged into App Store. Please login manually."
        else
            log "App Store account detected."
        fi
    fi
}

############################################
# Cleanup
############################################
cleanup() {
    log "Cleaning up..."
    brew autoremove || true
    brew cleanup || true
}

############################################
# Main
############################################
main() {
    log "Starting macOS desired state reconciliation"

    ensure_homebrew
    ensure_rosetta
    ensure_brew_bundle
    ensure_mas_login
    cleanup

    log "macOS desired state complete."
}

main "$@"