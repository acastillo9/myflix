#!/usr/bin/env bash
# MyFlix — Initialize Jellyfin
# Checks that Jellyfin is reachable and guides through the manual steps
# that cannot be automated (library creation, user accounts).

set -euo pipefail

source "$(dirname "$0")/common.sh"

load_env

APP_NAME="Jellyfin"
API_URL="http://localhost:${JELLYFIN_PORT:-8096}"
MARKER_FILE="${DATA_ROOT}/.init-jellyfin-done"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo "=========================================="
    echo "  Initializing $APP_NAME"
    echo "=========================================="
    echo ""

    # Wait for service
    wait_for_service "$APP_NAME" "${API_URL}/health" 30 5

    # Check if already initialized
    if is_initialized "$MARKER_FILE"; then
        info "$APP_NAME appears to already be initialized."
        read -rp "Re-run initialization? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Skipping."
            exit 0
        fi
    fi

    info "Jellyfin is reachable at ${API_URL}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Jellyfin requires manual setup via the web UI."
    echo "  Open: http://your-server-ip:${JELLYFIN_PORT:-8096}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Step 1 — Complete the initial setup wizard"
    echo "    • Create an admin user and password"
    echo "    • Choose your preferred language"
    echo ""
    echo "  Step 2 — Add media libraries (Dashboard → Libraries → Add)"
    echo ""
    echo "    Library       | Type   | Folder"
    echo "    ──────────────|────────|─────────────────────"
    echo "    Movies        | Movies | /data/media/movies"
    echo "    Series        | Shows  | /data/media/series"
    echo "    Anime         | Shows  | /data/media/anime"
    echo "    Music         | Music  | /data/media/music"
    echo "    Books         | Books  | /data/media/books"
    echo "    Now Downloading | Mixed | /data/downloads"
    echo ""
    echo "  Step 3 — Get the API key for Seerr"
    echo "    Dashboard → API Keys → + → copy the key"
    echo ""
    echo "  Step 4 — Configure Seerr to connect to Jellyfin"
    echo "    Open: http://your-server-ip:${SEERR_PORT:-5055}"
    echo "    • Set Jellyfin URL: http://jellyfin:${JELLYFIN_PORT:-8096}"
    echo "    • Paste the API key from Step 3"
    echo ""
    echo "  Step 5 — Connect Seerr to Radarr and Sonarr"
    echo "    Seerr → Settings → Services:"
    echo "    • Radarr:  http://radarr:${RADARR_PORT:-7878}  (get key from Radarr → Settings → General)"
    echo "    • Sonarr:  http://sonarr:${SONARR_PORT:-8989}  (get key from Sonarr → Settings → General)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    read -rp "Have you completed the Jellyfin setup? Mark as done? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        mark_initialized "$MARKER_FILE"
        log_init "$APP_NAME" "Initialization marked complete by user"
        echo ""
        info "Jellyfin marked as initialized."
        echo ""
        echo "Your MyFlix stack is now fully configured!"
        echo ""
        echo "Service URLs:"
        echo "  Jellyfin:    http://your-server:${JELLYFIN_PORT:-8096}"
        echo "  Seerr:       http://your-server:${SEERR_PORT:-5055}"
        echo "  Radarr:      http://your-server:${RADARR_PORT:-7878}"
        echo "  Sonarr:      http://your-server:${SONARR_PORT:-8989}"
        echo "  Bazarr:      http://your-server:${BAZARR_PORT:-6767}"
        echo "  Prowlarr:    http://your-server:${PROWLARR_PORT:-9696}"
        echo "  qBittorrent: http://your-server:${QBIT_WEBUI_PORT:-8085}"
        echo ""
    else
        echo ""
        warn "Setup not marked as complete. Re-run this script when done."
    fi
}

main "$@"
