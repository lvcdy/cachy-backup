# cachy-backup

CachyOS 系统备份与恢复工具。自动备份软件包列表、系统配置和 dotfile，一键恢复到新系统。

- **Host:** strix-g16
- **Kernel:** 7.1.1-2-cachyos (x86_64)
- **Packages:** 293 official + 10 AUR
- **AUR helper:** yay

## 项目结构

```
cachy-backup/
├── backup-system.sh        # 主调度脚本
├── strap.sh                # Bootstrap 一键恢复脚本
├── scripts/
│   ├── 00-utils.sh         # TUI 工具函数
│   ├── 10-backup.sh        # 备份模块
│   └── 20-restore.sh       # 恢复模块
├── dotfile/                # chezmoi 管理的 dotfile
├── packages/
│   ├── official.txt        # 官方源软件包列表
│   ├── aur.txt             # AUR 软件包列表
│   ├── flatpak.txt         # Flatpak 软件包列表
│   ├── explicit.txt        # 显式安装的包（含版本号）
│   ├── pacman.conf         # pacman 配置
│   ├── mirrorlist.txt      # 镜像源列表
│   ├── system-info.txt     # 系统信息快照
│   └── aur-cache/          # AUR 包的 PKGBUILD 备份
├── services/
│   ├── user-services.txt   # systemd 用户服务
│   └── system-services.txt # systemd 系统服务
└── README.md
```

## 快速开始

### 一键恢复（推荐）

在新系统上，运行以下命令即可一键恢复：

```bash
# 从 GitHub
bash <(curl -sL https://raw.githubusercontent.com/lvcdy/cachy-backup/main/strap.sh)

# 从 Gitee（国内镜像）
MIRROR=gitee bash <(curl -sL https://gitee.com/lvcdy/cachy-backup/raw/main/strap.sh)
```

### 命令行使用

```bash
./backup-system.sh [选项] <命令>

命令:
  backup   备份当前系统（默认）
  restore  从 GitHub 恢复系统

选项:
  -h, --help      显示帮助信息
  -v, --version   显示版本号
  -n, --dry-run   仅预览操作，不实际执行
  -f, --force     跳过所有确认提示
  -V, --verbose   详细输出
```

### 常用命令

```bash
# 交互式备份
./backup-system.sh

# 快速备份（跳过确认）
./backup-system.sh backup --force

# 预览恢复操作
./backup-system.sh restore --dry-run

# 详细模式
./backup-system.sh -V backup
```

## 手动恢复

```bash
# 1. 恢复 pacman 配置
sudo cp configs/pacman.conf /etc/pacman.conf
sudo cp configs/mirrorlist.txt /etc/pacman.d/mirrorlist

# 2. 更新 Keyring
sudo pacman -Sy archlinux-keyring && sudo pacman -Syyu

# 3. 安装官方软件包
sudo pacman -S --needed - < packages/official.txt

# 4. 安装 yay
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin && makepkg -si

# 5. 安装 AUR 软件包
yay -S --needed - < packages/aur.txt

# 6. 恢复 Flatpak 软件包
flatpak install -y $(cat packages/flatpak.txt)

# 7. 恢复 dotfile
chezmoi init --source ~/cachy-backup/dotfile
chezmoi apply
```

## 备份 Dotfile

使用 [chezmoi](https://www.chezmoi.io/) 管理 dotfile，配置文件位于 `~/.config/chezmoi/chezmoi.yaml`：

```yaml
sourceDir: "/home/zhz/git/cachy-backup/dotfile"
```

添加新文件：
```bash
chezmoi add --recursive ~/.config
```

推送更新：
```bash
chezmoi cd && git add . && git commit -m "update $(date +%Y-%m-%d)" && git push
```

## 特性

- **模块化架构**: 备份/恢复逻辑分离到独立模块
- **TUI 界面**: 彩色输出，清晰的进度显示
- **Flatpak 支持**: 自动备份和恢复 Flatpak 应用
- **服务备份**: 记录启用的 systemd 服务
- **Dry-run 模式**: 预览操作，不实际执行
- **Force 模式**: 跳过确认，适合自动化
- **Bootstrap 脚本**: 一键恢复，支持 GitHub/Gitee 镜像
- **chezmoi 集成**: 自动恢复 dotfile

## License

MIT
