#!/usr/bin/env bash
set -euo pipefail

# =============================================================
#  8h8g 数据同步入口
#  从 api.modrinth.com 同步项目/版本到本地实例
# =============================================================
#  用法:
#    bash sync-from-bbsmc.sh                          # 同步前 50 个热门 mod
#    bash sync-from-bbsmc.sh --limit 200              # 同步 200 个
#    bash sync-from-bbsmc.sh --metadata-only          # 仅元数据（不下载文件）
#    bash sync-from-bbsmc.sh --ids sodium iris        # 同步指定项目
#    bash sync-from-bbsmc.sh --import-data            # 导入缓存数据到本地 API
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_deps() {
    command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
        log_error "Python 3 is required"; exit 1
    }
    PYTHON=$(command -v python3 || command -v python)
    log_ok "Python: $($PYTHON --version 2>&1)"
}

install_deps() {
    if ! $PYTHON -c "import httpx" 2>/dev/null; then
        log_info "Installing Python dependencies..."
        pip install httpx 2>/dev/null || $PYTHON -m pip install httpx 2>/dev/null || {
            log_error "Failed to install httpx"; exit 1
        }
        log_ok "Dependencies installed"
    fi
}

load_env() {
    if [[ -f ".env" ]]; then
        export $(grep -v '^#' .env | xargs 2>/dev/null || true)
    fi
}

main() {
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  8h8g 数据同步${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""

    check_deps
    install_deps
    load_env

    mkdir -p "sync-data"

    # Export env vars for sync.py
    export TARGET_API="${TARGET_API:-http://labrinth:8000/v2}"
    export TARGET_ADMIN_KEY="${LABRINTH_ADMIN_KEY:-}"
    export TARGET_AUTH_TOKEN="${TARGET_AUTH_TOKEN:-}"
    export SYNC_DIR="${SYNC_DIR:-$SCRIPT_DIR/sync-data}"

    log_info "Starting sync..."
    $PYTHON "$SCRIPT_DIR/sync/sync.py" "$@"

    log_ok "Done!"
    echo ""
    echo -e "  ${YELLOW}数据目录:${NC} $SYNC_DIR"
    echo -e "  ${YELLOW}导入本地:${NC} bash $0 --import-data"
    echo ""
}

main "$@"
