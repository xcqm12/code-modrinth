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
# 8h8g Production Configuration - 多域名拆分部署
# Edit these values before running deploy

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
SMTP_HOST=mailpit
SMTP_PORT=1025
SMTP_TLS=none
SMTP_REPLY_TO_NAME=
SMTP_REPLY_TO_ADDRESS=

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

# Stripe (credit card payments)
STRIPE_API_KEY=
STRIPE_WEBHOOK_SECRET=

# PayPal (payouts & payments)
PAYPAL_API_URL=https://api-m.sandbox.paypal.com/v1/
PAYPAL_WEBHOOK_ID=
PAYPAL_CLIENT_ID=
PAYPAL_CLIENT_SECRET=
PAYPAL_NVP_USERNAME=
PAYPAL_NVP_PASSWORD=
PAYPAL_NVP_SIGNATURE=
PAYPAL_BALANCE_ALERT_THRESHOLD=0

# Chinese payment gateways (fill in your credentials)
ALIPAY_APP_ID=
ALIPAY_PRIVATE_KEY=
ALIPAY_PUBLIC_KEY=
ALIPAY_GATEWAY_URL=https://openapi-sandbox.dl.alipaydev.com/gateway.do
ALIPAY_NOTIFY_URL=https://api.bbsmc.org.cn/_internal/payment/notify/alipay
ALIPAY_RETURN_URL=https://bbsmc.org.cn/billing
WECHATPAY_APP_ID=
WECHATPAY_MCH_ID=
WECHATPAY_API_KEY=
WECHATPAY_API_V3_KEY=
WECHATPAY_NOTIFY_URL=https://api.bbsmc.org.cn/_internal/payment/notify/wechatpay
EPAY_API_URL=
EPAY_PID=
EPAY_KEY=
EPAY_NOTIFY_URL=https://api.bbsmc.org.cn/_internal/payment/notify/epay
EPAY_RETURN_URL=https://bbsmc.org.cn/billing
MAPAY_API_URL=
MAPAY_APP_ID=
MAPAY_APP_SECRET=
MAPAY_NOTIFY_URL=https://api.bbsmc.org.cn/_internal/payment/notify/mapay
MAPAY_RETURN_URL=https://bbsmc.org.cn/billing

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

# ---- Setup SSL (Let's Encrypt) for multiple domains ----
setup_ssl() {
    log_info "Setting up SSL certificates for all subdomains..."

    local all_domains=(
        "bbsmc.org.cn"
        "api.bbsmc.org.cn"
        "cdn.bbsmc.org.cn"
        "admin.bbsmc.org.cn"
        "launcher-meta.bbsmc.org.cn"
        "www.bbsmc.org.cn"
    )

    if command -v certbot >/dev/null 2>&1; then
        # Stop any system web server on port 80
        $DOCKER_COMPOSE down --remove-orphans 2>/dev/null || true
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl stop apache2 2>/dev/null || true
        sleep 2

        local first_domain="${all_domains[0]}"
        local cert_domains=""
        local cert_names=""
        for d in "${all_domains[@]}"; do
            if [[ -z "$cert_domains" ]]; then
                cert_domains="-d $d"
                cert_names="$d"
            else
                cert_domains="$cert_domains -d $d"
            fi
        done

        log_info "Obtaining wildcard/renewal certificate for $cert_names and subdomains ..."

        # Try wildcard cert first
        if sudo certbot certonly --standalone $cert_domains --non-interactive --agree-tos -m "admin@${first_domain}" 2>/dev/null; then
            log_ok "Multi-domain certificate obtained!"
            # Copy certs to each subdomain directory
            for d in "${all_domains[@]}"; do
                mkdir -p "$SCRIPT_DIR/ssl/$d"
                if [[ -f "/etc/letsencrypt/live/$first_domain/fullchain.pem" ]]; then
                    sudo cp "/etc/letsencrypt/live/$first_domain/fullchain.pem" "$SCRIPT_DIR/ssl/$d/"
                    sudo cp "/etc/letsencrypt/live/$first_domain/privkey.pem" "$SCRIPT_DIR/ssl/$d/"
                fi
            done
            sudo chown -R "$(whoami):$(whoami)" "$SCRIPT_DIR/ssl/"
            log_ok "SSL certificates copied to $SCRIPT_DIR/ssl/<domain>/ directories"
        else
            log_warn "Certbot failed. Trying individual certificates..."
            for d in "${all_domains[@]}"; do
                log_info "Obtaining certificate for $d ..."
                if sudo certbot certonly --standalone -d "$d" --non-interactive --agree-tos -m "admin@$d" 2>/dev/null; then
                    mkdir -p "$SCRIPT_DIR/ssl/$d"
                    sudo cp "/etc/letsencrypt/live/$d/fullchain.pem" "$SCRIPT_DIR/ssl/$d/"
                    sudo cp "/etc/letsencrypt/live/$d/privkey.pem" "$SCRIPT_DIR/ssl/$d/"
                    log_ok "Certificate obtained for $d"
                else
                    log_warn "Failed to obtain certificate for $d"
                fi
            done
            sudo chown -R "$(whoami):$(whoami)" "$SCRIPT_DIR/ssl/"
        fi
    else
        log_warn "certbot not found. Creating SSL directories - place certificates manually:"
        for d in "${all_domains[@]}"; do
            mkdir -p "$SCRIPT_DIR/ssl/$d"
            log_warn "  $SCRIPT_DIR/ssl/$d/fullchain.pem"
            log_warn "  $SCRIPT_DIR/ssl/$d/privkey.pem"
        done
        echo ""
        read -rp "Press Enter after placing certificates (or Ctrl+C to abort)..."
    fi
}

# ---- Free port 80/443 for Docker nginx ----
free_web_ports() {
    log_info "Freeing ports 80/443 for Docker nginx..."

    local freed_something=false

    # 1. Stop and disable system nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_warn "System nginx is running, stopping and disabling it..."
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl disable nginx 2>/dev/null || true
        log_ok "System nginx stopped and disabled"
        freed_something=true
    fi

    # 2. Stop and disable system apache2
    if systemctl is-active --quiet apache2 2>/dev/null; then
        log_warn "System apache2 is running, stopping and disabling it..."
        sudo systemctl stop apache2 2>/dev/null || true
        sudo systemctl disable apache2 2>/dev/null || true
        log_ok "System apache2 stopped and disabled"
        freed_something=true
    fi

    # 3. Stop and disable httpd (CentOS/RHEL)
    if systemctl is-active --quiet httpd 2>/dev/null; then
        log_warn "System httpd is running, stopping and disabling it..."
        sudo systemctl stop httpd 2>/dev/null || true
        sudo systemctl disable httpd 2>/dev/null || true
        log_ok "System httpd stopped and disabled"
        freed_something=true
    fi

    # 4. Stop any Docker containers occupying port 80 or 443
    local pids_80 pids_443
    pids_80=$(ss -tlnp 2>/dev/null | grep ':80 ' | grep -oP 'pid=\K[0-9]+' || true)
    pids_443=$(ss -tlnp 2>/dev/null | grep ':443 ' | grep -oP 'pid=\K[0-9]+' || true)

    if [[ -n "$pids_80" ]] || [[ -n "$pids_443" ]]; then
        log_warn "Found processes still occupying port 80/443, attempting to stop them..."

        # Find and stop Docker containers using these ports
        for pid in $pids_80 $pids_443; do
            local container_id
            container_id=$(docker inspect --format '{{.ID}}' "$(cat /proc/$pid/cgroup 2>/dev/null | grep -oP 'docker[-/]\K[0-9a-f]{12,}' | head -1)" 2>/dev/null || true)
            if [[ -n "$container_id" ]]; then
                log_warn "Stopping Docker container $container_id occupying port 80/443..."
                docker stop "$container_id" 2>/dev/null || true
                freed_something=true
            fi
        done

        # Force kill any remaining processes on port 80/443
        if command -v fuser >/dev/null 2>&1; then
            sudo fuser -k 80/tcp 2>/dev/null || true
            sudo fuser -k 443/tcp 2>/dev/null || true
            freed_something=true
        fi
    fi

    # 5. Final check
    sleep 2
    local still_80 still_443
    still_80=$(ss -tlnp 2>/dev/null | grep ':80 ' || true)
    still_443=$(ss -tlnp 2>/dev/null | grep ':443 ' || true)

    if [[ -n "$still_80" ]] || [[ -n "$still_443" ]]; then
        log_error "Port 80/443 is still occupied after cleanup attempt:"
        [[ -n "$still_80" ]] && echo "  80:  $still_80"
        [[ -n "$still_443" ]] && echo "  443: $still_443"
        log_error "Please manually stop the conflicting service and re-run deploy."
        exit 1
    fi

    if [[ "$freed_something" == "true" ]]; then
        log_ok "Ports 80/443 freed successfully"
    else
        log_ok "Ports 80/443 are already free"
    fi
}

# ---- Create temporary swap to prevent OOM during builds ----
create_swap() {
    local swap_size="${1:-4G}"
    local swap_file="/swapfile_tmp"

    local current_swap
    current_swap=$(swapon --show --noheadings 2>/dev/null | wc -l)
    if [[ "$current_swap" -gt 0 ]]; then
        log_ok "Swap already active ($(swapon --show --noheadings --output=SIZE 2>/dev/null | head -1))"
        return
    fi

    log_info "Creating temporary ${swap_size} swap file to prevent OOM during build..."
    sudo fallocate -l "$swap_size" "$swap_file" 2>/dev/null || sudo dd if=/dev/zero of="$swap_file" bs=1M count=$((4096)) 2>/dev/null
    sudo chmod 600 "$swap_file"
    sudo mkswap "$swap_file" >/dev/null 2>&1
    sudo swapon "$swap_file" 2>/dev/null || {
        log_warn "Failed to enable swap. Build may OOM on low-memory servers."
        return
    }
    log_ok "Temporary swap (${swap_size}) enabled at ${swap_file}"
}

remove_swap() {
    local swap_file="/swapfile_tmp"
    if swapon --show --noheadings 2>/dev/null | grep -q "$swap_file"; then
        log_info "Removing temporary swap file..."
        sudo swapoff "$swap_file" 2>/dev/null || true
        sudo rm -f "$swap_file" 2>/dev/null || true
        log_ok "Temporary swap removed"
    fi
}

# ---- Build and deploy ----
deploy() {
    log_info "Starting deployment..."

    # Free ports 80/443 before starting nginx
    free_web_ports

    # Create temporary swap for build stability on 8G servers
    create_swap 4G

    # Build Docker images SEQUENTIALLY to avoid OOM (Rust + Node.js together exceed 8G)
    # Force parallel limit to 1 to ensure true sequential builds
    export COMPOSE_PARALLEL_LIMIT=1
    export DOCKER_BUILDKIT=1

    log_info "Building labrinth (Rust backend) Docker image..."
    CARGO_BUILD_JOBS=2 $DOCKER_COMPOSE build --progress=plain labrinth

    log_info "Building frontend (Nuxt) Docker image..."
    $DOCKER_COMPOSE build --progress=plain frontend

    # Remove temporary swap after build
    remove_swap

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

# ---- Wait for Clickhouse to be ready ----
# labrinth 启动时需要连接 Clickhouse，但 index-search 用 --no-deps 跳过依赖，
# 需要显式等待 Clickhouse 健康后再跑索引。
wait_for_clickhouse() {
    log_info "Waiting for Clickhouse to become healthy..."
    local timeout=60
    local elapsed=0

    # Source the .env to get CLICKHOUSE_PASSWORD
    set -a; source "$SCRIPT_DIR/.env"; set +a

    while [[ "$elapsed" -lt "$timeout" ]]; do
        if $DOCKER_COMPOSE exec -T clickhouse \
            clickhouse-client --password "$CLICKHOUSE_PASSWORD" --query "SELECT 1" 2>/dev/null; then
            log_ok "Clickhouse is ready"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done

    log_error "Clickhouse not ready after ${timeout}s. Index task will likely fail."
    return 1
}

# ---- Initial search index ----
# labrinth 主进程只把项目变更投递到 Kafka，由 labrinth-indexer 消费写入 Typesense。
# 但增量索引只处理"新的"变更，首次部署时 Typesense 是空的，所以需要跑一次全量索引，
# 否则已存在/已审核通过的项目不会出现在搜索和浏览页面。
initial_search_index() {
    log_info "Running initial full search index (this may take a while)..."

    # Ensure Clickhouse is accepting connections before running the index task
    wait_for_clickhouse || true

    if $DOCKER_COMPOSE run --rm --no-deps labrinth \
        /labrinth/labrinth --run-background-task index-search; then
        log_ok "Search index built successfully"
    else
        log_warn "Initial search index failed. Projects may not appear in browse/search."
        log_warn "You can retry manually with:"
        log_warn "  $DOCKER_COMPOSE run --rm --no-deps labrinth /labrinth/labrinth --run-background-task index-search"
    fi
}

# ---- Post-deployment info ----
show_info() {
    local domain
    domain=$(grep -oP '^DOMAIN=\K.*' "$SCRIPT_DIR/.env" 2>/dev/null || echo "bbsmc.org.cn")

    echo ""
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  8h8g 多域名部署成功！Deployment Complete!${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""
    echo -e "  ${YELLOW}━━━ 服务访问地址 ━━━${NC}"
    echo -e "  Frontend (主站):          ${CYAN}https://$domain${NC}"
    echo -e "  API (API 后端):           ${CYAN}https://api.$domain${NC}"
    echo -e "  CDN (文件存储):           ${CYAN}https://cdn.$domain${NC}"
    echo -e "  Admin (管理后台):         ${CYAN}https://admin.$domain${NC}"
    echo -e "  Launcher Meta (加载器):   ${CYAN}https://launcher-meta.$domain${NC}"
    echo ""
    echo -e "  ${YELLOW}━━━ 管理密钥 ━━━${NC}"
    echo -e "  Admin Key: ${YELLOW}check .env file (LABRINTH_ADMIN_KEY)${NC}"
    echo ""
    echo -e "  ${YELLOW}━━━ 常用命令 ━━━${NC}"
    echo -e "    View logs:     ${CYAN}$DOCKER_COMPOSE logs -f${NC}"
    echo -e "    Restart:       ${CYAN}$DOCKER_COMPOSE restart${NC}"
    echo -e "    Stop:          ${CYAN}$DOCKER_COMPOSE down${NC}"
    echo -e "    Update:        ${CYAN}git pull && $DOCKER_COMPOSE build && $DOCKER_COMPOSE up -d${NC}"
    echo ""
    echo -e "  ${YELLOW}━━━ 搜索索引 ━━━${NC}"
    echo -e "    审核通过的项目由 ${CYAN}labrinth-indexer${NC} 服务写入 Typesense。"
    echo -e "    若项目未出现在浏览/搜索页，先查看消费者日志:"
    echo -e "      ${CYAN}$DOCKER_COMPOSE logs -f labrinth-indexer${NC}"
    echo -e "    手动重建全量索引:"
    echo -e "      ${CYAN}$DOCKER_COMPOSE run --rm --no-deps labrinth /labrinth/labrinth --run-background-task index-search${NC}"
    echo ""
    echo -e "  ${YELLOW}━━━ 后续步骤 ━━━${NC}"
    echo -e "    1. 配置 DNS: 将上述子域名 A 记录指向服务器 IP"
    echo -e "    2. 配置 OAuth (GitHub, Discord 等) 在 .env 文件中"
    echo -e "    3. 配置 SMTP 用于生产环境邮件发送"
    echo -e "    4. 创建管理员: ${CYAN}$DOCKER_COMPOSE exec labrinth /labrinth/labrinth --run-background-task create-admin${NC}"
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
    initial_search_index
    show_info
}

main "$@"
