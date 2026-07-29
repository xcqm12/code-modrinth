#!/usr/bin/env bash
set -euo pipefail

# =============================================================
#  8h8g 一键部署脚本 - 8h8g One-Click Deployment Script
#  适用于 8 核 8G 服务器 | For 8-core 8GB RAM server
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ---- Pre-flight checks ----
preflight() {
    log_info "Running pre-flight checks..."

    if [[ "$(uname)" != "Linux" ]]; then
        log_warn "This script is designed for Linux. You may need to adapt it for your OS."
    fi

    command -v docker >/dev/null 2>&1 || { log_error "Docker is not installed. Please install Docker first."; exit 1; }
    command -v docker-compose >/dev/null 2>&1 || command -v docker compose >/dev/null 2>&1 || { log_error "docker-compose / docker compose plugin is not installed."; exit 1; }

    DOCKER_COMPOSE="docker compose"
    if ! docker compose version >/dev/null 2>&1; then
        if docker-compose version >/dev/null 2>&1; then
            DOCKER_COMPOSE="docker-compose"
        else
            log_error "No docker compose command found."
            exit 1
        fi
    fi

    # Always use the deploy-specific compose file, not the root docker-compose.yml
    export COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

    log_ok "Docker $(docker --version | cut -d' ' -f3 | cut -d',' -f1) found"
    log_ok "$($DOCKER_COMPOSE version)"

    # Check system resources
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
    local mem_total
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "unknown")

    log_info "CPU cores: ${cpu_cores}, Memory: ${mem_total}M"
    if [[ "$mem_total" != "unknown" ]] && [[ "$mem_total" -lt 6144 ]]; then
        log_warn "Less than 6GB RAM detected. Performance may be degraded."
    fi
}

# ---- Setup environment ----
setup_env() {
    log_info "Setting up environment..."

    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_info "Creating .env file from template..."
        cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.template" 2>/dev/null || true
        cat > "$SCRIPT_DIR/.env" << 'ENVEOF'
# 8h8g Production Configuration
# Edit these values before running deploy

DOMAIN=bbsmc.org.cn
SITE_URL=https://bbsmc.org.cn

POSTGRES_USER=8h8g
POSTGRES_PASSWORD=8h8g_prod_db_pass
POSTGRES_DB=8h8g

REDIS_PASSWORD=8h8g_prod_redis_pass

TYPESENSE_API_KEY=8h8g_prod_typesense_key

LABRINTH_ADMIN_KEY=8h8g_prod_admin_key

SMTP_FROM_NAME=8h8g
SMTP_FROM_ADDRESS=no-reply@mail.bbsmc.org.cn
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_HOST=mailpit
SMTP_PORT=1025
SMTP_TLS=none

CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=8h8g_prod_clickhouse_pass
CLICKHOUSE_DATABASE=production_ariadne

RATE_LIMIT_IGNORE_KEY=8h8g_prod_rate_limit_key

GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
DISCORD_CLIENT_ID=
DISCORD_CLIENT_SECRET=
MICROSOFT_CLIENT_ID=
MICROSOFT_CLIENT_SECRET=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

STORAGE_BACKEND=local
ENVEOF
        log_warn "Please edit $SCRIPT_DIR/.env with your production secrets before deploying!"
        log_warn "Run: nano $SCRIPT_DIR/.env"
        exit 0
    fi

    log_ok "Environment file found at $SCRIPT_DIR/.env"

    # Validate required secrets are set
    local required_vars=(
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "TYPESENSE_API_KEY"
        "LABRINTH_ADMIN_KEY"
        "CLICKHOUSE_PASSWORD"
        "RATE_LIMIT_IGNORE_KEY"
    )

    local missing=0
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$SCRIPT_DIR/.env" 2>/dev/null; then
            log_error "Missing required variable: $var in .env"
            missing=$((missing + 1))
        fi
    done

    if [[ "$missing" -gt 0 ]]; then
        log_error "Please fix missing environment variables and re-run."
        exit 1
    fi
}

# ---- Setup SSL (Let's Encrypt) ----
setup_ssl() {
    log_info "Setting up SSL..."

    if [[ -f "$SCRIPT_DIR/ssl/fullchain.pem" ]] && [[ -f "$SCRIPT_DIR/ssl/privkey.pem" ]]; then
        log_ok "SSL certificates already exist at $SCRIPT_DIR/ssl/"
        return
    fi

    if command -v certbot >/dev/null 2>&1; then
        local domain
        domain=$(grep -oP '^DOMAIN=\K.*' "$SCRIPT_DIR/.env" 2>/dev/null || echo "bbsmc.org.cn")

        # Stop any Docker services that may be using port 80
        log_info "Stopping existing Docker services to free port 80 ..."
        $DOCKER_COMPOSE down --remove-orphans 2>/dev/null || true

        # Also stop any system web server on port 80 (nginx/apache2)
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl stop apache2 2>/dev/null || true

        log_info "Obtaining Let's Encrypt certificate for $domain ..."
        sudo certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "admin@$domain" || {
            log_warn "Certbot failed. You can still manually place certificates in $SCRIPT_DIR/ssl/"
            log_warn "Required files: fullchain.pem, privkey.pem"
            mkdir -p "$SCRIPT_DIR/ssl"
            return
        }

        mkdir -p "$SCRIPT_DIR/ssl"
        sudo cp "/etc/letsencrypt/live/$domain/fullchain.pem" "$SCRIPT_DIR/ssl/"
        sudo cp "/etc/letsencrypt/live/$domain/privkey.pem" "$SCRIPT_DIR/ssl/"
        sudo chown -R "$(whoami):$(whoami)" "$SCRIPT_DIR/ssl/"
        log_ok "SSL certificates obtained and copied to $SCRIPT_DIR/ssl/"
    else
        mkdir -p "$SCRIPT_DIR/ssl"
        log_warn "certbot not found. Please place your SSL certificates manually:"
        log_warn "  $SCRIPT_DIR/ssl/fullchain.pem"
        log_warn "  $SCRIPT_DIR/ssl/privkey.pem"
        echo ""
        read -rp "Press Enter after placing certificates (or Ctrl+C to abort)..."
    fi
}

# ---- Build and deploy ----
deploy() {
    log_info "Starting deployment..."

    # Build Docker images
    log_info "Building labrinth (Rust backend) Docker image..."
    $DOCKER_COMPOSE build labrinth

    log_info "Building frontend (Nuxt) Docker image..."
    $DOCKER_COMPOSE build frontend

    # Pull infrastructure images
    log_info "Pulling infrastructure images..."
    $DOCKER_COMPOSE pull postgres redis typesense clickhouse mail gotenberg redpanda nginx

    # Start services
    log_info "Starting all services..."
    $DOCKER_COMPOSE up -d

    log_ok "All services started!"
}

# ---- Wait for services ----
wait_for_services() {
    log_info "Waiting for services to become healthy..."

    local services=("postgres" "redis" "typesense" "clickhouse" "mail" "redpanda")
    local timeout=120
    local elapsed=0

    for svc in "${services[@]}"; do
        log_info "Waiting for $svc ..."
        elapsed=0
        while [[ "$elapsed" -lt "$timeout" ]]; do
            local status
            status=$($DOCKER_COMPOSE ps "$svc" --format json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('State',''))" 2>/dev/null || echo "unknown")
            if [[ "$status" == "running" ]]; then
                log_ok "$svc is running"
                break
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
    done

    # Give labrinth extra time to run migrations
    log_info "Waiting for labrinth to start (this may take a moment for DB migrations)..."
    sleep 15
}

# ---- Post-deployment info ----
show_info() {
    local domain
    domain=$(grep -oP '^DOMAIN=\K.*' "$SCRIPT_DIR/.env" 2>/dev/null || echo "bbsmc.org.cn")

    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  8h8g 部署成功！8h8g Deployment Complete!${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""
    echo -e "  Frontend:  ${CYAN}https://$domain${NC}"
    echo -e "  API:       ${CYAN}https://$domain/api/v2/${NC}"
    echo -e "  Admin Key: ${YELLOW}check .env file${NC}"
    echo ""
    echo -e "  Useful commands:"
    echo -e "    View logs:     ${CYAN}$DOCKER_COMPOSE logs -f${NC}"
    echo -e "    Restart:       ${CYAN}$DOCKER_COMPOSE restart${NC}"
    echo -e "    Stop:          ${CYAN}$DOCKER_COMPOSE down${NC}"
    echo -e "    Update:        ${CYAN}$DOCKER_COMPOSE build && $DOCKER_COMPOSE up -d${NC}"
    echo ""
    echo -e "  Next steps:"
    echo -e "    1. Configure OAuth apps (GitHub, Discord, etc.) in the .env file"
    echo -e "    2. Set up SMTP for production email delivery"
    echo -e "    3. Run ${CYAN}$DOCKER_COMPOSE exec labrinth /labrinth/labrinth --run-background-task create-admin${NC}"
    echo -e "       to create an admin user"
    echo ""
}

# ---- Main ----
main() {
    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  8h8g 一键部署脚本 | One-Click Deployment${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""

    preflight
    setup_env
    setup_ssl
    deploy
    wait_for_services
    show_info
}

main "$@"
