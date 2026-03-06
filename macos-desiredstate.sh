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
# setup daily backup v3 (logging + idempotent)
############################################
setup_daily_backup() {

    log "checking daily backup setup"

    backup_script="$HOME/daily_backup.sh"
    launchagent_dir="$HOME/Library/LaunchAgents"
    launchagent_file="$launchagent_dir/com.local.dailybackup.plist"

    mkdir -p "$launchagent_dir"

    ########################################
    # write/update backup script (managed)
    ########################################

    if [ ! -f "$backup_script" ]; then
        log "creating daily_backup.sh"
    else
        log "daily_backup.sh exists, updating to managed version"
    fi

    cat > "$backup_script" <<'EOF'
#!/bin/bash

LOG_FILE="$HOME/backup/backup.log"
exec >> "$LOG_FILE" 2>&1

echo "======================================="
echo "$(date) - backup started"

SOURCE_DIR="$HOME/Desktop"
LOCAL_BACKUP_DIR="$HOME/backup"
CONFIG_FILE="$HOME/.daily_backup_smb_config"
MOUNT_POINT="/Volumes/dailybackup"

mkdir -p "$LOCAL_BACKUP_DIR"

############################################
# ask for smb config
############################################

if [ ! -f "$CONFIG_FILE" ]; then
    echo "no smb config found, prompting user"

    SMB_URL=$(osascript -e 'text returned of (display dialog "Enter SMB path (example: smb://server/share)" default answer "")')
    SMB_USER=$(osascript -e 'text returned of (display dialog "Enter SMB username" default answer "")')
    SMB_PASS=$(osascript -e 'text returned of (display dialog "Enter SMB password" default answer "" with hidden answer)')

    echo "$SMB_URL" > "$CONFIG_FILE"
    echo "$SMB_USER" >> "$CONFIG_FILE"

    security add-internet-password -a "$SMB_USER" -s "$SMB_URL" -w "$SMB_PASS" -U

    echo "smb config stored"
fi

SMB_URL=$(sed -n '1p' "$CONFIG_FILE")
SMB_USER=$(sed -n '2p' "$CONFIG_FILE")
SMB_PASS=$(security find-internet-password -a "$SMB_USER" -s "$SMB_URL" -w 2>/dev/null)

############################################
# create compressed backup
############################################

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DAILY_NAME="daily_$TIMESTAMP.tar.gz"
LOCAL_FILE="$LOCAL_BACKUP_DIR/$DAILY_NAME"

echo "creating archive $LOCAL_FILE"

tar -czf "$LOCAL_FILE" -C "$SOURCE_DIR" .
echo "archive created"

############################################
# local retention daily (keep 3)
############################################

echo "applying local daily retention"
ls -t "$LOCAL_BACKUP_DIR"/daily_*.tar.gz 2>/dev/null | tail -n +4 | xargs -r rm

############################################
# weekly (sunday)
############################################

DAY_OF_WEEK=$(date +%u)

if [ "$DAY_OF_WEEK" -eq 7 ]; then
    WEEKLY_NAME="weekly_$TIMESTAMP.tar.gz"
    WEEKLY_FILE="$LOCAL_BACKUP_DIR/$WEEKLY_NAME"

    echo "creating weekly backup"
    cp "$LOCAL_FILE" "$WEEKLY_FILE"

    echo "applying local weekly retention"
    ls -t "$LOCAL_BACKUP_DIR"/weekly_*.tar.gz 2>/dev/null | tail -n +3 | xargs -r rm
fi

############################################
# mount smb
############################################

if ! mount | grep -q "$MOUNT_POINT"; then
    echo "mounting smb share"
    mkdir -p "$MOUNT_POINT"
    mount_smbfs "//$SMB_USER:$SMB_PASS@${SMB_URL#smb://}" "$MOUNT_POINT"

    if [ $? -ne 0 ]; then
        echo "smb mount failed"
        exit 1
    fi

    echo "smb mounted"
else
    echo "smb already mounted"
fi

############################################
# copy to smb
############################################

echo "copying backup to smb"
cp "$LOCAL_FILE" "$MOUNT_POINT/"

############################################
# smb retention daily (14)
############################################

echo "applying smb daily retention"
ls -t "$MOUNT_POINT"/daily_*.tar.gz 2>/dev/null | tail -n +15 | xargs -r rm

############################################
# smb retention weekly (8)
############################################

echo "applying smb weekly retention"
ls -t "$MOUNT_POINT"/weekly_*.tar.gz 2>/dev/null | tail -n +9 | xargs -r rm

echo "$(date) - backup completed"
EOF

    chmod +x "$backup_script"

    ########################################
    # launchagent setup (idempotent)
    ########################################

    if [ ! -f "$launchagent_file" ]; then
        log "creating launchagent"

        cat > "$launchagent_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>

    <key>Label</key>
    <string>com.local.dailybackup</string>

    <key>ProgramArguments</key>
    <array>
        <string>$backup_script</string>
    </array>

    <key>StartInterval</key>
    <integer>3600</integer>

    <key>RunAtLoad</key>
    <true/>

</dict>
</plist>
EOF

        launchctl load "$launchagent_file"
        log "launchagent created and loaded"
    else
        log "launchagent already exists"

        if ! launchctl list | grep -q "com.local.dailybackup"; then
            log "launchagent not loaded, loading"
            launchctl load "$launchagent_file"
        fi
    fi

    log "daily backup setup verified"
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

    setup_daily_backup

    fetch_brewfile
    ensure_brew_bundle
    ensure_mas_login
    cleanup

    log "macos desired state complete"
}

main "$@"
