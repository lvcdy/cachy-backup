# cachy-backup

```
   ██████╗ █████╗  ██████╗██╗  ██╗██╗   ██╗
  ██╔════╝██╔══██╗██╔════╝██║  ██║╚██╗ ██╔╝
  ██║     ███████║██║     ███████║ ╚████╔╝
  ██║     ██╔══██║██║     ██╔══██║  ╚██╔╝
  ╚██████╗██║  ██║╚██████╗██║  ██║   ██║
   ╚═════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝
```

CachyOS / Arch Linux 系统备份与恢复工具。自动备份软件包列表、系统配置、dotfile 和桌面环境，一键恢复到新系统。

**桌面环境:** niri (Wayland compositor) + Noctalia v5 Shell

## 获取

| 源 | 地址 |
|---|------|
| **GitHub** | https://github.com/lvcdy/cachy-backup |
| **Gitee (国内镜像)** | https://gitee.com/lvcdy/cachy-backup |

## 快速开始

### 一键恢复（推荐）

```bash
# GitHub
bash <(curl -sL https://raw.githubusercontent.com/lvcdy/cachy-backup/main/strap.sh)

# Gitee（国内推荐）
sh <(curl -sL https://gitee.com/lvcdy/cachy-backup/raw/main/strap.sh)
```

> `strap.sh` 会自动检测时区选择镜像源，下载仓库后调用 `restore.sh` 执行恢复。
> 需要 `curl`、`git`、`rsync`，缺失时会自动安装。

### TTY 环境恢复

桌面环境无法启动时，在 TTY 中恢复：

```bash
# Ctrl+Alt+F2 切到 TTY，登录后运行
bash <(curl -sL https://gitee.com/lvcdy/cachy-backup/raw/main/strap.sh)

# 恢复完成后启动桌面
sudo systemctl start greetd
```

### 命令行使用

```bash
# 备份当前系统
./backup.sh

# 恢复（从已 clone 的仓库）
./restore.sh

# 预览恢复操作
./restore.sh --dry-run
```

**选项:**

| 选项 | 说明 |
|------|------|
| `-h, --help` | 显示帮助信息 |
| `-v, --version` | 显示版本号 |
| `-n, --dry-run` | 仅预览操作 |
| `-f, --force` | 跳过所有确认提示 |
| `-V, --verbose` | 详细输出 |

## 项目结构

```
cachy-backup/
├── backup.sh                # 备份入口
├── restore.sh               # 恢复入口
├── strap.sh                 # Bootstrap 一键恢复
├── scripts/
│   ├── 00-utils.sh          # TUI 引擎 + 公共工具函数
│   ├── 10-backup.sh         # 备份模块
│   └── 20-restore.sh        # 恢复模块 (18 步流程)
├── config/
│   └── exclude-backup.txt   # rsync 排除规则
├── dotfile/                 # rsync 管理的 dotfile
│   ├── .config/             # ~/.config 备份
│   └── .local/              # ~/.local 备份
├── packages/                # 软件包列表 (备份时生成)
│   ├── official.txt         # 官方源包列表
│   ├── aur.txt              # AUR 包列表
│   └── flatpak.txt          # Flatpak 包列表
├── configs/                 # 系统配置快照 (备份时生成)
│   ├── pacman.conf
│   ├── mirrorlist.txt
│   ├── locale.conf / locale.gen
│   ├── snapper/
│   ├── greetd/
│   └── system-info.txt
├── services/                # systemd 服务列表 (备份时生成)
│   ├── user-services.txt
│   └── system-services.txt
└── LICENSE
```

## 恢复流程

`restore.sh` 执行 18 步恢复流程，支持断点续传（中断后重跑会跳过已完成的步骤）：

| 阶段 | 步骤 | 说明 |
|------|------|------|
| **系统基础** | 1. 显示管理器 | sddm → greetd 冲突处理 |
| | 2. pacman 配置 | 恢复 pacman.conf + 4 种镜像源选择 |
| | 3. 系统配置 | locale / snapper / greetd |
| | 4. 系统更新 | keyring + pacman -Syyu |
| **软件包** | 5. 官方包 | 检测缺失包，增量安装 |
| | 6. AUR 助手 | 自动安装 yay-bin |
| | 7. AUR 包 | 通过 yay 恢复 |
| | 8. Flatpak 包 | 自动安装 flatpak 并恢复 |
| **用户配置** | 9. Dotfile | ~/.config + ~/.local + home dotfiles |
| | 10. 服务 | systemd 用户/系统服务 |
| | 11. 字体 | fc-cache 重建 |
| | 12. 用户组 | video/audio/input/wheel |
| | 13. dconf | GTK/字体/光标等桌面设置 |
| | 14. 默认 Shell | chsh |
| | 15. crontab | 定时任务 |
| **桌面环境** | 16. Noctalia v5 | 安装 → 配置验证 → App Theming → niri 集成 → greeter |
| **收尾** | 17. 后处理 | desktop-database / icon-cache / glib-schemas |
| | 18. 验证 | 检查关键包/配置/服务/字体，提示重启 |

## 备份内容

### 系统配置
- pacman.conf / mirrorlist
- locale 设置
- snapper 快照配置
- greetd 登录管理器配置
- Noctalia v5 配置导出 + 版本 + 验证结果

### 软件包
- 官方源 (`pacman -Qqen`)
- AUR (`pacman -Qqem`)
- Flatpak

### 用户配置 (dotfile)
- **桌面:** niri、Noctalia v5 (TOML 配置 + 插件 + settings.toml)
- **终端:** kitty
- **Shell:** fish、starship、bash/zsh 启动文件
- **编辑器:** neovim (LazyVim)
- **输入法:** fcitx5
- **其他:** .gitconfig、~/.local/bin、自定义字体、desktop 文件

### 服务
- systemd 用户服务 (`systemctl --user list-unit-files`)
- systemd 系统服务

## 配置文件

首次备份时自动创建 `~/.config/cachy-backup.conf`：

```ini
REPO_URL=https://github.com/lvcdy/cachy-backup.git
GH_USER=lvcdy
```

## 快捷键集成

### Kitty

```conf
map ctrl+shift+b launch --type=overlay --title="Backup" ~/git/cachy-backup/backup.sh --force
map ctrl+shift+r launch --type=overlay --title="Restore" ~/git/cachy-backup/restore.sh --dry-run
```

### Fish

```fish
function backup;  command ~/git/cachy-backup/backup.sh $argv; end
function restore; command ~/git/cachy-backup/restore.sh $argv; end
```

## 特性

- **断点续传** — 恢复中断后重跑自动跳过已完成步骤
- **增量恢复** — 只安装缺失的包，已安装的自动跳过
- **Noctalia v5 集成** — TOML 配置验证、App Theming 渲染、niri 启动检查、greeter 同步
- **多镜像回退** — GitHub / Gitee / tarball / git clone 四级回退
- **pacman 锁检测** — 自动检测并清理残留锁文件
- **进度追踪** — 18 步进度条 + 日志摘要（错误/警告计数）
- **TTY 兼容** — 纯文本环境下完整运行
- **Dry-run** — 预览所有操作，不实际执行

## License

[MIT License](LICENSE)
