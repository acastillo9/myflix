#!/usr/bin/env bash
# MyFlix — Initialize Radarr
# Configures Radarr with root folder and download client

set -euo pipefail

source "$(dirname "$0")/common.sh"

load_env

APP_NAME="Radarr"
API_URL="http://localhost:${RADARR_PORT}"
MARKER_FILE="${DATA_ROOT}/.init-radarr-done"
CONFIG_FILE="${APPDATA_ROOT:-$DATA_ROOT/appdata}/radarr/config.xml"
ROOT_FOLDER="/data/media/movies"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo "=========================================="
    echo "  Initializing $APP_NAME"
    echo "=========================================="
    echo ""

    # Wait for service
    wait_for_service "$APP_NAME" "${API_URL}/ping" 30 5

    # Get API key
    API_KEY=$(get_api_key "$CONFIG_FILE")
    
    if [ -z "$API_KEY" ]; then
        warn "Could not find API key in config. Radarr may need initial setup."
        echo "Please complete the initial setup in the web UI first:"
        echo "  http://your-server-ip:${RADARR_PORT}"
        echo ""
        echo "Then run this script again."
        exit 1
    fi

    info "Found API key: ${API_KEY:0:5}..."

    # Check if already initialized
    if is_initialized "$MARKER_FILE"; then
        info "$APP_NAME appears to already be initialized."
        read -rp "Re-run initialization? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Skipping."
            exit 0
        fi
    fi

    # Step 1: Configure root folder
    step "Configuring root folder: $ROOT_FOLDER"
    
    folder_payload="{
        \"path\": \"$ROOT_FOLDER\"
    }"

    curl -sf -X POST "${API_URL}/api/v3/rootFolder" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $API_KEY" \
        -d "$folder_payload" &>/dev/null || {
        warn "Root folder may already exist or failed to create"
    }

    info "Root folder configured"

    # Step 2: Configure qBittorrent download client
    step "Configuring qBittorrent download client..."
    
    download_client_payload='{
        "enable": true,
        "protocol": "torrent",
        "priority": 1,
        "removeCompletedDownloads": true,
        "removeFailedDownloads": true,
        "name": "qBittorrent",
        "fields": [
            { "name": "host", "value": "qbittorrent" },
            { "name": "port", "value": '${QBIT_WEBUI_PORT:-8085}' },
            { "name": "username", "value": "" },
            { "name": "password", "value": "" },
            { "name": "movieCategory", "value": "movies" },
            { "name": "recentTvPriority", "value": 0 },
            { "name": "olderTvPriority", "value": 0 },
            { "name": "initialState", "value": 0 }
        ],
        "implementation": "QBittorrent",
        "implementationName": "qBittorrent",
        "configContract": "QBittorrentSettings"
    }'

    response=$(curl -sf -X POST "${API_URL}/api/v3/downloadClient" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $API_KEY" \
        -d "$download_client_payload" 2>/dev/null || echo "")

    if [ -n "$response" ]; then
        info "qBittorrent download client configured"
    else
        warn "Download client may already exist or failed to create"
    fi

    # Step 3: Configure media management (hardlinks)
    step "Configuring media management settings..."
    
    media_management_payload='{
        "autoUnmonitorPreviouslyDownloadedMovies": false,
        "recycleBin": "",
        "recycleBinCleanupDays": 7,
        "downloadPropersAndRepacks": "preferAndUpgrade",
        "createEmptyMovieFolders": false,
        "deleteEmptyFolders": false,
        "fileDate": "none",
        "rescanAfterRefresh": "always",
        "autoRenameFolders": true,
        "pathsDefaultStatic": false,
        "allowHardcodedSubs": true,
        "importExtraFiles": false,
        "extraFileExtensions": "srt,nfo,png",
        "enableMediaInfo": true
    }'

    curl -sf -X PUT "${API_URL}/api/v3/config/mediamanagement" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $API_KEY" \
        -d "$media_management_payload" &>/dev/null || {
        warn "Failed to update media management settings"
    }

    # Mark as initialized
    mark_initialized "$MARKER_FILE"
    log_init "$APP_NAME" "Initialization completed"

    echo ""
    info "$APP_NAME initialization complete!"
    echo ""
    echo "Configured:"
    echo "  - Root folder: $ROOT_FOLDER"
    echo "  - Download client: qBittorrent"
    echo ""
    echo "Next steps:"
    echo "  1. Configure quality profiles via the Radarr web UI"
    echo "  2. Add indexers (via Prowlarr sync or manually)"
    echo "  3. Run: bash $(dirname "$0")/init-sonarr.sh"
}

main "$@"
