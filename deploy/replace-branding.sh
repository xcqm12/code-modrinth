#!/usr/bin/env bash
set -euo pipefail

# =============================================================
#  品牌替换脚本 - 将 Modrinth 品牌图片替换为七零喵
# =============================================================
#  用法:
#    1. 将七零喵.png 放到 deploy/ 目录下
#    2. bash replace-branding.sh
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SOURCE_IMAGE="$SCRIPT_DIR/七零喵.png"
FRONTEND_PUBLIC="$PROJECT_DIR/apps/frontend/src/public"
FRONTEND_ASSETS="$PROJECT_DIR/apps/frontend/src/assets/images"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
    log_error "七零喵.png not found in $SCRIPT_DIR"
    log_error "Please place 七零喵.png in the deploy/ directory first"
    exit 1
fi

log_info "Replacing brand images with 七零喵.png..."

# 1. Favicon (convert to .ico - best effort, use .png as fallback)
if command -v convert >/dev/null 2>&1; then
    convert "$SOURCE_IMAGE" -resize 32x32 "$FRONTEND_PUBLIC/favicon.ico"
    convert "$SOURCE_IMAGE" -resize 32x32 "$FRONTEND_PUBLIC/favicon-light.ico"
    log_info "Favicon generated from 七零喵.png"
else
    # Fallback: copy png as ico (browsers accept png in link[rel=icon])
    cp "$SOURCE_IMAGE" "$FRONTEND_PUBLIC/favicon.ico"
    cp "$SOURCE_IMAGE" "$FRONTEND_PUBLIC/favicon-light.ico"
    log_warn "ImageMagick not found. Favicon copied as PNG (browsers will still show it)"
fi

# 2. Site logo
cp "$SOURCE_IMAGE" "$FRONTEND_ASSETS/logo.svg"
log_info "logo.svg replaced"

# 3. OG image
cp "$SOURCE_IMAGE" "$FRONTEND_PUBLIC/og-image.png"
log_info "OG image replaced"

log_info ""
log_info "Done! Brand images replaced with 七零喵.png"
log_info "Rebuild the frontend to see changes:"
log_info "  docker compose build frontend && docker compose up -d frontend"
