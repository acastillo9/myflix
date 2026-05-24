#!/usr/bin/env bash
# MyFlix — Health Check Script
# Monitors all services and sends email alerts on failures
#
# Usage:
#   bash healthcheck.sh                    # Run check once
#   bash healthcheck.sh schedule           # Install cron job (runs every 5 minutes)
#   bash healthcheck.sh unschedule         # Remove cron job
#   bash healthcheck.sh status             # Show service status

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
    if [ -f "$ENV_FILE" ]; then
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
    fi

    DATA_ROOT="${DATA_ROOT:-/media/storage}"
    HEALTHCHECK_ALERT_EMAIL="${HEALTHCHECK_ALERT_EMAIL:-}"
    
    # Service ports
    JELLYFIN_PORT="${JELLYFIN_PORT:-8096}"
    SEERR_PORT="${SEERR_PORT:-5055}"
    RADARR_PORT="${RADARR_PORT:-7878}"
    SONARR_PORT="${SONARR_PORT:-8989}"
    LIDARR_PORT="${LIDARR_PORT:-8686}"
    READARR_PORT="${READARR_PORT:-8787}"
    KAVITA_PORT="${KAVITA_PORT:-5000}"
    PROWLARR_PORT="${PROWLARR_PORT:-9696}"
    BAZARR_PORT="${BAZARR_PORT:-6767}"
    QBIT_WEBUI_PORT="${QBIT_WEBUI_PORT:-8085}"
    FLARESOLVERR_PORT="${FLARESOLVERR_PORT:-8191}"
}

# ---------------------------------------------------------------------------
# Service definitions
# ---------------------------------------------------------------------------
declare -A SERVICES
declare -A SERVICE_URLS

init_services() {
    SERVICES=(
        ["jellyfin"]="Jellyfin Media Server"
        ["seerr"]="Overseerr Request Manager"
        ["radarr"]="Radarr Movie Manager"
        ["sonarr"]="Sonarr TV Manager"
        ["prowlarr"]="Prowlarr Indexer Manager"
        ["bazarr"]="Bazarr Subtitle Manager"
        ["qbittorrent"]="qBittorrent Download Client"
        ["flaresolverr"]="FlareSolverr Cloudflare Bypass"
        ["watchtower"]="Watchtower Auto-Updater"
        ["lidarr"]="Lidarr Music Manager"
        ["readarr"]="Readarr Book Manager"
        ["kavita"]="Kavita Book Reader"
    )

    SERVICE_URLS=(
        ["jellyfin"]="http://localhost:${JELLYFIN_PORT}/health"
        ["seerr"]="http://localhost:${SEERR_PORT}/api/v1/status"
        ["radarr"]="http://localhost:${RADARR_PORT}/ping"
        ["sonarr"]="http://localhost:${SONARR_PORT}/ping"
        ["prowlarr"]="http://localhost:${PROWLARR_PORT}/ping"
        ["bazarr"]="http://localhost:${BAZARR_PORT}/ping"
        ["qbittorrent"]="http://localhost:${QBIT_WEBUI_PORT}"
        ["flaresolverr"]="http://localhost:${FLARESOLVERR_PORT}"
        ["watchtower"]=""  # No HTTP endpoint
        ["lidarr"]="http://localhost:${LIDARR_PORT}/ping"
        ["readarr"]="http://localhost:${READARR_PORT}/ping"
        ["kavita"]="http://localhost:${KAVITA_PORT}"
    )
}

# ---------------------------------------------------------------------------
# Check if service is running (Docker)
# ---------------------------------------------------------------------------
check_container_running() {
    local service=$1
    docker ps --format "{{.Names}}" | grep -q "^${service}$"
}

# ---------------------------------------------------------------------------
# Check service health endpoint
# ---------------------------------------------------------------------------
check_health_endpoint() {
    local url=$1
    
    if [ -z "$url" ]; then
        return 0  # No endpoint to check, assume OK
    fi
    
    curl -sf "$url" &>/dev/null
}

# ---------------------------------------------------------------------------
# Send email alert
# ---------------------------------------------------------------------------
send_alert() {
    local subject=$1
    local message=$2
    
    if [ -z "$HEALTHCHECK_ALERT_EMAIL" ]; then
        warn "No alert email configured. Set HEALTHCHECK_ALERT_EMAIL in .env"
        return
    fi
    
    # Try different methods to send email
    if command -v mail &>/dev/null; then
        echo "$message" | mail -s "$subject" "$HEALTHCHECK_ALERT_EMAIL" || {
            warn "Failed to send email alert via 'mail' command"
        }
    elif command -v sendmail &>/dev/null; then
        {
            echo "To: $HEALTHCHECK_ALERT_EMAIL"
            echo "Subject: $subject"
            echo ""
            echo "$message"
        } | sendmail "$HEALTHCHECK_ALERT_EMAIL" || {
            warn "Failed to send email alert via 'sendmail' command"
        }
    elif command -v msmtp &>/dev/null; then
        echo "$message" | msmtp "$HEALTHCHECK_ALERT_EMAIL" || {
            warn "Failed to send email alert via 'msmtp' command"
        }
    else
        warn "No email command found (mail, sendmail, or msmtp). Cannot send alerts."
    fi
}

# ---------------------------------------------------------------------------
# Log health check result
# ---------------------------------------------------------------------------
log_result() {
    local status=$1
    local log_file="${DATA_ROOT}/logs/healthcheck.log"
    
    mkdir -p "$(dirname "$log_file")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $status" >> "$log_file"
    
    # Rotate log if too large (> 10MB)
    if [ -f "$log_file" ] && [ $(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0) -gt 10485760 ]; then
        mv "$log_file" "${log_file}.old"
        touch "$log_file"
    fi
}

# ---------------------------------------------------------------------------
# Run health check
# ---------------------------------------------------------------------------
run_check() {
    step "Running health check..."
    echo ""
    
    init_services
    
    local failed_services=()
    local alert_message=""
    
    for service in "${!SERVICES[@]}"; do
        local description="${SERVICES[$service]}"
        local url="${SERVICE_URLS[$service]}"
        local status_icon="✓"
        local status_color="${GREEN}"
        local status_text="HEALTHY"
        local checks_passed=0
        local total_checks=0
        
        # Check 1: Container running
        total_checks=$((total_checks + 1))
        if check_container_running "$service"; then
            checks_passed=$((checks_passed + 1))
        else
            status_icon="✗"
            status_color="${RED}"
            status_text="DOWN"
        fi
        
        # Check 2: Health endpoint (if applicable)
        if [ -n "$url" ]; then
            total_checks=$((total_checks + 1))
            if check_health_endpoint "$url"; then
                checks_passed=$((checks_passed + 1))
            else
                status_icon="⚠"
                status_color="${YELLOW}"
                status_text="UNHEALTHY"
            fi
        fi
        
        # Display status
        printf "  ${status_color}%-12s${NC} %-35s %s\n" "$status_icon $service" "$description" "$status_text"
        
        # Track failures
        if [ $checks_passed -lt $total_checks ]; then
            failed_services+=("$service ($description)")
            alert_message="${alert_message}✗ $service - $status_text\n"
        fi
    done
    
    echo ""
    
    # Report results
    if [ ${#failed_services[@]} -eq 0 ]; then
        info "All services are healthy!"
        log_result "OK: All services healthy"
    else
        error "Some services are unhealthy:"
        for svc in "${failed_services[@]}"; do
            echo "  - $svc"
        done
        
        log_result "FAIL: ${#failed_services[@]} service(s) down"
        
        # Send alert
        local subject="[MyFlix ALERT] ${#failed_services[@]} service(s) unhealthy"
        local full_message="MyFlix Health Check Alert

The following services are unhealthy:

$(printf '%s\n' "${failed_services[@]}")

Time: $(date)
Server: $(hostname)

Please check the services and logs for more details.

---
MyFlix Health Check System"
        
        send_alert "$subject" "$full_message"
        
        return 1
    fi
    
    # Show disk usage
    echo ""
    step "Disk usage:"
    df -h "$DATA_ROOT" --output=source,size,used,avail,pcent | tail -1 | \
        awk '{printf "  Filesystem: %s\n  Total: %s\n  Used: %s (%s)\n  Available: %s\n", $1, $2, $3, $5, $4}'
}

# ---------------------------------------------------------------------------
# Show service status
# ---------------------------------------------------------------------------
show_status() {
    step "Service Status"
    echo ""
    
    init_services
    
    printf "  %-15s %-35s %-10s %-10s\n" "SERVICE" "DESCRIPTION" "CONTAINER" "HEALTH"
    echo "  $(printf '%*s' 70 '' | tr ' ' '-')"
    
    for service in "${!SERVICES[@]}"; do
        local description="${SERVICES[$service]}"
        local url="${SERVICE_URLS[$service]}"
        local container_status="${RED}DOWN${NC}"
        local health_status="N/A"
        
        if check_container_running "$service"; then
            container_status="${GREEN}UP${NC}"
            
            if [ -n "$url" ]; then
                if check_health_endpoint "$url"; then
                    health_status="${GREEN}OK${NC}"
                else
                    health_status="${RED}FAIL${NC}"
                fi
            else
                health_status="${YELLOW}N/A${NC}"
            fi
        fi
        
        printf "  %-15s %-35b %-10b %-10b\n" "$service" "$description" "$container_status" "$health_status"
    done
    
    echo ""
}

# ---------------------------------------------------------------------------
# Schedule health checks
# ---------------------------------------------------------------------------
schedule_check() {
    step "Installing health check cron job..."
    
    # Check if already scheduled
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_DIR/healthcheck.sh"; then
        warn "Health check is already scheduled"
        echo "Current cron entry:"
        crontab -l | grep "$SCRIPT_DIR/healthcheck.sh"
        return
    fi
    
    # Add to crontab (run every 5 minutes, log to file)
    (crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_DIR/healthcheck.sh >> ${DATA_ROOT}/logs/healthcheck-cron.log 2>&1") | crontab -
    
    info "Health check scheduled to run every 5 minutes"
    info "Logs will be saved to: ${DATA_ROOT}/logs/healthcheck-cron.log"
}

# ---------------------------------------------------------------------------
# Unschedule health checks
# ---------------------------------------------------------------------------
unschedule_check() {
    step "Removing health check cron job..."
    
    if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_DIR/healthcheck.sh"; then
        warn "No health check cron job found"
        return
    fi
    
    # Remove from crontab
    crontab -l 2>/dev/null | grep -v "$SCRIPT_DIR/healthcheck.sh" | crontab -
    
    info "Health check cron job removed"
}

# ---------------------------------------------------------------------------
# Show help
# ---------------------------------------------------------------------------
show_help() {
    cat << 'EOF'
MyFlix Health Check Script

Usage:
  bash healthcheck.sh <command>

Commands:
  check       Run health check once (default)
  status      Show detailed service status
  schedule    Install cron job (runs every 5 minutes)
  unschedule  Remove cron job
  help        Show this help message

Configuration:
  Set HEALTHCHECK_ALERT_EMAIL in your .env file to receive
  email alerts when services are unhealthy.

Examples:
  # Run check now
  bash healthcheck.sh

  # View service status
  bash healthcheck.sh status

  # Enable automated monitoring
  bash healthcheck.sh schedule

EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    load_env
    
    if [ $# -eq 0 ]; then
        run_check
        exit $?
    fi
    
    case "$1" in
        check)
            run_check
            ;;
        status)
            show_status
            ;;
        schedule)
            schedule_check
            ;;
        unschedule)
            unschedule_check
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
