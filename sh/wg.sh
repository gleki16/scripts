#!/usr/bin/env bash
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
			in | install)
				do_set_wg=1
				;;
			co | config)
				do_review_config=1
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

	echo "Syntax: wg.sh [options] command"
	echo ""
	echo "Install wireguard and config."
	echo ""
	echo "Commands:"
	echo "    install   (in)              Install wireguard config"
	echo "    member    (me)              Add or remove members"
	echo "    config    (co)              Review members config"
	echo ""
	echo "Options:"
	echo "    -h, --help                  Print this help message"

	exit ${exit_code}
}

error() {
	local wrong_reason="$@"

	echo -e "${r}error: ${h}${wrong_reason}"
	exit 1
}

main "$@"
