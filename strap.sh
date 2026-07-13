#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# strap.sh - Bootstrap Script for CachyOS Backup Restore
# ==============================================================================
#
# 一键恢复脚本，用于在新系统上快速恢复备份
#
# 使用方法:
#   bash <(curl -sL https://raw.githubusercontent.com/USER/cachy-backup/main/strap.sh)
#   bash <(curl -sL https://raw.githubusercontent.com/USER/cachy-backup/main/strap.sh) restore
#
# ==============================================================================

# --- 颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- 环境检测 ---

if [ "$(uname -s)" != "Linux" ]; then
    printf "${RED}Error: 此脚本仅支持 Linux 系统${NC}\n"
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    printf "${RED}Error: 不支持的架构: %s (仅支持 x86_64)${NC}\n" "$ARCH"
    exit 1
fi

# --- 权限封装 ---

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        if ! command -v sudo >/dev/null 2>&1; then
            printf "${RED}Error: 未找到 sudo 命令，请以 root 身份运行${NC}\n"
            exit 1
        fi
        sudo "$@"
    fi
}

# --- 配置 ---

TARGET_BRANCH="${BRANCH:-main}"
TARGET_DIR="/tmp/cachy-backup"
REPO_NAME="cachy-backup"

# --- 镜像选择 ---

select_mirror() {
    local default_choice="1"
    local default_name="GitHub"

    # 检测是否在中国
    local current_tz=""
    if [ -L /etc/localtime ]; then
        current_tz=$(readlink -f /etc/localtime || true)
    fi

    if [[ "$current_tz" == *"Asia/Shanghai"* ]] || [[ "$current_tz" == *"Chongqing"* ]] || [[ "$current_tz" == *"Urumqi"* ]]; then
        default_choice="2"
        default_name="Gitee"
    fi

    if [ -n "${MIRROR:-}" ]; then
        case "${MIRROR,,}" in
            github) SELECTED_MIRROR="GitHub" ;;
            gitee) SELECTED_MIRROR="Gitee" ;;
            *)
                printf "${RED}Error: 未知镜像 '%s' (支持: github, gitee)${NC}\n" "$MIRROR"
                exit 1
                ;;
        esac
        return 0
    fi

    printf "${BLUE}>>> 选择下载镜像${NC}\n"
    printf "  [1] GitHub  https://github.com/lvcdy/cachy-backup\n"
    printf "  [2] Gitee   https://gitee.com/lvcdy/cachy-backup\n"
    printf "\n"
    printf "默认: %s (直接回车使用默认)\n" "$default_name"
    printf "选择 [1-2]: "

    local choice=""
    read -r choice < /dev/tty || true
    choice=${choice:-$default_choice}

    case "$choice" in
        1) SELECTED_MIRROR="GitHub" ;;
        2) SELECTED_MIRROR="Gitee" ;;
        *)
            printf "${RED}Error: 无效选择 '%s'${NC}\n" "$choice"
            exit 1
            ;;
    esac
}

# --- 依赖检查 ---

check_dependencies() {
    local missing=()

    for cmd in curl git rsync; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        printf "${YELLOW}>>> 安装缺失依赖: %s${NC}\n" "${missing[*]}"
        run_as_root pacman -S --noconfirm --needed "${missing[@]}" >/dev/null 2>&1
    fi
}

# --- Banner ---

show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
   ██████╗ █████╗  ██████╗██╗  ██╗██╗   ██╗
  ██╔════╝██╔══██╗██╔════╝██║  ██║╚██╗ ██╔╝
  ██║     ███████║██║     ███████║ ╚████╔╝
  ██║     ██╔══██║██║     ██╔══██║  ╚██╔╝
  ╚██████╗██║  ██║╚██████╗██║  ██║   ██║
   ╚═════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝
EOF
    echo -e "${NC}"
    echo -e "${BOLD}   :: Bootstrap Restore Tool ::${NC}"
    echo ""
}

# --- 主流程 ---

main() {
    show_banner

    select_mirror
    check_dependencies

    # 构造下载 URL
    case "$SELECTED_MIRROR" in
        GitHub)
            TARBALL_URL="https://github.com/lvcdy/${REPO_NAME}/archive/refs/heads/${TARGET_BRANCH}.tar.gz"
            CLONE_URL="https://github.com/lvcdy/${REPO_NAME}.git"
            ;;
        Gitee)
            TARBALL_URL="https://gitee.com/lvcdy/${REPO_NAME}/repository/archive/${TARGET_BRANCH}.tar.gz"
            CLONE_URL="https://gitee.com/lvcdy/${REPO_NAME}.git"
            ;;
    esac

    printf "${BLUE}>>> 从 %s 下载备份仓库...${NC}\n" "$SELECTED_MIRROR"

    # 清理旧目录
    [ -d "$TARGET_DIR" ] && run_as_root rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"

    # 尝试下载（最多 3 次）
    local success=0
    for attempt in 1 2 3; do
        if curl -sSLf "$TARBALL_URL" | tar -xz -C "$TARGET_DIR" --strip-components=1; then
            success=1
            break
        fi

        if [ "$attempt" -lt 3 ]; then
            printf "${YELLOW}Warning: 下载失败 (尝试 %d/3)，3秒后重试...${NC}\n" "$attempt"
            sleep 3
            rm -rf "$TARGET_DIR"
            mkdir -p "$TARGET_DIR"
        fi
    done

    if [ "$success" -ne 1 ]; then
        # 回退到 git clone
        printf "${YELLOW}>>> tar 下载失败，尝试 git clone...${NC}\n"
        rm -rf "$TARGET_DIR"
        git clone --depth 1 "$CLONE_URL" "$TARGET_DIR" || {
            printf "${RED}Error: 无法下载备份仓库${NC}\n"
            exit 1
        }
    fi

    printf "${GREEN}>>> 下载完成${NC}\n\n"

    # 执行恢复
    chmod +x "$TARGET_DIR/backup-system.sh" 2>/dev/null || true
    chmod +x "$TARGET_DIR/scripts"/*.sh 2>/dev/null || true

    # 传递参数给主脚本
    local args=("restore")
    [ -n "${1:-}" ] && args=("$@")

    cd "$TARGET_DIR"
    bash backup-system.sh "${args[@]}" < /dev/tty
}

main "$@"
