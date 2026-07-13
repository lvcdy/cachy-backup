source /usr/share/cachyos-fish-config/cachyos-config.fish

set fish_greeting ""
set -p PATH ~/.local/bin
starship init fish | source
zoxide init fish --cmd cd | source

function y
	set tmp (mktemp -t "yazi-cwd.XXXXXX")
	yazi $argv --cwd-file="$tmp"
	if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
		builtin cd -- "$cwd"
	end
	rm -f -- "$tmp"
end

function cat 
	command bat $argv
end

function ls
	command eza --icons $argv
end
function lt
	command eza --icons --tree $argv
end

# grub
abbr grub 'LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 sudo grub-mkconfig -o /boot/grub/grub.cfg'
# 小黄鸭补帧 需要steam安装正版小黄鸭
abbr lsfg 'LSFG_PROCESS="miyu"'
# fa运行fastfetch
abbr fa fastfetch
abbr reboot 'systemctl reboot'
function sl 
	command sl | lolcat	
end
function 滚
	sysup 
end
function raw
	command ~/.config/scripts/random-anime-wallpaper.sh $argv
end

function 安装
	command yay -S $argv
end

function 卸载
	command yay -Rns $argv
end

# cachy-backup
function backup
	command ~/git/cachy-backup/backup-system.sh backup $argv
end
function 备份
	backup $argv
end
function restore
	command ~/git/cachy-backup/backup-system.sh restore $argv
end
function 恢复
	restore $argv
end

function dotpush
	set skip chezmoi zen mozilla thunderbird opencode Code go ibus pulse uv yay nautilus mpv firefox
	for item in ~/.config/*
		set name (basename "$item")
		contains -- "$name" $skip; and continue
		[ -d "$item" ]; and chezmoi add --recursive "$item" 2>/dev/null
		[ -f "$item" ]; and chezmoi add "$item" 2>/dev/null
	end
	chezmoi add --recursive ~/.local/share/fcitx5 2>/dev/null
	chezmoi cd
	git add .
	git diff --cached --quiet; and echo "no changes" && return 0
	git commit -m "update (date +%Y-%m-%d_%H-%M)"
	if command -q gh
		# gh 认证后 git push 自动使用 gh 凭证
		git push; or begin
			echo "push failed, trying to create repo..."
			set repo (basename (pwd))
			gh repo create $repo --private --source=. --push
		end
	else
		git push
	end
	echo "done"
end