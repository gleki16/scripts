# 安装 Arch (VPS 和 BIOS)


## 虛擬專用服务器 VPS 提供商

[Vultr][Vultr]：简单好用，功能全面，支持支付宝。

[Vultr]: https://www.vultr.com/zh/

[Linode][Linode]：注册和安装繁琐，需要绑定双币信用卡和谷歌邮箱。

[Linode]: https://www.linode.com/

其他提供商一率不推荐（贵，乱收钱，速度差，无法按时计费，不提供非管理型VPS）。

以下操作使用 Vultr


## Vultr 安装 Arch


### Vultr 注册

到 [Vultr 官网][Vultr] 注册账号，然后充值十刀。


### 创建实例

进入 [Vultr 控制台][my-vultr] 后，按下 蓝色加号 创建实例。

[my-vultr]: https://my.vultr.com/

- 选择服务器：选择云计算 `Cloud Compute`

- 服务器位置：选择东京 `Tokyo`

- 服务器类型：点击映像集 `ISO Library`，选择 `Arch Linux`

- 服务器大小：选择最小方案 `$5/mo` 月付5刀

最后按部署 `Deploy Now`

等待实例运行 `Running`

点击进入刚创建的实例

点击右上方的查看控制台 `View Console`，打开VNC

进入映像的启动引导程序后，选择第一项：`Arch Linux install medium` 回车

等待直到 `root@vultr ~ #` 出现

用 [站长工具][chinaz] 测试实例的 IP 有没被墙。

[chinaz]: https://ping.chinaz.com/

如果没有被墙（地图大部分不是红色），那恭喜你，可以进行下个步骤。如果被墙了（地图全红），则删掉实例`Server Destroy`，重新创建实例。


### 检查网络

`# ping 1.1.1.1` 测试网络是否可用，安装过程中需要用到网络


### 更新系统时间

`# timedatectl set-ntp true` 更新系统时间


### 建立硬盘分区

`# lsblk` 查看硬盘设备

我要把系统安装在 vda 这个硬盘中

`# parted /dev/vda` 打开分区

命令提示符会从 `#` 变成 `(parted)`

`(parted) mklabel gpt` 创建 GPT 分区表

`(parted) mkpart grub 1m 3m` 创建启动分区 (vda1)

`(parted) set 1 bios_grub on` 设置启动分区

`(parted) mkpart arch 3m -1m` 创建根分区 (vda2)

`(parted) p` 查看分区结果

`(parted) q` 退出 parted 交互模式


### 格式化分区

`# mkfs.btrfs -fL arch /dev/vda2` 格式化根分区为 Brtfs 格式


### 创建子卷

`# mount /dev/vda2 /mnt` 挂载根分区

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

`# mount -o autodefrag,compress=zstd,subvol=@ /dev/vda2 /mnt` 挂载根分区的 @ 子卷并启用碎片整理和压缩

`# mkdir -p /mnt/{home,.snapshots,swap,var}` 创建目录

挂载其他分区

```
# mount -o subvol=@home /dev/vda2 /mnt/home
# mount -o subvol=@snap /dev/vda2 /mnt/.snapshots
# mount -o subvol=@swap /dev/vda2 /mnt/swap
# mount -o subvol=@var /dev/vda2 /mnt/var
```


## 安装


### 安装必须软件包

`# pacman -Sy archlinux-keyring` 更新密钥环

`# pacstrap /mnt base base-devel linux linux-firmware fish` 安装基本包和 Fish


## 配置系统


### Fstab

`# genfstab -L /mnt >> /mnt/etc/fstab` 生成 fstab 文件

可选用 `cat /mnt/etc/fstab` 检查 fstab 文件


### 切换根目录

`# arch-chroot /mnt` 切换至安装好的 Arch


### 安装基本软件包

`# fish` 使用 fish，补全更智能

`# pacman -S btrfs-progs dhcpcd grub vim` 安装必要软件


### 设置时区

`# ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime` 设置时区

`# hwclock --systohc` 设置时间标准为 UTC


### 本地化

`# sed -i '/\(en_US\|zh_CN\).UTF-8/s/#//' /etc/locale.gen` 修改本地化信息

`# locale-gen` 生成本地化信息

`# echo LANG=en_US.UTF-8 > /etc/locale.conf` 将系统语言设置为英文，避免乱码

`# echo arch-vultr > /etc/hostname` 修改主机名


### 网络配置

`# vim /etc/hosts` 编辑主机表

加入以下字串：

```shell
主机IP      localhost
::1         localhost
主机IP      主机名.localdomain 主机名
```

按 `o` 切换到下行输入模式，按 `ESC` 回到命令模式，`:x` 命令保存文件并退出


### 设置网络

`# systemctl enable dhcpcd` 启用网络


### 修改根密码

`# passwd` 修改根密码


### 安装引导程序

`# grub-install --target=i386-pc /dev/vda` 安装 grub

`# grub-mkconfig -o /boot/grub/grub.cfg` 生成主配置文件


### 完成 Arch 创建

`# exit` 退出 Fish

`# exit` 退出 chroot 环境

`# poweroff` 关闭服务器

关闭 VNC 视窗


### 打开远程操作

返回 Vultr 的 `服务器信息` 页面

在 `设置` 选项卡上，单击 `自定义 ISO`，然后单击 `删除 ISO`

服务器重启后，单击 `View Console`，打开 VNC


### 新建用户

以根用户 `root` 登入

`# useradd -m 用户名` 创建新用户

`# passwd 用户名` 设置登陆密码

`# vim /etc/sudoers` 编辑超级用户权限

复制一行 `root ALL=(ALL) ALL`，并替换其中的 `root` 为新用户名，`:x!` 强制保存并退出。

`# exit` 退出根用户，并登陆新创建的用户


## 快速配置 arch

```shell
curl -fsSL https://github.com/rraayy246/uz/raw/master/jb/archv.fish | fish
```


## ssh 连接

`$ ssh-keygen` 生成公钥，一路回车

`$ ssh-copy-id user@host` 上传公钥

`$ ssh user@host` 登入主机


