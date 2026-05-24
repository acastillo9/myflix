#!/usr/bin/env bash
# MyFlix — Initialize Prowlarr
# Configures Prowlarr with FlareSolverr proxy

set -euo pipefail

source "$(dirname "$0")/common.sh"

load_env

APP_NAME="Prowlarr"
API_URL="http://localhost:${PROWLARR_PORT}"
MARKER_FILE="${DATA_ROOT}/.init-prowlarr-done"
CONFIG_FILE="${APPDATA_ROOT:-$DATA_ROOT/appdata}/prowlarr/config.xml"

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
        warn "Could not find API key in config. Prowlarr may need initial setup."
        echo "Please complete the initial setup in the web UI first:"
        echo "  http://your-server-ip:${PROWLARR_PORT}"
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

    step "Configuring FlareSolverr proxy..."
    
    # Add FlareSolverr proxy
    proxy_payload='{
        "name": "FlareSolverr",
        "fields": [
            { "name": "host", "value": "flaresolverr" },
            { "name": "port", "value": 8191 },
            { "name": "requestTimeout", "value": 60 }
        ],
        "implementation": "FlareSolverr",
        "implementationName": "FlareSolverr",
        "configContract": "FlareSolverrSettings"
    }'

    response=$(curl -sf -X POST "${API_URL}/api/v1/indexerProxy" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $API_KEY" \
        -d "$proxy_payload" 2>/dev/null || echo "")

    if [ -n "$response" ]; then
        info "FlareSolverr proxy configured successfully"
    else
        warn "Failed to configure FlareSolverr proxy (may already exist)"
    fi

    # Mark as initialized
    mark_initialized "$MARKER_FILE"
    log_init "$APP_NAME" "Initialization completed"

    echo ""
    info "$APP_NAME initialization complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Add indexers via the Prowlarr web UI"
    echo "  2. Sync indexers to Radarr and Sonarr"
    echo "  3. Run: bash $(dirname "$0")/init-radarr.sh"
}

main "$@"
