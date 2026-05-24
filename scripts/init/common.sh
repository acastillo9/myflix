#!/usr/bin/env bash
# MyFlix — Init Scripts Common Utilities
# Shared functions for declarative configuration scripts

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
# Load configuration from .env file
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

    # Set defaults
    DATA_ROOT="${DATA_ROOT:-/media/storage}"
    QBIT_WEBUI_PORT="${QBIT_WEBUI_PORT:-8085}"
    PROWLARR_PORT="${PROWLARR_PORT:-9696}"
    RADARR_PORT="${RADARR_PORT:-7878}"
    SONARR_PORT="${SONARR_PORT:-8989}"
    BAZARR_PORT="${BAZARR_PORT:-6767}"
    JELLYFIN_PORT="${JELLYFIN_PORT:-8096}"
    SEERR_PORT="${SEERR_PORT:-5055}"
}

# ---------------------------------------------------------------------------
# Wait for a service to be healthy
# ---------------------------------------------------------------------------
wait_for_service() {
    local service_name=$1
    local url=$2
    local max_attempts=${3:-30}
    local interval=${4:-5}

    step "Waiting for $service_name to be ready..."

    for ((i=1; i<=max_attempts; i++)); do
        if curl -sf "$url" &>/dev/null; then
            info "$service_name is ready!"
            return 0
        fi
        echo "  Attempt $i/$max_attempts... waiting ${interval}s"
        sleep "$interval"
    done

    error "$service_name failed to become ready after $((max_attempts * interval)) seconds"
    return 1
}

# ---------------------------------------------------------------------------
# Check if API key exists for a service
# ---------------------------------------------------------------------------
get_api_key() {
    local config_file=$1
    
    if [ -f "$config_file" ]; then
        # Try to extract API key from config file
        api_key=$(grep -oP '(?<=<ApiKey>)[^<]+' "$config_file" 2>/dev/null || \
                  grep -oP '(?<="ApiKey": ")[^"]+' "$config_file" 2>/dev/null || \
                  echo "")
        echo "$api_key"
    else
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# Test API connectivity
# ---------------------------------------------------------------------------
test_api() {
    local url=$1
    local api_key=$2
    
    if [ -n "$api_key" ]; then
        curl -sf -H "X-Api-Key: $api_key" "$url" &>/dev/null
    else
        curl -sf "$url" &>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# Check if already initialized (to avoid duplicate setup)
# ---------------------------------------------------------------------------
is_initialized() {
    local marker_file=$1
    [ -f "$marker_file" ]
}

mark_initialized() {
    local marker_file=$1
    touch "$marker_file"
}

# ---------------------------------------------------------------------------
# Log init activity
# ---------------------------------------------------------------------------
log_init() {
    local service=$1
    local message=$2
    local log_file="${DATA_ROOT}/logs/init.log"
    
    mkdir -p "$(dirname "$log_file")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$service] $message" >> "$log_file"
}
