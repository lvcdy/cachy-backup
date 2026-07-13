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

    # 恢复 pacman.conf
    if [ -f "$STAGING_DIR/configs/pacman.conf" ]; then
        if confirm "是否恢复 pacman.conf？" "y"; then
            exe sudo cp "$STAGING_DIR/configs/pacman.conf" /etc/pacman.conf || warn "pacman.conf 恢复失败"
        fi
    fi

    # 镜源选择
    if [ -f "$STAGING_DIR/configs/mirrorlist.txt" ]; then
        echo ""
        info "选择镜像源:"
        echo -e "       ${H_CYAN}[1]${NC} 恢复备份中的 mirrorlist (默认)"
        echo -e "       ${H_CYAN}[2]${NC} 使用 reflector 自动选择最快镜像"
        echo -e "       ${H_CYAN}[3]${NC} 使用 CachyOS 官方镜像"
        echo -e "       ${H_CYAN}[4]${NC} 跳过，保持当前 mirrorlist"
        echo ""

        local mirror_choice
        read -r -p "$(echo -e "   ${H_CYAN}选择 [1-4]: ${NC}")" mirror_choice < /dev/tty 2>/dev/null || mirror_choice="1"

        case "$mirror_choice" in
            1)
                exe sudo cp "$STAGING_DIR/configs/mirrorlist.txt" /etc/pacman.d/mirrorlist || warn "mirrorlist 恢复失败"
                success "已恢复备份 mirrorlist"
                ;;
            2)
                if command -v reflector &>/dev/null; then
                    log "使用 reflector 获取最快镜像..."
                    local reflector_rc=0
                    exe sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist || reflector_rc=$?
                    if [ "$reflector_rc" -ne 0 ]; then
                        warn "reflector 失败，使用备份 mirrorlist"
                        exe sudo cp "$STAGING_DIR/configs/mirrorlist.txt" /etc/pacman.d/mirrorlist
                    fi
                else
                    warn "reflector 未安装，使用备份 mirrorlist"
                    exe sudo cp "$STAGING_DIR/configs/mirrorlist.txt" /etc/pacman.d/mirrorlist
                fi
                ;;
            3)
                log "设置 CachyOS 官方镜像..."
                sudo tee /etc/pacman.d/mirrorlist >/dev/null <<'MIRROR'
## CachyOS Mirrorlist
Server = https://mirror.cachyos.org/repo/$arch/$repo
Server = https://mirror.cachyos.org.de/repo/$arch/$repo
MIRROR
                success "已设置 CachyOS 官方镜像"
                ;;
            4)
                info "保持当前 mirrorlist"
                ;;
            *)
                exe sudo cp "$STAGING_DIR/configs/mirrorlist.txt" /etc/pacman.d/mirrorlist || warn "mirrorlist 恢复失败"
                ;;
        esac
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

    # 确保 pacman 未被锁定
    ensure_pacman_unlocked || { error "pacman 被锁定，无法继续"; mark_done "system_update"; return 1; }

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
    show_package_progress "官方包" "$backup_count" "$missing_count"

    if [ "$missing_count" -eq 0 ]; then
        success "所有官方包已安装，无需更新"
        mark_done "official_packages"
        return 0
    fi

    if confirm "是否安装缺失的 ${missing_count} 个官方软件包？" "y"; then
        ensure_pacman_unlocked || { mark_done "official_packages"; return 1; }
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
        ensure_pacman_unlocked || { mark_done "aur_helper"; return 1; }
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
            ensure_pacman_unlocked || { mark_done "flatpak_packages"; return 1; }
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
    [ -d "$STAGING_DIR/dotfile/.local" ] && echo -e "       ${H_YELLOW}●${NC} ~/.local (share/fonts, share/fcitx5, share/applications, bin)"
    echo ""

    if confirm "是否恢复 dotfile？" "y"; then
        # ~/.config
        if [ -d "$STAGING_DIR/dotfile/.config" ]; then
            log "恢复 ~/.config..."
            mkdir -p "$HOME/.config"
            local exclude_file="$SCRIPT_DIR/../config/exclude-backup.txt"
            local exclude_args=(--exclude='.cache')
            [ -f "$exclude_file" ] && exclude_args=(--exclude-from "$exclude_file")
            exe rsync -a --info=progress2 \
                "${exclude_args[@]}" \
                "$STAGING_DIR/dotfile/.config/" "$HOME/.config/" || warn "~/.config 恢复失败"
        fi

        # ~/.local/share/fcitx5
        if [ -d "$STAGING_DIR/dotfile/.local/share/fcitx5" ]; then
            log "恢复 fcitx5 数据..."
            mkdir -p "$HOME/.local/share/fcitx5"
            exe rsync -a "$STAGING_DIR/dotfile/.local/share/fcitx5/" "$HOME/.local/share/fcitx5/" || warn "fcitx5 恢复失败"
        fi

        # ~/.local/bin/
        if [ -d "$STAGING_DIR/dotfile/.local/bin" ]; then
            log "恢复 ~/.local/bin/ ..."
            mkdir -p "$HOME/.local/bin"
            exe rsync -a "$STAGING_DIR/dotfile/.local/bin/" "$HOME/.local/bin/" || warn "~/.local/bin 恢复失败"
        fi

        # ~/.local/share/fonts/
        if [ -d "$STAGING_DIR/dotfile/.local/share/fonts" ]; then
            log "恢复用户字体..."
            mkdir -p "$HOME/.local/share/fonts"
            exe rsync -a "$STAGING_DIR/dotfile/.local/share/fonts/" "$HOME/.local/share/fonts/" || warn "用户字体恢复失败"
        fi

        # ~/.local/share/applications/
        if [ -d "$STAGING_DIR/dotfile/.local/share/applications" ]; then
            log "恢复自定义 desktop 文件..."
            mkdir -p "$HOME/.local/share/applications"
            exe rsync -a "$STAGING_DIR/dotfile/.local/share/applications/" "$HOME/.local/share/applications/" || warn "desktop 文件恢复失败"
        fi

        # ~/.local/share/noctalia/plugins/ (Noctalia v5 插件)
        if [ -d "$STAGING_DIR/dotfile/.local/share/noctalia" ]; then
            log "恢复 Noctalia 插件..."
            mkdir -p "$HOME/.local/share/noctalia"
            exe rsync -a "$STAGING_DIR/dotfile/.local/share/noctalia/" "$HOME/.local/share/noctalia/" || warn "Noctalia 插件恢复失败"
        fi

        # ~/.local/state/noctalia/settings.toml (Noctalia v5 GUI 覆盖)
        if [ -f "$STAGING_DIR/dotfile/.local/state/noctalia/settings.toml" ]; then
            log "恢复 Noctalia settings.toml..."
            mkdir -p "$HOME/.local/state/noctalia"
            cp "$STAGING_DIR/dotfile/.local/state/noctalia/settings.toml" "$HOME/.local/state/noctalia/settings.toml" 2>/dev/null || warn "Noctalia settings.toml 恢复失败"
        fi

        # ~/.profile / ~/.bash_profile / ~/.bashrc / ~/.zshenv
        log "恢复 Shell 启动文件..."
        for f in .profile .bash_profile .bashrc .zshenv .gitconfig; do
            if [ -f "$STAGING_DIR/dotfile/$f" ]; then
                cp "$STAGING_DIR/dotfile/$f" "$HOME/$f"
                log "  已恢复 ~/$f"
            fi
        done

        success "dotfile 已恢复"
    else
        info "跳过 dotfile 恢复"
    fi
    mark_done "dotfiles"
}

# ==============================================================================
# 恢复 systemd 服务
# ==============================================================================

restore_services() {
    is_done "services" && { info "服务已恢复，跳过"; return 0; }
    section "Services" "恢复 systemd 服务"

    # --- 用户服务 ---
    if [ -f "$STAGING_DIR/services/user-services.txt" ]; then
        local user_count
        user_count=$(wc -l < "$STAGING_DIR/services/user-services.txt")
        info "备份中有 ${BOLD}${user_count}${NC} 个用户服务"

        # 排除不适合直接启用的服务
        local skip_services="default.target graphical.target multi-user.target basic.target \
            sockets.target timers.target paths.target \
            grub-btrfs-snapper.timer grub-btrfsd.service"

        local enabled=0 skipped=0 failed=0
        while IFS= read -r service; do
            [ -z "$service" ] && continue

            # 跳过特殊 target
            local should_skip=0
            for skip in $skip_services; do
                if [ "$service" = "$skip" ]; then
                    should_skip=1
                    break
                fi
            done
            if [ "$should_skip" -eq 1 ]; then
                skipped=$((skipped + 1))
                continue
            fi

            # 只启用已安装的服务
            if systemctl --user list-unit-files "$service" &>/dev/null; then
                if systemctl --user enable "$service" 2>/dev/null; then
                    enabled=$((enabled + 1))
                else
                    failed=$((failed + 1))
                fi
            else
                skipped=$((skipped + 1))
            fi
        done < "$STAGING_DIR/services/user-services.txt"

        info_kv "已启用" "${H_GREEN}${BOLD}${enabled}${NC}"
        [ "$skipped" -gt 0 ] && info_kv "跳过" "${BOLD}${skipped}${NC}"
        [ "$failed" -gt 0 ] && info_kv "失败" "${H_YELLOW}${BOLD}${failed}${NC}"
    else
        info "未找到用户服务列表"
    fi

    # --- 系统服务 ---
    if [ -f "$STAGING_DIR/services/system-services.txt" ]; then
        local sys_count
        sys_count=$(wc -l < "$STAGING_DIR/services/system-services.txt")
        info "备份中有 ${BOLD}${sys_count}${NC} 个系统服务"

        local sys_skip="getty@.service serial-getty@.service \
            systemd-boot-system-token.service \
            systemd-firstboot.service \
            initrd-switch-root.service"

        local sys_enabled=0 sys_skipped=0
        while IFS= read -r service; do
            [ -z "$service" ] && continue

            local should_skip=0
            for skip in $sys_skip; do
                if [ "$service" = "$skip" ]; then
                    should_skip=1
                    break
                fi
            done
            [ "$should_skip" -eq 1 ] && { sys_skipped=$((sys_skipped + 1)); continue; }

            if systemctl list-unit-files "$service" &>/dev/null; then
                if sudo systemctl enable "$service" 2>/dev/null; then
                    sys_enabled=$((sys_enabled + 1))
                fi
            fi
        done < "$STAGING_DIR/services/system-services.txt"

        info_kv "系统服务已启用" "${H_GREEN}${BOLD}${sys_enabled}${NC}"
    fi

    # --- 确保关键桌面服务启用 ---
    log "确保关键桌面服务已启用..."
    local critical_user_services="pipewire.service pipewire-pulse.service wireplumber.service"
    for svc in $critical_user_services; do
        if systemctl --user list-unit-files "$svc" &>/dev/null; then
            systemctl --user enable "$svc" 2>/dev/null && log "  已启用 $svc"
        fi
    done

    success "服务恢复完成"
    mark_done "services"
}

# ==============================================================================
# 恢复字体缓存
# ==============================================================================

restore_fonts() {
    is_done "fonts" && { info "字体已恢复，跳过"; return 0; }
    section "Fonts" "重建字体缓存"

    if [ -d "$HOME/.local/share/fonts" ] && [ "$(ls -A "$HOME/.local/share/fonts" 2>/dev/null)" ]; then
        log "重建用户字体缓存..."
        if command -v fc-cache &>/dev/null; then
            exe fc-cache -fv "$HOME/.local/share/fonts" || warn "字体缓存重建失败"
            success "字体缓存已重建"
        else
            warn "fc-cache 未找到，请手动运行: fc-cache -fv"
        fi
    else
        info "无用户字体，跳过"
    fi
    mark_done "fonts"
}

# ==============================================================================
# 恢复用户组
# ==============================================================================

restore_user_groups() {
    is_done "user_groups" && { info "用户组已恢复，跳过"; return 0; }
    section "User Groups" "检查并添加用户组"

    if [ ! -f "$STAGING_DIR/metadata/user-groups.txt" ]; then
        info "未找到用户组备份，跳过"
        mark_done "user_groups"
        return 0
    fi

    local current_user="${SUDO_USER:-$USER}"

    # 必要的桌面环境组
    local required_groups="video audio input storage wheel"
    # 从备份中读取
    local backup_groups
    backup_groups=$(cat "$STAGING_DIR/metadata/user-groups.txt" 2>/dev/null)
    # 合并
    local all_groups
    all_groups=$(echo -e "$required_groups\n$backup_groups" | sort -u | grep -v '^$')

    local added=0
    while IFS= read -r grp; do
        [ -z "$grp" ] && continue
        # 检查组是否存在
        if getent group "$grp" &>/dev/null; then
            # 检查用户是否已在组中
            if ! id -nG "$current_user" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
                if sudo usermod -aG "$grp" "$current_user" 2>/dev/null; then
                    log "  已添加到 $grp"
                    added=$((added + 1))
                fi
            fi
        fi
    done <<< "$all_groups"

    if [ "$added" -gt 0 ]; then
        success "已添加 ${added} 个用户组（重新登录后生效）"
    else
        success "用户组已就绪"
    fi
    mark_done "user_groups"
}

# ==============================================================================
# 恢复 dconf 设置
# ==============================================================================

restore_dconf() {
    is_done "dconf" && { info "dconf 已恢复，跳过"; return 0; }
    section "dconf" "恢复桌面环境设置 (GTK/字体/光标)"

    if [ ! -f "$STAGING_DIR/metadata/dconf-user.ini" ]; then
        info "未找到 dconf 备份，跳过"
        mark_done "dconf"
        return 0
    fi

    if ! command -v dconf &>/dev/null; then
        warn "dconf 未安装，跳过"
        mark_done "dconf"
        return 0
    fi

    if confirm "是否恢复 dconf 设置（GTK主题/字体/光标等）？" "y"; then
        log "加载 dconf 设置..."
        dconf load / < "$STAGING_DIR/metadata/dconf-user.ini" 2>/dev/null || warn "dconf 加载部分失败"
        success "dconf 设置已恢复"
    else
        info "跳过 dconf 恢复"
    fi
    mark_done "dconf"
}

# ==============================================================================
# 恢复默认 Shell
# ==============================================================================

restore_default_shell() {
    is_done "default_shell" && { info "默认 Shell 已恢复，跳过"; return 0; }
    section "Default Shell" "恢复默认登录 Shell"

    if [ ! -f "$STAGING_DIR/metadata/default-shell.txt" ]; then
        info "未找到默认 Shell 备份，跳过"
        mark_done "default_shell"
        return 0
    fi

    local target_shell
    target_shell=$(cat "$STAGING_DIR/metadata/default-shell.txt")
    local current_shell
    current_shell=$(getent passwd "${SUDO_USER:-$USER}" 2>/dev/null | cut -d: -f7)

    if [ "$target_shell" = "$current_shell" ]; then
        success "默认 Shell 已是 $target_shell"
        mark_done "default_shell"
        return 0
    fi

    # 检查目标 shell 是否已安装
    if [ ! -x "$target_shell" ]; then
        warn "Shell $target_shell 未安装，跳过"
        mark_done "default_shell"
        return 0
    fi

    if confirm "是否将默认 Shell 从 $current_shell 切换到 $target_shell？" "y"; then
        local current_user="${SUDO_USER:-$USER}"
        exe sudo chsh -s "$target_shell" "$current_user" || warn "Shell 切换失败"
        success "默认 Shell 已切换为 $target_shell（重新登录后生效）"
    else
        info "保留当前 Shell: $current_shell"
    fi
    mark_done "default_shell"
}

# ==============================================================================
# 恢复 crontab
# ==============================================================================

restore_crontab() {
    is_done "crontab" && { info "crontab 已恢复，跳过"; return 0; }
    section "Crontab" "恢复定时任务"

    if [ ! -f "$STAGING_DIR/metadata/crontab.txt" ] || [ ! -s "$STAGING_DIR/metadata/crontab.txt" ]; then
        info "未找到 crontab 备份，跳过"
        mark_done "crontab"
        return 0
    fi

    local line_count
    line_count=$(wc -l < "$STAGING_DIR/metadata/crontab.txt")

    if confirm "是否恢复 crontab（${line_count} 条任务）？" "y"; then
        exe crontab "$STAGING_DIR/metadata/crontab.txt" || warn "crontab 恢复失败"
        success "crontab 已恢复"
    else
        info "跳过 crontab 恢复"
    fi
    mark_done "crontab"
}

# ==============================================================================
# 恢复 Noctalia v5 桌面环境
# ==============================================================================

restore_noctalia() {
    is_done "noctalia" && { info "Noctalia 已恢复，跳过"; return 0; }
    section "Noctalia" "恢复 Noctalia v5 桌面环境"

    # 检查备份是否包含 Noctalia 配置
    if [ ! -d "$STAGING_DIR/dotfile/.config/noctalia" ] && \
       [ ! -d "$STAGING_DIR/metadata/noctalia" ]; then
        info "备份中未发现 Noctalia 配置，跳过"
        mark_done "noctalia"
        return 0
    fi

    # 安装 noctalia-git
    if ! command -v noctalia &>/dev/null; then
        if pacman -Q noctalia-git &>/dev/null 2>&1; then
            info "noctalia-git 已安装"
        else
            log "安装 noctalia-git..."
            if [ -n "$AUR_HELPER" ]; then
                exe "$AUR_HELPER" -S --needed --noconfirm noctalia-git || warn "noctalia-git 安装失败，请手动: yay -S noctalia-git"
            else
                warn "未检测到 AUR Helper，请手动安装 noctalia-git"
            fi
        fi
    fi

    # 恢复 noctalia 配置元数据（如果存在）
    if [ -d "$STAGING_DIR/metadata/noctalia" ]; then
        # 验证配置
        if command -v noctalia &>/dev/null; then
            log "验证 Noctalia 配置..."
            local validation_result
            validation_result=$(noctalia config validate 2>&1) && local validate_ok=1 || local validate_ok=0
            if [ "$validate_ok" -ne 1 ]; then
                warn "Noctalia 配置验证失败:"
                echo -e "       ${H_YELLOW}${validation_result}${NC}"
                # 尝试用导出的配置覆盖
                if [ -f "$STAGING_DIR/metadata/noctalia/config-export.toml" ]; then
                    info "尝试恢复导出的配置..."
                    cp "$STAGING_DIR/metadata/noctalia/config-export.toml" "$HOME/.config/noctalia/config.toml" 2>/dev/null || true
                fi
            else
                success "Noctalia 配置验证通过"
            fi

            # 重新渲染 App Theming 模板
            log "渲染 Noctalia App Theming 模板..."
            if noctalia theme --apply 2>/dev/null; then
                success "App Theming 模板已渲染"
            else
                info "App Theming 渲染跳过 (Noctalia 未运行或模板未配置)"
            fi
        fi
    fi

    # niri 配置检查
    if [ -f "$HOME/.config/niri/config.kdl" ]; then
        if ! grep -q 'spawn-at-startup.*noctalia' "$HOME/.config/niri/config.kdl" 2>/dev/null; then
            warn "niri 配置中缺少 Noctalia 自动启动，请手动添加:"
            echo -e "       ${H_CYAN}spawn-at-startup \"noctalia\"${NC}"
        else
            log "niri 已配置 Noctalia 自动启动"
        fi
    fi

    # noctalia-greeter 检查
    if pacman -Q noctalia-greeter &>/dev/null 2>&1 || pacman -Qs noctalia-greeter &>/dev/null 2>&1; then
        info "noctalia-greeter 已安装"
        if [ -d "$STAGING_DIR/configs/greetd" ]; then
            log "检查 greeter 配置..."
            if [ ! -f "/var/lib/noctalia-greeter/appearance.json" ]; then
                warn "greeter 外观未同步，请在 Noctalia 中执行:"
                echo -e "       ${H_CYAN}Settings → Security → Noctalia Greeter → Sync Now${NC}"
            fi
        fi
    elif [ -d "$STAGING_DIR/configs/greetd" ] && [ -n "$AUR_HELPER" ]; then
        log "安装 noctalia-greeter..."
        exe "$AUR_HELPER" -S --needed --noconfirm noctalia-greeter || warn "noctalia-greeter 安装失败"
    fi

    success "Noctalia 配置已恢复"
    mark_done "noctalia"
}

# ==============================================================================
# 恢复后钩子
# ==============================================================================

restore_post_hooks() {
    is_done "post_hooks" && { info "后处理已完成，跳过"; return 0; }
    section "Post Hooks" "恢复后处理"

    log "刷新桌面数据库..."
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
    fi

    log "刷新图标缓存..."
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor/" 2>/dev/null || true
    fi

    log "编译 GSettings schema..."
    if command -v glib-compile-schemas &>/dev/null; then
        glib-compile-schemas "$HOME/.local/share/glib-2.0/schemas/" 2>/dev/null || true
    fi

    success "后处理完成"
    mark_done "post_hooks"
}

# ==============================================================================
# 恢复后验证
# ==============================================================================

verify_restore() {
    section "Verify" "恢复结果验证"

    local pass=0 fail=0 warn_count=0

    # --- 关键包检查 ---
    log "检查关键软件包..."
    local critical_pkgs="niri kitty fish neovim"
    for pkg in $critical_pkgs; do
        if pacman -Q "$pkg" &>/dev/null 2>&1; then
            printf "       ${H_GREEN}✔${NC} %-20s 已安装\n" "$pkg"
            pass=$((pass + 1))
        else
            printf "       ${H_YELLOW}⚠${NC} %-20s 未安装\n" "$pkg"
            warn_count=$((warn_count + 1))
        fi
    done

    # Noctalia
    if pacman -Q noctalia-git &>/dev/null 2>&1 || command -v noctalia &>/dev/null; then
        printf "       ${H_GREEN}✔${NC} %-20s 已安装\n" "noctalia"
        pass=$((pass + 1))
    elif [ -d "$STAGING_DIR/dotfile/.config/noctalia" ]; then
        printf "       ${H_YELLOW}⚠${NC} %-20s 未安装 (备份中有配置)\n" "noctalia"
        warn_count=$((warn_count + 1))
    fi

    # --- 关键配置文件 ---
    log "检查关键配置..."
    local config_checks=(
        "$HOME/.config/noctalia/Noctalia.toml:Noctalia 配置"
        "$HOME/.config/niri/config.kdl:niri 配置"
        "$HOME/.config/kitty/kitty.conf:kitty 配置"
        "$HOME/.config/fish/config.fish:fish 配置"
        "$HOME/.config/starship.toml:starship 配置"
    )
    for entry in "${config_checks[@]}"; do
        local path="${entry%%:*}"
        local label="${entry##*:}"
        if [ -e "$path" ]; then
            printf "       ${H_GREEN}✔${NC} %-20s 存在\n" "$label"
            pass=$((pass + 1))
        else
            printf "       ${H_GRAY}○${NC} %-20s 不存在\n" "$label"
        fi
    done

    # --- 关键服务 ---
    log "检查关键服务..."
    local critical_svcs="greetd pipewire"
    for svc in $critical_svcs; do
        if systemctl is-enabled "$svc" &>/dev/null 2>&1 || \
           systemctl --user is-enabled "$svc" &>/dev/null 2>&1; then
            printf "       ${H_GREEN}✔${NC} %-20s 已启用\n" "$svc"
            pass=$((pass + 1))
        else
            printf "       ${H_GRAY}○${NC} %-20s 未启用\n" "$svc"
        fi
    done

    # --- 字体 ---
    if [ -d "$HOME/.local/share/fonts" ] && [ "$(ls -A "$HOME/.local/share/fonts" 2>/dev/null)" ]; then
        local font_count
        font_count=$(find "$HOME/.local/share/fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) 2>/dev/null | wc -l)
        printf "       ${H_GREEN}✔${NC} %-20s %d 个字体文件\n" "用户字体" "$font_count"
        pass=$((pass + 1))
    fi

    # --- 日志文件 ---
    echo ""
    info_kv "通过" "${H_GREEN}${pass}${NC}"
    [ "$warn_count" -gt 0 ] && info_kv "警告" "${H_YELLOW}${warn_count}${NC}"
    [ "$fail" -gt 0 ] && info_kv "失败" "${H_RED}${fail}${NC}"
    info_kv "日志" "$LOG_FILE"

    # --- 重启提示 ---
    echo ""
    if confirm "是否现在重启系统以完成所有配置生效？" "n"; then
        info "60 秒后重启 (Ctrl+C 取消)..."
        sleep 60
        sudo reboot
    else
        echo ""
        info "请手动重启以使以下更改生效:"
        echo -e "       ${H_CYAN}●${NC} 用户组更改 (video/audio/input)"
        echo -e "       ${H_CYAN}●${NC} 显示管理器切换 (greetd)"
        echo -e "       ${H_CYAN}●${NC} systemd 服务启用"
        echo -e "       ${H_CYAN}●${NC} 默认 Shell 更改"
        echo ""
        info_kv "重启命令" "${H_CYAN}sudo reboot${NC}"
    fi
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

    # 初始化进度追踪
    init_progress 18

    # 恢复流程
    next_step; handle_display_manager    # 统一处理 sddm → greetd 切换
    next_step; restore_pacman_conf
    next_step; restore_system_configs    # locale/snapper/greetd 配置
    next_step; update_system
    next_step; restore_official_packages
    next_step; install_aur_helper
    next_step; restore_aur_packages
    next_step; restore_flatpak_packages
    next_step; restore_dotfiles          # ~/.config + ~/.local + home dotfiles
    next_step; restore_services          # systemd 用户/系统服务
    next_step; restore_fonts             # 字体缓存重建
    next_step; restore_user_groups       # video/audio/input/wheel 等
    next_step; restore_dconf             # GTK/字体/光标等桌面设置
    next_step; restore_default_shell     # chsh
    next_step; restore_crontab           # 定时任务
    next_step; restore_noctalia          # Noctalia v5 桌面环境配置
    next_step; restore_post_hooks        # fc-cache / desktop-database / icon-cache
    next_step; verify_restore            # 恢复后验证 + 重启提示

    # 清理进度文件
    [ -f "$STATE_FILE" ] && rm -f "$STATE_FILE"

    # TTY 环境下额外提示
    if [ "$TTY_MODE" -eq 1 ]; then
        echo ""
        warn "当前在 TTY 环境，恢复完成后需要手动启动桌面:"
        if [ "$BACKUP_USES_GREETD" -eq 1 ]; then
            echo -e "       ${H_CYAN}sudo systemctl start greetd${NC}"
        else
            echo -e "       ${H_CYAN}sudo systemctl start display-manager${NC}"
        fi
    fi

    # Noctalia 恢复后提示
    if [ -d "$STAGING_DIR/dotfile/.config/noctalia" ] || [ -d "$STAGING_DIR/metadata/noctalia" ]; then
        echo ""
        info "Noctalia v5 恢复后提示:"
        echo -e "       ${H_CYAN}1. 启动桌面后检查 Noctalia 是否正常加载${NC}"
        echo -e "       ${H_CYAN}2. 如需同步登录界面: Settings → Security → Noctalia Greeter → Sync Now${NC}"
        echo -e "       ${H_CYAN}3. 如 App Theming 模板未自动渲染: noctalia theme --apply${NC}"
    fi

    log_summary "Restore"
}
