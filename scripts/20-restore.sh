#!/bin/bash

# ==============================================================================
# 20-restore.sh - Restore Module
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

# 恢复模式禁用 set -e，允许单个步骤失败后继续
set +e

STAGING_DIR="${STAGING_DIR:-$HOME/.cache/cachy-backup-staging}"
REPO_NAME="${REPO_NAME:-cachy-backup}"
STATE_FILE="$STAGING_DIR/.restore_progress"

# 已知的显示管理器列表
KNOWN_DMS=("sddm" "gdm" "lightdm" "ly" "greetd" "lemurs" "lxdm" "plasma-login-manager")

# 需要清理的冲突包
CONFLICT_PACKAGES=("quickshell" "sddm")

# ==============================================================================
# 进度追踪
# ==============================================================================

mark_done() {
    echo "$1" >> "$STATE_FILE"
}

is_done() {
    [ -f "$STATE_FILE" ] && grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

# ==============================================================================
# TTY 环境检测
# ==============================================================================

check_tty() {
    # 检测是否在 TTY 环境
    if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        info "检测到 TTY 环境，将以纯文本模式运行"
        export TTY_MODE=1
    else
        export TTY_MODE=0
    fi
}

# ==============================================================================
# 显示管理器冲突检测
# ==============================================================================

check_dm_conflict() {
    is_done "dm_conflict" && { info "显示管理器检查已完成，跳过"; return 0; }
    section "Display Manager" "检测显示管理器冲突"

    local dm_found=""
    local dms_installed=()

    # 检测已安装的显示管理器
    for dm in "${KNOWN_DMS[@]}"; do
        if pacman -Q "$dm" &>/dev/null; then
            dms_installed+=("$dm")
            [ -z "$dm_found" ] && dm_found="$dm"
        fi
    done

    # 备份中使用 greetd
    local backup_uses_greetd=0
    [ -d "$STAGING_DIR/configs/greetd" ] && backup_uses_greetd=1

    if [ ${#dms_installed[@]} -gt 0 ]; then
        echo ""
        info "检测到已安装的显示管理器:"
        for dm in "${dms_installed[@]}"; do
            echo -e "       ${H_YELLOW}●${NC} $dm"
        done
        echo ""

        # 如果备份使用 greetd，但系统有其他 DM
        if [ "$backup_uses_greetd" -eq 1 ] && [[ ! " ${dms_installed[*]} " =~ " greetd " ]]; then
            warn "备份使用 greetd，但系统有其他显示管理器"
            if confirm "是否卸载冲突的显示管理器并安装 greetd？" "n"; then
                for dm in "${dms_installed[@]}"; do
                    log "卸载 $dm..."
                    exe sudo pacman -Rns --noconfirm "$dm" || warn "$dm 卸载失败"
                done
                log "安装 greetd..."
                exe sudo pacman -S --noconfirm --needed greetd || warn "greetd 安装失败"
                success "显示管理器已切换到 greetd"
            else
                info "保留当前显示管理器，跳过 greetd 配置"
                # 标记不恢复 greetd
                mark_done "skip_greetd"
            fi
        fi
    else
        info "未检测到已安装的显示管理器"
        if [ "$backup_uses_greetd" -eq 1 ]; then
            if confirm "备份使用 greetd，是否安装？" "y"; then
                exe sudo pacman -S --noconfirm --needed greetd || warn "greetd 安装失败"
                success "greetd 已安装"
            else
                mark_done "skip_greetd"
            fi
        fi
    fi

    mark_done "dm_conflict"
}

# ==============================================================================
# 清理冲突包 (quickshell/sddm)
# ==============================================================================

cleanup_conflicts() {
    is_done "cleanup" && { info "冲突包清理已完成，跳过"; return 0; }
    section "Cleanup" "清理冲突包"

    local to_remove=()

    # 检测需要清理的包
    for pkg in "${CONFLICT_PACKAGES[@]}"; do
        if pacman -Q "$pkg" &>/dev/null; then
            to_remove+=("$pkg")
        fi
    done

    if [ ${#to_remove[@]} -gt 0 ]; then
        echo ""
        warn "检测到以下可能冲突的包:"
        for pkg in "${to_remove[@]}"; do
            echo -e "       ${H_YELLOW}●${NC} $pkg"
        done
        echo ""

        if confirm "是否卸载这些包？" "y"; then
            for pkg in "${to_remove[@]}"; do
                log "卸载 $pkg..."
                exe sudo pacman -Rns --noconfirm "$pkg" || warn "$pkg 卸载失败"
            done
            success "冲突包已清理"
        else
            info "跳过清理"
        fi
    else
        info "未检测到冲突包"
    fi

    mark_done "cleanup"
}

# ==============================================================================
# 恢复 pacman 配置
# ==============================================================================

restore_pacman_conf() {
    is_done "pacman_conf" && { info "pacman 配置已恢复，跳过"; return 0; }
    section "Pacman Config" "恢复 pacman 配置文件"

    local has_conf=0
    [ -f "$STAGING_DIR/configs/pacman.conf" ] && has_conf=1
    [ -f "$STAGING_DIR/configs/mirrorlist.txt" ] && has_conf=1

    if [ "$has_conf" -eq 0 ]; then
        warn "未找到 pacman 配置文件，跳过"
        mark_done "pacman_conf"
        return 0
    fi

    if confirm "是否恢复 pacman.conf 和 mirrorlist？(会覆盖当前配置)" "n"; then
        if [ -f "$STAGING_DIR/configs/pacman.conf" ]; then
            exe sudo cp "$STAGING_DIR/configs/pacman.conf" /etc/pacman.conf || warn "pacman.conf 恢复失败"
        fi
        if [ -f "$STAGING_DIR/configs/mirrorlist.txt" ]; then
            exe sudo cp "$STAGING_DIR/configs/mirrorlist.txt" /etc/pacman.d/mirrorlist || warn "mirrorlist 恢复失败"
        fi
        success "pacman 配置已恢复"
    else
        info "跳过 pacman 配置恢复"
    fi
    mark_done "pacman_conf"
}

# ==============================================================================
# 恢复 locale/snapper/greetd
# ==============================================================================

restore_system_configs() {
    is_done "system_configs" && { info "系统配置已恢复，跳过"; return 0; }
    section "System Configs" "恢复 locale/snapper/greetd"

    # locale
    if [ -f "$STAGING_DIR/configs/locale.conf" ]; then
        if confirm "是否恢复 locale 设置？" "n"; then
            exe sudo cp "$STAGING_DIR/configs/locale.conf" /etc/locale.conf || warn "locale.conf 恢复失败"
            if [ -f "$STAGING_DIR/configs/locale.gen" ]; then
                exe sudo cp "$STAGING_DIR/configs/locale.gen" /etc/locale.gen || warn "locale.gen 恢复失败"
                exe sudo locale-gen || warn "locale-gen 失败"
            fi
            success "locale 已恢复"
        else
            info "跳过 locale"
        fi
    fi

    # snapper
    if [ -d "$STAGING_DIR/configs/snapper" ]; then
        if confirm "是否恢复 snapper 配置？" "n"; then
            sudo mkdir -p /etc/snapper/configs
            exe sudo cp "$STAGING_DIR/configs/snapper"/* /etc/snapper/configs/ || warn "snapper 恢复失败"
            success "snapper 配置已恢复"
        else
            info "跳过 snapper"
        fi
    fi

    # greetd (检查是否需要跳过)
    if is_done "skip_greetd"; then
        info "跳过 greetd 配置（用户选择或存在冲突）"
    elif [ -d "$STAGING_DIR/configs/greetd" ]; then
        if confirm "是否恢复 greetd 配置？" "n"; then
            sudo mkdir -p /etc/greetd
            exe sudo cp -r "$STAGING_DIR/configs/greetd"/* /etc/greetd/ || warn "greetd 恢复失败"
            # 启用 greetd 服务
            exe sudo systemctl enable greetd || warn "greetd 服务启用失败"
            success "greetd 配置已恢复"
        else
            info "跳过 greetd"
        fi
    fi
    mark_done "system_configs"
}

# ==============================================================================
# 更新系统
# ==============================================================================

update_system() {
    is_done "system_update" && { info "系统已更新，跳过"; return 0; }
    section "System Update" "更新系统和 Keyring"

    log "更新 archlinux-keyring..."
    exe sudo pacman -Sy --needed --noconfirm archlinux-keyring || warn "keyring 更新失败，继续..."

    log "系统全量更新..."
    exe sudo pacman -Syyu --noconfirm || warn "系统更新失败，继续..."

    success "系统已更新"
    mark_done "system_update"
}

# ==============================================================================
# 恢复官方软件包
# ==============================================================================

restore_official_packages() {
    is_done "official_packages" && { info "官方包已恢复，跳过"; return 0; }
    section "Official Packages" "恢复官方软件包"

    if [ ! -f "$STAGING_DIR/packages/official.txt" ] || [ ! -s "$STAGING_DIR/packages/official.txt" ]; then
        warn "未找到官方包列表，跳过"
        mark_done "official_packages"
        return 0
    fi

    local backup_count
    backup_count=$(wc -l < "$STAGING_DIR/packages/official.txt")

    # 检查系统当前已安装的软件包
    local installed_count
    installed_count=$(pacman -Qqen 2>/dev/null | wc -l || echo 0)

    # 计算缺失的软件包
    local missing_packages
    missing_packages=$(comm -23 <(sort "$STAGING_DIR/packages/official.txt") <(pacman -Qqen 2>/dev/null | sort) || true)
    local missing_count
    missing_count=$(echo "$missing_packages" | grep -c . || echo 0)

    echo ""
    info_kv "备份包数" "${BOLD}${backup_count}${NC}"
    info_kv "已安装" "${BOLD}${installed_count}${NC}"
    info_kv "缺失" "${H_YELLOW}${BOLD}${missing_count}${NC}"
    echo ""

    if [ "$missing_count" -eq 0 ]; then
        success "所有官方包已安装，无需更新"
        mark_done "official_packages"
        return 0
    fi

    if confirm "是否安装缺失的 ${missing_count} 个官方软件包？" "y"; then
        log "正在安装缺失的官方软件包..."
        echo "$missing_packages" | sudo pacman -S --needed --noconfirm - || warn "部分官方包安装失败"
        success "官方软件包恢复完成"
    else
        info "跳过官方软件包恢复"
    fi
    mark_done "official_packages"
}

# ==============================================================================
# 安装 AUR 助手
# ==============================================================================

install_aur_helper() {
    is_done "aur_helper" && { info "AUR 助手已安装，跳过"; return 0; }
    section "AUR Helper" "安装 AUR 助手"

    local helper
    helper=$(detect_aur_helper)

    if [ -n "$helper" ]; then
        info "已安装 AUR 助手: ${H_GREEN}${helper}${NC}"
        AUR_HELPER="$helper"
        mark_done "aur_helper"
        return 0
    fi

    if confirm "未检测到 AUR 助手，是否安装 yay-bin？" "y"; then
        log "安装编译依赖..."
        exe sudo pacman -S --needed --noconfirm base-devel git || { warn "编译依赖安装失败"; mark_done "aur_helper"; return 1; }

        log "克隆并编译 yay-bin..."
        rm -rf /tmp/yay-bin
        exe git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin || { warn "yay 克隆失败"; mark_done "aur_helper"; return 1; }
        (cd /tmp/yay-bin && exe makepkg -si --noconfirm) || { warn "yay 编译失败"; mark_done "aur_helper"; return 1; }
        rm -rf /tmp/yay-bin

        AUR_HELPER="yay"
        success "yay 已安装"
    else
        warn "未安装 AUR 助手，将无法恢复 AUR 包"
        AUR_HELPER=""
    fi
    mark_done "aur_helper"
}

# ==============================================================================
# 恢复 AUR 软件包
# ==============================================================================

restore_aur_packages() {
    is_done "aur_packages" && { info "AUR 包已恢复，跳过"; return 0; }
    section "AUR Packages" "恢复 AUR 软件包"

    if [ ! -f "$STAGING_DIR/packages/aur.txt" ] || [ ! -s "$STAGING_DIR/packages/aur.txt" ]; then
        warn "未找到 AUR 包列表，跳过"
        mark_done "aur_packages"
        return 0
    fi

    local count
    count=$(wc -l < "$STAGING_DIR/packages/aur.txt")

    if [ -z "${AUR_HELPER:-}" ]; then
        warn "无 AUR 助手，无法恢复 AUR 包"
        info "手动恢复: yay -S --needed - < packages/aur.txt"
        mark_done "aur_packages"
        return 0
    fi

    if confirm "是否恢复 ${count} 个 AUR 软件包？" "y"; then
        log "正在安装 AUR 软件包..."
        exe "$AUR_HELPER" -S --needed - < "$STAGING_DIR/packages/aur.txt" || warn "部分 AUR 包安装失败"
        success "AUR 软件包恢复完成"
    else
        info "跳过 AUR 软件包恢复"
    fi
    mark_done "aur_packages"
}

# ==============================================================================
# 恢复 Flatpak 软件包
# ==============================================================================

restore_flatpak_packages() {
    is_done "flatpak_packages" && { info "Flatpak 包已恢复，跳过"; return 0; }
    section "Flatpak Packages" "恢复 Flatpak 软件包"

    if [ ! -f "$STAGING_DIR/packages/flatpak.txt" ] || [ ! -s "$STAGING_DIR/packages/flatpak.txt" ]; then
        info "未找到 Flatpak 包列表，跳过"
        mark_done "flatpak_packages"
        return 0
    fi

    local count
    count=$(wc -l < "$STAGING_DIR/packages/flatpak.txt")

    # 确保 flatpak 已安装
    if ! command -v flatpak &>/dev/null; then
        if confirm "未检测到 flatpak，是否安装？" "y"; then
            exe sudo pacman -S --needed --noconfirm flatpak || warn "flatpak 安装失败"
        else
            warn "跳过 Flatpak 恢复"
            mark_done "flatpak_packages"
            return 0
        fi
    fi

    if confirm "是否恢复 ${count} 个 Flatpak 软件包？" "y"; then
        log "正在安装 Flatpak 软件包..."
        xargs -a "$STAGING_DIR/packages/flatpak.txt" flatpak install -y --noninteractive 2>/dev/null || \
            warn "部分 Flatpak 包安装失败"
        success "Flatpak 软件包恢复完成"
    else
        info "跳过 Flatpak 软件包恢复"
    fi
    mark_done "flatpak_packages"
}

# ==============================================================================
# 恢复 Dotfile
# ==============================================================================

restore_dotfiles() {
    is_done "dotfiles" && { info "dotfile 已恢复，跳过"; return 0; }
    section "Dotfiles" "恢复用户配置文件"

    if [ ! -d "$STAGING_DIR/dotfile" ]; then
        info "未找到 dotfile 备份，跳过"
        mark_done "dotfiles"
        return 0
    fi

    if confirm "是否恢复 dotfile？(~/.config 等)" "y"; then
        # ~/.config
        if [ -d "$STAGING_DIR/dotfile/dot_config" ]; then
            log "恢复 ~/.config..."
            mkdir -p "$HOME/.config"
            exe rsync -a "$STAGING_DIR/dotfile/dot_config/" "$HOME/.config/" || warn "~/.config 恢复失败"
        fi

        # ~/.local/share/fcitx5
        if [ -d "$STAGING_DIR/dotfile/private_dot_local/private_share/fcitx5" ]; then
            log "恢复 fcitx5 数据..."
            mkdir -p "$HOME/.local/share/fcitx5"
            exe rsync -a "$STAGING_DIR/dotfile/private_dot_local/private_share/fcitx5/" "$HOME/.local/share/fcitx5/" || warn "fcitx5 恢复失败"
        fi

        success "dotfile 已恢复"
    else
        info "跳过 dotfile 恢复"
    fi
    mark_done "dotfiles"
}

# ==============================================================================
# 主函数
# ==============================================================================

run_restore() {
    local gh_user="$1"

    show_banner
    check_tty

    section "Restore" "开始系统恢复"

    # 显示备份信息
    if [ -f "$STAGING_DIR/configs/system-info.txt" ]; then
        echo ""
        info_kv "Backup Host" "$(grep '^hostname:' "$STAGING_DIR/configs/system-info.txt" | cut -d: -f2 | xargs)"
        info_kv "Backup Date" "$(grep '^date:' "$STAGING_DIR/configs/system-info.txt" | cut -d: -f2- | xargs)"
        info_kv "Backup Kernel" "$(grep '^kernel:' "$STAGING_DIR/configs/system-info.txt" | cut -d: -f2 | xargs)"
        info_kv "TTY Mode" "$([ "$TTY_MODE" -eq 1 ] && echo 'Yes' || echo 'No')"
        echo ""
    fi

    # 检查是否可以恢复
    if [ -f "$STATE_FILE" ]; then
        local done_count
        done_count=$(wc -l < "$STATE_FILE")
        info "检测到上次进度 ($done_count 步已完成)，将跳过已完成的步骤"
        echo ""
    fi

    AUR_HELPER=$(detect_aur_helper)

    # 恢复流程
    cleanup_conflicts          # 清理 quickshell/sddm 等冲突包
    check_dm_conflict          # 检测显示管理器冲突
    restore_pacman_conf
    restore_system_configs
    update_system
    restore_official_packages
    install_aur_helper
    restore_aur_packages
    restore_flatpak_packages
    restore_dotfiles

    # 清理进度文件
    [ -f "$STATE_FILE" ] && rm -f "$STATE_FILE"

    echo ""
    success "🎉 系统恢复完成！"
    echo ""

    # TTY 环境下提示启动桌面
    if [ "$TTY_MODE" -eq 1 ]; then
        warn "当前在 TTY 环境，恢复完成后需要手动启动桌面:"
        echo -e "       ${H_CYAN}sudo systemctl start greetd${NC}"
        echo ""
    fi

    info_kv "Log File" "$LOG_FILE"
    echo ""
}
