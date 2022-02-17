#!/data/data/com.termux/files/usr/bin/env bash
set -eo pipefail

main() {
	color
	parse_arguments "$@"

	if [ "$do_install_proc" = 1 ]; then
		install_proc
		exit 0
	fi

	if [ "$do_copy_config" = 1 ]; then
		copy_config
	fi
	if [ "$do_install_pkg" = 1 ]; then
		install_pkg
	fi
}

color() {
	g="\033[1;32m" # 绿
	r="\033[1;31m" # 红
	y="\033[1;33m" # 黄
	b="\033[1;36m" # 蓝
	w="\033[1;37m" # 白
	h="\033[0m"    # 后缀
}

parse_arguments() {
	if [ "$#" -eq 0 ]; then
		do_install_proc=1
	fi

	while [ "$#" -gt 0 ]; do
		case "$1" in
			cf | config)
				do_copy_config=1
				;;
			in | install)
				do_install_pkg=1
				;;
			-h | --help)
				usage 0
				;;
			*)
				usage 1
				;;
		esac
		shift
	done
}

usage() {
	local exit_code="$1"

	echo "Syntax: termux.sh [options] command"
	echo ""
	echo "Install basic pkg and config."
	echo ""
	echo "Commands:"
	echo "    config    (cf)              Copy config"
	echo "    install   (in)              Install basic pkg"
	echo ""
	echo "Options:"
	echo "    -h, --help                  Print this help message"

	exit ${exit_code}
}

install_proc() {
	termux_set
	install_pkg
	copy_config
	write_config

	echo "please reboot"
}

termux_set() {
	# 连接内部存储。
	termux-setup-storage
}

change_source() {
	sed -i 's@^\(deb.*stable main\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-packages-24 stable main@' $PREFIX/etc/apt/sources.list
	sed -i 's@^\(deb.*games stable\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/game-packages-24 games stable@' $PREFIX/etc/apt/sources.list.d/game.list
	sed -i 's@^\(deb.*science stable\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/science-packages-24 science stable@' $PREFIX/etc/apt/sources.list.d/science.list
	pkg update
}

install_pkg() {
	local base_pkg=(curl git openssh rsync)
	local shell_pkg=(fish lf neovim starship)
	local nvim_pkg=(bat clang lua54 nodejs yarn)
	local other_pkg=(man tree wget zsh)

	pkg upgrade -y
	pkg install -y ${base_pkg[@]} ${shell_pkg[@]} ${nvim_pkg[@]} ${other_pkg[@]}
}

clone_cfg_repo() {
	cfg_dir="$HOME/dotfiles"

	if [ ! -d "$cfg_dir" ]; then
		git clone --depth=1 https://gitlab.com/glek/dotfiles.git ${cfg_dir}
	fi

	cd ${cfg_dir}
	git config --global user.email 'rraayy246@gmail.com'
	git config --global user.name 'ray'
	git config --global pull.rebase false
	git config --global credential.helper store
	cd
}

copy_config() {
	clone_cfg_repo

	rsync -a ${cfg_dir}/.config $HOME
	fish ${cfg_dir}/env.fish
}

write_config() {
	chsh -s fish

	echo -e 'if status is-interactive\n\tstarship init fish | source\nend' > $HOME/.config/fish/config.fish

	curl -fLo $HOME/.termux/font.ttf --create-dirs https://github.com/powerline/fonts/raw/master/UbuntuMono/Ubuntu%20Mono%20derivative%20Powerline.ttf

	set_nvim
}

set_nvim() {
	git clone --depth=1 https://gitlab.com/glek/dotnvim.git ~/.config/nvim

	#nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
}

error() {
	local wrong_reason="$@"

	echo -e "${r}error: ${h}${wrong_reason}"
	exit 1
}

main "$@"
