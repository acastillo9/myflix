#!/usr/bin/env bash
# MyFlix — Server Setup Script
# Run this ONCE on your Linux server to create the folder structure and permissions.
#
# Usage:
#   sudo bash setup-server.sh [DATA_ROOT] [PUID] [PGID]
#
# Defaults:
#   DATA_ROOT=/media/storage  PUID=1000  PGID=1000

set -euo pipefail

DATA_ROOT="${1:-/media/storage}"
PUID="${2:-1000}"
PGID="${3:-1000}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

if [ ! -d "$DATA_ROOT" ]; then
    error "$DATA_ROOT does not exist. Mount your storage drive first."
    echo "  Example: sudo mkdir -p $DATA_ROOT && sudo mount /dev/sdX1 $DATA_ROOT"
    exit 1
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

echo ""
echo "============================================="
echo "  MyFlix Server Setup"
echo "============================================="
echo "  DATA_ROOT : $DATA_ROOT"
echo "  PUID      : $PUID"
echo "  PGID      : $PGID"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# Create media library folders
# ---------------------------------------------------------------------------
echo "Creating media library folders..."
for dir in movies series anime music books; do
    mkdir -p "$DATA_ROOT/media/$dir"
    info "Created $DATA_ROOT/media/$dir"
done

# ---------------------------------------------------------------------------
# Create download category folders
# ---------------------------------------------------------------------------
echo ""
echo "Creating download folders..."
mkdir -p "$DATA_ROOT/downloads/torrents/incomplete"
for dir in movies series anime music books; do
    mkdir -p "$DATA_ROOT/downloads/torrents/$dir"
    info "Created $DATA_ROOT/downloads/torrents/$dir"
done

# ---------------------------------------------------------------------------
# Create appdata folders (container configs)
# ---------------------------------------------------------------------------
echo ""
echo "Creating appdata folders..."
for dir in jellyfin/config jellyfin/cache seerr radarr sonarr lidarr readarr kavita prowlarr bazarr qbittorrent; do
    mkdir -p "$DATA_ROOT/appdata/$dir"
    info "Created $DATA_ROOT/appdata/$dir"
done

# ---------------------------------------------------------------------------
# Set ownership and permissions
# ---------------------------------------------------------------------------
echo ""
echo "Setting ownership ($PUID:$PGID) and permissions..."
chown -R "$PUID:$PGID" "$DATA_ROOT"
chmod -R 2775 "$DATA_ROOT"
info "Ownership and permissions set (2775 with setgid)"

# ---------------------------------------------------------------------------
# Hardlink verification test
# ---------------------------------------------------------------------------
echo ""
echo "Running hardlink verification test..."
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

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo "  Setup Complete!"
echo "============================================="
echo ""
echo "  Folder structure:"
echo "    $DATA_ROOT/media/{movies,series,anime,music,books}"
echo "    $DATA_ROOT/downloads/torrents/{incomplete,movies,series,anime,music,books}"
echo "    $DATA_ROOT/appdata/{jellyfin,seerr,radarr,sonarr,...}"
echo ""
echo "  Next steps:"
echo "    1. Copy your .env.example to .env and edit it:"
echo "       cp .env.example .env"
echo "    2. Set DATA_ROOT=$DATA_ROOT in .env"
echo "    3. Start the stack:"
echo "       docker compose up -d"
echo ""
