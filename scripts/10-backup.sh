#!/bin/bash

# ==============================================================================
# 10-backup.sh - Backup Module
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-utils.sh"

BACKUP_DIR="/tmp/system-backup-$$"
STAGING_DIR="${STAGING_DIR:-$HOME/.cache/cachy-backup-staging}"
REPO_NAME="${REPO_NAME:-cachy-backup}"

# ==============================================================================
# 备份软件包列表
# ==============================================================================

backup_packages() {
    section "Packages" "备份软件包列表"

    mkdir -p "$BACKUP_DIR/packages"

    # 官方包
    log "备份 pacman 官方软件包列表..."
    pacman -Qqen | sort > "$BACKUP_DIR/packages/official.txt"
    local official_count
    official_count=$(wc -l < "$BACKUP_DIR/packages/official.txt" || echo 0)
    info_kv "Official" "${BOLD}${official_count}${NC}" "packages"

    # AUR 包
    log "备份 AUR 软件包列表..."
    pacman -Qqem 2>/dev/null | sort > "$BACKUP_DIR/packages/aur.txt" || true
    local aur_count
    aur_count=$(wc -l < "$BACKUP_DIR/packages/aur.txt" || echo 0)
    info_kv "AUR" "${BOLD}${aur_count}${NC}" "packages"

    # 显式安装列表（含版本）
    log "备份显式安装列表（含版本号）..."
    pacman -Qe | sort > "$BACKUP_DIR/packages/explicit.txt"

    # Flatpak
    if command -v flatpak &>/dev/null; then
        log "备份 Flatpak 软件包列表..."
        flatpak list --app --columns=application 2>/dev/null | sort > "$BACKUP_DIR/packages/flatpak.txt" || true
        local flatpak_count
        flatpak_count=$(wc -l < "$BACKUP_DIR/packages/flatpak.txt" || echo 0)
        info_kv "Flatpak" "${BOLD}${flatpak_count}${NC}" "packages"
    fi

    # yay 构建缓存
    local cache_dir="$HOME/.cache/yay"
    [ -z "${AUR_HELPER:-}" ] && cache_dir="$HOME/.cache/${AUR_HELPER:-yay}"

    if [ -d "$cache_dir" ]; then
        log "备份 AUR 构建缓存 PKGBUILD..."
        mkdir -p "$BACKUP_DIR/packages/aur-cache"
        local count=0
        for pkg in "$cache_dir"/*/; do
            [ -d "$pkg" ] || continue
            local pkgname
            pkgname=$(basename "$pkg")
            if [ -f "$pkg/PKGBUILD" ]; then
                mkdir -p "$BACKUP_DIR/packages/aur-cache/$pkgname"
                cp "$pkg/PKGBUILD" "$BACKUP_DIR/packages/aur-cache/$pkgname/"
                [ -f "$pkg/.SRCINFO" ] && cp "$pkg/.SRCINFO" "$BACKUP_DIR/packages/aur-cache/$pkgname/"
                count=$((count + 1))
            fi
        done
        info_kv "AUR Cache" "${BOLD}${count}${NC}" "PKGBUILDs"
    fi
}

# ==============================================================================
# 备份系统配置
# ==============================================================================

backup_configs() {
    section "System Config" "备份系统配置文件"

    mkdir -p "$BACKUP_DIR/configs"

    # pacman 配置
    if [ -f /etc/pacman.conf ]; then
        log "备份 pacman.conf..."
        cp /etc/pacman.conf "$BACKUP_DIR/configs/pacman.conf"
    fi

    # mirrorlist
    if [ -f /etc/pacman.d/mirrorlist ]; then
        log "备份 mirrorlist..."
        cp /etc/pacman.d/mirrorlist "$BACKUP_DIR/configs/mirrorlist.txt"
    fi

    # locale
    if [ -f /etc/locale.conf ]; then
        log "备份 locale.conf..."
        cp /etc/locale.conf "$BACKUP_DIR/configs/locale.conf"
    fi
    [ -f /etc/locale.gen ] && cp /etc/locale.gen "$BACKUP_DIR/configs/locale.gen"

    # snapper
    if [ -d /etc/snapper/configs ]; then
        log "备份 snapper 配置..."
        mkdir -p "$BACKUP_DIR/configs/snapper"
        cp /etc/snapper/configs/* "$BACKUP_DIR/configs/snapper/" 2>/dev/null || true
    fi

    # greetd
    if [ -d /etc/greetd ]; then
        log "备份 greetd 配置..."
        mkdir -p "$BACKUP_DIR/configs/greetd"
        cp -r /etc/greetd/* "$BACKUP_DIR/configs/greetd/" 2>/dev/null || true
    fi

    # 系统信息
    log "生成系统信息快照..."
    {
        echo "hostname: $(hostname)"
        echo "date: $(date --iso-8601=seconds)"
        echo "kernel: $(uname -r)"
        echo "arch: $(uname -m)"
        echo "shell: $SHELL"
        echo "os: $(source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "unknown")"
        echo "cpu: $(lscpu 2>/dev/null | grep 'Model name' | sed 's/Model name:\s*//' || echo "unknown")"
        echo "memory: $(free -h 2>/dev/null | awk '/Mem:/{print $2}' || echo "unknown")"
        echo "aur_helper: ${AUR_HELPER:-none}"
    } > "$BACKUP_DIR/configs/system-info.txt"
}

# ==============================================================================
# 备份服务列表
# ==============================================================================

backup_services() {
    section "Services" "备份 systemd 服务列表"

    mkdir -p "$BACKUP_DIR/services"

    log "备份启用的用户服务..."
    systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null \
        | awk '{print $1}' | sort > "$BACKUP_DIR/services/user-services.txt" || true

    log "备份启用的系统服务..."
    systemctl list-unit-files --state=enabled --no-legend 2>/dev/null \
        | awk '{print $1}' | sort > "$BACKUP_DIR/services/system-services.txt" || true

    local user_count system_count
    user_count=$(wc -l < "$BACKUP_DIR/services/user-services.txt" 2>/dev/null || echo 0)
    system_count=$(wc -l < "$BACKUP_DIR/services/system-services.txt" 2>/dev/null || echo 0)
    info_kv "User Services" "${BOLD}${user_count}${NC}"
    info_kv "System Services" "${BOLD}${system_count}${NC}"
}

# ==============================================================================
# 备份 Dotfile
# ==============================================================================

backup_dotfiles() {
    section "Dotfiles" "备份用户配置文件"

    mkdir -p "$BACKUP_DIR/dotfile/.config"
    mkdir -p "$BACKUP_DIR/dotfile/.local/share"

    # ~/.config
    log "备份 ~/.config..."
    local exclude_file="$SCRIPT_DIR/../config/exclude-backup.txt"
    local exclude_args=()
    if [ -f "$exclude_file" ]; then
        exclude_args=(--exclude-from "$exclude_file")
    else
        # 回退：硬编码排除列表
        exclude_args=(
            --exclude='.cache' --exclude='Cache' --exclude='cache'
            --exclude='GPUCache' --exclude='ShaderCache' --exclude='DawnCache'
            --exclude='Code' --exclude='chromium' --exclude='google-chrome'
            --exclude='firefox' --exclude='zen' --exclude='mozilla'
            --exclude='discord' --exclude='Slack' --exclude='Telegram'
            --exclude='opencode' --exclude='yay' --exclude='paru'
            --exclude='node_modules' --exclude='*.log' --exclude='*.tmp'
            --exclude='*.png' --exclude='*.jpg' --exclude='*.jpeg'
            --exclude='LICENSE' --exclude='README.md' --exclude='README-RU.md'
        )
    fi

    rsync -a --delete \
        "${exclude_args[@]}" \
        "$HOME/.config/" "$BACKUP_DIR/dotfile/.config/" 2>/dev/null || true

    # ~/.local/share/fcitx5
    if [ -d "$HOME/.local/share/fcitx5" ]; then
        log "备份 fcitx5 数据..."
        rsync -a --delete \
            --exclude='build' \
            --exclude='*.prism.bin' \
            --exclude='*.table.bin' \
            --exclude='*.userdb' \
            --exclude='*.userdb.txt' \
            "$HOME/.local/share/fcitx5/" "$BACKUP_DIR/dotfile/.local/share/fcitx5/" 2>/dev/null || true
    fi

    # ~/.local/share/noctalia/plugins/ (Noctalia v5 插件)
    if [ -d "$HOME/.local/share/noctalia" ]; then
        log "备份 Noctalia 插件..."
        mkdir -p "$BACKUP_DIR/dotfile/.local/share/noctalia"
        rsync -a --delete \
            "$HOME/.local/share/noctalia/" "$BACKUP_DIR/dotfile/.local/share/noctalia/" 2>/dev/null || true
    fi

    # ~/.local/state/noctalia/settings.toml (Noctalia v5 GUI 覆盖)
    if [ -f "$HOME/.local/state/noctalia/settings.toml" ]; then
        log "备份 Noctalia settings.toml..."
        mkdir -p "$BACKUP_DIR/dotfile/.local/state/noctalia"
        cp "$HOME/.local/state/noctalia/settings.toml" "$BACKUP_DIR/dotfile/.local/state/noctalia/settings.toml" 2>/dev/null || true
    fi

    # ~/.profile / ~/.bash_profile / ~/.bashrc
    log "备份 Shell 启动文件..."
    for f in .profile .bash_profile .bashrc .zshenv; do
        [ -f "$HOME/$f" ] && cp "$HOME/$f" "$BACKUP_DIR/dotfile/$f"
    done

    # ~/.gitconfig
    if [ -f "$HOME/.gitconfig" ]; then
        log "备份 .gitconfig..."
        cp "$HOME/.gitconfig" "$BACKUP_DIR/dotfile/.gitconfig"
    fi

    # ~/.local/bin/
    if [ -d "$HOME/.local/bin" ] && [ "$(ls -A "$HOME/.local/bin" 2>/dev/null)" ]; then
        log "备份 ~/.local/bin/ ..."
        rsync -a "$HOME/.local/bin/" "$BACKUP_DIR/dotfile/.local/bin/" 2>/dev/null || true
    fi

    # ~/.local/share/fonts/
    if [ -d "$HOME/.local/share/fonts" ] && [ "$(ls -A "$HOME/.local/share/fonts" 2>/dev/null)" ]; then
        log "备份用户字体..."
        rsync -a "$HOME/.local/share/fonts/" "$BACKUP_DIR/dotfile/.local/share/fonts/" 2>/dev/null || true
    fi

    # ~/.local/share/applications/ (自定义 desktop 文件)
    if [ -d "$HOME/.local/share/applications" ] && [ "$(ls -A "$HOME/.local/share/applications" 2>/dev/null)" ]; then
        log "备份自定义 desktop 文件..."
        rsync -a "$HOME/.local/share/applications/" "$BACKUP_DIR/dotfile/.local/share/applications/" 2>/dev/null || true
    fi

    local count
    count=$(find "$BACKUP_DIR/dotfile" -type f | wc -l)
    info_kv "Dotfiles" "${BOLD}${count}${NC}" "files"
}

# ==============================================================================
# 备份系统元数据 (用户组/默认Shell/dconf/crontab)
# ==============================================================================

backup_system_metadata() {
    section "System Metadata" "备份用户组 / Shell / dconf / crontab"

    mkdir -p "$BACKUP_DIR/metadata"

    # 用户组
    log "备份用户组..."
    groups "$USER" 2>/dev/null | sed 's/^[^ ]* : //' | tr ' ' '\n' | sort > "$BACKUP_DIR/metadata/user-groups.txt" || true
    local group_count
    group_count=$(wc -l < "$BACKUP_DIR/metadata/user-groups.txt" 2>/dev/null || echo 0)
    info_kv "User Groups" "${BOLD}${group_count}${NC}"

    # 默认 Shell
    log "备份默认 Shell..."
    getent passwd "$USER" 2>/dev/null | cut -d: -f7 > "$BACKUP_DIR/metadata/default-shell.txt" || echo "/bin/bash" > "$BACKUP_DIR/metadata/default-shell.txt"
    local shell_name
    shell_name=$(cat "$BACKUP_DIR/metadata/default-shell.txt")
    info_kv "Default Shell" "${BOLD}${shell_name}${NC}"

    # dconf 设置
    if command -v dconf &>/dev/null; then
        log "备份 dconf 设置..."
        dconf dump / > "$BACKUP_DIR/metadata/dconf-user.ini" 2>/dev/null || true
        local dconf_size
        dconf_size=$(wc -c < "$BACKUP_DIR/metadata/dconf-user.ini" 2>/dev/null || echo 0)
        info_kv "dconf" "${BOLD}${dconf_size}${NC}" "bytes"
    fi

    # crontab
    log "备份 crontab..."
    crontab -l > "$BACKUP_DIR/metadata/crontab.txt" 2>/dev/null || true

    # Noctalia v5 配置状态
    if command -v noctalia &>/dev/null; then
        log "备份 Noctalia 配置..."
        mkdir -p "$BACKUP_DIR/metadata/noctalia"
        # 导出合并后的用户配置
        noctalia config export > "$BACKUP_DIR/metadata/noctalia/config-export.toml" 2>/dev/null || true
        # 记录版本
        noctalia --version > "$BACKUP_DIR/metadata/noctalia/version.txt" 2>/dev/null || true
        # 验证配置
        noctalia config validate > "$BACKUP_DIR/metadata/noctalia/validate.txt" 2>&1 || true
        info_kv "Noctalia" "$(cat "$BACKUP_DIR/metadata/noctalia/version.txt" 2>/dev/null || echo 'unknown')"
    fi

    # niri compositor 配置
    if [ -f "$HOME/.config/niri/config.kdl" ]; then
        log "备份 niri 配置..."
        mkdir -p "$BACKUP_DIR/metadata/niri"
        cp "$HOME/.config/niri/config.kdl" "$BACKUP_DIR/metadata/niri/config.kdl" 2>/dev/null || true
    fi
}

# ==============================================================================
# 生成 README 和 .gitignore
# ==============================================================================

generate_docs() {
    section "Documentation" "生成项目文档"

    local official_count aur_count flatpak_count
    official_count=$( [ -f "$BACKUP_DIR/packages/official.txt" ] && wc -l < "$BACKUP_DIR/packages/official.txt" || echo 0)
    aur_count=$( [ -f "$BACKUP_DIR/packages/aur.txt" ] && wc -l < "$BACKUP_DIR/packages/aur.txt" || echo 0)
    flatpak_count=$( [ -f "$BACKUP_DIR/packages/flatpak.txt" ] && wc -l < "$BACKUP_DIR/packages/flatpak.txt" || echo 0)

    # .gitignore
    cat > "$BACKUP_DIR/.gitignore" <<'EOF'
*.tar
*.tar.gz
*.zip
*.iso
*.pkg.tar.zst
*.log
core
*.bak
*.backup
*.prism.bin
*.table.bin
private_rime_ice.userdb/
private_rime_ice.userdb.txt
EOF

    # README
    cat > "$BACKUP_DIR/README.md" <<EOF
# $REPO_NAME

- **Host:** $(hostname)
- **Date:** $(date --iso-8601=seconds)
- **Kernel:** $(uname -r)
- **Packages:** ${official_count} official, ${aur_count} AUR, ${flatpak_count} flatpak
- **AUR helper:** ${AUR_HELPER:-yay}

## 最近同步

$(date '+%Y-%m-%d %H:%M:%S')

## 一键恢复

\`\`\`bash
bash <(curl -sL https://raw.githubusercontent.com/USER/$REPO_NAME/main/strap.sh) restore
\`\`\`

## 手动恢复

\`\`\`bash
# 1. 恢复 pacman 配置
sudo cp configs/pacman.conf /etc/pacman.conf
sudo cp configs/mirrorlist.txt /etc/pacman.d/mirrorlist

# 2. 更新系统
sudo pacman -Sy archlinux-keyring && sudo pacman -Syyu

# 3. 安装官方包
sudo pacman -S --needed - < packages/official.txt

# 4. 安装 yay
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin && makepkg -si

# 5. 安装 AUR 包
yay -S --needed - < packages/aur.txt

# 6. 恢复 Flatpak（如有）
flatpak install -y \$(cat packages/flatpak.txt)
\`\`\`
EOF

    success "文档生成完成"
}

# ==============================================================================
# Git 推送
# ==============================================================================

push_to_github() {
    section "Git Push" "推送到远程仓库"

    local gh_user="$1"
    local config_file="$HOME/.config/cachy-backup.conf"
    local repo_url=""

    # 检查是否已配置仓库
    if [ -f "$config_file" ]; then
        repo_url=$(grep "^REPO_URL=" "$config_file" | cut -d= -f2-)
    fi

    # 首次备份：配置仓库
    if [ -z "$repo_url" ]; then
        echo ""
        warn "首次备份，需要配置仓库地址"
        echo ""

        # 检查是否在交互式环境
        if [ -t 0 ] || [ -c /dev/tty ]; then
            echo -e "   ${H_CYAN}选项:${NC}"
            echo -e "   [1] GitHub (创建新仓库)"
            echo -e "   [2] Gitee (国内镜像)"
            echo -e "   [3] 使用已有仓库"
            echo ""

            local choice
            read -r -p "$(echo -e "   ${H_CYAN}选择 [1-3]: ${NC}")" choice < /dev/tty

            case "$choice" in
                1)
                    repo_url="https://github.com/$gh_user/$REPO_NAME.git"
                    if ! gh repo view "$gh_user/$REPO_NAME" &>/dev/null; then
                        log "创建 GitHub 公开仓库..."
                        exe gh repo create "$REPO_NAME" --description "CachyOS system backup" --public
                    fi
                    ;;
                2)
                    repo_url="https://gitee.com/$gh_user/$REPO_NAME.git"
                    log "请手动在 Gitee 创建仓库: $repo_url"
                    ;;
                *)
                    read -r -p "$(echo -e "   ${H_CYAN}输入仓库地址 (如 https://github.com/user/repo): ${NC}")" repo_url < /dev/tty
                    repo_url="${repo_url%.git}.git"
                    ;;
            esac
        else
            # 非交互式环境，使用默认配置
            repo_url="https://github.com/$gh_user/$REPO_NAME.git"
            log "非交互式环境，使用默认仓库: $repo_url"
            if ! gh repo view "$gh_user/$REPO_NAME" &>/dev/null; then
                log "创建 GitHub 公开仓库..."
                exe gh repo create "$REPO_NAME" --description "CachyOS system backup" --public
            fi
        fi

        # 保存配置
        mkdir -p "$(dirname "$config_file")"
        echo "REPO_URL=$repo_url" > "$config_file"
        echo "GH_USER=$gh_user" >> "$config_file"
        success "仓库配置已保存到 $config_file"
        echo ""
    fi

    # 从配置读取
    repo_url=$(grep "^REPO_URL=" "$config_file" | cut -d= -f2-)
    gh_user=$(grep "^GH_USER=" "$config_file" | cut -d= -f2-)

    info_kv "仓库地址" "$repo_url"

    # 初始化/克隆仓库
    if [ ! -d "$STAGING_DIR/.git" ]; then
        if git ls-remote "$repo_url" &>/dev/null; then
            log "克隆已有远程仓库（浅克隆）..."
            rm -rf "$STAGING_DIR"
            exe git clone --depth 1 "$repo_url" "$STAGING_DIR"
        else
            log "初始化本地仓库..."
            mkdir -p "$STAGING_DIR"
            git -C "$STAGING_DIR" init
            git -C "$STAGING_DIR" branch -M main
            git -C "$STAGING_DIR" remote add origin "$repo_url"
        fi
    else
        # staging 已存在，同步到远程最新（处理 force push 导致的历史分叉）
        git -C "$STAGING_DIR" fetch --depth 1 origin 2>/dev/null || true
        git -C "$STAGING_DIR" reset --hard origin/main 2>/dev/null || true
    fi

    # 同步文件
    log "增量同步备份文件..."
    exe rsync -a --delete \
        --exclude='.git/' \
        --exclude='scripts/' \
        --exclude='strap.sh' \
        --exclude='backup.sh' \
        "$BACKUP_DIR/" "$STAGING_DIR/"

    cd "$STAGING_DIR"

    # Git 用户配置
    if ! git config user.name &>/dev/null && ! git config --global user.name &>/dev/null; then
        log "自动配置 Git 用户..."
        git config user.name "$gh_user"
        local gh_email
        gh_email=$(gh api user/emails --jq '.[] | select(.primary == true) | .email' 2>/dev/null || echo "${gh_user}@users.noreply.github.com")
        git config user.email "$gh_email"
    fi

    git remote set-url origin "$repo_url" 2>/dev/null || true

    # 更新主 README.md 中的最近同步时间
    if [ -f "$STAGING_DIR/README.md" ]; then
        local sync_time
        sync_time=$(date '+%Y-%m-%d %H:%M:%S')
        sed -i "s|- \*\*最近同步:\*\*.*|- **最近同步:** $sync_time|" "$STAGING_DIR/README.md"
        log "更新最近同步时间: $sync_time"
    fi

    git add -A
    if git diff --cached --quiet; then
        warn "无变更，跳过推送"
    else
        local official_count
        official_count=$(wc -l < "$STAGING_DIR/packages/official.txt" 2>/dev/null || echo 0)
        local aur_count
        aur_count=$(wc -l < "$STAGING_DIR/packages/aur.txt" 2>/dev/null || echo 0)
        local commit_msg="Backup: $(date +%Y-%m-%d_%H-%M) | ${official_count}pkgs+${aur_count}aur"
        exe git commit -m "$commit_msg"

        # 强制推送，确保备份内容同步到远程
        exe git push -u origin main --force
        success "备份已推送到 $repo_url"

        # 更新 GitHub 仓库描述
        if command -v gh &>/dev/null; then
            local repo_desc
            repo_desc="CachyOS 备份 | $(hostname) | $(date '+%Y-%m-%d %H:%M')"
            log "更新仓库描述: $repo_desc"
            gh repo edit "$gh_user/$REPO_NAME" --description "$repo_desc" 2>/dev/null || warn "仓库描述更新失败"
        fi
    fi

    local backup_size
    backup_size=$(du -sh "$STAGING_DIR" | cut -f1)
    info_kv "Backup Size" "$backup_size"
}

# ==============================================================================
# 主函数
# ==============================================================================

run_backup() {
    local gh_user="$1"

    show_banner
    section "Backup" "开始系统备份"

    AUR_HELPER=$(detect_aur_helper)
    info_kv "AUR Helper" "${AUR_HELPER:-none}"
    info_kv "Host" "$(hostname)"
    info_kv "Kernel" "$(uname -r)"

    backup_packages
    backup_configs
    backup_services
    backup_dotfiles
    backup_system_metadata
    generate_docs
    push_to_github "$gh_user"

    # 清理
    rm -rf "$BACKUP_DIR"

    echo ""
    success "🎉 备份完成！"
    echo ""

    log_summary "Backup"
}
