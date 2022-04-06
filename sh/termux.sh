#!/data/data/com.termux/files/usr/bin/env bash
set -eo pipefail

main() {
	color
	parse_arguments "$@"

	if [ "$do_install_proc" = 1 ]; then
		install_proc
		exit 0
	fi

	if [ "$do_install_pkg" = 1 ]; then
		install_pkg
	fi
	if [ "$do_copy_config" = 1 ]; then
		copy_config
	fi
}

parse_arguments() {
	if [ "$#" -eq 0 ]; then
		do_install_proc=1
	fi

	while [ "$#" -gt 0 ]; do
		case "$1" in
			co | config)
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

	echo -e "${g}termux.sh${h} 0.1.0"
	echo -e "    install basic pkg and config"
	echo -e ""
	echo -e "${y}usage:${h}"
	echo -e "    termux.sh [options] [subcommand]"
	echo -e ""
	echo -e "${y}options:${h}"
	echo -e "    ${g}-h${h}, ${g}--help${h}              print this help message"
	echo -e ""
	echo -e "${y}subcommands:${h}"
	echo -e "    ${g}co${h}, ${g}config${h}              copy config"
	echo -e "    ${g}in${h}, ${g}install${h}             install basic pkg"

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
	local shell_pkg=(fish lf helix starship zoxide)
	local other_pkg=(bat man tree wget zsh)

	pkg upgrade -y
	pkg install -y ${base_pkg[@]} ${shell_pkg[@]} ${other_pkg[@]}
}

clone_cfg_repo() {
	cfg_dir="$HOME/dotfiles"

	if [ ! -d "$cfg_dir" ]; then
		git clone --depth=1 https://gitlab.com/glek/dotfiles.git ${cfg_dir}
	fi

	cd ${cfg_dir}
	git config --global credential.helper store
	git config --global pull.rebase false
	git config --global user.email 'rraayy246@gmail.com'
	git config --global user.name 'ray'
	cd
}

copy_config() {
	clone_cfg_repo

	rsync -a ${cfg_dir}/.config $HOME
	fish ${cfg_dir}/env.fish
}

write_config() {
	chsh -s fish

	cat << EOF > $HOME/.config/fish/config.fish
if status is-interactive
	starship init fish | source
	zoxide init fish | source
end
EOF

	curl -fLo $HOME/.termux/font.ttf --create-dirs https://github.com/powerline/fonts/raw/master/UbuntuMono/Ubuntu%20Mono%20derivative%20Powerline.ttf
}

error() {
	local wrong_reason="$*"

	echo -e "${r}error:${h} ${wrong_reason}"
	exit 1
}

color() {
	r="\033[31m" # 红
	g="\033[32m" # 绿
	y="\033[33m" # 黄
	b="\033[34m" # 蓝
	p="\033[35m" # 紫
	c="\033[36m" # 青
	w="\033[37m" # 白
	h="\033[0m"  # 后缀
}

main "$@"
