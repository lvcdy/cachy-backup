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
# 日志摘要
# ==============================================================================

log_summary() {
    local mode="${1:-unknown}"  # backup / restore
    local logfile="$LOG_FILE"

    [ ! -f "$logfile" ] && return 0

    local total_lines warn_count error_count exec_count
    total_lines=$(wc -l < "$logfile" 2>/dev/null || echo 0)
    warn_count=$(grep -c "\[WARN\]" "$logfile" 2>/dev/null || echo 0)
    error_count=$(grep -c "\[ERROR\]" "$logfile" 2>/dev/null || echo 0)
    exec_count=$(grep -c "\[EXEC\]" "$logfile" 2>/dev/null || echo 0)

    # 追加摘要到日志
    {
        echo ""
        echo "============================================================"
        echo "  $mode 摘要"
        echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  日志行: $total_lines"
        echo "  执行命令: $exec_count"
        echo "  警告: $warn_count"
        echo "  错误: $error_count"
        echo "============================================================"
    } >> "$logfile" 2>/dev/null

    # 如果有错误/警告，提示用户
    if [ "$error_count" -gt 0 ] || [ "$warn_count" -gt 0 ]; then
        echo ""
        info_kv "日志路径" "$logfile"
        [ "$warn_count" -gt 0 ] && info_kv "警告数" "${H_YELLOW}${warn_count}${NC}"
        [ "$error_count" -gt 0 ] && info_kv "错误数" "${H_RED}${error_count}${NC}"
        echo ""
        info "查看完整日志: ${H_CYAN}cat $logfile${NC}"
        info "查看错误: ${H_CYAN}grep ERROR $logfile${NC}"
    else
        echo ""
        success "${mode} 完成，无错误/警告"
        info_kv "日志" "$logfile"
    fi
}

# ==============================================================================
# 包安装进度显示
# ==============================================================================

show_package_progress() {
    local label="$1"
    local total="$2"
    local missing="$3"
    echo ""
    info_kv "$label 总数" "${BOLD}${total}${NC}"
    info_kv "待安装" "${H_YELLOW}${BOLD}${missing}${NC}"
    echo ""
    log "开始安装 $missing 个包 (总共 $total 个)..."
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
        # 如果是通过 strap.sh 调用且设置了 SUDO_USER，则允许运行
        if [ -n "${SUDO_USER:-}" ]; then
            warn "检测到 sudo 环境，将以用户 ${SUDO_USER} 身份运行"
            return 0
        fi
        fatal "请不要以 root 权限运行此脚本！\n脚本内部会在需要时自动请求 sudo。"
    fi
}

check_archlinux() {
    # 更健壮的 Arch 系检测，兼容容器环境和衍生版
    if [ -f /etc/os-release ]; then
        if grep -q "ID=arch" /etc/os-release || grep -q "ID=cachyos" /etc/os-release; then
            return 0
        fi
    fi
    # 备用检测：检查 pacman 是否存在
    if command -v pacman &>/dev/null; then
        return 0
    fi
    fatal "此脚本仅支持 Arch Linux 系统"
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

# ==============================================================================
# Pacman 锁检测
# ==============================================================================

ensure_pacman_unlocked() {
    local lock_file="/var/lib/pacman/db.lck"

    if [ ! -e "$lock_file" ]; then
        return 0
    fi

    warn "检测到 pacman 锁文件: $lock_file"

    # 检查是否有进程在使用
    if command -v fuser &>/dev/null && fuser "$lock_file" &>/dev/null 2>&1; then
        error "pacman 数据库正被其他进程占用"
        fuser -v "$lock_file" 2>/dev/null || true
        return 1
    fi

    if pgrep -x pacman &>/dev/null 2>&1; then
        error "pacman 正在运行中，请等待完成后重试"
        pgrep -af pacman 2>/dev/null || true
        return 1
    fi

    # 残留锁文件，安全清理
    warn "检测到残留锁文件，正在清理..."
    sudo rm -f "$lock_file"
    success "pacman 锁文件已清理"
    return 0
}

# ==============================================================================
# 进度追踪
# ==============================================================================

# 全局进度变量
CURRENT_STEP=0
TOTAL_STEPS=0

init_progress() {
    TOTAL_STEPS="$1"
    CURRENT_STEP=0
}

next_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local pct=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo ""
    echo -e "${H_BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC}  ${BOLD}进度 [${CURRENT_STEP}/${TOTAL_STEPS}]${NC}  ${H_CYAN}${pct}%${NC}"
    echo -e "${H_BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    write_log "PROGRESS" "Step ${CURRENT_STEP}/${TOTAL_STEPS} (${pct}%)"
}

show_progress_bar() {
    local current="$1"
    local total="$2"
    local width=40
    local filled=$((current * width / total))
    local empty=$((width - filled))
    local pct=$((current * 100 / total))

    printf "\r   ["
    printf "%${filled}s" '' | tr ' ' '█'
    printf "%${empty}s" '' | tr ' ' '░'
    printf "] %3d%%" "$pct"
}
