#!/bin/bash

# ==============================================================================
# 00-utils.sh - TUI Visual Engine & Common Utilities
# ==============================================================================

# --- 颜色与样式 ---
export NC='\033[0m'
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'
export UNDER='\033[4m'

export H_RED='\033[1;31m'
export H_GREEN='\033[1;32m'
export H_YELLOW='\033[1;33m'
export H_BLUE='\033[1;34m'
export H_PURPLE='\033[1;35m'
export H_CYAN='\033[1;36m'
export H_WHITE='\033[1;37m'
export H_GRAY='\033[1;90m'
export H_MAGENTA='\033[1;35m'

export BG_BLUE='\033[44m'
export BG_PURPLE='\033[45m'

# --- 符号 ---
export TICK="${H_GREEN}✔${NC}"
export CROSS="${H_RED}✘${NC}"
export INFO="${H_BLUE}ℹ${NC}"
export WARN_SYM="${H_YELLOW}⚠${NC}"
export ARROW="${H_CYAN}➜${NC}"

# --- 日志文件 ---
export LOG_FILE="/tmp/cachy-backup-$$.log"
touch "$LOG_FILE" 2>/dev/null || true

# ==============================================================================
# 日志函数
# ==============================================================================

write_log() {
    local level="$1"
    shift
    local msg="$*"
    local clean_msg
    clean_msg=$(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%H:%M:%S')] [$level] $clean_msg" >> "$LOG_FILE" 2>/dev/null || true
}

log() {
    echo -e "   $ARROW $1"
    write_log "LOG" "$1"
}

info() {
    echo -e "   $INFO $1"
    write_log "INFO" "$1"
}

success() {
    echo -e "   $TICK ${H_GREEN}$1${NC}"
    write_log "SUCCESS" "$1"
}

warn() {
    echo -e "   $WARN_SYM ${H_YELLOW}${BOLD}WARNING:${NC} ${H_YELLOW}$1${NC}"
    write_log "WARN" "$1"
}

error() {
    echo -e ""
    echo -e "${H_RED}   ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${H_RED}   ┃  ERROR: $1${NC}"
    echo -e "${H_RED}   ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo -e ""
    write_log "ERROR" "$1"
}

fatal() {
    error "$1"
    exit 1
}

# ==============================================================================
# 视觉组件
# ==============================================================================

hr() {
    printf "${H_GRAY}%*s${NC}\n" "${COLUMNS:-80}" '' | tr ' ' '─'
}

section() {
    local title="$1"
    local subtitle="$2"
    echo ""
    echo -e "${H_PURPLE}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${H_PURPLE}│${NC} ${BOLD}${H_WHITE}$title${NC}"
    echo -e "${H_PURPLE}│${NC} ${H_CYAN}$subtitle${NC}"
    echo -e "${H_PURPLE}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
    write_log "SECTION" "$title - $subtitle"
}

info_kv() {
    local key="$1"
    local val="$2"
    local extra="${3:-}"
    printf "   ${H_BLUE}●${NC} %-15s : ${BOLD}%s${NC} ${DIM}%s${NC}\n" "$key" "$val" "$extra"
    write_log "INFO" "$key=$val"
}

# ==============================================================================
# 命令执行器
# ==============================================================================

exe() {
    local full_command="$*"
    echo -e "   ${H_GRAY}┌──[ ${H_MAGENTA}EXEC${H_GRAY} ]────────────────────────────────────────────────────${NC}"
    echo -e "   ${H_GRAY}│${NC} ${H_CYAN}$ ${NC}${BOLD}$full_command${NC}"
    write_log "EXEC" "$full_command"

    "$@"
    local status=$?

    if [ $status -eq 0 ]; then
        echo -e "   ${H_GRAY}└──────────────────────────────────────────────────────── ${H_GREEN}OK${H_GRAY} ─┘${NC}"
    else
        echo -e "   ${H_GRAY}└────────────────────────────────────────────────────── ${H_RED}FAIL${H_GRAY} ─┘${NC}"
        write_log "FAIL" "Exit Code: $status"
    fi
    return $status
}

exe_silent() {
    "$@" >/dev/null 2>&1
}

# ==============================================================================
# Banner
# ==============================================================================

show_banner() {
    clear
    echo -e "${H_CYAN}"
    cat << 'EOF'
   ██████╗ █████╗  ██████╗██╗  ██╗██╗   ██╗
  ██╔════╝██╔══██╗██╔════╝██║  ██║╚██╗ ██╔╝
  ██║     ███████║██║     ███████║ ╚████╔╝
  ██║     ██╔══██║██║     ██╔══██║  ╚██╔╝
  ╚██████╗██║  ██║╚██████╗██║  ██║   ██║
   ╚═════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝
EOF
    echo -e "${NC}"
    echo -e "${DIM}   :: System Backup & Restore Tool ::${NC}"
    echo -e ""
}

# ==============================================================================
# 交互确认
# ==============================================================================

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local force="${FORCE:-0}"

    if [[ "$force" -eq 1 ]]; then
        write_log "FORCE" "Auto-confirm: $prompt"
        return 0
    fi

    local yn
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi

    if ! read -r -p "$(echo -e "   ${H_CYAN}${prompt}${NC}")" yn < /dev/tty; then
        echo ""
        fatal "用户取消了输入操作"
    fi

    yn="${yn:-$default}"
    case "$yn" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

# ==============================================================================
# 环境检测
# ==============================================================================

check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        fatal "请不要以 root 权限运行此脚本！\n脚本内部会在需要时自动请求 sudo。"
    fi
}

check_archlinux() {
    if [ ! -f /etc/arch-release ]; then
        fatal "此脚本仅支持 Arch Linux 系统"
    fi
}

detect_aur_helper() {
    if command -v yay &>/dev/null; then
        echo "yay"
    elif command -v paru &>/dev/null; then
        echo "paru"
    else
        echo ""
    fi
}
