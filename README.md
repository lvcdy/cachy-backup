# cachy-backup

CachyOS 系统备份与恢复工具。自动备份软件包列表、系统配置和 dotfile，一键恢复到新系统。

- **Host:** strix-g16
- **Kernel:** 7.1.1-2-cachyos (x86_64)
- **Packages:** 293 official + 10 AUR
- **AUR helper:** yay

## 项目结构

```
cachy-backup/
├── backup-system.sh        # 备份/恢复脚本
├── dotfile/                # chezmoi 管理的 dotfile（~/.config 等）
├── packages/
│   ├── official.txt        # 官方源软件包列表
│   ├── aur.txt             # AUR 软件包列表
│   ├── explicit.txt        # 显式安装的包（含版本号）
│   ├── pacman.conf         # pacman 配置
│   ├── mirrorlist.txt      # 镜像源列表
│   ├── system-info.txt     # 系统信息快照
│   └── yay-cache/          # AUR 包的 PKGBUILD 备份
└── README.md
```

## 一键恢复

在新系统上，安装 `github-cli` 并登录后运行：

```bash
# 方法 A：单行命令（无需手动克隆）
sudo pacman -S --noconfirm github-cli && \
gh auth login && \
bash <(gh api repos/$(gh api user --jq '.login')/cachy-backup/contents/backup-system.sh -H "Accept: application/vnd.github.raw") restore

# 方法 B：克隆仓库恢复
git clone git@github.com:lvcdy/cachy-backup.git ~/cachy-backup && \
cd ~/cachy-backup && \
chmod +x backup-system.sh && \
./backup-system.sh restore
```

## 手动恢复

```bash
# 1. 恢复 pacman 配置
sudo cp packages/pacman.conf /etc/pacman.conf
sudo cp packages/mirrorlist.txt /etc/pacman.d/mirrorlist

# 2. 更新 Keyring
sudo pacman -Sy archlinux-keyring && sudo pacman -Syyu

# 3. 安装官方软件包
pacman -S --needed - < packages/official.txt

# 4. 安装 yay
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
cd /tmp/yay-bin && makepkg -si

# 5. 安装 AUR 软件包
yay -S --needed - < packages/aur.txt

# 6. 恢复 dotfile（设置 chezmoi 源目录后）
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

## 更新备份

```bash
./backup-system.sh
```

脚本会自动备份当前系统的软件包列表和配置，提交并推送到 GitHub。
