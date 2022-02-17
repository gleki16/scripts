#!/usr/bin/env bash
set -eo pipefail

main() {
	color
	parse_arguments "$@"
	check_root_permission

	if [ "$do_grub_install" = 1 ]; then
		grub_install
		exit 0
	fi
	if [ "$do_grub_mkconfig" = 1 ]; then
		grub_mkconfig
		exit 0
	fi

	if [ "$do_etc_rw" = 1 ]; then
		etc_rw
		exit 0
	fi

	if [ "$do_rollback" = 1 ]; then
		rollback
		exit 0
	fi

	if [ "$do_set_root_rw" = 1 ]; then
		set_root_rw
		exit 0
	fi
	if [ "$do_set_root_ro" = 1 ]; then
		set_root_ro
		exit 0
	fi

	if [ "$do_update_bin" = 1 ]; then
		update_bin
	fi

	if [ "$do_update_etc" = 1 ] ||
		[ "$do_update_system" = 1 ] ||
		[ "$do_run_shell" = 1 ]
	then
		create_snapshot
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
			bi | bin)
				do_update_bin=1
				;;
			up | dup)
				do_update_system=1
				;;
			et | etc)
				do_update_etc=1
				;;
			rb | rollback)
				do_rollback=1
				shift
				snapshot_id="$1"
				;;
			sh | shell)
				do_run_shell=1
				;;
			rw)
				do_set_root_rw=1
				;;
			ro)
				do_set_root_ro=1
				;;
			--etc-rw)
				do_etc_rw=1
				;;
			--grub-install)
				do_grub_install=1
				;;
			--grub-mkconfig)
				do_grub_mkconfig=1
				;;
			-h | --help)
				usage
				exit 0
				;;
			*)
				usage
				exit 1
				;;
		esac
		shift
	done
}

usage() {
	echo "Syntax: transactional-update [options] command"
	echo ""
	echo "Applies package updates to a new snapshot without touching the running system."
	echo ""
	echo "Commands:"
	echo "    bin       (bi)              Update this script"
	echo "    dup       (up)              Update system to a new subvolume"
	echo "    etc       (et)              Update /etc to a new subvolume"
	echo "    rollback  (rb) [number]     Rollback to given subvolume"
	echo "    rw                          Make root subvolume rw"
	echo "    ro                          Make root subvolume ro"
	echo "    shell     (sh)              Open rw shell in new snapshot before exiting"
	echo ""
	echo "Options:"
	echo "    -h, --help                  Print this help message"
}

grub_install() {
	check_efi

	case "$bios_type" in
		uefi)
			grub-install --target=x86_64-efi --efi-directory=/boot/efi
			;;
		bios)
			set_root_part

			if echo $root_part | grep -q 'nvme'; then
				local grub_part=`echo $root_part | sed 's/p[0-9]$//'`
			else
				local grub_part=`echo $root_part | sed 's/[0-9]$//'`
			fi

			grub-install --target=i386-pc $grub_part
			;;
	esac
}

grub_mkconfig() {
	grub_install
	grub-mkconfig -o /boot/grub/grub.cfg
}

etc_rw() {
	local upper_dir=/tmp/etc/upper
	local work_dir=/tmp/etc/work

	mkdir -p $upper_dir $work_dir
	mount -t overlay overlay -o lowerdir=/etc,upperdir=${upper_dir},workdir=${work_dir} /etc
}

rollback() {
	snapshot_dir="/.snapshots/$snapshot_id/snapshot"

	if [ ! -d "$snapshot_dir" ]; then
		error "${snapshot_id} not a snapshot"
	fi

	set_snapshot_rw
	mount_snapshots
	arch-chroot $snapshot_dir "$0" --grub-install
	set_snapshot_ro
}

set_root_rw() {
	set_root_part
	set_root_snapshot

	set_snapshot_rw

	mount -o remount,rw $root_part /
	mount --bind /usr/lib/pacman/local /var/lib/pacman/local
}

set_root_ro() {
	set_root_snapshot

	set_snapshot_ro
}

update_bin() {
	local script_name="transactional-update"
	local script_url="https://gitlab.com/glek/scripts/raw/main/sh/transactional-update.sh"
	local snapshot_list=(`ls /.snapshots`)

	curl -fLo /tmp/$script_name $script_url

	for snapshot_id in ${snapshot_list[@]}; do
		snapshot_dir="/.snapshots/$snapshot_id/snapshot"

		set_snapshot_rw
		rsync /tmp/$script_name $snapshot_dir/bin
		set_snapshot_ro
	done

	rm /tmp/$script_name
}

create_snapshot() {
	local desc=("up")

	if [ "$do_update_etc" = 1 ]; then
		desc+=("etc")
	fi
	if [ "$do_update_system" = 1 ]; then
		desc+=("sys")
	fi
	if [ "$do_run_shell" = 1 ]; then
		desc+=("sh")
	fi

	snapshot_id=`snapper create --print-number --cleanup-algorithm=number --description=${desc[*]}`
	snapshot_dir="/.snapshots/$snapshot_id/snapshot"

	set_snapshot_rw
	mount_snapshots

	if [ "$do_update_etc" = 1 ]; then
		rsync -ah --delete --info=progress2 --inplace --no-whole-file --exclude=resolv.conf /etc $snapshot_dir
	fi

	arch-chroot $snapshot_dir "$0" --grub-mkconfig

	if [ "$do_update_system" = 1 ]; then
		echo 'sorting mirrors ...'
		arch-chroot $snapshot_dir reflector --latest 20 --protocol https --save /etc/pacman.d/mirrorlist --sort rate
		arch-chroot $snapshot_dir pacman -Syu --needed --noconfirm
	fi

	if [ "$do_run_shell" = 1 ]; then
		arch-chroot $snapshot_dir fish
	fi

	set_snapshot_ro
}

mount_snapshots() {
	set_root_part

	mount $root_part $snapshot_dir
	arch-chroot $snapshot_dir mount -a
}

set_snapshot_rw() {
	btrfs property set $snapshot_dir ro false
}

set_snapshot_ro() {
	btrfs property set $snapshot_dir ro true
}

set_root_part() {
	root_part=`df | awk '$6=="/" {print $1}'`
}

set_root_snapshot() {
	snapshot_dir=`findmnt --output source --noheadings / | sed -e 's|.*\(/\.snapshots.*snapshot\).*|\1|g'`
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
	local wrong_reason="$@"

	echo -e $r"error: "$h$wrong_reason
	exit 1
}

main "$@"
