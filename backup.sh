#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# cachy-backup - CachyOS 系统备份与恢复工具
# ==============================================================================

VERSION="2.0.0"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
REPO_NAME="${REPO_NAME:-cachy-backup}"
STAGING_DIR="${STAGING_DIR:-$HOME/.cache/cachy-backup-staging}"

# --- Source Utils ---
if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# --- 全局变量 ---
MODE=""
DRY_RUN=0
export FORCE=0
export VERBOSE=0
GH_USER=""

# ==============================================================================
# 帮助信息
# ==============================================================================

show_help() {
    cat <<EOF
${H_CYAN}${BOLD}CachyOS 系统备份与恢复工具${NC} v${VERSION}

${BOLD}用法:${NC}
  $(basename "$0") [选项] <命令>

${BOLD}命令:${NC}
  backup   备份当前系统（默认）
  restore  从 GitHub 恢复系统

${BOLD}选项:${NC}
  -h, --help      显示帮助信息
  -v, --version   显示版本号
  -n, --dry-run   仅预览操作
  -f, --force     跳过确认提示
  -V, --verbose   详细输出

${BOLD}示例:${NC}
  $(basename "$0")                  # 交互式备份
  $(basename "$0") backup --force   # 快速备份
  $(basename "$0") restore --dry-run # 预览恢复
EOF
}

show_version() {
    echo "cachy-backup v${VERSION}"
}

# ==============================================================================
# 参数解析
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -f|--force)
                FORCE=1
                shift
                ;;
            -V|--verbose)
                VERBOSE=1
                shift
                ;;
            backup|restore)
                MODE="$1"
                shift
                ;;
            *)
                fatal "未知选项: $1\n运行 '$(basename "$0") --help' 查看帮助"
                ;;
        esac
    done

    MODE="${MODE:-backup}"
}

# ==============================================================================
# GitHub 认证
# ==============================================================================

check_github_auth() {
    section "GitHub Auth" "检查 GitHub 认证状态"

    if ! command -v gh &>/dev/null; then
        if [ -t 0 ] || [ -c /dev/tty ]; then
            log "安装 GitHub CLI..."
            exe sudo pacman -S --noconfirm --needed github-cli
        else
            fatal "gh 未安装，请手动运行: sudo pacman -S github-cli"
        fi
    fi

    # 显式检查认证状态，避免 set -e 在非交互环境下的干扰
    if ! gh auth status &>/dev/null; then
        if [ -t 0 ] || [ -c /dev/tty ]; then
            warn "需要登录 GitHub"
            exe gh auth login -p https -w
        else
            fatal "gh 未登录，请先运行 'gh auth login'"
        fi
    fi

    GH_USER=$(gh api user --jq '.login') || fatal "无法获取 GitHub 用户名"
    info_kv "GitHub User" "${H_GREEN}${GH_USER}${NC}"
}

# ==============================================================================
# 系统仪表盘
# ==============================================================================

sys_dashboard() {
    local config_file="$HOME/.config/cachy-backup.conf"
    local repo_url="未配置"
    if [ -f "$config_file" ]; then
        repo_url=$(grep "^REPO_URL=" "$config_file" | cut -d= -f2- || echo "未配置")
    fi

    echo -e "${H_BLUE}╔════ SYSTEM INFO ════════════════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Host${NC}     : $(hostname)"
    echo -e "${H_BLUE}║${NC} ${BOLD}Kernel${NC}   : $(uname -r)"
    echo -e "${H_BLUE}║${NC} ${BOLD}Mode${NC}     : ${H_CYAN}${MODE^^}${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Repo${NC}     : ${repo_url}"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Options${NC}  : ${H_YELLOW}DRY-RUN${NC}"
    fi
    if [ "$FORCE" -eq 1 ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Options${NC}  : ${H_RED}FORCE (skip confirmations)${NC}"
    fi
    echo -e "${H_BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ==============================================================================
# 恢复准备
# ==============================================================================

prepare_restore() {
    local config_file="$HOME/.config/cachy-backup.conf"
    local repo_url=""

    # 检查是否已配置仓库
    if [ -f "$config_file" ]; then
        repo_url=$(grep "^REPO_URL=" "$config_file" | cut -d= -f2-)
    fi

    # 未配置则使用默认仓库
    if [ -z "$repo_url" ]; then
        repo_url="https://github.com/lvcdy/cachy-backup.git"
        info "使用默认仓库: $repo_url"
    fi

    info_kv "仓库地址" "$repo_url"

    if [ ! -d "$STAGING_DIR/.git" ]; then
        log "克隆备份仓库..."
        rm -rf "$STAGING_DIR"
        exe git clone "$repo_url" "$STAGING_DIR" || fatal "克隆失败，请检查仓库地址"
    else
        log "更新备份仓库..."
        exe git -C "$STAGING_DIR" pull || fatal "更新失败"
    fi

    if [ ! -d "$STAGING_DIR/packages" ]; then
        fatal "备份仓库中未找到 packages 目录"
    fi
}

# ==============================================================================
# Dry-run 预览
# ==============================================================================

show_dry_run() {
    section "Dry Run" "预览将执行的操作"

    if [ "$MODE" = "backup" ]; then
        echo -e "   ${ARROW} 备份 pacman 官方软件包列表"
        echo -e "   ${ARROW} 备份 AUR 软件包列表"
        echo -e "   ${ARROW} 备份 Flatpak 软件包列表"
        echo -e "   ${ARROW} 备份 systemd 服务列表"
        echo -e "   ${ARROW} 备份系统配置 (pacman/locale/snapper/greetd)"
        echo -e "   ${ARROW} 推送到 GitHub ($GH_USER/$REPO_NAME)"
    else
        if [ -d "$STAGING_DIR/packages" ]; then
            local official_count aur_count flatpak_count
            official_count=$( [ -f "$STAGING_DIR/packages/official.txt" ] && wc -l < "$STAGING_DIR/packages/official.txt" || echo 0)
            aur_count=$( [ -f "$STAGING_DIR/packages/aur.txt" ] && wc -l < "$STAGING_DIR/packages/aur.txt" || echo 0)
            flatpak_count=$( [ -f "$STAGING_DIR/packages/flatpak.txt" ] && wc -l < "$STAGING_DIR/packages/flatpak.txt" || echo 0)
            echo -e "   ${ARROW} 恢复 pacman 配置"
            echo -e "   ${ARROW} 恢复 locale/snapper/greetd"
            echo -e "   ${ARROW} 更新系统和 keyring"
            echo -e "   ${ARROW} 恢复 ${official_count} 个官方包"
            echo -e "   ${ARROW} 安装 AUR 助手"
            echo -e "   ${ARROW} 恢复 ${aur_count} 个 AUR 包"
            echo -e "   ${ARROW} 恢复 ${flatpak_count} 个 Flatpak 包"
            echo -e "   ${ARROW} 恢复 dotfile"
        fi
    fi

    echo ""
    info "以上为预览操作，不会实际执行"
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    parse_args "$@"
    check_not_root
    check_archlinux
    check_github_auth

    show_banner
    sys_dashboard

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$MODE" = "restore" ]; then
            prepare_restore
        fi
        show_dry_run
        exit 0
    fi

    case "$MODE" in
        backup)
            source "$SCRIPTS_DIR/10-backup.sh"
            run_backup "$GH_USER"
            ;;
        restore)
            prepare_restore
            source "$SCRIPTS_DIR/20-restore.sh"
            run_restore "$GH_USER"
            ;;
    esac

    # 显示日志位置
    echo ""
    info_kv "Log File" "$LOG_FILE"
    echo ""
}

main "$@"
