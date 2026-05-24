#!/usr/bin/env bash
# MyFlix — Backup & Restore Script
# Backs up and restores container configurations (appdata) to prevent data loss.
#
# Usage:
#   sudo bash backup-restore.sh backup           # Create backup now
#   sudo bash backup-restore.sh restore          # List and restore from backup
#   sudo bash backup-restore.sh schedule         # Install daily backup cron job
#   sudo bash backup-restore.sh unschedule       # Remove cron job
#   sudo bash backup-restore.sh list             # List available backups

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
# Load configuration
# ---------------------------------------------------------------------------
load_env() {
    if [ ! -f "$ENV_FILE" ]; then
        error ".env file not found at $ENV_FILE"
        exit 1
    fi

    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    DATA_ROOT="${DATA_ROOT:-/media/storage}"
    APPDATA_ROOT="${APPDATA_ROOT:-$DATA_ROOT/appdata}"
    BACKUP_DIR="${DATA_ROOT}/backups"
    RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
}

# ---------------------------------------------------------------------------
# Ensure backup directory exists
# ---------------------------------------------------------------------------
ensure_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        step "Creating backup directory..."
        mkdir -p "$BACKUP_DIR"
        info "Created $BACKUP_DIR"
    fi
}

# ---------------------------------------------------------------------------
# Create backup
# ---------------------------------------------------------------------------
create_backup() {
    step "Creating backup..."

    if [ ! -d "$APPDATA_ROOT" ]; then
        error "APPDATA_ROOT directory does not exist: $APPDATA_ROOT"
        exit 1
    fi

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/myflix-backup-${TIMESTAMP}.tar.gz"

    echo "  Source: $APPDATA_ROOT"
    echo "  Destination: $BACKUP_FILE"
    echo "  This may take a few minutes..."
    echo ""

    # Create backup with progress
    tar -czf "$BACKUP_FILE" -C "$APPDATA_ROOT" . 2>/dev/null || {
        error "Failed to create backup"
        rm -f "$BACKUP_FILE"
        exit 1
    }

    # Get file size
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    info "Backup created: $BACKUP_FILE ($BACKUP_SIZE)"

    # Cleanup old backups
    cleanup_old_backups

    # Show disk usage
    show_disk_usage
}

# ---------------------------------------------------------------------------
# Cleanup old backups
# ---------------------------------------------------------------------------
cleanup_old_backups() {
    step "Cleaning up old backups (keeping last $RETENTION_DAYS days)..."

    DELETED_COUNT=0
    while IFS= read -r file; do
        rm -f "$file"
        info "Deleted old backup: $(basename "$file")"
        DELETED_COUNT=$((DELETED_COUNT + 1))
    done < <(find "$BACKUP_DIR" -name "myflix-backup-*.tar.gz" -type f -mtime +$RETENTION_DAYS 2>/dev/null)

    if [ $DELETED_COUNT -eq 0 ]; then
        info "No old backups to delete"
    else
        info "Deleted $DELETED_COUNT old backup(s)"
    fi
}

# ---------------------------------------------------------------------------
# List backups
# ---------------------------------------------------------------------------
list_backups() {
    step "Available backups:"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        warn "No backups found in $BACKUP_DIR"
        return
    fi

    echo ""
    printf "%-5s %-25s %-15s %-20s\n" "#" "Date" "Size" "Filename"
    echo "────────────────────────────────────────────────────────────────"

    COUNT=1
    for file in $(ls -t "$BACKUP_DIR"/myflix-backup-*.tar.gz 2>/dev/null); do
        if [ -f "$file" ]; then
            BASENAME=$(basename "$file")
            # Extract date from filename (myflix-backup-YYYYMMDD_HHMMSS.tar.gz)
            DATE_STR=$(echo "$BASENAME" | grep -oP '\d{8}_\d{6}' || echo "unknown")
            FORMATTED_DATE=$(date -d "${DATE_STR:0:8} ${DATE_STR:9:2}:${DATE_STR:11:2}:${DATE_STR:13:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$DATE_STR")
            SIZE=$(du -h "$file" | cut -f1)
            printf "%-5s %-25s %-15s %-20s\n" "$COUNT" "$FORMATTED_DATE" "$SIZE" "$BASENAME"
            COUNT=$((COUNT + 1))
        fi
    done
    echo ""
}

# ---------------------------------------------------------------------------
# Restore backup
# ---------------------------------------------------------------------------
restore_backup() {
    step "Restore from backup"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        error "No backups found in $BACKUP_DIR"
        exit 1
    fi

    # List backups and ask user to select
    list_backups

    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/myflix-backup-*.tar.gz 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -eq 0 ]; then
        error "No backup files found"
        exit 1
    fi

    read -rp "Enter backup number to restore [1-$BACKUP_COUNT]: " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$BACKUP_COUNT" ]; then
        error "Invalid selection"
        exit 1
    fi

    # Get selected file
    SELECTED_FILE=$(ls -t "$BACKUP_DIR"/myflix-backup-*.tar.gz 2>/dev/null | sed -n "${selection}p")

    if [ ! -f "$SELECTED_FILE" ]; then
        error "Selected backup file not found"
        exit 1
    fi

    echo ""
    warn "WARNING: This will OVERWRITE all current configurations!"
    warn "Source: $SELECTED_FILE"
    warn "Destination: $APPDATA_ROOT"
    echo ""
    read -rp "Are you sure you want to restore? Type 'yes' to confirm: " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Restore cancelled."
        exit 0
    fi

    # Stop containers before restore
    step "Stopping containers..."
    cd "$PROJECT_ROOT" && docker compose stop || true

    # Create safety backup of current state
    SAFETY_BACKUP="$BACKUP_DIR/myflix-backup-pre-restore-$(date +%Y%m%d_%H%M%S).tar.gz"
    step "Creating safety backup of current state..."
    tar -czf "$SAFETY_BACKUP" -C "$APPDATA_ROOT" . 2>/dev/null || warn "Could not create safety backup"
    info "Safety backup created: $SAFETY_BACKUP"

    # Clear existing appdata
    step "Clearing existing appdata..."
    rm -rf "${APPDATA_ROOT:?}"/*

    # Extract backup
    step "Extracting backup..."
    tar -xzf "$SELECTED_FILE" -C "$APPDATA_ROOT" || {
        error "Failed to extract backup"
        exit 1
    }

    # Set correct ownership
    step "Setting permissions..."
    PUID="${PUID:-1000}"
    PGID="${PGID:-1000}"
    chown -R "$PUID:$PGID" "$APPDATA_ROOT"
    chmod -R 2775 "$APPDATA_ROOT"

    # Restart containers
    step "Restarting containers..."
    cd "$PROJECT_ROOT" && docker compose up -d

    info "Restore completed successfully!"
    echo ""
    echo "Your services should now be available with the restored configuration."
}

# ---------------------------------------------------------------------------
# Schedule automatic backups
# ---------------------------------------------------------------------------
schedule_backup() {
    step "Installing daily backup cron job..."

    CRON_CMD="0 2 * * * $SCRIPT_DIR/backup-restore.sh backup >> $DATA_ROOT/backups/backup.log 2>&1"

    # Check if already scheduled
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_DIR/backup-restore.sh"; then
        warn "Backup is already scheduled"
        echo "Current cron entry:"
        crontab -l | grep "$SCRIPT_DIR/backup-restore.sh"
        return
    fi

    # Add to crontab
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -

    info "Daily backup scheduled at 2:00 AM"
    info "Logs will be saved to: $DATA_ROOT/backups/backup.log"
}

# ---------------------------------------------------------------------------
# Unschedule automatic backups
# ---------------------------------------------------------------------------
unschedule_backup() {
    step "Removing backup cron job..."

    if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_DIR/backup-restore.sh"; then
        warn "No backup cron job found"
        return
    fi

    # Remove from crontab
    crontab -l 2>/dev/null | grep -v "$SCRIPT_DIR/backup-restore.sh" | crontab -

    info "Backup cron job removed"
}

# ---------------------------------------------------------------------------
# Show disk usage
# ---------------------------------------------------------------------------
show_disk_usage() {
    if command -v df &>/dev/null; then
        echo ""
        step "Disk usage:"
        df -h "$DATA_ROOT" --output=source,size,used,avail,pcent | tail -1 | \
            awk '{printf "  Filesystem: %s\n  Total: %s\n  Used: %s (%s)\n  Available: %s\n", $1, $2, $3, $5, $4}'
    fi
}

# ---------------------------------------------------------------------------
# Show help
# ---------------------------------------------------------------------------
show_help() {
    cat << 'EOF'
MyFlix Backup & Restore Script

Usage:
  sudo bash backup-restore.sh <command>

Commands:
  backup      Create a backup of all container configurations now
  restore     List backups and restore from a selected one
  list        List all available backups
  schedule    Install daily backup cron job (runs at 2:00 AM)
  unschedule  Remove daily backup cron job
  help        Show this help message

Examples:
  # Create backup now
  sudo bash backup-restore.sh backup

  # Restore from a previous backup
  sudo bash backup-restore.sh restore

  # Set up automatic daily backups
  sudo bash backup-restore.sh schedule

Configuration:
  Set BACKUP_RETENTION_DAYS in your .env file to control how many
  days of backups to keep (default: 30).

EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi

    load_env
    ensure_backup_dir

    case "$1" in
        backup)
            create_backup
            ;;
        restore)
            restore_backup
            ;;
        list)
            list_backups
            ;;
        schedule)
            schedule_backup
            ;;
        unschedule)
            unschedule_backup
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
