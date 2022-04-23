#!/usr/bin/env bash
set -eo pipefail

main() {
	color
	parse_arguments "$@"
	check_root_permission

	if [ "$do_connect_wifi" = 1 ]; then
		connect_wifi
	fi
	if [ "$do_open_ssh" = 1 ]; then
		open_ssh
		exit 0
	fi

	check_efi

	if [ "$do_live_env_proc" = 1 ]; then
		live_env_proc
		exit 0
	fi
	if [ "$do_in_chroot_proc" = 1 ]; then
		in_chroot_proc
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
		do_live_env_proc=1
	fi

	while [ "$#" -gt 0 ]; do
		case "$1" in
			co | config)
				do_copy_config=1
				;;
			in | install)
				do_install_pkg=1
				;;
			ss | ssh)
				do_open_ssh=1
				;;
			wi | wifi)
				do_connect_wifi=1
				;;
			--in-chroot)
				do_in_chroot_proc=1
				shift
				user_name="$1"
				shift
				user_pass="$1"
				shift
				use_gui="$1"
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

	echo -e "${g}arch.sh${e} 0.1.0"
	echo -e "quick install arch"
	echo -e ""
	echo -e "${y}usage:${e}"
	echo -e "    arch.sh [options] [subcommand]"
	echo -e ""
	echo -e "${y}options:${e}"
	echo -e "    ${g}-h${e}, ${g}--help${e}"
	echo -e "        print this help message"
	echo -e ""
	echo -e "${y}subcommands:${e}"
	echo -e "    ${g}co${e}, ${g}config${e}"
	echo -e "        copy config"
	echo -e ""
	echo -e "    ${g}in${e}, ${g}install${e}"
	echo -e "        install basic pkg"
	echo -e ""
	echo -e "    ${g}ss${e}, ${g}ssh${e}"
	echo -e "        open ssh service"
	echo -e ""
	echo -e "    ${g}wi${e}, ${g}wifi${e}"
	echo -e "        connect to a wifi"

	exit ${exit_code}
}

live_env_proc() {
	check_network
	update_system_clock
	enter_user_var
	use_gui_or_not
	set_partition
	set_subvol
	install_base_system
	set_fstab
	set_hostname
	change_root
}

in_chroot_proc() {
	set_time_zone
	set_locale
	set_network
	set_passwd
	set_pacman
	install_bootloader
	install_pkg
	copy_config
	write_config
	set_auto_start
	fix_mnt_point
}

connect_wifi() {
	local iw_dev=$(iw dev | awk '$1=="Interface"{print $2}')

	iwctl station ${iw_dev} scan
	iwctl station ${iw_dev} get-networks
	echo -ne "${y}read: ${e}wifi name you want to connect to: "
	read ssid
	iwctl station ${iw_dev} connect "${ssid}"
}

open_ssh() {
	local interface=$(ip -o -4 route show to default | awk '{print $5}')
	local ip=$(ip -4 addr show $interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

	read_only_format user_pass "enter your root passwd:" '^[-_,.a-zA-Z0-9]\+$'
	echo "${USER}:${user_pass}" | chpasswd
	systemctl start sshd

	echo -e "${g}# ssh ${USER}@${ip}${e}"
	echo -e "${g}passwd = ${user_pass}${e}"
}

read_only_format() {
	local var_name_to_be_set="$1"
	local output_hint="$2"
	local matching_format="$3"

	while true; do
		echo -ne "${y}read: ${e}$output_hint "
		read reply
		if echo "$reply" | grep -q "$matching_format"; then
			echo -ne "${y}read: ${e}${reply}, are you sure? "
			read sure
			if [ "$sure" = 'y' -o "$sure" = '' ]; then
				break
			fi
		else
			echo -e "${r}wrong format.${e}"
		fi
	done

	eval ${var_name_to_be_set}="$reply"
}

check_network() {
	if ping -c 1 -w 1 1.1.1.1 &>/dev/null; then
		echo -e "${g}network connection is successful.${e}"
	else
		error "Network connection failed."
	fi
}

update_system_clock() {
	timedatectl set-ntp true
}

enter_user_var() {
	read_only_format host_name "enter your hostname:"    '^[a-zA-Z][-a-zA-Z0-9]*$'
	read_only_format user_name "enter your username:"    '^[a-z][-a-z0-9]*$'
	read_only_format user_pass "enter your user passwd:" '^[-_,.a-zA-Z0-9]*$'
}

use_gui_or_not() {
	echo -ne "${y}read: ${e}use GUI or not? "
	read reply

	case "$reply" in
		y)
			use_gui=1
			;;
		n)
			use_gui=0
			;;
		*)
			if [ $(systemd-detect-virt) = "none" ]; then
				use_gui=1
			else
				use_gui=0
			fi
			;;
	esac
}

set_partition() {
	echo -e "${r}automatic partition or manual partition: ${e}"
	sel reply "automatic" "manual"

	if [ "$reply" = "automatic" ]; then
		select_partition main_part

		parted -s ${main_part} mklabel gpt
		if [ "$bios_type" = "uefi" ]; then
			parted -s ${main_part} \
				mkpart esp 1m 513m \
				set 1 esp on \
				mkpart arch 513m 100%
		else
			parted -s ${main_part} \
				mkpart grub 1m 3m \
				set 1 bios_grub on \
				mkpart arch 3m 100%
		fi

		if echo ${main_part} | grep -q 'nvme'; then
			boot_part="${main_part}p1"
			root_part="${main_part}p2"
		else
			boot_part="${main_part}1"
			root_part="${main_part}2"
		fi

		if [ "$bios_type" = "uefi" ]; then
			mkfs.fat -F32 ${boot_part}
		fi
	else
		select_partition boot_part
		select_partition root_part
	fi
}

select_partition() {
	local partition_name="$1"
	local partition_list=($(lsblk -lno NAME | grep '^\(nvme\|sd.\|vd.\)'))

	lsblk -o NAME,SIZE
	echo -e "${r}select a partition as the ${e}${partition_name}${r} partition:${e}"

	sel part ${partition_list[@]}
	eval ${partition_name}="/dev/${part}"
}

sel() {
	local var_name_to_be_set="$1"
	shift
	local option_list=($@)

	select option in ${option_list[@]}; do
		if [ "$option" != "" ] && [[ "${option_list[@]}" =~ "$option"  ]]; then
			echo -ne "${y}read: ${e}${option}, are you sure? "
			read sure
			if [ "$sure" = 'y' -o "$sure" = '' ]; then
				break
			fi
		fi
	done

	eval ${var_name_to_be_set}=${option}
}

set_subvol() {
	local subvol_list=(.snapshots 'boot/grub' home opt root srv 'usr/local' var)

	if findmnt /mnt; then
		umount -fR /mnt
	fi

	mkfs.btrfs -fL arch ${root_part}
	mount ${root_part} /mnt

	btrfs subvolume create /mnt/@

	for subvol in ${subvol_list[@]}; do
		mkdir -p /mnt/@/$(dirname $subvol)
		btrfs subvolume create /mnt/@/${subvol}
	done

	chattr +C /mnt/@/var

	mkdir /mnt/@/.snapshots/1
	btrfs subvolume create /mnt/@/.snapshots/1/snapshot

	local default_id=$(btrfs inspect-internal rootid /mnt/@/.snapshots/1/snapshot)
	btrfs subvolume set-default ${default_id} /mnt

	umount -R /mnt

	mount -o noatime,autodefrag,compress=zstd,discard=async ${root_part} /mnt

	for subvol in ${subvol_list[@]}; do
		mkdir -p /mnt/${subvol}
		mount -o subvol=/@/${subvol} ${root_part} /mnt/${subvol}
	done

	if [ "$bios_type" = 'uefi' ]; then
		mkdir -p /mnt/boot/efi
		mount ${boot_part} /mnt/boot/efi
	fi

	# 避免回滚时 pacman 数据库和软件不同步
	mkdir -p     /mnt/usr/lib/pacman/local /mnt/var/lib/pacman/local
	mount --bind /mnt/usr/lib/pacman/local /mnt/var/lib/pacman/local
}

install_base_system() {
	local basic_pkg=(base base-devel linux linux-firmware btrfs-progs fish dhcpcd reflector vim)

	pacman -Sy --noconfirm archlinux-keyring

	pacstrap /mnt ${basic_pkg[@]}
}

set_fstab() {
	# 绑定挂载无法被 genfstab 正确识别，所以先卸载
	umount /mnt/var/lib/pacman/local

	genfstab -L /mnt >> /mnt/etc/fstab

	mount --bind /mnt/usr/lib/pacman/local /mnt/var/lib/pacman/local

	# 手动写入绑定挂载
	echo '/usr/lib/pacman/local /var/lib/pacman/local none defaults,bind 0 0' >> /mnt/etc/fstab
}

set_hostname() {
	echo ${host_name} > /mnt/etc/hostname
}

change_root() {
	local script_url="https://gitlab.com/glek/scripts/raw/main/sh/arch.sh"

	curl -fLo /mnt/arch.sh ${script_url}
	chmod +x /mnt/arch.sh

	arch-chroot /mnt /arch.sh --in-chroot "$user_name" "$user_pass" "$use_gui"

	set_resolve
	rm /mnt/arch.sh

	umount -R /mnt

	echo -e "${r}please reboot.${e}"
}

set_resolve() {
	cat << EOF > /mnt/etc/resolv.conf
nameserver ::1
nameserver 127.0.0.1
options edns0 single-request-reopen
EOF
	chattr +i /mnt/etc/resolv.conf
}

set_time_zone() {
	local city="Asia/Shanghai"

	ln -sf /usr/share/zoneinfo/${city} /etc/localtime
	hwclock --systohc
}

set_locale() {
	sed -i '/#\(en_US\|zh_CN\).UTF-8/s/#//' /etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" > /etc/locale.conf
}

set_network() {
	local host_name=$(cat /etc/hostname)

	cat << EOF >> /etc/hosts
127.0.0.1	localhost
::1		localhost
127.0.1.1	${host_name}.localdomain ${host_name}
EOF
}

set_passwd() {
	echo "root:${user_pass}" | chpasswd

	useradd -mG wheel ${user_name}
	echo "${user_name}:${user_pass}" | chpasswd
	sed -i '/# %wheel .* NOPASSWD/s/# //' /etc/sudoers
}

set_pacman() {
	sed -i '/^#Color$/s/#//' /etc/pacman.conf

	cat << EOF >> /etc/pacman.conf
[archlinuxcn]
Server = http://repo.archlinuxcn.org/\$arch
EOF

	pacman -Syy --noconfirm archlinuxcn-keyring
}

install_bootloader() {
	local root_part=$(df | awk '$6=="/" {print $1}')
	local boot_pkg=(grub grub-btrfs)

	if [ "$bios_type" = 'uefi' ]; then
		boot_pkg+=(efibootmgr)
	fi

	if [ "$use_gui" = 1 ]; then
		boot_pkg+=(os-prober)
	fi

	pacman_install ${boot_pkg[@]}

	case "$bios_type" in
		uefi)
			grub-install --target=x86_64-efi --efi-directory=/boot/efi
			;;
		bios)
			if echo ${root_part} | grep -q 'nvme'; then
				local grub_part=$(echo ${root_part} | sed 's/p[0-9]$//')
			else
				local grub_part=$(echo ${root_part} | sed 's/[0-9]$//')
			fi
			grub-install --target=i386-pc ${grub_part}
			;;
	esac

	# 修正 grub 查找内核
	sed -i 's/rootflags=subvol=${rootsubvol} //' /etc/grub.d/10_linux
	sed -i 's/rootflags=subvol=${rootsubvol} //' /etc/grub.d/20_linux_xen

	sed -i '/GRUB_TIMEOUT=/s/5/1/' /etc/default/grub

	if [ "$use_gui" = 1 ]; then
		echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
		# 禁用看门狗定时器
		sed -i '/GRUB_CMDLINE_LINUX_DEFAULT=/s/"$/ nowatchdog&/' /etc/default/grub
	fi

	grub-mkconfig -o /boot/grub/grub.cfg
}

pacman_install() {

	# 一次性安装太多软件容易安装失败，
	# 所以连试三次，增加成功的几率。

	local pkg_list=($@)

	for i in $(seq 3); do
		if pacman -S --needed --noconfirm ${pkg_list[@]}; then
			break
		fi
	done
}

install_pkg() {
	local network_pkg=(aria2 curl git go-ipfs openssh wireguard-tools)
	local terminal_pkg=(helix starship zellij zoxide zsh)
	local file_pkg=(lf p7zip snapper snap-pac)
	local sync_pkg=(chrony rsync)
	local search_pkg=(fzf mlocate)
	local new_search_pkg=(fd ripgrep bat tealdeer exa)
	local system_pkg=(fcron bottom man pacman-contrib pkgstats)
	local maintain_pkg=(arch-install-scripts dosfstools parted)
	local security_pkg=(dnscrypt-proxy gocryptfs nftables)
	local depend_pkg=(perl-file-mimeinfo qrencode)
	local aur_pkg=(paru)

	pacman_install ${network_pkg[@]}  ${terminal_pkg[@]}
	pacman_install ${file_pkg[@]}     ${sync_pkg[@]}
	pacman_install ${search_pkg[@]}   ${new_search_pkg[@]}
	pacman_install ${system_pkg[@]}   ${maintain_pkg[@]}
	pacman_install ${security_pkg[@]} ${depend_pkg[@]} ${aur_pkg[@]}

	# iptables-nft 不能直接装，需要进行确认
	echo -e "y\n\n" | pacman -S --needed iptables-nft

	if [ "$use_gui" = 1 ]; then
		install_gui_pkg
	fi
}

install_gui_pkg() {
	local cpu_vendor=$(grep vendor_id /proc/cpuinfo)
	if echo "$cpu_vendor" | grep -q 'AuthenticAMD'; then
		local ucode_pkg="amd-ucode"
	elif echo "$cpu_vendor" | grep -q 'GenuineIntel'; then
		local ucode_pkg="intel-ucode"
	fi

	local lspci_VGA="$(lspci | grep '3D\|VGA')"
	if echo "$lspci_VGA" | grep -q 'AMD'; then
		local gpu_pkg="xf86-video-amdgpu"
	elif echo "$lspci_VGA" | grep -q 'Intel'; then
		local gpu_pkg="xf86-video-intel"
	elif echo "$lspci_VGA" | grep -q 'NVIDIA'; then
		local gpu_pkg="xf86-video-nouveau"
	fi

	local audio_pkg=(pipewire pipewire-alsa pipewire-pulse)
	local bluetooth_pkg=(bluez bluez-utils blueman)
	local touch_pkg=(libinput)

	local driver_pkg=(${ucode_pkg[@]} ${gpu_pkg[@]} ${audio_pkg[@]} ${bluetooth_pkg[@]} ${touch_pkg[@]})
	local manager_pkg=(networkmanager tlp)
	local display_pkg=(wayland sway swayidle waylock wl-clipboard xorg-xwayland)
	local desktop_pkg=(alacritty grim slurp mako qt5-wayland waybar wofi)
	local browser_pkg=(firefox firefox-i18n-zh-cn)
	local media_pkg=(imv vlc)
	local input_pkg=(fcitx5-im fcitx5-chinese-addons)
	local control_pkg=(light playerctl sddm udiskie)
	local virtual_pkg=(flatpak qemu libvirt virt-manager dnsmasq bridge-utils openbsd-netcat edk2-ovmf)
	local office_pkg=(foliate libreoffice-fresh-zh-cn)
	local font_pkg=(noto-fonts-cjk noto-fonts-emoji otf-font-awesome ttf-ubuntu-font-family)

	pacman_install ${driver_pkg[@]}  ${manager_pkg[@]}
	pacman_install ${display_pkg[@]} ${desktop_pkg[@]}
	pacman_install ${browser_pkg[@]} ${media_pkg[@]}
	pacman_install ${input_pkg[@]}   ${control_pkg[@]}
	pacman_install ${virtual_pkg[@]} ${office_pkg[@]}
	pacman_install ${font_pkg[@]}
}

copy_config() {
	user_home="/home/${user_name}"

	set_cfg_repo

	fish ${cfg_dir}/env.fish
	do_as_user fish ${cfg_dir}/env.fish

	sync_cfg_dir etc /
	sync_cfg_dir .config /root
	sync_cfg_dir .config ${user_home}
}

do_as_user() {

	# 避免创建出的目录或文件，用户无权操作。

	cd ${user_home}
	sudo -u ${user_name} "$@"
	cd
}

set_cfg_repo() {

	# uz 是存放我所有设定的仓库

	cfg_dir="${user_home}/dotfiles"
	cfg_url="https://gitlab.com/glek/dotfiles.git"

	do_as_user git clone --depth=1 ${cfg_url} ${cfg_dir}

	cd ${cfg_dir}
	do_as_user git config --global credential.helper store
	do_as_user git config --global pull.rebase false
	do_as_user git config --global user.email 'rraayy246@gmail.com'
	do_as_user git config --global user.name 'ray'
	cd
}

sync_cfg_dir() {

	# 如果目标目录非用户的目录，则不复制所有者信息，
	# 以免其他程序无权限操作。

	local src_in_cfg_dir="$1"
	local dest_dir="$2"
	local src_dir="${cfg_dir}/${src_in_cfg_dir}"

	if echo "$dest_dir" | grep -q '^/home'; then
		rsync -a --inplace --no-whole-file ${src_dir} ${dest_dir}
	else
		rsync -rlptD --inplace --no-whole-file ${src_dir} ${dest_dir}
	fi
}

write_config() {
	set_cron
	set_ipfs
	set_shell
	set_snapper
	set_ssh
	set_swap
	set_tldr

	if [ "$use_gui" = 1 ]; then
		set_bluetooth
		set_light
		set_virtualizer
		set_wallpaper
	fi
}

set_cron() {
	if [ "$use_gui" = 1 ]; then
		sed '/[^@]reboot/s/^/#/' ${cfg_dir}/cron > /tmp/cron
		fcrontab /tmp/cron
		rm /tmp/cron
	else
		fcrontab ${cfg_dir}/cron
	fi
}

set_ipfs() {
	do_as_user ipfs init
	systemctl enable ipfs@${user_name}
}

set_shell() {
	sed -i '/home\|root/s/bash/zsh/' /etc/passwd

	echo "# 如果没有 .zshrc，zsh 会要你新建一个" > ${user_home}/.zshrc
}

set_snapper() {
	# 防止快照被索引
	sed -i '/PRUNENAMES/s/.git/& .snapshots/' /etc/updatedb.conf

	sed -i '/SNAPPER_CONFIGS=/s/""/"root"/' /etc/conf.d/snapper

	local date=$(date +'%F %T')
	cat << EOF > /.snapshots/1/info.xml
<?xml version="1.0"?>
<snapshot>
  <type>single</type>
  <num>1</num>
  <date>${date}</date>
  <cleanup>number</cleanup>
  <description>first root filesystem</description>
</snapshot>
EOF
	chmod 600 /.snapshots/1/info.xml
}

set_ssh() {
	ssh-keygen -A
}

set_swap() {
	local swap_file="/var/lib/swap/swapfile"
	local swap_size=2G

	mkdir -p $(dirname $swap_file)
	touch ${swap_file}
	chattr +C ${swap_file}
	chattr -c ${swap_file}

	fallocate -l ${swap_size} ${swap_file}

	chmod 600 ${swap_file}
	mkswap ${swap_file}

	echo "${swap_file} none swap defaults 0 0" >> /etc/fstab

	# 最大限度使用物理内存
	echo "vm.swappiness = 0" > /etc/sysctl.d/swappiness.conf
	sysctl $(cat /etc/sysctl.d/swappiness.conf | sed 's/ //g')
}

set_tldr() {
	do_as_user tldr --update
}

set_bluetooth() {
	usermod -aG lp ${user_name}
}

set_light() {
	usermod -aG video ${user_name}
}

set_virtualizer() {
	sed -i '/#unix_sock_group = "libvirt"/s/#//' /etc/libvirt/libvirtd.conf
	sed -i '/#unix_sock_rw_perms = "0770"/s/#//' /etc/libvirt/libvirtd.conf
	usermod -aG libvirt ${user_name}
}

set_wallpaper() {
	do_as_user mkdir -p ${user_home}/a/pixra/bimple
	sync_cfg_dir black.png ${user_home}/a/pixra/bimple/black.png
}

set_auto_start() {
	local mask_list=(systemd-resolved)
	local disable_list=(systemd-timesyncd)
	local btrfs_scrub="btrfs-scrub@$(systemd-escape -p /).timer"
	local enable_list=(${btrfs_scrub} chronyd dnscrypt-proxy fcron grub-btrfs.path nftables paccache.timer pkgstats.timer sshd)

	if [ "$use_gui" = 1 ]; then
		# dhcpcd 和 NetworkManager 不能同时启动
		disable_list+=(dhcpcd)
		enable_list+=(bluetooth libvirtd NetworkManager sddm tlp)
	else
		enable_list+=(dhcpcd)
	fi

	systemctl mask    ${mask_list[@]}
	systemctl disable ${disable_list[@]}
	systemctl enable  ${enable_list[@]}
}

fix_mnt_point() {
	local default_subvol="\/@\/.snapshots\/1\/snapshot"

	sed -i "/${default_subvol}/s/,subvolid=[0-9]\+,subvol=${default_subvol}//" /etc/fstab
}

check_efi() {
	if [ -d /sys/firmware/efi ]; then
		bios_type="uefi"
	else
		bios_type="bios"
	fi
}

check_root_permission() {
	if [ "$USER" != "root" ]; then
		error "no permission"
	fi
}

error() {
	local wrong_reason="$*"

	echo -e "${r}error:${e} ${wrong_reason}"
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
	e="\033[0m"  # 后缀
}

main "$@"
