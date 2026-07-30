#!/usr/bin/env bash
set -euo pipefail

# =============================================================
#  8h8g 轻量部署脚本 - 适用于 4 核 4G 服务器
#  Lightweight deployment for 4-core 4GB RAM servers
#  支持宝塔 SSL、自动 swap、顺序构建、资源限制覆盖
# =============================================================
#  用法:
#    首次部署:  bash deploy-4h4g.sh
#    更新部署:  git pull && bash deploy-4h4g.sh
#    仅构建:    bash deploy-4h4g.sh --build-only
#    仅启动:    bash deploy-4h4g.sh --up-only
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

COMPOSE_BASE="-f docker-compose.yml"
COMPOSE_4H4G="-f docker-compose.4h4g.yml"
COMPOSE_CMD="docker compose $COMPOSE_BASE $COMPOSE_4H4G"
SWAP_FILE="/swapfile_8h8g"

# 部署的域名
DOMAINS=(
  "bbsmc.org.cn"
  "api.bbsmc.org.cn"
  "cdn.bbsmc.org.cn"
  "admin.bbsmc.org.cn"
  "launcher-meta.bbsmc.org.cn"
)

# ---- Pre-flight ----
preflight() {
    log_info "Running pre-flight checks..."

    command -v docker >/dev/null 2>&1 || { log_error "Docker not installed"; exit 1; }
    local compose_ok=false
    docker compose version >/dev/null 2>&1 && compose_ok=true
    command -v docker-compose >/dev/null 2>&1 && compose_ok=true
    $compose_ok || { log_error "docker compose not found"; exit 1; }

    local mem_total
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "4096")
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo 4)
    log_info "Memory: ${mem_total}M, Cores: ${cpu_cores}"

    if [[ "$mem_total" -lt 3072 ]]; then
        log_warn "Less than 3GB RAM detected. Build will be very slow."
    fi
    log_ok "Pre-flight passed"
}

# ---- Git pull ----
git_pull() {
    if [[ -d .git ]]; then
        log_info "Pulling latest code..."
        git pull --ff-only 2>/dev/null || log_warn "git pull failed, continuing with local code"
    fi
}

# ---- Setup swap ----
setup_swap() {
    if swapon --show --noheadings 2>/dev/null | grep -q "$SWAP_FILE"; then
        log_ok "Swap already active on $SWAP_FILE"
        return
    fi

    local swap_size="6G"
    log_info "Creating ${swap_size} swap file (prevents OOM during build)..."
    sudo fallocate -l "$swap_size" "$SWAP_FILE" 2>/dev/null || \
        sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((6*1024)) 2>/dev/null
    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE" >/dev/null 2>&1
    sudo swapon "$SWAP_FILE" 2>/dev/null || {
        log_warn "Swap creation failed. Build may OOM."
        return
    }
    log_ok "Swap ${swap_size} enabled at ${SWAP_FILE}"
}

cleanup_swap() {
    if swapon --show --noheadings 2>/dev/null | grep -q "$SWAP_FILE"; then
        log_info "Removing temporary swap..."
        sudo swapoff "$SWAP_FILE" 2>/dev/null || true
        sudo rm -f "$SWAP_FILE" 2>/dev/null || true
        log_ok "Swap removed"
    fi
}

# ---- Setup env ----
setup_env() {
    log_info "Setting up environment..."

    if [[ ! -f ".env" ]]; then
        log_info "Creating .env from template..."
        cat > ".env" << 'ENVEOF'
# 8h8g 4h4g Deployment - 编辑后重新运行脚本
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
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=8h8g_prod_clickhouse_pass
CLICKHOUSE_DATABASE=production_ariadne
RATE_LIMIT_IGNORE_KEY=8h8g_prod_rate_limit_key

SMTP_FROM_NAME=8h8g
SMTP_FROM_ADDRESS=no-reply@mail.bbsmc.org.cn
SMTP_HOST=mail
SMTP_PORT=1025
SMTP_TLS=none

GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
MICROSOFT_CLIENT_ID=
MICROSOFT_CLIENT_SECRET=

STORAGE_BACKEND=local
ENVEOF
        log_warn "请编辑 .env 文件填入密钥后重新运行: nano .env"
        exit 0
    fi
    log_ok "Environment file found"

    local required_vars=(
        "POSTGRES_PASSWORD" "REDIS_PASSWORD" "TYPESENSE_API_KEY"
        "LABRINTH_ADMIN_KEY" "CLICKHOUSE_PASSWORD" "RATE_LIMIT_IGNORE_KEY"
    )
    local missing=0
    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=$" ".env" 2>/dev/null; then
            log_error "$var is empty in .env"
            missing=$((missing + 1))
        fi
    done
    if [[ "$missing" -gt 0 ]]; then
        exit 1
    fi
}

# ---- Setup SSL via 宝塔 cert symlinks ----
setup_ssl() {
    log_info "Setting up SSL certificates..."

    mkdir -p ssl

    # 尝试从宝塔证书目录创建软链接
    local bt_cert_base="/www/server/panel/vhost/cert"
    local all_linked=true

    for d in "${DOMAINS[@]}"; do
        if [[ -L "ssl/$d" ]] || [[ -f "ssl/$d/fullchain.pem" ]]; then
            log_ok "SSL cert for $d already exists"
            continue
        fi

        if [[ -d "$bt_cert_base/$d" ]] && [[ -f "$bt_cert_base/$d/fullchain.pem" ]]; then
            ln -sf "$bt_cert_base/$d" "ssl/$d"
            log_ok "Linked 宝塔 cert for $d"
        else
            log_warn "No SSL certificate found for $d (neither in ssl/ nor 宝塔)"
            log_warn "  nginx entrypoint will generate a self-signed placeholder"
            all_linked=false
        fi
    done

    # 为 nginx entrypoint 自签名准备目录
    for d in "${DOMAINS[@]}"; do
        mkdir -p "ssl/$d"
    done
    # www 共享 bbsmc.org.cn 证书
    mkdir -p "ssl/www.bbsmc.org.cn"

    if [[ "$all_linked" == "true" ]]; then
        log_ok "All SSL certificates configured"
    else
        log_warn "Some domains lack SSL certs. nginx will use self-signed placeholders."
    fi
}

# ---- Free ports 80/443 ----
free_web_ports() {
    log_info "Checking ports 80/443..."

    # 宝塔 nginx 占用了端口，需要停掉
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_warn "Stopping system nginx (宝塔)..."
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl disable nginx 2>/dev/null || true
        log_ok "System nginx stopped"
    fi
    if systemctl is-active --quiet httpd 2>/dev/null; then
        sudo systemctl stop httpd 2>/dev/null || true
        sudo systemctl disable httpd 2>/dev/null || true
    fi

    sleep 2
    if ss -tlnp 2>/dev/null | grep -qE ':80 |:443 '; then
        log_warn "Port 80/443 still in use:"
        ss -tlnp 2>/dev/null | grep -E ':80 |:443 ' || true
        log_warn "Proceeding anyway (may conflict)..."
    else
        log_ok "Ports 80/443 are free"
    fi
}

# ---- Pull infrastructure images ----
pull_images() {
    log_info "Pulling infrastructure images..."
    $COMPOSE_CMD pull postgres redis typesense clickhouse mail gotenberg redpanda 2>/dev/null || true
    log_ok "Infrastructure images pulled"
}

# ---- Build images (4h4g: sequential, low memory) ----
build_images() {
    setup_swap

    local cargo_jobs=1
    local node_mem="1024"

    # 1. Labrinth (Rust)
    log_info "Building labrinth (Rust, CARGO_BUILD_JOBS=${cargo_jobs})..."
    CARGO_BUILD_JOBS=${cargo_jobs} DOCKER_BUILDKIT=1 \
        docker compose --progress plain $COMPOSE_BASE $COMPOSE_4H4G build labrinth

    # 2. Frontend (Nuxt) - 使用内部地址构建
    log_info "Building frontend (Nuxt, max-old-space-size=${node_mem})..."
    DOCKER_BUILDKIT=1 \
        docker compose --progress plain $COMPOSE_BASE $COMPOSE_4H4G build frontend

    cleanup_swap
    log_ok "All images built"
}

# ---- Stop existing stack ----
stop_stack() {
    log_info "Stopping existing services..."
    $COMPOSE_CMD down --remove-orphans 2>/dev/null || true
    log_ok "Existing services stopped"
}

# ---- Start services ----
start_stack() {
    log_info "Starting services..."
    $COMPOSE_CMD up -d
    log_ok "Services started"
}

# ---- Wait for healthy ----
wait_healthy() {
    log_info "Waiting for infrastructure services..."
    local infra=("postgres" "redis" "typesense" "clickhouse" "mail" "redpanda")
    for svc in "${infra[@]}"; do
        local timeout=180 elapsed=0
        while [[ "$elapsed" -lt "$timeout" ]]; do
            local status
            status=$($COMPOSE_CMD ps "$svc" --format json 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('State',''))
except: print('unknown')" 2>/dev/null || echo "unknown")
            if [[ "$status" == "running" ]]; then
                log_ok "$svc ready"
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

# ---- Post-deployment info ----
show_info() {
    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  8h8g 4h4g 部署完成！Deployment Complete!${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""
    echo -e "  ${CYAN}https://bbsmc.org.cn${NC}"
    echo -e "  ${CYAN}https://api.bbsmc.org.cn${NC}"
    echo -e "  ${CYAN}https://cdn.bbsmc.org.cn${NC}"
    echo -e "  ${CYAN}https://admin.bbsmc.org.cn${NC}"
    echo -e "  ${CYAN}https://launcher-meta.bbsmc.org.cn${NC}"
    echo ""
    echo -e "  ${YELLOW}查看日志:${NC}  $COMPOSE_CMD logs -f"
    echo -e "  ${YELLOW}重启服务:${NC}  $COMPOSE_CMD restart"
    echo -e "  ${YELLOW}停止服务:${NC}  $COMPOSE_CMD down"
    echo -e "  ${YELLOW}更新部署:${NC}  git pull && bash $0"
    echo ""
}

# ---- Main ----
main() {
    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  8h8g 轻量部署 (4核4G) | 4h4g Deploy${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""

    preflight
    git_pull
    setup_env
    free_web_ports
    setup_ssl

    if [[ "${1:-}" == "--up-only" ]]; then
        start_stack
        wait_healthy
        show_info
        exit 0
    fi

    if [[ "${1:-}" != "--build-only" ]]; then
        stop_stack
    fi

    pull_images
    build_images
    start_stack
    wait_healthy
    show_info
}

main "$@"
