#!/usr/bin/env bash

set -euo pipefail
set -x

############################################
# macos desired state - debug mode
############################################

repo_raw_base="https://raw.githubusercontent.com/p3rss0n/public/main"
tmp_dir="/tmp/macos-desiredstate"
brewfile="$tmp_dir/brewfile"

log() {
    printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$1"
}

############################################
# prevent running as root
############################################
if [ "$EUID" -eq 0 ]; then
    echo "do not run this script with sudo."
    exit 1
fi

############################################
# prepare temp directory
############################################
log "creating temp dir: $tmp_dir"
mkdir -p "$tmp_dir"
ls -ld "$tmp_dir"

############################################
# ensure command line tools (brew method)
############################################
ensure_clt() {

    log "checking command line tools"

    if xcode-select -p >/dev/null 2>&1; then
        log "command line tools already installed"
        xcode-select -p
        return
    fi

    log "installing clt using brew method"

    sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    log "listing available software updates"
    softwareupdate -l || true

    clt_label=$(
        softwareupdate -l 2>/dev/null \
        | grep "Command Line Tools" \
        | sed -e 's/^ *\* *//' \
        | head -n 1
    )

    log "detected clt label: ${clt_label:-none}"

    if [ -n "${clt_label:-}" ]; then
        log "installing ${clt_label}"
        sudo softwareupdate -i "$clt_label" --verbose
        sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        log "clt installation complete"
    else
        sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        log "clt not available via softwareupdate"
        log "falling back to interactive installer"
        xcode-select --install
        exit 1
    fi
}

############################################
# ensure homebrew
############################################
ensure_homebrew() {

    log "checking for homebrew"

    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        log "brew found at /opt/homebrew"
        brew --version
        return
    fi

    if [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        log "brew found at /usr/local"
        brew --version
        return
    fi

    log "brew not found, installing"

    brew_install_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    log "downloading brew installer from $brew_install_url"

    curl -v -f -L "$brew_install_url" -o "$tmp_dir/brew-install.sh"

    ls -l "$tmp_dir/brew-install.sh"

    /bin/bash "$tmp_dir/brew-install.sh"

    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    log "brew installation complete"
    brew --version
}

############################################
# ensure rosetta (apple silicon only)
############################################
ensure_rosetta() {

    arch="$(uname -m)"
    log "detected architecture: $arch"

    if [ "$arch" != "arm64" ]; then
        log "not arm64, skipping rosetta"
        return
    fi

    if /usr/bin/pgrep oahd >/dev/null 2>&1; then
        log "rosetta already installed"
        return
    fi

    log "installing rosetta"
    sudo softwareupdate --install-rosetta --agree-to-license || true
}

############################################
# fetch brewfile
############################################
fetch_brewfile() {

    brewfile_url="$repo_raw_base/brewfile"
    log "fetching brewfile from $brewfile_url"

    curl -v -f -L "$brewfile_url" -o "$brewfile"

    log "brewfile saved to $brewfile"
    ls -l "$brewfile"

    log "brewfile content:"
    cat "$brewfile"
}

############################################
# sync brewfile
############################################
ensure_brew_bundle() {

    if [ ! -f "$brewfile" ]; then
        log "brewfile missing, skipping bundle"
        return
    fi

    log "running brew update"
    brew update

    log "running brew upgrade"
    brew upgrade

    log "running brew bundle"
    brew bundle --file="$brewfile" --verbose

    log "brew bundle complete"
}

############################################
# ensure mas login
############################################
ensure_mas_login() {

    if ! command -v mas >/dev/null 2>&1; then
        log "mas not installed"
        return
    fi

    if mas account >/dev/null 2>&1; then
        log "mas account detected"
    else
        log "no mas login detected"
    fi
}

############################################
# cleanup
############################################
cleanup() {

    log "running brew autoremove"
    brew autoremove || true

    log "running brew cleanup"
    brew cleanup || true
}

############################################
# main
############################################
main() {

    log "starting macos desired state"

    ensure_clt
    ensure_homebrew
    ensure_rosetta
    fetch_brewfile
    ensure_brew_bundle
    ensure_mas_login
    cleanup

    log "macos desired state complete"
}

main "$@"