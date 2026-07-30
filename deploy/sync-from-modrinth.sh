#!/usr/bin/env bash
set -euo pipefail

# =============================================================
#  Modrinth → 8h8g 数据同步入口
#  从 api.modrinth.com 同步项目/版本到本地实例
# =============================================================
#  用法:
#    bash sync-from-modrinth.sh                 # 同步前 50 个热门 mod
#    bash sync-from-modrinth.sh --limit 200     # 同步 200 个
#    bash sync-from-modrinth.sh --metadata-only # 仅元数据（不下载文件）
#    bash sync-from-modrinth.sh --ids sodium iris lithium # 同步指定项目
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ---- Check dependencies ----
check_deps() {
    command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || {
        log_error "Python 3 is required"
        log_error "Install: apt install python3 python3-pip"
        exit 1
    }
    PYTHON=$(command -v python3 || command -v python)
    log_ok "Python: $($PYTHON --version 2>&1)"
}

# ---- Install deps ----
install_deps() {
    if ! $PYTHON -c "import httpx" 2>/dev/null; then
        log_info "Installing Python dependencies..."
        pip install httpx 2>/dev/null || $PYTHON -m pip install httpx 2>/dev/null || {
            log_error "Failed to install httpx. Try: pip install httpx"
            exit 1
        }
        log_ok "Dependencies installed"
    fi
}

# ---- Check .env for admin key ----
load_env() {
    if [[ -f ".env" ]]; then
        export $(grep -v '^#' .env | xargs 2>/dev/null || true)
    fi
}

# ---- Main ----
main() {
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}  Modrinth → 8h8g 数据同步${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""

    check_deps
    install_deps
    load_env

    # Build args
    ARGS=("$@")

    # Ensure output dir
    mkdir -p "sync-data"

    log_info "Starting sync..."
    $PYTHON "$SCRIPT_DIR/sync/sync.py" "${ARGS[@]}"

    log_ok "Sync complete!"
    echo ""
    echo -e "  ${YELLOW}数据目录:${NC} $SCRIPT_DIR/sync-data/"
    echo -e "  ${YELLOW}导入本地 API:${NC} 见文档"
    echo ""
}

main "$@"
