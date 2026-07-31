#!/usr/bin/env bash
set -euo pipefail

# =============================================================
#  设置自动同步定时任务（每3天同步一次）
# =============================================================
#  用法: bash setup-cron-sync.sh
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-from-bbsmc.sh"
CRON_LOG="$SCRIPT_DIR/sync-cron.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }

# 检查脚本是否存在
if [[ ! -f "$SYNC_SCRIPT" ]]; then
    log_error "sync-from-bbsmc.sh not found at $SYNC_SCRIPT"
    exit 1
fi

# 检查 python3-httpx
if ! python3 -c "import httpx" 2>/dev/null; then
    log_warn "python3-httpx not installed, installing..."
    apt install -y python3-httpx 2>/dev/null || pip install --break-system-packages httpx 2>/dev/null || {
        log_error "Failed to install httpx"
        exit 1
    }
    log_ok "httpx installed"
fi

# 检查是否已有定时任务
EXISTING=$(crontab -l 2>/dev/null || true)
if echo "$EXISTING" | grep -q "$SYNC_SCRIPT"; then
    log_info "Sync cron job already exists"
    echo "$EXISTING"
    exit 0
fi

# 每3天执行一次（在凌晨3点）
CRON_LINE="0 3 */3 * * cd $SCRIPT_DIR && CACHE_TTL=259200 MAX_STORAGE=524288000 bash $SYNC_SCRIPT --import-data --limit 25 >> $CRON_LOG 2>&1"

# 写入 crontab
if echo "$EXISTING" | grep -q .; then
    (echo "$EXISTING"; echo "$CRON_LINE") | crontab -
else
    echo "$CRON_LINE" | crontab -
fi

log_ok "Cron job installed! Runs every 3 days at 3:00 AM"
log_info "Log: $CRON_LOG"
log_info ""
log_info "当前定时任务:"
crontab -l
