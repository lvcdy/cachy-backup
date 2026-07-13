#!/bin/bash

# ==============================================================================
# 20-restore.sh - Restore Module
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

STAGING_DIR="${STAGING_DIR:-$HOME/.cache/cachy-backup-staging}"
REPO_NAME="${REPO_NAME:-cachy-backup}"

# ==============================================================================
# 恢复 pacman 配置
# ==============================================================================

restore_pacman_conf() {
    section "Pacman Config" "恢复 pacman 配置文件"

    local has_conf=0
    [ -f "$STAGING_DIR/configs/pacman.conf" ] && has_conf=1
    [ -f "$STAGING_DIR/configs/mirrorlist.txt" ] && has_conf=1

    if [ "$has_conf" -eq 0 ]; then
        warn "未找到 pacman 配置文件，跳过"
        return 0
    fi

    if confirm "是否恢复 pacman.conf 和 mirrorlist？(会覆盖当前配置)" "n"; then
        if [ -f "$STAGING_DIR/configs/pacman.conf" ]; then
            exe sudo cp "$STAGING_DIR/configs/pacman.conf" /etc/pacman.conf
        fi
        if [ -f "$STAGING_DIR/configs/mirrorlist.txt" ]; then
            exe sudo cp "$STAGING_DIR/configs/mirrorlist.txt" /etc/pacman.d/mirrorlist
        fi
        success "pacman 配置已恢复"
    else
        info "跳过 pacman 配置恢复"
    fi
}

# ==============================================================================
# 恢复 locale/snapper/greetd
# ==============================================================================

restore_system_configs() {
    section "System Configs" "恢复 locale/snapper/greetd"

    # locale
    if [ -f "$STAGING_DIR/configs/locale.conf" ]; then
        if confirm "是否恢复 locale 设置？" "n"; then
            exe sudo cp "$STAGING_DIR/configs/locale.conf" /etc/locale.conf
            if [ -f "$STAGING_DIR/configs/locale.gen" ]; then
                exe sudo cp "$STAGING_DIR/configs/locale.gen" /etc/locale.gen
                exe sudo locale-gen
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
            exe sudo cp "$STAGING_DIR/configs/snapper"/* /etc/snapper/configs/
            success "snapper 配置已恢复"
        else
            info "跳过 snapper"
        fi
    fi

    # greetd
    if [ -d "$STAGING_DIR/configs/greetd" ]; then
        if confirm "是否恢复 greetd 配置？" "n"; then
            sudo mkdir -p /etc/greetd
            exe sudo cp -r "$STAGING_DIR/configs/greetd"/* /etc/greetd/
            success "greetd 配置已恢复"
        else
            info "跳过 greetd"
        fi
    fi
}

# ==============================================================================
# 更新系统
# ==============================================================================

update_system() {
    section "System Update" "更新系统和 Keyring"

    log "更新 archlinux-keyring..."
    exe sudo pacman -Sy --needed --noconfirm archlinux-keyring

    log "系统全量更新..."
    exe sudo pacman -Syyu --noconfirm

    success "系统已更新"
}

# ==============================================================================
# 恢复官方软件包
# ==============================================================================

restore_official_packages() {
    section "Official Packages" "恢复官方软件包"

    if [ ! -f "$STAGING_DIR/packages/official.txt" ] || [ ! -s "$STAGING_DIR/packages/official.txt" ]; then
        warn "未找到官方包列表，跳过"
        return 0
    fi

    local count
    count=$(wc -l < "$STAGING_DIR/packages/official.txt")

    if confirm "是否恢复 ${count} 个官方软件包？" "y"; then
        log "正在安装官方软件包..."
        exe sudo pacman -S --needed - < "$STAGING_DIR/packages/official.txt"
        success "官方软件包恢复完成"
    else
        info "跳过官方软件包恢复"
    fi
}

# ==============================================================================
# 安装 AUR 助手
# ==============================================================================

install_aur_helper() {
    section "AUR Helper" "安装 AUR 助手"

    local helper
    helper=$(detect_aur_helper)

    if [ -n "$helper" ]; then
        info "已安装 AUR 助手: ${H_GREEN}${helper}${NC}"
        AUR_HELPER="$helper"
        return 0
    fi

    if confirm "未检测到 AUR 助手，是否安装 yay-bin？" "y"; then
        log "安装编译依赖..."
        exe sudo pacman -S --needed --noconfirm base-devel git

        log "克隆并编译 yay-bin..."
        rm -rf /tmp/yay-bin
        exe git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
        (cd /tmp/yay-bin && exe makepkg -si --noconfirm)
        rm -rf /tmp/yay-bin

        AUR_HELPER="yay"
        success "yay 已安装"
    else
        warn "未安装 AUR 助手，将无法恢复 AUR 包"
        AUR_HELPER=""
    fi
}

# ==============================================================================
# 恢复 AUR 软件包
# ==============================================================================

restore_aur_packages() {
    section "AUR Packages" "恢复 AUR 软件包"

    if [ ! -f "$STAGING_DIR/packages/aur.txt" ] || [ ! -s "$STAGING_DIR/packages/aur.txt" ]; then
        warn "未找到 AUR 包列表，跳过"
        return 0
    fi

    local count
    count=$(wc -l < "$STAGING_DIR/packages/aur.txt")

    if [ -z "${AUR_HELPER:-}" ]; then
        warn "无 AUR 助手，无法恢复 AUR 包"
        info "手动恢复: ${AUR_HELPER:-yay} -S --needed - < packages/aur.txt"
        return 0
    fi

    if confirm "是否恢复 ${count} 个 AUR 软件包？" "y"; then
        log "正在安装 AUR 软件包..."
        exe "$AUR_HELPER" -S --needed - < "$STAGING_DIR/packages/aur.txt"
        success "AUR 软件包恢复完成"
    else
        info "跳过 AUR 软件包恢复"
    fi
}

# ==============================================================================
# 恢复 Flatpak 软件包
# ==============================================================================

restore_flatpak_packages() {
    section "Flatpak Packages" "恢复 Flatpak 软件包"

    if [ ! -f "$STAGING_DIR/packages/flatpak.txt" ] || [ ! -s "$STAGING_DIR/packages/flatpak.txt" ]; then
        info "未找到 Flatpak 包列表，跳过"
        return 0
    fi

    local count
    count=$(wc -l < "$STAGING_DIR/packages/flatpak.txt")

    # 确保 flatpak 已安装
    if ! command -v flatpak &>/dev/null; then
        if confirm "未检测到 flatpak，是否安装？" "y"; then
            exe sudo pacman -S --needed --noconfirm flatpak
        else
            warn "跳过 Flatpak 恢复"
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
}

# ==============================================================================
# 恢复 Dotfile
# ==============================================================================

restore_dotfiles() {
    section "Dotfiles" "恢复用户配置文件"

    if [ ! -d "$STAGING_DIR/dotfile" ]; then
        info "未找到 dotfile 备份，跳过"
        return 0
    fi

    if confirm "是否恢复 dotfile？(~/.config 等)" "y"; then
        # ~/.config
        if [ -d "$STAGING_DIR/dotfile/dot_config" ]; then
            log "恢复 ~/.config..."
            mkdir -p "$HOME/.config"
            exe rsync -a "$STAGING_DIR/dotfile/dot_config/" "$HOME/.config/"
        fi

        # ~/.local/share/fcitx5
        if [ -d "$STAGING_DIR/dotfile/private_dot_local/private_share/fcitx5" ]; then
            log "恢复 fcitx5 数据..."
            mkdir -p "$HOME/.local/share/fcitx5"
            exe rsync -a "$STAGING_DIR/dotfile/private_dot_local/private_share/fcitx5/" "$HOME/.local/share/fcitx5/"
        fi

        success "dotfile 已恢复"
    else
        info "跳过 dotfile 恢复"
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

run_restore() {
    local gh_user="$1"

    show_banner
    section "Restore" "开始系统恢复"

    # 显示备份信息
    if [ -f "$STAGING_DIR/configs/system-info.txt" ]; then
        echo ""
        info_kv "Backup Host" "$(grep '^hostname:' "$STAGING_DIR/configs/system-info.txt" | cut -d: -f2 | xargs)"
        info_kv "Backup Date" "$(grep '^date:' "$STAGING_DIR/configs/system-info.txt" | cut -d: -f2- | xargs)"
        info_kv "Backup Kernel" "$(grep '^kernel:' "$STAGING_DIR/configs/system-info.txt" | cut -d: -f2 | xargs)"
        echo ""
    fi

    AUR_HELPER=$(detect_aur_helper)

    restore_pacman_conf
    restore_system_configs
    update_system
    restore_official_packages
    install_aur_helper
    restore_aur_packages
    restore_flatpak_packages
    restore_dotfiles

    echo ""
    success "🎉 系统恢复完成！"
    echo ""
}
