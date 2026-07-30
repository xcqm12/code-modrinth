#!/usr/bin/env bash
set -euo pipefail

# =============================================================
#  8h8g 轻量部署脚本 - 适用于 4 核 4G 服务器
#  Lightweight deployment for 4-core 4GB RAM servers
# =============================================================
#  策略：
#    1. 创建 6G swap 防止 OOM
#    2. 顺序构建，每次只构建一个镜像
#    3. 限制 Rust 并行编译为 1 核
#    4. 限制 Node.js 最大堆内存为 2G
#    5. 关闭 Docker BuildKit 并行
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

DOCKER_COMPOSE="docker compose"

# ---- Pre-flight ----
preflight() {
    log_info "Running pre-flight checks..."
    command -v docker >/dev/null 2>&1 || { log_error "Docker not installed"; exit 1; }
    command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1 || { log_error "docker compose not found"; exit 1; }

    export COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

    local mem_total
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "4096")
    log_info "Memory: ${mem_total}M, Cores: $(nproc 2>/dev/null || echo 4)"

    if [[ "$mem_total" -lt 3072 ]]; then
        log_warn "Less than 3GB RAM detected. Build may be very slow."
    fi
    log_ok "Pre-flight passed"
}

# ---- Setup swap ----
setup_swap() {
    if swapon --show --noheadings 2>/dev/null | grep -q .; then
        log_ok "Swap already active ($(swapon --show --noheadings --output=SIZE 2>/dev/null | head -1))"
        return
    fi

    local swap_size="6G"
    log_info "Creating ${swap_size} swap file..."
    sudo fallocate -l "$swap_size" /swapfile_4h4g 2>/dev/null || sudo dd if=/dev/zero of=/swapfile_4h4g bs=1M count=$((6*1024)) 2>/dev/null
    sudo chmod 600 /swapfile_4h4g
    sudo mkswap /swapfile_4h4g >/dev/null 2>&1
    sudo swapon /swapfile_4h4g 2>/dev/null || { log_warn "Swap failed. OOM risk."; return; }
    log_ok "Swap ${swap_size} enabled"
}

cleanup_swap() {
    if swapon --show --noheadings 2>/dev/null | grep -q "/swapfile_4h4g"; then
        sudo swapoff /swapfile_4h4g 2>/dev/null || true
        sudo rm -f /swapfile_4h4g 2>/dev/null || true
        log_ok "Temporary swap removed"
    fi
}

# ---- Setup env ----
setup_env() {
    log_info "Setting up environment..."

    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_info "Creating .env from template..."
        cat > "$SCRIPT_DIR/.env" << 'ENVEOF'
# 8h8g 4h4g Deployment
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
CLICKHOUSE_PASSWORD=8h8g_prod_clickhouse_pass
RATE_LIMIT_IGNORE_KEY=8h8g_prod_rate_limit_key

SMTP_FROM_NAME=8h8g
SMTP_FROM_ADDRESS=no-reply@mail.bbsmc.org.cn
SMTP_HOST=mailpit
SMTP_PORT=1025
SMTP_TLS=none

CLICKHOUSE_USER=default
CLICKHOUSE_DATABASE=production_ariadne

GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
MICROSOFT_CLIENT_ID=
MICROSOFT_CLIENT_SECRET=

STORAGE_BACKEND=local
ENVEOF
        log_warn "Edit $SCRIPT_DIR/.env with secrets, then re-run"
        exit 0
    fi
    log_ok "Environment file found"
}

# ---- Build images (ultra-conservative for 4G RAM) ----
build_images() {
    setup_swap

    local node_options="--max-old-space-size=2048"
    local cargo_jobs=1

    # 1. Infrastructure images (no compilation)
    log_info "Pulling infrastructure images..."
    $DOCKER_COMPOSE pull postgres redis typesense clickhouse mail gotenberg redpanda nginx 2>/dev/null || true

    # 2. Labrinth (Rust) - single job, sequential
    log_info "Building labrinth (Rust, CARGO_BUILD_JOBS=${cargo_jobs})..."
    CARGO_BUILD_JOBS=${cargo_jobs} DOCKER_BUILDKIT=1 $DOCKER_COMPOSE build --progress=plain labrinth

    # 3. Frontend (Nuxt) - reduced heap
    log_info "Building frontend (Nuxt, --max-old-space-size=2048)..."
    NODE_OPTIONS="${node_options}" DOCKER_BUILDKIT=1 $DOCKER_COMPOSE build --progress=plain frontend

    cleanup_swap
    log_ok "All images built"
}

# ---- Deploy ----
deploy_stack() {
    log_info "Starting services..."
    $DOCKER_COMPOSE up -d
    log_ok "Services started"
}

# ---- Wait for healthy ----
wait_healthy() {
    log_info "Waiting for services..."
    local services=("postgres" "redis" "typesense" "clickhouse" "mail" "redpanda")
    for svc in "${services[@]}"; do
        local timeout=120 elapsed=0
        while [[ "$elapsed" -lt "$timeout" ]]; do
            local status
            status=$($DOCKER_COMPOSE ps "$svc" --format json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('State',''))" 2>/dev/null || echo "unknown")
            [[ "$status" == "running" ]] && { log_ok "$svc ready"; break; }
            sleep 5; elapsed=$((elapsed + 5))
        done
    done
    log_info "Waiting for labrinth (migrations)..."
    sleep 15
}

# ---- Main ----
main() {
    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  8h8g 轻量部署 (4核4G) | Lightweight 4h4g Deploy${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""

    preflight
    setup_env
    build_images
    deploy_stack
    wait_healthy

    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  部署完成！Deployment Complete!${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""
    echo -e "  ${CYAN}https://bbsmc.org.cn${NC}"
    echo -e "  ${CYAN}https://api.bbsmc.org.cn${NC}"
    echo ""
    echo -e "  Commands:"
    echo -e "    Logs:   ${CYAN}$DOCKER_COMPOSE logs -f${NC}"
    echo -e "    Update: ${CYAN}git pull && bash $0${NC}"
    echo ""
}

main "$@"
