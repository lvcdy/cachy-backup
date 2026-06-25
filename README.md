# cachy-backup

- **Host:** $(hostname)
- **Date:** $(date --iso-8601=seconds)
- **Kernel:** $(uname -r)
- **Packages:** 293 official, 10 AUR
- **AUR helper:** yay

## 恢复软件指南 (Restore Guide)

在新系统上，您只需安装 `github-cli` 并登录，然后运行以下命令之一即可一键恢复：

### 方法 A：单行命令（推荐，无需手动克隆）
```bash
sudo pacman -S --noconfirm github-cli && \
gh auth login && \
bash <(gh api repos/\$(gh api user --jq '.login')/cachy-backup/contents/backup-system.sh -H "Accept: application/vnd.github.raw") restore
```

### 方法 B：克隆仓库恢复
```bash
sudo pacman -S --noconfirm github-cli && \
gh auth login && \
gh repo clone cachy-backup && \
cd cachy-backup && \
chmod +x backup-system.sh && \
./backup-system.sh restore
```

---

## 手动恢复参考流程

```bash
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
# (shopt -s nullglob; cd packages/yay-cache && for pkg in */; do cd "$pkg" && makepkg -si && cd ..; done)
```
