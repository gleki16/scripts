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
	set_ip
	port=51820

	rm -rf .

	echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/ip_forward.conf
	sudo sysctl $(cat /etc/sysctl.d/ip_forward.conf | sed 's/ //g')

	wg genkey | tee pri1 | wg pubkey > pub1
	wg genkey | tee pri2 | wg pubkey > pub2

	chmod 600 pri1
	chmod 600 pri2

	cat << EOF | sudo tee /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $(cat pri1)
Address = 10.10.10.1/32
ListenPort = ${port}
PostUp   = nft add rule inet nat postrouting oifname ${interface} masquerade
PostDown = nft flush ruleset; nft -f /etc/nftables.conf

[Peer]
PublicKey = $(cat pub2)
AllowedIPs = 10.10.10.2/32
EOF

    generate_mem_config 2

    sudo wg-quick up wg0
    sudo systemctl enable wg-quick@wg0

    echo "安装完成！"
}

change_mem() {
	set_ip
	port=$(sudo cat /etc/wireguard/wg0.conf | grep -oP '(?<=ListenPort = )\d+')

	while true; do
		local mem_list=($(sudo cat /etc/wireguard/wg0.conf | grep -oP '(?<=\.)\d+(?=\/)'))

		echo ""
		echo "已存在成员："
		echo "${mem_list[@]}"

		echo "输入成员数字（存在则删除，不存在则创建）"
		read -p "> " i
		if [[ "$i" =~ ^[1-9][0-9]+$ ]] && [ ${i} -ge 2 -a ${i} -le 254 ]; then
			if [[ "${mem_list[@]}" =~ "$i" ]]; then
				sudo wg set wg0 peer $(cat pub${i}) remove
				sudo wg-quick save wg0
				rm wg${i}.conf pub${i} pri${i}
			else
				wg genkey | tee pri${i} | wg pubkey > pub${i}
				chmod 600 pri${i}
				sudo wg set wg0 peer $(cat pub${i}) allowed-ips 10.10.10.${i}/32
				sudo wg-quick save wg0
				generate_member_config ${i}
			fi
		else
			break
		fi
	done
}

review_config() {
	local mem_list=$(sudo cat /etc/wireguard/wg0.conf | grep -oP '(?<=\.)\d+(?=\/)')

	while true; do
		echo
		echo "已存在成员："
		echo "${mem_list[@]}"

		echo "输入成员数字（查看配置）"
		read -p "> " i
		if [[ "$i" =~ ^[1-9][0-9]+$ ]] && [[ "${mem_list[@]}" =~ "$i" ]]; then
			echo ""
			echo ""
			echo " cat << EOF | sudo tee /etc/wireguard/wg${i}.conf"
			cat wg${i}.conf
			echo "EOF"
			echo ""
			echo ""
			qrencode -t ansiutf8 < wg${i}.conf
			echo
		else
			break
		fi
	done
}

set_ip() {
	interface=$(ip -o -4 route show to default | awk '{print $5}')
	ip=$(ip -4 addr show ${interface} | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
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
