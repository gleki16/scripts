#!/usr/bin/env bash
set -eo pipefail

main() {
	color
	parse_arguments "$@"
	cd_wg_dir

	if [ "$do_set_wg" = 1 ]; then
		set_wg
		local do_change_mem=1
	fi
	if [ "$do_change_mem" = 1 ]; then
		change_mem
		local do_review_config=1
	fi
	if [ "$do_review_config" = 1 ]; then
		review_config
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
	while [ "$#" -gt 0 ]; do
		case "$1" in
			set)
				do_set_wg=1
				;;
			me | member)
				do_change_mem=1
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
	echo "    set                         Set wireguard to use"
	echo "    member    (me)              Add or remove members"
	echo "    config    (co)              Review members config"
	echo ""
	echo "Options:"
	echo "    -h, --help                  Print this help message"

	exit ${exit_code}
}

cd_wg_dir() {
	local wg_dir="$HOME/.wireguard"

	mkdir -p ${wg_dir}
}

set_wg() {
}

change_mem() {
}

review_config() {
}

set_ip() {
	local interface=$(ip -o -4 route show to default | awk '{print $5}')
	ip=$(ip -4 addr show $interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
}

generate_mem_config() {
	local mem_number="$1"

	cat << EOF > wg${mem_number}.conf
[Interface]
PrivateKey = $(cat pri${mem_number})
Address = 10.10.10.${mem_number}

[Peer]
PublicKey = $(cat pub1)
Endpoint = ${ip}:${port}
AllowedIPs = 0.0.0.0/0
EOF
}

error() {
	local wrong_reason="$@"

	echo -e "${r}error: ${h}${wrong_reason}"
	exit 1
}

main "$@"
