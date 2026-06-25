#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
shopt -s nullglob

REPO_NAME="cachy-backup"
REPO_DESC="System software backup: $(hostname) $(date +%Y-%m-%d)"
BACKUP_DIR="/tmp/system-backup"
STAGING_DIR="$HOME/.cache/cachy-backup-staging"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

info()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

cleanup() { rm -rf "$BACKUP_DIR"; }

# ── 安全检查 ──────────────────────────────────

if [ "$EUID" -eq 0 ]; then
    error "请不要以 root 权限（sudo）直接运行此脚本！\n脚本内部会在需要时自动请求 sudo 提升权限。直接以 root 运行会导致 GitHub 认证和 AUR 编译安装失败。"
fi

# ── 命令行参数解析 ──────────────────────────────

MODE="backup"
if [ "${1:-}" = "restore" ]; then
    MODE="restore"
elif [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo -e "${CYAN}系统备份与恢复脚本${NC}"
    echo "用法: $0 [backup|restore]"
    echo "  backup  : 备份当前系统的软件包列表和配置并推送至 GitHub（默认）"
    echo "  restore : 从 GitHub 仓库恢复软件包和系统配置"
    exit 0
fi

# ── 交互式确认函数 ──────────────────────────────

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local yn
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    # 确保从控制台 tty 读取，即使脚本是通过管道/重定向执行的
    if ! read -r -p "$prompt" yn < /dev/tty; then
        echo ""
        error "用户取消了输入操作"
    fi
    yn="${yn:-$default}"
    case "$yn" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

# ── 依赖检查 ──────────────────────────────────

check_dependencies() {
    if ! command -v gh &>/dev/null; then
        info "正在安装 GitHub CLI (gh)..."
        sudo pacman -S --noconfirm github-cli
    fi

    info "检查 gh 登录状态..."
    if ! gh auth status &>/dev/null; then
        if [ -t 0 ] || [ -c /dev/tty ]; then
            warn "需要登录 GitHub，请在弹出的页面完成登录"
            gh auth login -p https -w || error "gh auth login 失败"
        else
            error "检测到处于非交互式环境且 gh 未登录！请先在终端中手动运行一次本脚本或执行 'gh auth login' 完成登录。"
        fi
    fi

    GH_USER=$(gh api user --jq '.login') || error "无法获取 GitHub 用户名"
    info "已登录为: $GH_USER"
}

# ── 备份模式 ──────────────────────────────────

run_backup() {
    check_dependencies

    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"/packages

    # ── 软件包列表 ──────────────────────────────────

    info "备份 pacman 官方软件包列表（仅显式安装，排除依赖）..."
    pacman -Qqen | sort > "$BACKUP_DIR/packages/official.txt"
    wc -l < "$BACKUP_DIR/packages/official.txt" | xargs printf "  %d 个官方包\n"

    info "备份 AUR 软件包列表（仅显式安装，排除依赖）..."
    pacman -Qqem | sort > "$BACKUP_DIR/packages/aur.txt"
    wc -l < "$BACKUP_DIR/packages/aur.txt" | xargs printf "  %d 个 AUR 包\n"

    info "备份已显式安装的包（含版本，供参考）..."
    pacman -Qe | sort > "$BACKUP_DIR/packages/explicit.txt"

    if [ -d "$HOME/.cache/yay" ]; then
        info "备份 yay 构建缓存中的 PKGBUILD 和 .SRCINFO..."
        mkdir -p "$BACKUP_DIR/packages/yay-cache"
        for pkg in "$HOME/.cache/yay"/*/; do
            pkgname=$(basename "$pkg")
            if [ -f "$pkg/PKGBUILD" ]; then
                mkdir -p "$BACKUP_DIR/packages/yay-cache/$pkgname"
                cp "$pkg/PKGBUILD" "$BACKUP_DIR/packages/yay-cache/$pkgname/"
                [ -f "$pkg/.SRCINFO" ] && cp "$pkg/.SRCINFO" "$BACKUP_DIR/packages/yay-cache/$pkgname/"
            fi
        done
    fi

    # ── 系统信息与配置 ──────────────────────────────

    info "备份系统信息..."
    {
        echo "hostname: $(hostname)"
        echo "date: $(date --iso-8601=seconds)"
        echo "kernel: $(uname -r)"
        echo "arch: $(uname -m)"
        echo "shell: $SHELL"
    } > "$BACKUP_DIR/packages/system-info.txt"

    info "备份 pacman mirrorlist..."
    cp /etc/pacman.d/mirrorlist "$BACKUP_DIR/packages/mirrorlist.txt" 2>/dev/null || true

    info "备份 pacman.conf..."
    cp /etc/pacman.conf "$BACKUP_DIR/packages/pacman.conf" 2>/dev/null || true

    # ── 备份脚本自身 ────────────────────────────────

    info "将备份脚本自身备份到仓库中..."
    SCRIPT_PATH=$(realpath "$0")
    cp "$SCRIPT_PATH" "$BACKUP_DIR/backup-system.sh"

    # ── .gitignore ──────────────────────────────────

    cat > "$BACKUP_DIR/.gitignore" <<'EOF'
*.tar
*.tar.gz
*.zip
*.iso
*.pkg.tar.zst
*.log
core
EOF

    # ── README ──────────────────────────────────

    info "创建 README..."

    OFFICIAL_COUNT=$(wc -l < "$BACKUP_DIR/packages/official.txt")
    AUR_COUNT=$(wc -l < "$BACKUP_DIR/packages/aur.txt")

    cat > "$BACKUP_DIR/README.md" <<EOF
# $REPO_NAME

- **Host:** \$(hostname)
- **Date:** \$(date --iso-8601=seconds)
- **Kernel:** \$(uname -r)
- **Packages:** $OFFICIAL_COUNT official, $AUR_COUNT AUR
- **AUR helper:** yay

## 恢复软件指南 (Restore Guide)

在新系统上，您只需安装 \`github-cli\` 并登录，然后运行以下命令之一即可一键恢复：

### 方法 A：单行命令（推荐，无需手动克隆）
\`\`\`bash
sudo pacman -S --noconfirm github-cli && \\
gh auth login && \\
bash <(gh api repos/\\\$(gh api user --jq '.login')/cachy-backup/contents/backup-system.sh -H "Accept: application/vnd.github.raw") restore
\`\`\`

### 方法 B：克隆仓库恢复
\`\`\`bash
sudo pacman -S --noconfirm github-cli && \\
gh auth login && \\
gh repo clone cachy-backup && \\
cd cachy-backup && \\
chmod +x backup-system.sh && \\
./backup-system.sh restore
\`\`\`

---

## 手动恢复参考流程

\`\`\`bash
# 1. 恢复 pacman 配置
sudo cp packages/mirrorlist.txt /etc/pacman.d/mirrorlist
sudo cp packages/pacman.conf /etc/pacman.conf

# 2. 升级系统并更新 Keyring（防止新系统安装时因签名过期报错）
sudo pacman -Sy archlinux-keyring
sudo pacman -Syyu

# 3. 恢复官方软件包
pacman -S --needed - < packages/official.txt

# 4. 安装 yay（AUR 助手）编译所需的依赖，并安装 yay
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin && makepkg -si && cd ~

# 5. 恢复 AUR 软件包
yay -S --needed - < packages/aur.txt

# 6. 如 yay 缓存不可用，可从 PKGBUILD 备份中恢复特定的 AUR 包
# (shopt -s nullglob; cd packages/yay-cache && for pkg in */; do cd "\$pkg" && makepkg -si && cd ..; done)
\`\`\`
EOF

    # ── 推送至 GitHub ──────────────────────────────────

    REPO_URL="https://github.com/$GH_USER/$REPO_NAME.git"

    # 极高鲁棒性的 Git 仓储初始化/克隆逻辑
    if [ ! -d "$STAGING_DIR/.git" ]; then
        if gh repo view "$GH_USER/$REPO_NAME" &>/dev/null; then
            info "发现已有远程 GitHub 仓库，正在克隆至本地以保持历史记录一致..."
            rm -rf "$STAGING_DIR"
            git clone "$REPO_URL" "$STAGING_DIR"
        else
            info "创建新的 GitHub 仓库..."
            gh repo create "$REPO_NAME" --description "$REPO_DESC" --private
            mkdir -p "$STAGING_DIR"
            git -C "$STAGING_DIR" init
            git -C "$STAGING_DIR" branch -M main
            git -C "$STAGING_DIR" remote add origin "$REPO_URL"
        fi
    fi

    # 增量同步文件，保留本地 .git 目录
    info "增量同步备份文件至暂存区..."
    rsync -a --delete --exclude='.git/' "$BACKUP_DIR/" "$STAGING_DIR/"

    cd "$STAGING_DIR"

    # 检查本地/全局 Git 用户信息配置，防止 commit 挂掉
    if ! git config user.name &>/dev/null && ! git config --global user.name &>/dev/null; then
        warn "未检测到本地或全局 Git 用户配置，自动配置本地用户..."
        git config user.name "$GH_USER"
        GH_EMAIL=$(gh api user/emails --jq '.[] | select(.primary == true) | .email' 2>/dev/null || echo "${GH_USER}@users.noreply.github.com")
        git config user.email "$GH_EMAIL"
    fi

    # 确保 remote 地址正确
    git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL"

    git add -A
    if git diff --cached --quiet; then
        warn "无任何配置变更，跳过本次推送。"
    else
        git commit -m "Software Backup: $(date +%Y-%m-%d_%H-%M)"
        info "正在推送软件备份至 GitHub..."
        git push -u origin main
    fi

    info "完成！备份已成功同步至: https://github.com/$GH_USER/$REPO_NAME"

    BACKUP_SIZE=$(du -sh "$STAGING_DIR" | cut -f1)
    info "备份总大小: $BACKUP_SIZE"

    cleanup
}

# ── 恢复模式 ──────────────────────────────────

run_restore() {
    check_dependencies

    REPO_URL="https://github.com/$GH_USER/$REPO_NAME.git"

    # 拉取最新的备份文件
    if [ ! -d "$STAGING_DIR/.git" ]; then
        info "正在从 GitHub 克隆备份仓库..."
        rm -rf "$STAGING_DIR"
        git clone "$REPO_URL" "$STAGING_DIR" || error "克隆备份仓库失败，请确保您已经备份过系统。"
    else
        info "备份仓库已存在，正在更新备份文件..."
        git -C "$STAGING_DIR" pull || error "更新备份仓库失败。"
    fi

    if [ ! -d "$STAGING_DIR/packages" ]; then
        error "在备份仓库中未找到 packages 目录，无法进行恢复！"
    fi

    # 1. 恢复 pacman 相关的配置文件
    local has_conf=0
    [ -f "$STAGING_DIR/packages/pacman.conf" ] && has_conf=1
    [ -f "$STAGING_DIR/packages/mirrorlist.txt" ] && has_conf=1

    if [ "$has_conf" -eq 1 ]; then
        if confirm "是否恢复备份的 pacman.conf 和 mirrorlist 配置文件？(这会覆盖你新系统的当前配置)" "n"; then
            if [ -f "$STAGING_DIR/packages/pacman.conf" ]; then
                info "恢复 /etc/pacman.conf..."
                sudo cp "$STAGING_DIR/packages/pacman.conf" /etc/pacman.conf
            fi
            if [ -f "$STAGING_DIR/packages/mirrorlist.txt" ]; then
                info "恢复 /etc/pacman.d/mirrorlist..."
                sudo cp "$STAGING_DIR/packages/mirrorlist.txt" /etc/pacman.d/mirrorlist
            fi
        else
            info "跳过 pacman 配置文件恢复。"
        fi
    fi

    # 2. 升级系统及 Keyring
    info "正在升级系统并安装/更新 archlinux-keyring（以防止签名过期导致软件安装失败）..."
    sudo pacman -Sy --needed archlinux-keyring
    sudo pacman -Syyu --noconfirm

    # 3. 恢复官方软件包
    if [ -f "$STAGING_DIR/packages/official.txt" ] && [ -s "$STAGING_DIR/packages/official.txt" ]; then
        if confirm "是否恢复官方软件包列表？" "y"; then
            info "正在恢复官方软件包..."
            sudo pacman -S --needed - < "$STAGING_DIR/packages/official.txt"
        else
            info "跳过官方软件包恢复。"
        fi
    fi

    # 4. 安装 yay
    if ! command -v yay &>/dev/null; then
        if confirm "未检测到 yay (AUR 助手)，是否自动编译并安装 yay-bin？" "y"; then
            info "正在安装编译依赖 (base-devel, git)..."
            sudo pacman -S --needed --noconfirm base-devel git
            info "正在克隆并编译 yay-bin..."
            rm -rf /tmp/yay-bin
            git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
            (cd /tmp/yay-bin && makepkg -si --noconfirm)
            rm -rf /tmp/yay-bin
        else
            warn "未安装 yay，将无法恢复 AUR 软件包！"
        fi
    fi

    # 5. 恢复 AUR 软件包
    if command -v yay &>/dev/null; then
        if [ -f "$STAGING_DIR/packages/aur.txt" ] && [ -s "$STAGING_DIR/packages/aur.txt" ]; then
            if confirm "是否恢复 AUR 软件包列表？" "y"; then
                info "正在恢复 AUR 软件包..."
                yay -S --needed - < "$STAGING_DIR/packages/aur.txt"
            else
                info "跳过 AUR 软件包恢复。"
            fi
        fi
    else
        if [ -f "$STAGING_DIR/packages/aur.txt" ] && [ -s "$STAGING_DIR/packages/aur.txt" ]; then
            warn "由于未安装 yay，无法恢复 AUR 软件包。您可以手动运行以下命令安装：\n  yay -S --needed - < $STAGING_DIR/packages/aur.txt"
        fi
    fi

    info "🎉 恭喜！系统软件包和配置恢复已成功完成！"
}

# ── 执行分支 ──────────────────────────────────

if [ "$MODE" = "backup" ]; then
    run_backup
elif [ "$MODE" = "restore" ]; then
    run_restore
fi
