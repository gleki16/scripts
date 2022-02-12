# 安装 Arch Linux (UEFI 和 GPT)


## 安装前的准备


### 下载 Arch Linux 镜像

<https://www.archlinux.org/download/>

`$ md5sum ~/xz/archlinux.iso` 验证镜像完整性

将输出和下载页面提供的 md5 值对比一下，看看是否一致，不一致则不要继续安装，换个节点重新下载直到一致为止。


### 镜像写入 U 盘

`$ lsblk -f` 查看设备

`$ sudo umount /dev/sda` /dev/sda 是我的闪盘，卸载闪盘。

`$ sudo cp /home/ray/xz/archlinux.iso /dev/sda` 镜像写入闪盘


### 启动到 live 环境

在 UEFI BIOS 中设置启动硬盘为刚刚写入 Arch 系统的闪盘。

进入闪盘的启动引导程序后，选择第一项：Arch Linux archiso x86_64 UEFI CD


### 检查网络

连接网线，无线网络请使用 `iwctl`

可选用 `ip link` 查看连接

可选用 `ping 1.1.1.1` 测试网络是否可用，安装过程中需要用到网络


### 更新系统时间

`# timedatectl set-ntp true` 更新系统时间


### 建立硬盘分区

`# parted -l` 查看硬盘设备

我要把系统安装在 nvme0n1 这个硬盘中（nvme0n1 是固态硬盘，sda 是普通硬盘）

`# parted /dev/nvme0n1` 打开分区

命令提示符会从 `#` 变成 `(parted)`

`(parted) mklabel gpt` 创建 GPT 分区表

`(parted) mkpart esp 1m 513m` 创建启动分区 (nvme0n1p1)

`(parted) set 1 boot on` 设置 esp 为启动分区

`(parted) mkpart arch 513m -1m` 创建根分区 (nvme0n1p2)

`(parted) p` 查看分区结果

`(parted) q` 退出 parted 交互模式


### 加密根分区

`# cryptsetup luksFormat /dev/nvme0n1p2` 加密根分区

输入你要设置的密码

`# cryptsetup open /dev/nvme0n1p2 ray` 使用密码打开根分区

最后的参数是一个名字，它会是解密后的设备在 `/dev/mapper` 下的文件名。


### 格式化分区

`# mkfs.fat -F32 /dev/nvme0n1p1` 格式化启动分区为 fat32 格式

如果格式化失败，可能是硬盘设备存在 Device Mapper：`dmsetup status` 显示 dm 状态 `dmsetup remove <dev-id>` 删除 dm

`# mkfs.btrfs -fL arch /dev/mapper/ray` 格式化根分区为 Brtfs 格式


### 创建子卷

`# mount /dev/mapper/ray /mnt` 挂载根分区

创建 根，家，快照，日志 子卷

```
# btrfs subvolume create /mnt/@
# btrfs subvolume create /mnt/@home
# btrfs subvolume create /mnt/@snap
# btrfs subvolume create /mnt/@swap
# btrfs subvolume create /mnt/@var
```

`# umount /mnt` 卸载根分区


### 挂载分区

`# mount -o autodefrag,compress=zstd,subvol=@ /dev/mapper/ray /mnt` 挂载根分区的 @ 子卷并启用碎片整理和压缩

`# mkdir -p /mnt/{boot/efi,home,.snapshots,swap,var}` 创建目录

挂载其他分区

```
# mount /dev/nvme0n1p1 /mnt/boot/efi
# mount -o subvol=@home /dev/mapper/ray /mnt/home
# mount -o subvol=@snap /dev/mapper/ray /mnt/.snapshots
# mount -o subvol=@swap /dev/mapper/ray /mnt/swap
# mount -o subvol=@var /dev/mapper/ray /mnt/var
```


## 安装


### 选择镜像

`# vim /etc/pacman.d/mirrorlist` 配置 pacman 镜像源

找到标有China的镜像源，命令模式下按下 `dd` 可以剪切光标下的行，按 `gg` 回到文件首，按 `P`（注意是大写的）将行粘贴到文件最前面的位置（优先级最高）。

最后记得用 `:wq` 命令保存文件并退出。


### 安装必须软件包

`# pacstrap /mnt base base-devel linux linux-firmware fish` 安装基本包和 fish


## 配置系统


### Fstab

`# genfstab -L /mnt >> /mnt/etc/fstab` 生成 fstab 文件

可选用 `cat /mnt/etc/fstab` 检查 fstab 文件


### 切换根目录

`# arch-chroot /mnt` 切换至安装好的 Arch


### 安装基本软件包

`# fish` 使用 fish，补全更智能

`# pacman -S amd-ucode btrfs-progs dhcpcd efibootmgr grub os-prober vim` 安装必要软件

amd-ucode 为 AMD CPU 微码，使用 Intel CPU 者替换成 intel-ucode

因为本次安装使用 Btrfs 文件系统，所以要安装 btrfs-progs。


### 设置时区

`# ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime` 设置时区

`# hwclock --systohc` 设置时间标准为 UTC


### 本地化

`# vim /etc/locale.gen` 修改本地化信息

移除 en_US.UTF-8 UTF-8 、zh_CN.UTF-8 UTF-8 前面的 # 后保存。

按 `x` 删除当前光标所在处的字符，按 `u` 撤消最后执行的命令，`:x` 命令保存文件并退出。

`# locale-gen` 生成本地化信息

`# echo LANG=en_US.UTF-8 > /etc/locale.conf` 将系统语言设置为英文，避免乱码

`# echo arch > /etc/hostname` 修改主机名


### 网络配置

`# vim /etc/hosts` 编辑主机表

加入以下字串：

```shell
127.0.0.1       localhost
::1             localhost
127.0.1.1       Arch.localdomain Arch
```

按 `o` 切换到下行输入模式，按 `ESC` 回到命令模式，`:x` 命令保存文件并退出。

`# systemctl enable dhcpcd` 设置 dhcpcd 自启动，下次启动才能连上网


### Root 密码

`# passwd` 修改根密码


### 修改内核钩子

`# vim /etc/mkinitcpio.conf` 修改内核钩子

找到 `HOOKS` 开头那行，在 `keyboard` 后加入 `encrypt`，如下：

`HOOKS=(base ... keyboard encrypt ...)`

如果是安装在可移动设备上，要把 `block` 和 `keyboard` 移动到 `autodetect` 之前。

保存并退出

`# mkinitcpio -p linux` 重新生成 initramfs


### 安装引导程序

`# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub` 安装 grub

如果是安装在可移动设备上，要再加上 `--removable` 参数。

`# vim /etc/default/grub` 修改启动参数

找到 `GRUB_CMDLINE_LINUX=` 开头那行，在引号中写入如下字串，nvme0n1p2 为根分区，分区和设备名以冒号分隔：

`GRUB_CMDLINE_LINUX="cryptdevice=/dev/nvme0n1p2:ray"`

保存并退出

`# grub-mkconfig -o /boot/grub/grub.cfg` 生成主配置文件

可选用 `vim /boot/grub/grub.cfg` 检查 Grub 文件


### 重启

`# exit` 退出 Fish

`# exit` 退出 chroot 环境

可选用 `umount -R /mnt` 手动卸载被挂载的分区

`# reboot` 重启时，记得移除安装介质


## 搭建桌面环境

以根用户 `root` 登入


### 创建用户

`# useradd -m 用户名` 创建新用户

`# passwd 用户名` 设置登陆密码

`# vim /etc/sudoers` 编辑超级用户权限

复制一行 root ALL=(ALL) ALL，并替换其中的 root 为新用户名，`:x!` 强制保存并退出。

`# exit` 退出根用户，并登陆新创建的用户。


## 快速配置 arch

```shell
curl -fsSL https://github.com/rraayy246/uz/raw/master/jb/arch.fish | fish
```


