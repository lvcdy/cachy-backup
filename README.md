# cachy-backup

CachyOS 系统备份与恢复工具。自动备份软件包列表、系统配置和 dotfile，一键恢复到新系统。

## 系统信息

- **Host:** cachyos-x8664
- **Kernel:** 7.1.3-2-cachyos (x86_64)
- **Packages:** 200 official + 0 AUR
- **AUR helper:** yay
- **Desktop:** niri + noctalia
- **Display Manager:** greetd

## 项目结构

```
cachy-backup/
├── backup.sh               # 备份脚本
├── restore.sh              # 恢复脚本
├── strap.sh                # Bootstrap 一键恢复脚本
├── scripts/
│   ├── 00-utils.sh         # TUI 工具函数
│   ├── 10-backup.sh        # 备份模块
│   └── 20-restore.sh       # 恢复模块
├── dotfile/                # rsync 管理的 dotfile
│   ├── dot_config/         # ~/.config 备份
│   └── private_dot_local/  # ~/.local 备份
├── configs/
│   ├── pacman.conf         # pacman 配置
│   ├── mirrorlist.txt      # 镜像源列表
│   ├── locale.conf         # locale 设置
│   ├── locale.gen          # locale 生成配置
│   ├── snapper/            # snapper 快照配置
│   ├── greetd/             # greetd 登录管理器配置
│   └── system-info.txt     # 系统信息快照
├── packages/
│   ├── official.txt        # 官方源软件包列表
│   ├── aur.txt             # AUR 软件包列表
│   ├── flatpak.txt         # Flatpak 软件包列表
│   ├── explicit.txt        # 显式安装的包（含版本号）
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

### TTY 环境恢复（桌面环境挂掉时）

如果桌面环境无法启动，可以在 TTY 环境下恢复：

```bash
# 1. 切换到 TTY (Ctrl+Alt+F2)
# 2. 登录后运行
bash <(curl -sL https://raw.githubusercontent.com/lvcdy/cachy-backup/main/strap.sh) restore

# 3. 恢复完成后启动桌面
sudo systemctl start greetd
```

### 命令行使用

```bash
# 备份
./backup.sh [选项]

# 恢复
./restore.sh [选项]

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
./backup.sh

# 快速备份（跳过确认）
./backup.sh --force

# 预览恢复操作
./restore.sh --dry-run

# 详细模式
./backup.sh -V
```

### Kitty 快捷键

在 kitty.conf 中添加：

```conf
# 备份/恢复快捷键
map ctrl+shift+b launch --type=overlay --title="Backup" ~/git/cachy-backup/backup.sh --force
map ctrl+shift+r launch --type=overlay --title="Restore" ~/git/cachy-backup/restore.sh --dry-run
```

### Fish 函数

在 config.fish 中添加：

```fish
# cachy-backup
function backup
    command ~/git/cachy-backup/backup.sh $argv
end
function 备份
    backup $argv
end
function restore
    command ~/git/cachy-backup/restore.sh $argv
end
function 恢复
    restore $argv
end
```

## 恢复流程

恢复脚本会自动执行以下步骤：

1. **清理冲突包** - 检测并卸载 quickshell/sddm 等冲突包
2. **显示管理器检测** - 检测已安装的显示管理器，处理 greetd 冲突
3. **恢复 pacman 配置** - mirrorlist、pacman.conf
4. **恢复系统配置** - locale、snapper、greetd
5. **更新系统** - keyring、系统更新
6. **恢复软件包** - 官方包、AUR 包、Flatpak
7. **恢复 dotfile** - ~/.config、fcitx5 数据

## 配置文件

备份配置保存在 `~/.config/cachy-backup.conf`：

```ini
REPO_URL=https://github.com/lvcdy/cachy-backup.git
GH_USER=lvcdy
```

首次备份时会自动创建配置文件。

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

# 6. 恢复 dotfile
rsync -a dotfile/dot_config/ ~/.config/
```

## 备份内容

### 系统配置
- pacman.conf 和 mirrorlist
- locale 设置
- snapper 快照配置
- greetd 登录管理器配置

### 软件包
- 官方软件包列表 (pacman -Qqen)
- AUR 软件包列表 (pacman -Qqem)
- Flatpak 软件包列表
- AUR 包的 PKGBUILD 缓存

### 用户配置 (dotfile)
- niri 窗口管理器配置
- noctalia 主题/Shell 配置
- fish shell 配置
- starship 提示符配置
- kitty 终端配置
- neovim 编辑器配置
- yazi 文件管理器配置
- fcitx5 输入法配置
- GTK 设置

### 服务
- systemd 用户服务列表
- systemd 系统服务列表

## 特性

- **模块化架构**: 备份/恢复逻辑分离到独立模块
- **TUI 界面**: 彩色输出，清晰的进度显示
- **TTY 支持**: 可在纯文本环境下运行
- **显示管理器检测**: 自动检测并处理 DM 冲突
- **冲突包清理**: 自动清理 quickshell/sddm 等冲突包
- **断点续传**: 恢复中断后可继续
- **Flatpak 支持**: 自动备份和恢复 Flatpak 应用
- **服务备份**: 记录启用的 systemd 服务
- **Dry-run 模式**: 预览操作，不实际执行
- **Force 模式**: 跳过确认，适合自动化

## License

MIT
