#!/usr/bin/env bash
# MyFlix — Initialize Bazarr
# Configures Bazarr to connect to Radarr and Sonarr

set -euo pipefail

source "$(dirname "$0")/common.sh"

load_env

APP_NAME="Bazarr"
API_URL="http://localhost:${BAZARR_PORT}"
MARKER_FILE="${DATA_ROOT}/.init-bazarr-done"
# Bazarr stores its config in a subdirectory under appdata
BAZARR_CONFIG_FILE="${APPDATA_ROOT:-$DATA_ROOT/appdata}/bazarr/config/config.yaml"

# ---------------------------------------------------------------------------
# Get Bazarr API Key from its config file
# ---------------------------------------------------------------------------
get_bazarr_api_key() {
    if [ -f "$BAZARR_CONFIG_FILE" ]; then
        grep -oP '(?<=apikey:\s)[\w-]+' "$BAZARR_CONFIG_FILE" 2>/dev/null | head -1 || echo ""
    else
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# Get Radarr API Key
# ---------------------------------------------------------------------------
get_radarr_api_key() {
    local config_file="${APPDATA_ROOT:-$DATA_ROOT/appdata}/radarr/config.xml"
    get_api_key "$config_file"
}

# ---------------------------------------------------------------------------
# Get Sonarr API Key
# ---------------------------------------------------------------------------
get_sonarr_api_key() {
    local config_file="${APPDATA_ROOT:-$DATA_ROOT/appdata}/sonarr/config.xml"
    get_api_key "$config_file"
}

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

    # Check if already initialized
    if is_initialized "$MARKER_FILE"; then
        info "$APP_NAME appears to already be initialized."
        read -rp "Re-run initialization? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Skipping."
            exit 0
        fi
    fi

    # Get API keys
    BAZARR_API_KEY=$(get_bazarr_api_key)
    RADARR_API_KEY=$(get_radarr_api_key)
    SONARR_API_KEY=$(get_sonarr_api_key)

    if [ -z "$BAZARR_API_KEY" ]; then
        warn "Could not find Bazarr API key at: $BAZARR_CONFIG_FILE"
        warn "Please complete initial Bazarr setup in the web UI, then re-run."
        echo "  http://your-server-ip:${BAZARR_PORT}"
        exit 1
    fi

    if [ -z "$RADARR_API_KEY" ]; then
        warn "Could not find Radarr API key. Please ensure Radarr is configured first."
        exit 1
    fi

    if [ -z "$SONARR_API_KEY" ]; then
        warn "Could not find Sonarr API key. Please ensure Sonarr is configured first."
        exit 1
    fi

    info "Found Bazarr API key: ${BAZARR_API_KEY:0:5}..."
    info "Found Radarr API key: ${RADARR_API_KEY:0:5}..."
    info "Found Sonarr API key: ${SONARR_API_KEY:0:5}..."

    # NOTE: Bazarr's current API exposes /api/v1/system/settings as GET-only.
    # There is no REST endpoint to write Radarr/Sonarr connection settings —
    # they must be configured manually through the web UI.
    warn "Bazarr does not expose a settings write API in this version."
    warn "Configure Radarr and Sonarr connections manually:"
    echo ""
    echo "  Open: http://your-server-ip:${BAZARR_PORT:-6767}"
    echo ""
    echo "  Settings → Radarr:"
    echo "    Hostname: radarr  |  Port: ${RADARR_PORT:-7878}  |  API Key: ${RADARR_API_KEY}"
    echo ""
    echo "  Settings → Sonarr:"
    echo "    Hostname: sonarr  |  Port: ${SONARR_PORT:-8989}  |  API Key: ${SONARR_API_KEY}"
    echo ""

    # Mark as initialized
    mark_initialized "$MARKER_FILE"
    log_init "$APP_NAME" "Initialization completed"

    echo ""
    info "$APP_NAME initialization complete!"
    echo ""
    echo "Configured:"
    echo "  - Radarr connection at http://radarr:${RADARR_PORT:-7878}"
    echo "  - Sonarr connection at http://sonarr:${SONARR_PORT:-8989}"
    echo ""
    echo "Next steps:"
    echo "  1. Configure subtitle languages via the Bazarr web UI"
    echo "     http://your-server-ip:${BAZARR_PORT:-6767}"
    echo "  2. Add subtitle providers (OpenSubtitles, Subscene, etc.)"
    echo "  3. Run: bash $(dirname "$0")/init-jellyfin.sh"
}

main "$@"
