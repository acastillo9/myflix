#!/usr/bin/env bash
# MyFlix — Download Cleanup Script
# Safely removes completed downloads (and optionally old media) to reclaim disk space.
#
# Modes (set via CLEANUP_MODE env var or .env file):
#   ephemeral  — deletes media AND downloads older than CLEANUP_MAX_AGE_HOURS (default 48h)
#                Use when you have limited storage and treat the server as a streaming cache.
#   persistent — deletes only downloads that have been hardlinked (link count >= 2)
#                and are older than CLEANUP_MAX_AGE_HOURS (default 168h / 7 days).
#                Preserves the media library.
#
# Usage:
#   bash cleanup-downloads.sh                    # uses defaults or .env
#   CLEANUP_MODE=ephemeral bash cleanup-downloads.sh
#
# Cron example (runs daily at 3 AM):
#   0 3 * * * /opt/myflix/scripts/cleanup-downloads.sh >> /var/log/myflix-cleanup.log 2>&1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env if present (looks in parent directory of scripts/)
ENV_FILE="$SCRIPT_DIR/../.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DATA_ROOT="${DATA_ROOT:-/media/storage}"
CLEANUP_MODE="${CLEANUP_MODE:-ephemeral}"
CLEANUP_MAX_AGE_HOURS="${CLEANUP_MAX_AGE_HOURS:-48}"
MAX_AGE_MINUTES=$((CLEANUP_MAX_AGE_HOURS * 60))

DOWNLOAD_DIR="$DATA_ROOT/downloads/torrents"
MEDIA_DIR="$DATA_ROOT/media"
INCOMPLETE_DIR="$DOWNLOAD_DIR/incomplete"
LOG_TAG="myflix-cleanup"

# Counters
deleted=0
skipped=0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $1"; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if [ ! -d "$DOWNLOAD_DIR" ]; then
    log "ERROR: Download directory not found: $DOWNLOAD_DIR"
    exit 1
fi

log "Starting cleanup — mode=$CLEANUP_MODE, max_age=${CLEANUP_MAX_AGE_HOURS}h, data_root=$DATA_ROOT"

# ---------------------------------------------------------------------------
# Clean downloads directory (both modes)
# ---------------------------------------------------------------------------
log "Cleaning downloads directory: $DOWNLOAD_DIR"

while IFS= read -r -d '' file; do
    # Never touch incomplete downloads
    if [[ "$file" == "$INCOMPLETE_DIR"/* ]]; then
        continue
    fi

    # Check age
    if [ -z "$(find "$file" -maxdepth 0 -mmin +"$MAX_AGE_MINUTES" -print 2>/dev/null)" ]; then
        skipped=$((skipped + 1))
        continue
    fi

    if [ "$CLEANUP_MODE" = "persistent" ]; then
        # In persistent mode, only delete if hardlinked (library copy exists)
        links=$(stat -c '%h' "$file" 2>/dev/null || echo "1")
        if [ "$links" -lt 2 ]; then
            skipped=$((skipped + 1))
            log "SKIP (no library copy, links=$links): $file"
            continue
        fi
    fi

    rm -f "$file" && {
        deleted=$((deleted + 1))
        log "DELETED download: $file"
    }
done < <(find "$DOWNLOAD_DIR" -maxdepth 3 -type f \
    -not -path "$INCOMPLETE_DIR/*" \
    -not -name ".hardlink-test" \
    -print0 2>/dev/null)

# Remove empty directories in downloads (keep category roots and incomplete)
find "$DOWNLOAD_DIR" -mindepth 2 -type d -empty \
    -not -name "incomplete" \
    -not -name "movies" \
    -not -name "series" \
    -not -name "anime" \
    -not -name "music" \
    -not -name "books" \
    -delete 2>/dev/null || true

# ---------------------------------------------------------------------------
# Clean media directory (ephemeral mode only)
# ---------------------------------------------------------------------------
if [ "$CLEANUP_MODE" = "ephemeral" ]; then
    log "Cleaning media directory (ephemeral mode): $MEDIA_DIR"

    while IFS= read -r -d '' file; do
        # Check age
        if [ -z "$(find "$file" -maxdepth 0 -mmin +"$MAX_AGE_MINUTES" -print 2>/dev/null)" ]; then
            skipped=$((skipped + 1))
            continue
        fi

        rm -f "$file" && {
            deleted=$((deleted + 1))
            log "DELETED media: $file"
        }
    done < <(find "$MEDIA_DIR" -maxdepth 4 -type f \
        -not -name ".hardlink-test" \
        -not -name "*.nfo" \
        -print0 2>/dev/null)

    # Remove empty directories in media (keep category roots)
    find "$MEDIA_DIR" -mindepth 2 -type d -empty \
        -not -name "movies" \
        -not -name "series" \
        -not -name "anime" \
        -not -name "music" \
        -not -name "books" \
        -delete 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "Complete — deleted=$deleted skipped=$skipped"

# Report disk usage
if command -v df &>/dev/null; then
    FREE=$(df -h "$DATA_ROOT" --output=avail | tail -1 | tr -d ' ')
    USED=$(df -h "$DATA_ROOT" --output=pcent | tail -1 | tr -d ' ')
    log "Disk: ${USED} used, ${FREE} available on $DATA_ROOT"
fi
