#!/usr/bin/env bash
# MyFlix — Server Setup Script
# Run this ONCE on your Linux server to create the folder structure and permissions.
#
# Usage:
#   sudo bash setup-server.sh
#
# This script reads configuration from the .env file in the project root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# ---------------------------------------------------------------------------
# Load configuration from .env file
# ---------------------------------------------------------------------------
load_env() {
    if [ ! -f "$ENV_FILE" ]; then
        error ".env file not found at $ENV_FILE"
        echo ""
        echo "Please create the .env file first:"
        echo "  cp $PROJECT_ROOT/.env.example $PROJECT_ROOT/.env"
        echo "  nano $PROJECT_ROOT/.env  # Edit with your values"
        exit 1
    fi

    step "Loading configuration from .env..."
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    # Set defaults if not in .env
    PUID="${PUID:-1000}"
    PGID="${PGID:-1000}"
    DATA_ROOT="${DATA_ROOT:-/media/storage}"
    APPDATA_ROOT="${APPDATA_ROOT:-$DATA_ROOT/appdata}"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
preflight_checks() {
    step "Running preflight checks..."

    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi

    if [ ! -d "$DATA_ROOT" ]; then
        error "DATA_ROOT directory does not exist: $DATA_ROOT"
        echo ""
        echo "  Please mount your storage drive first:"
        echo "    sudo mkdir -p $DATA_ROOT"
        echo "    sudo mount /dev/sdX1 $DATA_ROOT"
        echo ""
        echo "  Or update DATA_ROOT in your .env file to the correct path."
        exit 1
    fi

    # Verify APPDATA_ROOT is a subdirectory of DATA_ROOT or separate but valid
    if [[ ! "$APPDATA_ROOT" =~ ^$DATA_ROOT ]]; then
        if [ ! -d "$APPDATA_ROOT" ]; then
            warn "APPDATA_ROOT ($APPDATA_ROOT) is outside DATA_ROOT and doesn't exist"
            read -rp "Create $APPDATA_ROOT? [y/N] " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                mkdir -p "$APPDATA_ROOT"
            else
                error "Setup aborted. Please update APPDATA_ROOT in .env"
                exit 1
            fi
        fi
    fi

    # Verify it's a real filesystem (not just a directory on the root partition)
    ROOT_DEV=$(df --output=source / | tail -1)
    DATA_DEV=$(df --output=source "$DATA_ROOT" | tail -1)
    if [ "$ROOT_DEV" = "$DATA_DEV" ]; then
        warn "$DATA_ROOT is on the root filesystem. This will work but eats into your OS disk."
        warn "For production use, mount a dedicated drive at $DATA_ROOT."
        echo ""
        read -rp "Continue anyway? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
}

# ---------------------------------------------------------------------------
# Display configuration
# ---------------------------------------------------------------------------
show_config() {
    echo ""
    echo "============================================="
    echo "  MyFlix Server Setup"
    echo "============================================="
    echo "  DATA_ROOT      : $DATA_ROOT"
    echo "  APPDATA_ROOT   : $APPDATA_ROOT"
    echo "  PUID           : $PUID"
    echo "  PGID           : $PGID"
    echo "============================================="
    echo ""
    read -rp "Does this configuration look correct? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted. Please edit $ENV_FILE and run again."
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# Create media library folders
# ---------------------------------------------------------------------------
create_media_folders() {
    step "Creating media library folders..."
    for dir in movies series anime music books; do
        mkdir -p "$DATA_ROOT/media/$dir"
        info "Created $DATA_ROOT/media/$dir"
    done
}

# ---------------------------------------------------------------------------
# Create download category folders
# ---------------------------------------------------------------------------
create_download_folders() {
    step "Creating download folders..."
    mkdir -p "$DATA_ROOT/downloads/torrents/incomplete"
    for dir in movies series anime music books; do
        mkdir -p "$DATA_ROOT/downloads/torrents/$dir"
        info "Created $DATA_ROOT/downloads/torrents/$dir"
    done
}

# ---------------------------------------------------------------------------
# Create appdata folders (container configs)
# ---------------------------------------------------------------------------
create_appdata_folders() {
    step "Creating appdata folders..."
    for dir in jellyfin/config jellyfin/cache seerr radarr sonarr lidarr readarr kavita prowlarr bazarr qbittorrent; do
        mkdir -p "$APPDATA_ROOT/$dir"
        info "Created $APPDATA_ROOT/$dir"
    done
}

# ---------------------------------------------------------------------------
# Create backup folder
# ---------------------------------------------------------------------------
create_backup_folder() {
    step "Creating backup folder..."
    mkdir -p "$DATA_ROOT/backups"
    info "Created $DATA_ROOT/backups"
}

# ---------------------------------------------------------------------------
# Set ownership and permissions
# ---------------------------------------------------------------------------
set_permissions() {
    step "Setting ownership ($PUID:$PGID) and permissions..."
    chown -R "$PUID:$PGID" "$DATA_ROOT"
    chmod -R 2775 "$DATA_ROOT"

    # If APPDATA_ROOT is separate, set its permissions too
    if [[ ! "$APPDATA_ROOT" =~ ^$DATA_ROOT ]]; then
        chown -R "$PUID:$PGID" "$APPDATA_ROOT"
        chmod -R 2775 "$APPDATA_ROOT"
    fi

    info "Ownership and permissions set (2775 with setgid)"
}

# ---------------------------------------------------------------------------
# Hardlink verification test
# ---------------------------------------------------------------------------
verify_hardlinks() {
    step "Running hardlink verification test..."
    TEST_SRC="$DATA_ROOT/downloads/torrents/.hardlink-test"
    TEST_DST="$DATA_ROOT/media/.hardlink-test"

    echo "hardlink-test" > "$TEST_SRC"
    if ln "$TEST_SRC" "$TEST_DST" 2>/dev/null; then
        SRC_INODE=$(stat -c '%i' "$TEST_SRC")
        DST_INODE=$(stat -c '%i' "$TEST_DST")
        if [ "$SRC_INODE" = "$DST_INODE" ]; then
            info "Hardlinks work! (inode $SRC_INODE)"
        else
            error "Hardlink created but inodes differ — filesystem issue"
        fi
        rm -f "$TEST_SRC" "$TEST_DST"
    else
        error "Hardlinks FAILED between downloads/ and media/"
        error "Are they on the same filesystem? Check with: df $DATA_ROOT/downloads $DATA_ROOT/media"
        rm -f "$TEST_SRC"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
main() {
    load_env
    preflight_checks
    show_config
    create_media_folders
    create_download_folders
    create_appdata_folders
    create_backup_folder
    set_permissions
    verify_hardlinks

    echo ""
    echo "============================================="
    echo "  Setup Complete!"
    echo "============================================="
    echo ""
    echo "  Folder structure:"
    echo "    $DATA_ROOT/media/{movies,series,anime,music,books}"
    echo "    $DATA_ROOT/downloads/torrents/{incomplete,movies,series,anime,music,books}"
    echo "    $APPDATA_ROOT/{jellyfin,seerr,radarr,sonarr,...}"
    echo "    $DATA_ROOT/backups/  (for automated backups)"
    echo ""
    echo "  Next steps:"
    echo "    1. Start the stack:"
    echo "       docker compose up -d"
    echo "    2. Configure services (see README.md)"
    echo "    3. Set up automated backups:"
    echo "       sudo bash $SCRIPT_DIR/backup-restore.sh schedule"
    echo ""
}

main "$@"
