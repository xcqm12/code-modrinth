#!/usr/bin/env bash
set -euo pipefail

# =============================================================
#  8h8g 一键部署脚本 - 8h8g One-Click Deployment Script
#  适用于 8 核 8G 服务器 | For 8-core 8GB RAM server
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

COMPOSE_FILE="docker-compose.yml"
DOCKER_COMPOSE="docker compose"
SWAP_FILE="/swapfile_8h8g"

ALL_DOMAINS=(
  "bbsmc.org.cn"
  "api.bbsmc.org.cn"
  "cdn.bbsmc.org.cn"
  "admin.bbsmc.org.cn"
  "launcher-meta.bbsmc.org.cn"
  "www.bbsmc.org.cn"
)

# ---- Pre-flight checks ----
preflight() {
    log_info "Running pre-flight checks..."

    if [[ "$(uname)" != "Linux" ]]; then
        log_warn "This script is designed for Linux. You may need to adapt it for your OS."
    fi

    command -v docker >/dev/null 2>&1 || { log_error "Docker is not installed"; exit 1; }
    docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 || { log_error "docker compose plugin not found"; exit 1; }

    if ! docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker-compose"
    fi

    log_ok "Docker $(docker --version | cut -d' ' -f3 | cut -d',' -f1) found"

    local cpu_cores mem_total
    cpu_cores=$(nproc 2>/dev/null || echo "unknown")
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "unknown")
    log_info "CPU cores: ${cpu_cores}, Memory: ${mem_total}M"

    if [[ "$mem_total" != "unknown" ]] && [[ "$mem_total" -lt 6144 ]]; then
        log_warn "Less than 6GB RAM detected. Consider using deploy-4h4g.sh instead."
    fi
}

# ---- Git pull ----
git_pull() {
    if [[ -d .git ]]; then
        log_info "Pulling latest code..."
        git pull --ff-only 2>/dev/null || log_warn "git pull failed, continuing with local code"
    fi
}

# ---- Setup environment ----
setup_env() {
    log_info "Setting up environment..."

    if [[ ! -f ".env" ]]; then
        log_info "Creating .env file..."
        cat > ".env" << 'ENVEOF'
# 8h8g Production Configuration
DOMAIN=bbsmc.org.cn
SITE_URL=https://bbsmc.org.cn
API_URL=https://api.bbsmc.org.cn/v2/
CDN_URL=https://cdn.bbsmc.org.cn

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
SMTP_HOST=mail
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
        log_warn "Edit .env with your secrets then re-run: nano .env"
        exit 0
    fi
    log_ok "Environment file found"

    local required_vars=(
        "POSTGRES_PASSWORD" "REDIS_PASSWORD" "TYPESENSE_API_KEY"
        "LABRINTH_ADMIN_KEY" "CLICKHOUSE_PASSWORD" "RATE_LIMIT_IGNORE_KEY"
    )
    local missing=0
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" ".env" 2>/dev/null; then
            log_error "Missing required variable: $var in .env"
            missing=$((missing + 1))
        fi
    done
    if [[ "$missing" -gt 0 ]]; then
        exit 1
    fi
}

# ---- Setup SSL (prefer 宝塔 cert symlinks, fallback to self-signed) ----
setup_ssl() {
    log_info "Setting up SSL certificates..."

    mkdir -p ssl
    local bt_base="/www/server/panel/vhost/cert"
    local has_real_certs=false

    for d in "${ALL_DOMAINS[@]}"; do
        mkdir -p "ssl/$d"
        if [[ -f "ssl/$d/fullchain.pem" ]]; then
            log_ok "SSL cert for $d already in ssl/$d"
            has_real_certs=true
        elif [[ -d "$bt_base/$d" ]] && [[ -f "$bt_base/$d/fullchain.pem" ]]; then
            ln -sf "$bt_base/$d" "ssl/$d"
            log_ok "Linked 宝塔 cert for $d"
            has_real_certs=true
        else
            log_warn "No real SSL cert for $d - nginx entrypoint will generate self-signed placeholder"
        fi
    done

    if [[ "$has_real_certs" == "true" ]]; then
        log_ok "SSL certificates configured"
    else
        log_warn "No real SSL certificates found. Only self-signed certs will be used."
        log_warn "The frontend build may fail (Node.js rejects self-signed certs)."
        log_warn "Either:"
        log_warn "  1. Apply for certs in 宝塔 panel, then re-run this script"
        log_warn "  2. Set API_URL=http://labrinth:8000/v2/ in .env and rebuild frontend"
    fi
}

# ---- Free port 80/443 for Docker nginx ----
free_web_ports() {
    log_info "Freeing ports 80/443 for Docker nginx..."

    # 1. Stop system nginx (includes 宝塔 nginx)
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_warn "Stopping system nginx (宝塔)..."
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl disable nginx 2>/dev/null || true
        log_ok "System nginx stopped"
    fi
    if systemctl is-active --quiet httpd 2>/dev/null; then
        sudo systemctl stop httpd 2>/dev/null || true
        sudo systemctl disable httpd 2>/dev/null || true
        log_ok "System httpd stopped"
    fi

    # 2. Force-kill any process on port 80/443
    if command -v fuser >/dev/null 2>&1; then
        sudo fuser -k 80/tcp 2>/dev/null || true
        sudo fuser -k 443/tcp 2>/dev/null || true
    fi

    sleep 2

    # 3. Check final state
    local still_80 still_443
    still_80=$(ss -tlnp 2>/dev/null | grep ':80 ' || true)
    still_443=$(ss -tlnp 2>/dev/null | grep ':443 ' || true)

    if [[ -n "$still_80" ]] || [[ -n "$still_443" ]]; then
        log_warn "Port 80/443 still occupied (may be Docker container):"
        [[ -n "$still_80" ]] && echo "  80:  $still_80"
        [[ -n "$still_443" ]] && echo "  443: $still_443"
        log_warn "Proceeding anyway - existing Docker nginx will reuse these ports"
    else
        log_ok "Ports 80/443 are free"
    fi
}

# ---- Create temporary swap ----
create_swap() {
    local swap_size="${1:-4G}"
    if swapon --show --noheadings 2>/dev/null | grep -q "$SWAP_FILE"; then
        log_ok "Swap already active on $SWAP_FILE"
        return
    fi
    if swapon --show --noheadings 2>/dev/null | grep -q .; then
        log_ok "Swap already active ($(swapon --show --noheadings --output=SIZE 2>/dev/null | head -1))"
        return
    fi

    log_info "Creating temporary ${swap_size} swap file..."
    sudo fallocate -l "$swap_size" "$SWAP_FILE" 2>/dev/null || \
        sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count=4096 2>/dev/null
    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE" >/dev/null 2>&1
    sudo swapon "$SWAP_FILE" 2>/dev/null || {
        log_warn "Failed to enable swap. Build may OOM."
        return
    }
    log_ok "Swap ${swap_size} enabled at ${SWAP_FILE}"
}

remove_swap() {
    if swapon --show --noheadings 2>/dev/null | grep -q "$SWAP_FILE"; then
        log_info "Removing temporary swap..."
        sudo swapoff "$SWAP_FILE" 2>/dev/null || true
        sudo rm -f "$SWAP_FILE" 2>/dev/null || true
        log_ok "Temporary swap removed"
    fi
}

# ---- Build and deploy ----
deploy() {
    log_info "Starting deployment..."

    free_web_ports
    create_swap 4G

    export COMPOSE_PARALLEL_LIMIT=1
    export DOCKER_BUILDKIT=1

    # Pull infrastructure images first
    log_info "Pulling infrastructure images..."
    $DOCKER_COMPOSE -f "$COMPOSE_FILE" pull postgres redis typesense clickhouse mail gotenberg redpanda nginx 2>/dev/null || true

    # Build labrinth (Rust)
    log_info "Building labrinth (Rust, CARGO_BUILD_JOBS=2)..."
    CARGO_BUILD_JOBS=2 $DOCKER_COMPOSE -f "$COMPOSE_FILE" build labrinth

    # Build frontend (Nuxt)
    log_info "Building frontend (Nuxt)..."
    $DOCKER_COMPOSE -f "$COMPOSE_FILE" build frontend

    remove_swap

    # Start all services
    log_info "Starting all services..."
    $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d

    log_ok "All services started!"
}

# ---- Wait for services ----
wait_for_services() {
    log_info "Waiting for services to become healthy..."

    local services=("postgres" "redis" "typesense" "clickhouse" "mail" "redpanda")
    local timeout=120

    for svc in "${services[@]}"; do
        log_info "Waiting for $svc ..."
        local elapsed=0
        while [[ "$elapsed" -lt "$timeout" ]]; do
            local status
            status=$($DOCKER_COMPOSE -f "$COMPOSE_FILE" ps "$svc" --format json 2>/dev/null \
                | grep -o '"State":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
            if [[ "$status" == "running" ]]; then
                log_ok "$svc is running"
                break
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
        if [[ "$elapsed" -ge "$timeout" ]]; then
            log_warn "$svc not ready after ${timeout}s, continuing..."
        fi
    done

    log_info "Waiting for labrinth (DB migrations + startup)..."
    sleep 20
}

# ---- Initial search index ----
initial_search_index() {
    log_info "Running initial full search index (this may take a while)..."

    if $DOCKER_COMPOSE -f "$COMPOSE_FILE" run --rm --no-deps labrinth \
        /labrinth/labrinth --run-background-task index-search 2>/dev/null; then
        log_ok "Search index built successfully"
    else
        log_warn "Initial search index failed. You can retry manually:"
        log_warn "  $DOCKER_COMPOSE -f $COMPOSE_FILE run --rm --no-deps labrinth /labrinth/labrinth --run-background-task index-search"
    fi
}

# ---- Post-deployment info ----
show_info() {
    local domain
    domain=$(grep -oP '^DOMAIN=\K.*' ".env" 2>/dev/null || echo "bbsmc.org.cn")

    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  8h8g 部署成功！Deployment Complete!${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""
    echo -e "  ${YELLOW}━━━ 服务访问地址 ━━━${NC}"
    echo -e "  Frontend (主站):          ${CYAN}https://$domain${NC}"
    echo -e "  API (API 后端):           ${CYAN}https://api.$domain${NC}"
    echo -e "  CDN (文件存储):           ${CYAN}https://cdn.$domain${NC}"
    echo -e "  Admin (管理后台):         ${CYAN}https://admin.$domain${NC}"
    echo -e "  Launcher Meta (加载器):   ${CYAN}https://launcher-meta.$domain${NC}"
    echo ""
    echo -e "  ${YELLOW}━━━ 常用命令 ━━━${NC}"
    echo -e "    Logs:     ${CYAN}$DOCKER_COMPOSE -f $COMPOSE_FILE logs -f${NC}"
    echo -e "    Restart:  ${CYAN}$DOCKER_COMPOSE -f $COMPOSE_FILE restart${NC}"
    echo -e "    Stop:     ${CYAN}$DOCKER_COMPOSE -f $COMPOSE_FILE down${NC}"
    echo -e "    Update:   ${CYAN}git pull && bash $0${NC}"
    echo ""
    echo -e "  ${YELLOW}━━━ 搜索索引 ━━━${NC}"
    echo -e "    增量索引: ${CYAN}$DOCKER_COMPOSE -f $COMPOSE_FILE logs -f labrinth-indexer${NC}"
    echo -e "    全量重建: ${CYAN}$DOCKER_COMPOSE -f $COMPOSE_FILE run --rm --no-deps labrinth /labrinth/labrinth --run-background-task index-search${NC}"
    echo ""
    echo -e "  ${YELLOW}━━━ 后续步骤 ━━━${NC}"
    echo -e "    1. 配置 DNS: 将子域名 A 记录指向服务器 IP"
    echo -e "    2. 配置 OAuth (GitHub, Discord 等) 在 .env 中"
    echo -e "    3. 配置 SMTP 生产环境邮箱"
    echo -e "    4. 创建管理员: ${CYAN}$DOCKER_COMPOSE -f $COMPOSE_FILE exec labrinth /labrinth/labrinth --run-background-task create-admin${NC}"
    echo ""
}

# ---- Main ----
main() {
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  8h8g 一键部署脚本 | One-Click Deployment${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""

    preflight
    git_pull
    setup_env
    free_web_ports
    setup_ssl
    deploy
    wait_for_services
    initial_search_index
    show_info
}

main "$@"
