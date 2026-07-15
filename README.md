# cachy-backup

- **Host:** cachyos-x8664
- **Date:** 2026-07-15T11:43:22+08:00
- **Kernel:** 7.1.3-2-cachyos
- **Packages:** 199 official, 1 AUR, 0 flatpak
- **AUR helper:** yay

## 最近同步

2026-07-15 11:43:22

## 一键恢复

```bash
bash <(curl -sL https://raw.githubusercontent.com/USER/cachy-backup/main/strap.sh) restore
```

## 手动恢复

```bash
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
flatpak install -y $(cat packages/flatpak.txt)
```
