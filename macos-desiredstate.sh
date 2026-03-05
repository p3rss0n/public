#!/usr/bin/env bash

set -euo pipefail
set -x

############################################
# macos desired state - full debug
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
# ensure command line tools
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

    softwareupdate -l || true

    clt_label=$(
        softwareupdate -l 2>/dev/null \
        | grep "Command Line Tools" \
        | sed -e 's/^ *\* *//' \
        | head -n 1
    )

    log "detected clt label: ${clt_label:-none}"

    if [ -n "${clt_label:-}" ]; then
        sudo softwareupdate -i "$clt_label" --verbose
        sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        log "clt installation complete"
    else
        sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        log "clt not available via softwareupdate"
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
        brew --version
        return
    fi

    if [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        brew --version
        return
    fi

    log "brew not found, installing"

    brew_install_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    curl -v -f -L "$brew_install_url" -o "$tmp_dir/brew-install.sh"

    /bin/bash "$tmp_dir/brew-install.sh"

    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    brew --version
}

############################################
# ensure rosetta (apple silicon only)
############################################
ensure_rosetta() {

    arch="$(uname -m)"
    log "architecture: $arch"

    if [ "$arch" != "arm64" ]; then
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
# reset dock once
############################################
reset_dock_once() {

    dock_flag="$HOME/.macos_desiredstate_dock_reset_done"

    if [ -f "$dock_flag" ]; then
        log "dock already reset previously. skipping."
        return
    fi

    log "performing one-time full dock reset"

    defaults write com.apple.dock persistent-apps -array
    defaults write com.apple.dock persistent-others -array

    killall Dock

    touch "$dock_flag"

    log "dock reset complete (will not run again)"
}

############################################
# fetch brewfile
############################################
fetch_brewfile() {

    brewfile_url="$repo_raw_base/brewfile"
    log "fetching brewfile from $brewfile_url"

    curl -v -f -L "$brewfile_url" -o "$brewfile"

    ls -l "$brewfile"
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

    brew update
    brew upgrade
    brew bundle --file="$brewfile" --verbose
}

############################################
# ensure mas login
############################################
ensure_mas_login() {

    if ! command -v mas >/dev/null 2>&1; then
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

    brew autoremove || true
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

    reset_dock_once

    fetch_brewfile
    ensure_brew_bundle
    ensure_mas_login
    cleanup

    log "macos desired state complete"
}

main "$@"
