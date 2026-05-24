#!/usr/bin/env bash
# MyFlix — Log Rotation Setup
# Configures log rotation for MyFlix logs.
# Uses envsubst to expand ${DATA_ROOT}, ${PUID}, ${PGID} from .env into the
# installed /etc/logrotate.d/myflix config (logrotate cannot expand shell vars).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Load .env so DATA_ROOT / PUID / PGID are available for envsubst
    if [ ! -f "$ENV_FILE" ]; then
        error ".env file not found at $ENV_FILE"
        echo "Please create it first: cp $PROJECT_ROOT/.env.example $PROJECT_ROOT/.env"
        exit 1
    fi
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a

    DATA_ROOT="${DATA_ROOT:-/media/storage}"
    PUID="${PUID:-1000}"
    PGID="${PGID:-1000}"

    echo "Setting up log rotation for MyFlix..."

    # Check dependencies
    if ! command -v logrotate &>/dev/null; then
        error "logrotate is not installed. Please install it first:"
        echo "  apt-get install logrotate    # Debian/Ubuntu"
        echo "  yum install logrotate        # RHEL/CentOS"
        exit 1
    fi
    if ! command -v envsubst &>/dev/null; then
        error "envsubst is not installed (part of gettext). Please install it first:"
        echo "  apt-get install gettext-base    # Debian/Ubuntu"
        echo "  yum install gettext             # RHEL/CentOS"
        exit 1
    fi

    TEMPLATE="$PROJECT_ROOT/config/logrotate.d/myflix"
    if [ ! -f "$TEMPLATE" ]; then
        error "Logrotate template not found at $TEMPLATE"
        exit 1
    fi

    # Expand variables and install
    export DATA_ROOT PUID PGID
    envsubst '${DATA_ROOT} ${PUID} ${PGID}' < "$TEMPLATE" > /etc/logrotate.d/myflix
    info "Log rotation configuration installed at /etc/logrotate.d/myflix"
    info "  DATA_ROOT  : $DATA_ROOT"
    info "  PUID/PGID  : $PUID/$PGID"

    # Verify the expanded config is valid
    if logrotate -d /etc/logrotate.d/myflix &>/dev/null; then
        info "Configuration test passed"
    else
        warn "Configuration test failed — check /etc/logrotate.d/myflix manually"
    fi

    echo ""
    echo "Log rotation is now configured to run daily via cron."
    echo "Logs will be kept for 7 days (daily) or 4 weeks (weekly)."
}

main "$@"
