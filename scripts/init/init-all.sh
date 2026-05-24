#!/usr/bin/env bash
# MyFlix — Initialize All Services
# Runs all initialization scripts in the correct order

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    load_env

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         MyFlix — Automated Service Initialization          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    warn "IMPORTANT: Ensure all containers are running before proceeding."
    echo ""
    read -rp "Are all containers running and ready? [y/N] " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Please start the stack first:"
        echo "  docker compose up -d"
        echo ""
        echo "Then run this script again."
        exit 0
    fi

    echo ""
    step "Starting initialization of all services..."
    echo ""

    # Define initialization order
    declare -a INIT_SCRIPTS=(
        "init-prowlarr.sh:Configure Prowlarr with FlareSolverr"
        "init-radarr.sh:Configure Radarr with qBittorrent"
        "init-sonarr.sh:Configure Sonarr with qBittorrent"
        "init-bazarr.sh:Configure Bazarr with Radarr/Sonarr"
        "init-jellyfin.sh:Guide Jellyfin and Seerr setup"
    )

    failed_scripts=()

    for item in "${INIT_SCRIPTS[@]}"; do
        script="${item%%:*}"
        description="${item##*:}"
        
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "  $description"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""

        if [ -f "$SCRIPT_DIR/$script" ]; then
            if bash "$SCRIPT_DIR/$script"; then
                info "$script completed successfully"
            else
                error "$script failed"
                failed_scripts+=("$script")
                echo ""
                read -rp "Continue with remaining scripts? [y/N] " continue
                if [[ ! "$continue" =~ ^[Yy]$ ]]; then
                    break
                fi
            fi
        else
            warn "Script not found: $script"
        fi
    done

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Initialization Complete!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    if [ ${#failed_scripts[@]} -eq 0 ]; then
        info "All services initialized successfully!"
    else
        warn "Some scripts failed:"
        for script in "${failed_scripts[@]}"; do
            echo "  - $script"
        done
        echo ""
        echo "You may need to complete configuration manually via the web UIs."
    fi

    echo ""
    echo "Manual configuration still required:"
    echo "  1. Add indexers in Prowlarr and sync to Radarr/Sonarr"
    echo "  2. Configure quality profiles in Radarr/Sonarr"
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
}

main "$@"
