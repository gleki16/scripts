#!/usr/bin/env fish

function main
    set_echo_color
    analysis_argu $argv
    check_root_permission

    if test "$do_connect_wifi" = 1
        connect_wifi
    end

    if test "$do_open_ssh" = 1
        open_ssh
        exit 0
    end

    check_efi

    if test "$do_live_env_proc" = 1
        live_env_proc
        exit 0
    end

    if test "$do_in_chroot_proc" = 1
        in_chroot_proc
        exit 0
    end
end

function live_env_proc
    check_network
    update_system_clock
    update_mirror
    enter_user_var
    use_gui_or_not
    set_partition
    set_subvol
    install_base_system
    set_fstab
    set_hostname
    change_root
end

function in_chroot_proc
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
end

function set_echo_color
    set -g r '\033[1;31m' # 红
    set -g g '\033[1;32m' # 绿
    set -g y '\033[1;33m' # 黄
    set -g b '\033[1;36m' # 蓝
    set -g w '\033[1;37m' # 白
    set -g h '\033[0m'    # 后缀
end

function analysis_argu
    set argu_list $argv

    while test (count $argu_list) -gt 0
        switch $argu_list[1]
            case -h --help
                usage
            case -i --in-chroot
                set -g do_in_chroot_proc 1

                set -e argu_list[1]
                set -g user_name $argu_list[1]

                set -e argu_list[1]
                set -g user_pass $argu_list[1]

                set -e argu_list[1]
                set -g use_gui $argu_list[1]
            case -l --live
                set -g do_live_env_proc 1
            case -s --ssh
                set -g do_open_ssh 1
            case -w --wifi
                set -g do_connect_wifi 1
            case '*'
                error 'wrong argument: '$argu_list[1]
        end

        set -e argu_list[1]
    end
end

function usage
    echo 'Syntax: transactional-update [option...]'
    echo
    echo 'quick install arch.'
    echo
    echo 'General Commands:'
    echo '-i, --install     localization and configuration arch.'
    echo '-l, --live        install the base arch from the live environment.'
    echo '-s, --ssh         open ssh service.'
    echo '-w, --wifi        connect to a wifi.'
    echo
    echo 'Options:'
    echo '-h, --help        Display this help and exit.'

    exit 0
end

function check_root_permission
    if test "$USER" != 'root'
        error 'no root permission.'
    end
end

function check_efi
    if test -d /sys/firmware/efi
        set -g bios_type 'uefi'
    else
        set -g bios_type 'bios'
    end
end

function connect_wifi
    set iw_dev (iw dev | awk '$1=="Interface"{print $2}')

    iwctl station $iw_dev scan
    iwctl station $iw_dev get-networks
    read -p 'echo -e $r"ssid you want to connect to: "$h' ssid
    iwctl station $iw_dev connect $ssid[1]
end

function open_ssh
    set interface (ip -o -4 route show to default | awk '{print $5}')
    set ip        (ip -4 addr show $interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

    read_only_format user_pass $r'enter'$h' your root passwd:' '^[-_,.a-zA-Z0-9]\+$'
    echo "$USER:$user_pass" | chpasswd
    systemctl start sshd

    echo -e $g'# ssh '$USER'@'$ip$h
    echo -e $g"passwd = $user_pass"$h
end

function read_only_format
    set var_name_to_be_set $argv[1]
    set output_hint        $argv[2]
    set matching_format    $argv[3]

    while true
        read -p 'echo -e "$output_hint "' ans
        if echo -- "$ans" | grep -q $matching_format
            read -p 'echo -e "$ans, are you sure? "' sure
            if test "$sure" = 'y' -o "$sure" = ''
                break
            end
        else
            echo -e $r'wrong format.'$h
        end
    end

    set -g $var_name_to_be_set "$ans"
end

function check_network
    if ping -c 1 -w 1 1.1.1.1 &>/dev/null
        echo -e $g'network connection is successful.'$h
    else
        error 'Network connection failed.'
    end
end

function update_system_clock
    timedatectl set-ntp true
end

function update_mirror
end

function enter_user_var
    read_only_format host_name $r'enter'$h' your hostname:'    '^[a-zA-Z][-a-zA-Z0-9]*$'
    read_only_format user_name $r'enter'$h' your username:'    '^[a-z][-a-z0-9]*$'
    read_only_format user_pass $r'enter'$h' your user passwd:' '^[-_,.a-zA-Z0-9]*$'
end

function use_gui_or_not
    read -p 'echo -e "use GUI or not? "' ans

    switch $ans
        case y
            set -g use_gui 1
        case n
            set -g use_gui 0
        case '*'
            if test (systemd-detect-virt) = 'none'
                set -g use_gui 1
            else
                set -g use_gui 0
            end
    end
end

function set_partition
    echo -e $r'automatic partition or manual partition: '$h
    select ans 'automatic' 'manual'

    if test $ans = 'automatic'
        select_partition main_part

        parted /dev/$main_part mklabel gpt
        if test $bios_type = 'uefi'
            parted /dev/$main_part mkpart esp 1m 513m
            parted /dev/$main_part set 1 boot on
            parted /dev/$main_part mkpart arch 513m 100%
        else
            parted /dev/$main_part mkpart grub 1m 3m
            parted /dev/$main_part set 1 bios_grub on
            parted /dev/$main_part mkpart arch 3m 100%
        end

        if echo $main_part | grep -q 'nvme'
            set -g boot_part /dev/$main_part'p1'
            set -g root_part /dev/$main_part'p2'
        else
            set -g boot_part /dev/$main_part'1'
            set -g root_part /dev/$main_part'2'
        end

        if test $bios_type = 'uefi'
            mkfs.fat -F32 $boot_part
        end
    else
        select_partition boot_part
        select_partition root_part
        set -g boot_part /dev/$boot_part
        set -g root_part /dev/$root_part
    end
end

function select_partition
    set partition_name $argv[1]
    set partition_list (lsblk -l | awk '{ print $1 }' | grep '^\(nvme\|sd.\|vd.\)')

    lsblk
    echo -e $r'select a partition as the '$h$partition_name$r' partition: '$h
    select $partition_name $partition_list
end

function select
    set var_name_to_be_set $argv[1]
    set option_list        $argv[2..-1]

    for i in (seq (count $option_list))
        echo $i. $option_list[$i]
    end

    while true
        read -p 'echo -e "❯ "' ans
        if echo -- $ans | grep -q '^[1-9][0-9]*$'; and test $ans -le (count $option_list)
            read -p 'echo -e "$option_list[$ans], are you sure? "' sure
            if test "$sure" = 'y' -o "$sure" = ''
                break
            end
        else
            echo -e $r'wrong format.'$h
        end
    end

    set -g $var_name_to_be_set $option_list[$ans]
end

function set_subvol
    set subvol_list var 'usr/local' srv root opt home .snapshots

    umount -fR /mnt &>/dev/null

    mkfs.btrfs -fL arch $root_part
    mount $root_part /mnt

    btrfs subvolume create /mnt/@

    mkdir -p /mnt/@/{usr,boot/grub}

    for subvol in $subvol_list
        btrfs subvolume create /mnt/@/$subvol
    end

    chattr +C /mnt/@/var

    mkdir /mnt/@/.snapshots/1
    btrfs subvolume create /mnt/@/.snapshots/1/snapshot

    set default_id (btrfs inspect-internal rootid /mnt/@/.snapshots/1/snapshot)
    btrfs subvolume set-default $default_id /mnt

    umount -R /mnt

    mount -o autodefrag,compress=zstd $root_part /mnt

    for subvol in $subvol_list
        mkdir -p /mnt/$subvol
        mount -o subvol=/@/$subvol $root_part /mnt/$subvol
    end

    if test $bios_type = 'uefi'
        mkdir -p /mnt/boot/efi
        mount $boot_part /mnt/boot/efi
    end

    # 避免回滚时 pacman 数据库和软件不同步
    mkdir -p     /mnt/usr/lib/pacman/local /mnt/var/lib/pacman/local
    mount --bind /mnt/usr/lib/pacman/local /mnt/var/lib/pacman/local
end

function install_base_system
    set basic_pkg base base-devel linux linux-firmware btrfs-progs fish dhcpcd reflector vim

    pacman -Sy --noconfirm archlinux-keyring

    pacman -S --needed --noconfirm reflector
    echo 'sorting mirrors ...'
    reflector --latest 20 --protocol https --save /etc/pacman.d/mirrorlist --sort rate

    pacstrap /mnt $basic_pkg
end

function set_fstab
    # 绑定挂载无法被 genfstab 正确识别，所以先卸载
    umount /mnt/var/lib/pacman/local

    genfstab -L /mnt >> /mnt/etc/fstab

    mount --bind /mnt/usr/lib/pacman/local /mnt/var/lib/pacman/local

    # 手动写入绑定挂载
    echo '/usr/lib/pacman/local /var/lib/pacman/local none defaults,bind 0 0' >> /mnt/etc/fstab
end

function set_hostname
    echo $host_name > /mnt/etc/hostname
end

function change_root
    rsync /etc/pacman.d/mirrorlist /mnt/etc/pacman.d

    rsync (status -f) /mnt/arch.fish
    chmod +x /mnt/arch.fish

    arch-chroot /mnt /arch.fish -i "$user_name" "$user_pass" "$use_gui"

    set_resolve
    rm /mnt/arch.fish
    btrfs property set /mnt/.snapshots/1/snapshot ro true

    umount -R /mnt

    echo -e $r'please reboot.'$h
end

function set_resolve
    echo -e 'nameserver ::1\nnameserver 127.0.0.1\noptions edns0 single-request-reopen' > /mnt/etc/resolv.conf
    chattr +i /mnt/etc/resolv.conf
end

function set_time_zone
    set city Asia/Shanghai

    ln -sf /usr/share/zoneinfo/$city /etc/localtime
    hwclock --systohc
end

function set_locale
    sed -i '/\(en_US\|zh_CN\).UTF-8/s/#//' /etc/locale.gen
    locale-gen
    echo 'LANG=en_US.UTF-8' > /etc/locale.conf
end

function set_network
    set host_name  (cat /etc/hostname)

    echo -e '127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t'$host_name'.localdomain '$host_name >> /etc/hosts
end

function set_passwd
    echo "root:$user_pass" | chpasswd

    useradd -mG wheel $user_name
    echo "$user_name:$user_pass" | chpasswd
    sed -i '/# %wheel ALL=(ALL) NOPASSWD: ALL/s/# //' /etc/sudoers
end

function set_pacman
    sed -i '/^#Color$/s/#//' /etc/pacman.conf

    # 添加 archlinuxcn 源
    curl -fLo /etc/pacman.d/archlinuxcn-mirrorlist https://raw.githubusercontent.com/archlinuxcn/mirrorlist-repo/master/archlinuxcn-mirrorlist
    sed -i '/Server =/s/^#//' /etc/pacman.d/archlinuxcn-mirrorlist
    echo -e '[archlinuxcn]\nInclude = /etc/pacman.d/archlinuxcn-mirrorlist' >> /etc/pacman.conf

    pacman -Syy --noconfirm archlinuxcn-keyring
end

function install_bootloader
    set root_part  (df | awk '$6=="/" {print $1}')
    set boot_pkg grub

    if test $bios_type = 'uefi'
        set -a boot_pkg efibootmgr
    end

    if test "$use_gui" = 1
        set -a boot_pkg os-prober
    end

    pacman_install $boot_pkg

    switch $bios_type
        case uefi
            grub-install --target=x86_64-efi --efi-directory=/boot/efi
        case bios
            if echo $root_part | grep -q 'nvme'
                set grub_part (echo $root_part | sed 's/p[0-9]$//')
            else
                set grub_part (echo $root_part | sed 's/[0-9]$//')
            end
            grub-install --target=i386-pc $grub_part
    end

    if test "$use_gui" = 1
        echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
    end
    sed -i '/GRUB_TIMEOUT=/s/5/1/' /etc/default/grub
    echo 'SUSE_BTRFS_SNAPSHOT_BOOTING=true' >> /etc/default/grub

    grub-mkconfig -o /boot/grub/grub.cfg
end

function pacman_install

    # 一次性安装太多软件容易安装失败，
    # 所以连试三次，增加成功的几率。

    set pkg_list $argv

    for i in (seq 3)
        if pacman -S --needed --noconfirm $pkg_list
            break
        end
    end
end

function install_pkg
    set network_pkg    curl git openssh wget wireguard-tools
    set terminal_pkg   neovim python-pynvim starship
    set file_pkg       lf p7zip snapper
    set sync_pkg       chrony rsync
    set search_pkg     ctags fzf mlocate tree highlight
    set new_search_pkg fd ripgrep bat tldr exa
    set system_pkg     fcron btop man pacman-contrib pkgstats
    set maintain_pkg   arch-install-scripts dosfstools parted
    set security_pkg   dnscrypt-proxy gocryptfs nftables
    set depend_pkg     lua nodejs perl-file-mimeinfo qrencode yarn zsh
    set aur_pkg        paru

    pacman_install $network_pkg  $terminal_pkg
    pacman_install $file_pkg     $sync_pkg
    pacman_install $search_pkg   $new_search_pkg
    pacman_install $system_pkg   $maintain_pkg
    pacman_install $security_pkg $depend_pkg $aur_pkg

    # iptables-nft 不能直接装，需要进行确认
    echo -e 'y\n\n' | pacman -S --needed iptables-nft

    if test "$use_gui" = 1
        install_gui_pkg
    end
end

function install_gui_pkg
    set lscpu (lscpu)
    if echo $lscpu | grep -q 'AuthenticAMD'
        set ucode_pkg amd-ucode
    else if echo $lscpu | grep -q 'GenuineIntel'
        set ucode_pkg intel-ucode
    end

    set lspci_VGA (lspci | grep '3D\|VGA')
    if echo $lspci_VGA | grep -q 'AMD'
        set gpu_pkg xf86-video-amdgpu
    else if echo $lspci_VGA | grep -q 'Intel'
        set gpu_pkg xf86-video-intel
    else if echo $lspci_VGA | grep -q 'NVIDIA'
        set gpu_pkg xf86-video-nouveau
    end

    set audio_pkg     alsa-utils pulseaudio pulseaudio-alsa pulseaudio-bluetooth
    set bluetooth_pkg bluez bluez-utils blueman
    set touch_pkg     libinput

    set driver_pkg    $ucode_pkg $gpu_pkg $audio_pkg $bluetooth_pkg $touch_pkg
    set manager_pkg   networkmanager tlp
    set display_pkg   wayland sway swaybg swayidle swaylock xorg-xwayland
    set desktop_pkg   alacritty i3status-rust grim slurp wofi lm_sensors qt5-wayland
    set browser_pkg   firefox firefox-i18n-zh-cn
    set media_pkg     imv vlc
    set input_pkg     fcitx5-im fcitx5-rime
    set control_pkg   brightnessctl playerctl lm_sensors upower
    set virtual_pkg   flatpak qemu libvirt virt-manager dnsmasq bridge-utils openbsd-netcat edk2-ovmf
    set office_pkg    calibre libreoffice-fresh-zh-cn
    set font_pkg      noto-fonts-cjk noto-fonts-emoji ttf-font-awesome ttf-ubuntu-font-family
    set program_pkg   bash-language-server clang rust

    pacman_install $driver_pkg  $manager_pkg
    pacman_install $display_pkg $desktop_pkg
    pacman_install $browser_pkg $media_pkg
    pacman_install $input_pkg   $control_pkg
    pacman_install $virtual_pkg $office_pkg
    pacman_install $font_pkg    $program_pkg
end

function copy_config
    set -g user_home /home/$user_name
    set user_mkdir gz xz

    do_as_user mkdir -p $user_home/$user_mkdir
    set_cfg_repo

    fish $cfg_dir/env.fish
    do_as_user fish $cfg_dir/env.fish

    sync_cfg_dir etc /
    sync_cfg_dir .config /root
    sync_cfg_dir .config $user_home

    if test "$use_gui" = 1
        sync_cfg_dir .local $user_home
    end
end

function do_as_user

    # 避免创建出的目录或文件，用户无权操作。

    cd $user_home
    sudo -u $user_name $argv
    cd
end

function set_cfg_repo

    # uz 是存放我所有设定的仓库

    set -g cfg_dir $user_home/dotfiles

    do_as_user git clone --depth 1 https://gitlab.com/glek/dotfiles.git $cfg_dir

    cd $cfg_dir
    git config credential.helper store
    do_as_user git config --global user.email 'rraayy246@gmail.com'
    do_as_user git config --global user.name 'ray'
    do_as_user git config --global pull.rebase false
    cd
end

function sync_cfg_dir

    # 如果目标目录非用户的目录，则不复制所有者信息，
    # 以免其他程序无权限操作。

    set src_in_cfg_dir $argv[1]
    set dest_dir       $argv[2]
    set src_dir $cfg_dir/$src_in_cfg_dir

    if echo $dest_dir | grep -q '^/home'
        rsync -a --inplace --no-whole-file $src_dir $dest_dir
    else
        rsync -rlptD --inplace --no-whole-file $src_dir $dest_dir
    end
end

function write_config
    sed -i '/home\|root/s/bash/fish/' /etc/passwd

    no_gui_set  /root

    set_cron
	set_nvim
    set_ssh
    set_snapper
    set_swap

    if test "$use_gui" = 1
        do_as_user mkdir -p $user_home/a/pixra/bimple
        sync_cfg_dir black.png $user_home/a/pixra/bimple/black.png

        set_virtualizer
    else
        no_gui_set $user_home
    end
end

function no_gui_set
    set home_dir $argv[1]

    echo -e 'if status is-interactive\n\tstarship init fish | source\nend' > $home_dir/.config/fish/config.fish
end

function set_cron
    if test "$use_gui" = 1
        sed '/and reboot/s/^/#/' $cfg_dir/cron > /tmp/cron
        fcrontab /tmp/cron
        rm /tmp/cron
    else
        fcrontab $cfg_dir/cron
    end
end

function set_nvim
	do_as_user git clone --depth=1 https://gitlab.com/glek/dotnvim.git ~/.config/nvim

	do_as_user nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

	mkdir -p /root/.local/share
	rsync -r $user_home/.config/nvim /root/.config
	rsync -r $user_home/.local/share/nvim /root/.local/share
end

function set_ssh
    ssh-keygen -A
end

function set_snapper
	set script_name transactional-update
	set script_url https://gitlab.com/glek/scripts/raw/main/sh/transactional-update

    # 防止快照被索引
    sed -i '/PRUNENAMES/s/.git/& .snapshots/' /etc/updatedb.conf

    sed -i '/SNAPPER_CONFIGS=/s/""/"root"/' /etc/conf.d/snapper

    set date (date +'%F %T')
    echo '<?xml version="1.0"?>
<snapshot>
  <type>single</type>
  <num>1</num>
  <date>'$date'</date>
  <cleanup>number</cleanup>
  <description>first root filesystem</description>
</snapshot>' > /.snapshots/1/info.xml

	curl -fLo /bin/$script_name $script_url
    chmod +x /bin/$script_name
end

function set_swap
    set swap_dir /var/lib/swap
    set swap_file $swap_dir/swapfile
    set swap_size 2G

    mkdir $swap_dir
    touch $swap_file
    chattr +C $swap_file
    chattr -c $swap_file

    fallocate -l $swap_size $swap_file

    chmod 600 $swap_file
    mkswap $swap_file

    echo $swap_file' none swap defaults 0 0' >> /etc/fstab

    # 最大限度使用物理内存
    echo 'vm.swappiness = 0' > /etc/sysctl.d/swappiness.conf
    sysctl (cat /etc/sysctl.d/swappiness.conf | sed 's/ //g')
end

function set_virtualizer
    sed -i '/#unix_sock_group = "libvirt"/s/#//' /etc/libvirt/libvirtd.conf
    sed -i '/#unix_sock_rw_perms = "0770"/s/#//' /etc/libvirt/libvirtd.conf
    usermod -a -G libvirt $user_name
end

function set_auto_start
    set mask_list    systemd-resolved
    set disable_list systemd-timesyncd
    set enable_list  chronyd dnscrypt-proxy fcron nftables paccache.timer pkgstats.timer sshd

    if test "$use_gui" = 1
        # dhcpcd 和 NetworkManager 不能同时启动
        set -a disable_list dhcpcd
        set -a enable_list  bluetooth NetworkManager tlp
    else
        set -a enable_list  dhcpcd
    end

    systemctl mask    $mask_list
    systemctl disable $disable_list
    systemctl enable  $enable_list
end

function fix_mnt_point
    set default_subvol '\/@\/.snapshots\/1\/snapshot'

    sed -i '/'$default_subvol'/s/rw,/ro,/' /etc/fstab
    sed -i '/'$default_subvol'/s/,subvolid=[0-9]\+,subvol='$default_subvol'//' /etc/fstab
end

function error
    set wrong_reason $argv

    echo -e $r$wrong_reason$h
    exit 1
end

main $argv
