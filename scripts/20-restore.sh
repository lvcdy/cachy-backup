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

# 备份中使用 greetd
BACKUP_USES_GREETD=0

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
    if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        info "检测到 TTY 环境，将以纯文本模式运行"
        export TTY_MODE=1
    else
        export TTY_MODE=0
    fi
}

# ==============================================================================
# 显示管理器统一处理
# ==============================================================================

handle_display_manager() {
    is_done "display_manager" && { info "显示管理器已处理，跳过"; return 0; }
    section "Display Manager" "处理显示管理器 (sddm → greetd)"

    # 检测备份中是否有 greetd 配置
    BACKUP_USES_GREETD=0
    [ -d "$STAGING_DIR/configs/greetd" ] && BACKUP_USES_GREETD=1

    # 检测当前系统安装了哪些 DM
    local dms_installed=()
    for dm in sddm gdm lightdm ly greetd lemurs lxdm plasma-login-manager; do
        if pacman -Q "$dm" &>/dev/null; then
            dms_installed+=("$dm")
        fi
    done

    local has_sddm=0
    local has_greetd=0
    for dm in "${dms_installed[@]}"; do
        [ "$dm" = "sddm" ] && has_sddm=1
        [ "$dm" = "greetd" ] && has_greetd=1
    done

    # 场景 1: 备份使用 greetd
    if [ "$BACKUP_USES_GREETD" -eq 1 ]; then
        if [ "$has_sddm" -eq 1 ]; then
            warn "检测到 sddm，备份使用 greetd"
            echo ""
            for dm in "${dms_installed[@]}"; do
                echo -e "       ${H_YELLOW}●${NC} 已安装: $dm"
            done
            echo ""

            if confirm "卸载 sddm 并安装 greetd？" "y"; then
                for dm in "${dms_installed[@]}"; do
                    if [ "$dm" != "greetd" ]; then
                        log "卸载 $dm..."
                        exe sudo pacman -Rns --noconfirm "$dm" || warn "$dm 卸载失败"
                    fi
                done
                if [ "$has_greetd" -eq 0 ]; then
                    log "安装 greetd..."
                    exe sudo pacman -S --noconfirm --needed greetd || warn "greetd 安装失败"
                fi
                success "显示管理器已切换到 greetd"
            else
                info "保留当前显示管理器"
                mark_done "skip_greetd"
            fi
        elif [ "$has_greetd" -eq 0 ] && [ ${#dms_installed[@]} -eq 0 ]; then
            info "未检测到显示管理器"
            if confirm "备份使用 greetd，是否安装？" "y"; then
                exe sudo pacman -S --noconfirm --needed greetd || warn "greetd 安装失败"
                success "greetd 已安装"
            else
                mark_done "skip_greetd"
            fi
        else
            info "greetd 已安装，无需切换"
        fi
    else
        # 备份不使用 greetd
        if [ ${#dms_installed[@]} -gt 0 ]; then
            info "当前显示管理器: ${dms_installed[*]}"
            info "备份未使用 greetd，保留当前配置"
        else
            info "未检测到显示管理器，备份中也无 DM 配置"
        fi
        mark_done "skip_greetd"
    fi

    mark_done "display_manager"
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

    if confirm "是否恢复 pacman.conf 和 mirrorlist？" "y"; then
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
# 恢复系统配置 (locale/snapper/greetd)
# ==============================================================================

restore_system_configs() {
    is_done "system_configs" && { info "系统配置已恢复，跳过"; return 0; }
    section "System Configs" "恢复 locale / snapper / greetd"

    # locale
    if [ -f "$STAGING_DIR/configs/locale.conf" ]; then
        if confirm "是否恢复 locale 设置？" "y"; then
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
        if confirm "是否恢复 snapper 配置？" "y"; then
            sudo mkdir -p /etc/snapper/configs
            exe sudo cp "$STAGING_DIR/configs/snapper"/* /etc/snapper/configs/ || warn "snapper 恢复失败"
            success "snapper 配置已恢复"
        else
            info "跳过 snapper"
        fi
    fi

    # greetd
    if is_done "skip_greetd"; then
        info "跳过 greetd 配置（用户选择跳过 DM 切换）"
    elif [ -d "$STAGING_DIR/configs/greetd" ]; then
        if confirm "是否恢复 greetd 配置文件？" "y"; then
            sudo mkdir -p /etc/greetd
            exe sudo cp -r "$STAGING_DIR/configs/greetd"/* /etc/greetd/ || warn "greetd 配置恢复失败"

            # 禁用 sddm，启用 greetd
            if pacman -Q sddm &>/dev/null; then
                log "禁用 sddm 服务..."
                exe sudo systemctl disable sddm 2>/dev/null || true
            fi
            log "启用 greetd 服务..."
            exe sudo systemctl enable greetd || warn "greetd 服务启用失败"
            success "greetd 配置已恢复，服务已启用"
        else
            info "跳过 greetd 配置"
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

    local installed_count
    installed_count=$(pacman -Qqen 2>/dev/null | wc -l || echo 0)

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

    echo ""
    info "将恢复以下目录:"
    [ -d "$STAGING_DIR/dotfile/.config" ] && echo -e "       ${H_YELLOW}●${NC} ~/.config (noctalia, fish, kitty, niri 等)"
    [ -d "$STAGING_DIR/dotfile/.local" ] && echo -e "       ${H_YELLOW}●${NC} ~/.local/share/fcitx5"
    echo ""

    if confirm "是否恢复 dotfile？" "y"; then
        # ~/.config (用 --delete 清理旧配置)
        if [ -d "$STAGING_DIR/dotfile/.config" ]; then
            log "恢复 ~/.config..."
            mkdir -p "$HOME/.config"
            exe rsync -a --delete \
                --exclude='.cache' \
                "$STAGING_DIR/dotfile/.config/" "$HOME/.config/" || warn "~/.config 恢复失败"
        fi

        # ~/.local/share/fcitx5
        if [ -d "$STAGING_DIR/dotfile/.local/share/fcitx5" ]; then
            log "恢复 fcitx5 数据..."
            mkdir -p "$HOME/.local/share/fcitx5"
            exe rsync -a "$STAGING_DIR/dotfile/.local/share/fcitx5/" "$HOME/.local/share/fcitx5/" || warn "fcitx5 恢复失败"
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
    handle_display_manager    # 统一处理 sddm → greetd 切换
    restore_pacman_conf
    restore_system_configs    # locale/snapper/greetd 配置
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
        if [ "$BACKUP_USES_GREETD" -eq 1 ]; then
            echo -e "       ${H_CYAN}sudo systemctl start greetd${NC}"
        else
            echo -e "       ${H_CYAN}sudo systemctl start display-manager${NC}"
        fi
        echo ""
    fi

    info_kv "Log File" "$LOG_FILE"
    echo ""
}
